import Foundation
import ReticulumSwift

// rnx — Reticulum Remote Execution Utility.
//
// Python reference: RNS/Utilities/rnx.py (740 lines).
//
// This file owns argument parsing, terminal drawing, the interactive REPL, signal handling
// and every exit code. All protocol work lives in ReticulumSwift's RNX* types, which are
// pure and unit-tested; nothing here does anything a test would want to assert.

let VERSION = Reticulum.version
let APP_NAME = RNXApp.appName

// MARK: - Interrupt handling

/// Set from the SIGINT handler. Python catches KeyboardInterrupt around the whole of
/// `main()`, prints an empty line, tears the link down and exits 0 (rnx.py:671-676).
/// A signal handler cannot do that safely, so the spin loops poll this flag instead.
nonisolated(unsafe) var rnxInterrupted: sig_atomic_t = 0

// MARK: - Raw terminal output

// Everything goes through C stdio rather than FileHandle, because Swift's `print` writes
// to `stdout` too: mixing the two would reorder the output (FileHandle writes bypass the
// stdio buffer, so a `print("")` before a FileHandle write can surface after it).

func writeOut(_ text: String) {
    fputs(text, stdout)
}

func writeOut(_ data: Data) {
    guard !data.isEmpty else { return }
    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        _ = fwrite(base, 1, data.count, stdout)
    }
}

func writeErr(_ data: Data) {
    guard !data.isEmpty else { return }
    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        _ = fwrite(base, 1, data.count, stderr)
    }
}

func writeErrLine(_ text: String) {
    fputs(text + "\n", stderr)
}

// MARK: - Shared session state

/// Python keeps `identity`, `reticulum`, `link`, `listener_destination`, `stats`,
/// `current_progress` and `speed` as module globals, which is precisely what lets an
/// interactive session reuse one Link — and what makes the transfer meter carry over
/// between commands. Same lifetime here.
final class Session {
    var connection: InstanceConnection?
    var identity: Identity?
    var client: RNXClient?

    /// Never reset between commands, reproducing Python's module-global `stats`.
    private let statsLock = NSLock()
    private var stats = RNXTransferStats()

    func recordProgress(_ progress: Double, transferSize: Int) {
        statsLock.lock()
        stats.record(progress: progress, transferSize: transferSize,
                     at: Date().timeIntervalSince1970)
        statsLock.unlock()
    }

    var statusLine: String {
        statsLock.lock(); defer { statsLock.unlock() }
        return stats.statusLine()
    }
}

let session = Session()

// MARK: - Spinners

/// Python: `spin(until, msg, timeout)` — rnx.py:254-272.
///
/// Reproduced byte for byte, quirks included: the initial write happens *before* `until()`
/// is first evaluated, so even an already-satisfied predicate draws and erases; and the
/// erase writes two columns fewer than were written, leaving one trailing space.
@discardableResult
func spin(until: () -> Bool, msg: String, timeout: TimeInterval?) -> Bool {
    var index = 0
    let symbols = RNXApp.spinnerSymbols
    let deadline = timeout.map { Date().timeIntervalSince1970 + $0 }

    writeOut(msg + "   ")   // Python: print(msg+"  ", end=" ") — msg plus three spaces.
    while (deadline == nil || Date().timeIntervalSince1970 < deadline!) && !until() {
        if rnxInterrupted != 0 { break }
        Thread.sleep(forTimeInterval: 0.1)
        writeOut("\u{8}\u{8}" + String(symbols[index]) + " ")
        fflush(stdout)                                  // Python: sys.stdout.flush()
        index = (index + 1) % symbols.count
    }
    writeOut("\r" + String(repeating: " ", count: msg.count) + "  \r")
    fflush(stdout)
    handleInterruptIfNeeded()

    if let deadline, Date().timeIntervalSince1970 > deadline { return false }
    return true
}

/// Python: `spin_stat(until, timeout)` — rnx.py:277-299. No initial write, a fixed
/// 82-column blank field before each frame, and a trailing space from `print(end=" ")`.
@discardableResult
func spinStat(until: () -> Bool, timeout: TimeInterval?) -> Bool {
    var index = 0
    let symbols = RNXApp.spinnerSymbols
    let deadline = timeout.map { Date().timeIntervalSince1970 + $0 }
    let blank = String(repeating: " ", count: RNXApp.statClearWidth)

    while (deadline == nil || Date().timeIntervalSince1970 < deadline!) && !until() {
        if rnxInterrupted != 0 { break }
        Thread.sleep(forTimeInterval: 0.1)
        writeOut("\r" + blank + "\rReceiving result " + String(symbols[index]) + " "
                 + session.statusLine + " ")
        fflush(stdout)                                  // Python: sys.stdout.flush()
        index = (index + 1) % symbols.count
    }
    writeOut("\r" + blank + "\r")
    fflush(stdout)
    handleInterruptIfNeeded()

    if let deadline, Date().timeIntervalSince1970 > deadline { return false }
    return true
}

/// Python: `except KeyboardInterrupt: print(""); link.teardown(); exit()` — rnx.py:671-676.
func handleInterruptIfNeeded() {
    guard rnxInterrupted != 0 else { return }
    print("")
    session.client?.teardown()
    exit(0)
}

// MARK: - Argument parser

func makeParser() -> ArgumentParser {
    var parser = ArgumentParser(program: APP_NAME, overview: RNXHelpText.description)
    parser.positional("destination", help: "hexadecimal hash of the listener", required: false)
    parser.positional("command", help: "command to be execute", required: false)
    parser.option(["--config"], metavar: "path",
                  help: "path to alternative Reticulum config directory")
    parser.counted(["-v", "--verbose"], help: "increase verbosity")
    parser.counted(["-q", "--quiet"], help: "decrease verbosity")
    parser.flag(["-p", "--print-identity"], help: "print identity and destination info and exit")
    parser.flag(["-l", "--listen"], help: "listen for incoming commands")
    parser.option(["-i"], metavar: "identity", help: "path to identity to use")
    parser.flag(["-x", "--interactive"], help: "enter interactive mode")
    parser.flag(["-b", "--no-announce"], help: "don't announce at program start")
    parser.appending(["-a"], metavar: "allowed_hash", help: "accept from this identity")
    parser.flag(["-n", "--noauth"], help: "accept commands from anyone")
    parser.flag(["-N", "--noid"], help: "don't identify to listener")
    parser.flag(["-d", "--detailed"], help: "show detailed result output")
    parser.flag(["-m"], help: "mirror exit code of remote command")
    parser.option(["-w"], metavar: "seconds", help: "connect and request timeout before giving up")
    parser.option(["-W"], metavar: "seconds", help: "max result download time")
    parser.option(["--stdin"], metavar: "STDIN", help: "pass input to stdin")
    parser.option(["--stdout"], metavar: "STDOUT", help: "max size in bytes of returned stdout")
    parser.option(["--stderr"], metavar: "STDERR", help: "max size in bytes of returned stderr")
    parser.flag(["--version"], help: "show program's version number and exit")
    return parser
}

/// Python: argparse writes the usage line and an error to **stderr** and exits 2.
func usageError(_ message: String) -> Never {
    writeErrLine(RNXHelpText.usage)
    writeErrLine("\(APP_NAME): error: \(message)")
    exit(Int32(RNXApp.Result.usageError.rawValue))
}

// MARK: - Options

struct Options {
    var configDirectory: URL?
    var verbosity = 0
    var quietness = 0
    var printIdentity = false
    var listen = false
    var identityPath: String?
    var interactive = false
    var noAnnounce = false
    var allowed: [String] = []
    var noAuth = false
    var noID = false
    var detailed = false
    var mirror = false
    /// Python: `default=RNS.Transport.PATH_REQUEST_TIMEOUT` — an **int**, not coerced by
    /// `type=float`, so the defaulted value goes on the wire as msgpack fixint 15.
    var timeout: TimeInterval = 15
    var timeoutWasDefaulted = true
    var resultTimeout: TimeInterval?
    var stdin: String?
    var stdoutLimit: Int?
    var stderrLimit: Int?
    var destination: String?
    var command: String?

    /// Python: `targetloglevel = 3+verbosity-quietness`, then clamped to
    /// [LOG_CRITICAL, LOG_EXTREME] inside `Reticulum.__init__` (Reticulum.py:301-302).
    /// `-qqqq` therefore lands on 0, never on LOG_NONE.
    var logLevel: Reticulum.LogLevel {
        let requested = 3 + verbosity - quietness
        let clamped = min(max(requested, RNXApp.minLogLevel), RNXApp.maxLogLevel)
        return Reticulum.LogLevel(rawValue: clamped) ?? .notice
    }
}

func parseOptions() -> Options {
    let parser = makeParser()
    let parsed: ParsedArguments
    do {
        parsed = try parser.parse(Array(CommandLine.arguments.dropFirst()))
    } catch let error as ArgumentError {
        usageError(parser.message(for: error))
    } catch {
        usageError("\(error)")
    }

    if parsed.wantsHelp {
        writeOut(RNXHelpText.help)
        exit(0)
    }
    if parsed.flag("--version") {
        // Python: argparse's version action prints "rnx {RNS.__version__}".
        print("\(APP_NAME) \(VERSION)")
        exit(0)
    }

    var options = Options()
    options.configDirectory = parsed.value("--config").map {
        DaemonBootstrap.expandTildeURL($0)
    }
    options.verbosity = parsed.count("--verbose")
    options.quietness = parsed.count("--quiet")
    options.printIdentity = parsed.flag("--print-identity")
    options.listen = parsed.flag("--listen")
    options.identityPath = parsed.value("-i")
    options.interactive = parsed.flag("--interactive")
    options.noAnnounce = parsed.flag("--no-announce")
    // `values(_:)` is nil when the option never appeared; rnx treats that the same as
    // an empty allow-list, since Python's `args.allowed` defaults to [].
    options.allowed = parsed.values("-a") ?? []
    options.noAuth = parsed.flag("--noauth")
    options.noID = parsed.flag("--noid")
    options.detailed = parsed.flag("--detailed")
    options.mirror = parsed.flag("-m")

    if let raw = parsed.value("-w") {
        guard let value = Double(raw) else {
            usageError("argument -w: invalid float value: '\(raw)'")
        }
        options.timeout = value
        options.timeoutWasDefaulted = false
    }
    if let raw = parsed.value("-W") {
        guard let value = Double(raw) else {
            usageError("argument -W: invalid float value: '\(raw)'")
        }
        options.resultTimeout = value
    }
    options.stdin = parsed.value("--stdin")
    if let raw = parsed.value("--stdout") {
        guard let value = Int(raw) else {
            usageError("argument --stdout: invalid int value: '\(raw)'")
        }
        options.stdoutLimit = value
    }
    if let raw = parsed.value("--stderr") {
        guard let value = Int(raw) else {
            usageError("argument --stderr: invalid int value: '\(raw)'")
        }
        options.stderrLimit = value
    }

    options.destination = parsed.positionals.count > 0 ? parsed.positionals[0] : nil
    options.command = parsed.positionals.count > 1 ? parsed.positionals[1] : nil
    if parsed.positionals.count > 2 {
        usageError("unrecognized arguments: "
                   + parsed.positionals.dropFirst(2).joined(separator: " "))
    }
    return options
}

// MARK: - Stack bring-up

/// Python's `RNS.log` line shape (`__init__.py:131`):
/// `"[" + timestamp + "] " + loglevelname(level) + " " + msg`, where `loglevelname` is
/// ten columns wide — so a notice line carries three spaces before the message.
/// ReticulumSwift's default printer emits `"[\(Date())] [NOTICE] msg"` instead.
func installPythonLogFormat() {
    Reticulum.logHandler = { message, level in
        let timestamp = Reticulum.logTimestamps
            ? "[" + RNSUtilities.timestampStr(Date().timeIntervalSince1970) + "] "
            : ""
        print(timestamp + Reticulum.loglevelname(level) + " " + message)
        fflush(stdout)
    }
}

/// Python: `RNS.Reticulum(configdir=configdir, loglevel=targetloglevel)` — rnx.py:67, 343.
/// Built exactly once per process, matching the `reticulum` module global.
func bringUpStack(_ options: Options) -> InstanceConnection {
    if let existing = session.connection { return existing }
    do {
        let connection = try InstanceConnection.attach(configDirectory: options.configDirectory,
                                                       requireSharedInstance: false,
                                                       logLevel: options.logLevel,
                                                       synthesizeInterfaces: true)
        // MUST come after start(): applyConfig() assigns globalLogLevel from the config
        // file (default `loglevel = 4`), so anything set beforehand is silently discarded
        // and -v/-q become no-ops. Python does the reverse — a requested loglevel
        // suppresses the config value entirely (Reticulum.py:455).
        Reticulum.globalLogLevel = options.logLevel
        session.connection = connection
        return connection
    } catch {
        print("Could not start Reticulum: \(error)")
        exit(Int32(RNXApp.Result.argumentError.rawValue))
    }
}

/// Python: `prepare_identity(identitypath)` — rnx.py:50-61. Created once per process.
func prepareIdentity(_ options: Options, configDirectory: URL) -> Identity {
    if let existing = session.identity { return existing }
    let url = options.identityPath.map {
        DaemonBootstrap.expandTildeURL($0)
    } ?? RNXListener.defaultIdentityURL(configDir: configDirectory)
    do {
        let identity = try RNXListener.loadOrCreateIdentity(at: url)
        session.identity = identity
        return identity
    } catch {
        print("Could not load or create identity at \(url.path): \(error)")
        exit(Int32(RNXApp.Result.argumentError.rawValue))
    }
}

// MARK: - Listener

/// Python: `listen(...)` — rnx.py:63-138. Never returns; `-p` exits 0 partway through.
func runListener(_ options: Options) -> Never {
    let connection = bringUpStack(options)
    let identity = prepareIdentity(options, configDirectory: connection.configDirectory)

    // Python builds the destination before the -p check, and -p exits before ANY
    // allowed-list parsing, before handler registration and before any announce.
    if options.printIdentity {
        guard let destination = try? Destination(identity: identity,
                                                 direction: .in,
                                                 kind: .single,
                                                 appName: RNXApp.appName,
                                                 aspects: [RNXApp.aspect]) else {
            print("Could not create destination")
            exit(Int32(RNXApp.Result.argumentError.rawValue))
        }
        // Labels padded so the colon sits at 1-based column 14. str(identity) is
        // prettyhexrep(identity.hash) (Identity.py:955).
        print("Identity     : " + RNSUtilities.prettyhexrep(identity.hash))
        print("Listening on : " + RNSUtilities.prettyhexrep(destination.hash))
        exit(0)
    }

    var allowedHashes: [Data] = []
    if !options.noAuth {
        for value in options.allowed {
            do {
                allowedHashes.append(try RNXListener.parseAllowedHash(value))
            } catch RNXListener.ListenerError.invalidAllowedHashLength {
                // Python formats the numbers rather than hard-coding them (rnx.py:85).
                let hexLength = RNXApp.destinationHexLength
                print("Allowed destination length is invalid, must be \(hexLength) "
                      + "hexadecimal characters (\(hexLength / 2) bytes).")
                exit(Int32(RNXApp.Result.argumentError.rawValue))
            } catch {
                print("Invalid destination entered. Check your input.")
                exit(Int32(RNXApp.Result.argumentError.rawValue))
            }
        }
        do {
            allowedHashes.append(contentsOf: try RNXListener.loadAllowedIdentitiesFile())
        } catch {
            // Python prints CPython's own fromhex message here; the wording cannot be
            // reproduced, so a descriptive substitute is used. The exit code matches.
            print("Invalid entry in allowed_identities file. Check your input.")
            exit(Int32(RNXApp.Result.argumentError.rawValue))
        }
    }

    // Python: rnx.py:113-114. The "rncx" typo is verbatim, and this is a plain print(),
    // not an RNS.log line.
    if allowedHashes.isEmpty && !options.noAuth {
        print("Warning: No allowed identities configured, rncx will not accept any commands!")
    }

    #if os(macOS)
    let executor = ProcessCommandExecutor()
    #else
    print("Command execution is only supported on macOS")
    exit(Int32(RNXApp.Result.argumentError.rawValue))
    #endif

    let listener: RNXListener
    do {
        listener = try RNXListener(identity: identity,
                                   transport: connection.reticulum.transport,
                                   executor: executor,
                                   allowedIdentityHashes: allowedHashes,
                                   allowAll: options.noAuth)
    } catch {
        print("Could not create listener: \(error)")
        exit(Int32(RNXApp.Result.argumentError.rawValue))
    }
    listener.register()

    Reticulum.log("rnx listening for commands on "
                  + RNSUtilities.prettyhexrep(listener.destination.hash))

    if !options.noAnnounce { try? listener.announce() }

    // Python: `while True: time.sleep(1)` — no periodic re-announce, no clean shutdown.
    while true {
        if rnxInterrupted != 0 { print(""); exit(0) }
        Thread.sleep(forTimeInterval: 1)
    }
}

// MARK: - Client

/// Python: `execute(...)` — rnx.py:326-551.
///
/// Returns the remote return code in interactive mode (only ever non-nil under `-m`);
/// exits the process in every other case, exactly as Python does.
@discardableResult
func runClient(_ options: Options, command: String, stdin: String?, interactive: Bool) -> Int? {
    let hexLength = RNXApp.destinationHexLength

    // Unconditional, and BEFORE the stack comes up — an invalid destination never
    // brings Reticulum up, even under -x.
    let destinationHash: Data
    do {
        destinationHash = try RNXClient.parseDestination(options.destination ?? "")
    } catch RNXClient.ClientError.invalidDestinationLength {
        print("Allowed destination length is invalid, must be \(hexLength) "
              + "hexadecimal characters (\(hexLength / 2) bytes).")
        exit(Int32(RNXApp.Result.invalidDestination.rawValue))
    } catch {
        print("Invalid destination entered. Check your input.")
        exit(Int32(RNXApp.Result.invalidDestination.rawValue))
    }

    let connection = bringUpStack(options)
    let identity = prepareIdentity(options, configDirectory: connection.configDirectory)
    let prettyDestination = RNSUtilities.prettyhexrep(destinationHash)

    let client: RNXClient
    if let existing = session.client {
        client = existing
    } else {
        client = RNXClient(transport: connection.reticulum.transport,
                           identity: identity,
                           destinationHash: destinationHash)
        session.client = client
    }

    // Python: rnx.py:348-352. When a path is already known the spinner never draws.
    if !client.hasPath {
        try? client.requestPath()
        if !spin(until: { client.hasPath },
                 msg: "Path to " + prettyDestination + " requested",
                 timeout: options.timeout) {
            print("Path not found")
            exit(Int32(RNXApp.Result.pathNotFound.rawValue))
        }
    }

    do {
        try client.openLinkIfNeeded()
    } catch {
        // Python does not check the recall result and silently builds a destination with
        // the wrong hash; Swift throws, which is mapped onto the same visible outcome.
        print("Could not establish link with " + prettyDestination)
        exit(Int32(RNXApp.Result.linkFailed.rawValue))
    }

    if !spin(until: { client.linkStatus == .active },
             msg: "Establishing link with " + prettyDestination,
             timeout: options.timeout) {
        print("Could not establish link with " + prettyDestination)
        exit(Int32(RNXApp.Result.linkFailed.rawValue))
    }

    try? client.identifyIfNeeded(noID: options.noID)

    var request = RNXRequest(command: command,
                             timeout: options.timeout,
                             stdoutLimit: options.stdoutLimit,
                             stderrLimit: options.stderrLimit,
                             stdin: stdin.map { Data($0.utf8) })
    // Python's defaulted -w reaches the wire as msgpack fixint 15.
    request.timeoutPacksAsInteger = options.timeoutWasDefaulted

    let rexecTimeout = RNXClient.rexecTimeout(commandTimeout: options.timeout,
                                              rtt: client.link?.rtt)

    let receipt: RequestReceipt
    do {
        receipt = try client.sendCommand(request, timeout: rexecTimeout) { progress, r in
            // Python: remote_execution_progress — rnx.py:304-321.
            session.recordProgress(progress, transferSize: r.responseTransferSize ?? 0)
        }
    } catch {
        print("Could not request remote execution")
        if interactive { return nil }
        exit(Int32(RNXApp.Result.requestFailed.rawValue))
    }

    // Python ignores this spin()'s return value, so a timeout here falls through to the
    // status checks rather than exiting. Note the predicate treats FAILED as "keep
    // spinning", so a failure is only noticed once the spinner times out.
    spin(until: {
            client.linkStatus == .closed
                || (!RNXClient.isFailed(receipt.status) && !RNXClient.isSent(receipt.status))
         },
         msg: "Sending execution request",
         timeout: rexecTimeout + 0.5)

    if client.linkStatus == .closed {
        print("Could not request remote execution, link was closed")
        exit(Int32(RNXApp.Result.requestFailed.rawValue))   // unconditional, even under -x
    }

    if receipt.isFailed {
        print("Could not request remote execution")
        if interactive { return nil }
        exit(Int32(RNXApp.Result.requestFailed.rawValue))
    }

    spin(until: { !RNXClient.isDelivered(receipt.status) },
         msg: "Command delivered, awaiting result",
         timeout: options.timeout)

    if receipt.isFailed {
        print("No result was received")
        if interactive { return nil }
        exit(Int32(RNXApp.Result.noResult.rawValue))
    }

    spinStat(until: { !RNXClient.isReceiving(receipt.status) }, timeout: options.resultTimeout)

    if receipt.isFailed {
        print("Receiving result failed")
        if interactive { return nil }
        exit(Int32(RNXApp.Result.receiveFailed.rawValue))
    }

    guard let responseData = receipt.response else {
        print("No response")
        if interactive { return nil }
        exit(Int32(RNXApp.Result.noResponse.rawValue))
    }

    let result: RNXResult
    do {
        result = try RNXResult(unpacking: try MsgPack.decode(responseData))
    } catch {
        print("Received invalid result")
        if interactive { return nil }
        exit(Int32(RNXApp.Result.invalidResult.rawValue))
    }

    guard result.executed else {
        // Python prints nothing else on this path — both output blocks are inside
        // `if executed:`.
        print("Remote could not execute command")
        if interactive { return nil }
        exit(Int32(RNXApp.Result.remoteExecFailed.rawValue))
    }

    let metrics = RNXResultRenderer.Metrics(requestSize: receipt.requestSize,
                                            responseSize: receipt.responseSize,
                                            sentAt: receipt.sentAt,
                                            responseConcludedAt: receipt.responseConcludedAt)
    let rendered = RNXResultRenderer.render(result: result,
                                            detailed: options.detailed,
                                            metrics: metrics,
                                            stdoutLimitArg: options.stdoutLimit,
                                            stderrLimitArg: options.stderrLimit)
    // Raw bytes, no trailing newline added. Python decodes as UTF-8 with no error handler
    // and tracebacks on binary output; writing raw bytes is better behaviour but means
    // binary payloads will not match Python byte for byte on stdout.
    if !rendered.stdoutBytes.isEmpty { writeOut(rendered.stdoutBytes) }
    if !rendered.stderrBytes.isEmpty { writeErr(rendered.stderrBytes) }
    fflush(stdout)
    if !rendered.trailer.isEmpty { print(rendered.trailer) }

    if !interactive { client.teardown() }

    if !interactive && options.mirror {
        if let code = result.returnCode {
            // Python passes the value to exit(), so a negative signal code (-15) is taken
            // mod 256 by the shell — which is exactly what exit(Int32) does here too.
            exit(Int32(truncatingIfNeeded: code))
        }
        exit(Int32(RNXApp.Result.mirrorNoReturnCode.rawValue))
    }
    if interactive { return options.mirror ? result.returnCode : nil }
    exit(0)
}

// MARK: - Interactive REPL

/// Python: rnx.py:611-664. Command history and cbreak mode are commented out there and
/// are not implemented here either.
func runREPL(_ options: Options) -> Never {
    var code: Int?
    while true {
        let prefix = (code != nil && code != 0) ? String(code!) : ""
        writeOut(prefix + "> ")
        // Python relies on input() flushing stdout; readLine() does not, so flush here.
        fflush(stdout)

        guard let command = readLine(strippingNewline: true) else {
            // EOFError (and an interrupted read) → exit(0).
            exit(0)
        }
        let lowered = command.lowercased()
        if lowered == "exit" || lowered == "quit" { exit(0) }
        if rnxInterrupted != 0 { handleInterruptIfNeeded() }
        if lowered == "clear" {
            writeOut("\u{1B}c")
            continue    // Python does not execute, and does not reset `code`
        }
        // Python passes stdin=None in interactive mode (rnx.py:658).
        code = runClient(options, command: command, stdin: nil, interactive: true)
    }
}

// MARK: - Entry point

struct rnx {
    static func main() {
        signal(SIGINT) { _ in rnxInterrupted = 1 }
        installPythonLogFormat()

        let options = parseOptions()

        // Python: rnx.py:580-590 — -p goes through listen() too, and exits 0 from inside.
        if options.listen || options.printIdentity {
            runListener(options)
        } else if options.destination != nil, let command = options.command {
            runClient(options, command: command, stdin: options.stdin,
                      interactive: options.interactive)
        }

        // Deliberately a separate statement, not an `elif` — `rnx <dest> <cmd> -x` runs the
        // command once and then drops into the REPL on the same Link (rnx.py:611).
        if options.destination != nil && options.interactive {
            runREPL(options)
        } else {
            print("")
            writeOut(RNXHelpText.help)
            print("")
        }
    }
}

rnx.main()
