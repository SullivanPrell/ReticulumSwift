import Foundation
import ReticulumSwift
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// `rnpath` — the Reticulum Path Management Utility.
//
// Python reference: RNS/Utilities/rnpath.py (RNS 1.4.0). This file is argument parsing,
// printing and exit codes only; every decision, string and exit code lives in
// ReticulumSwift's RNPathApp / RNPathRunner so it can be asserted from XCTest.

// MARK: - Output sinks

/// Python's `print(x)` — one terminated line on stdout.
func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

/// Python's `print(x, end="")` / `end=" "` — raw, unterminated, flushed immediately.
func emitProgress(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

func emitError(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

/// The Braille spinner writes backspaces and raw glyphs. Python does that unconditionally,
/// which makes redirected output unusable for scripting; gating only the spinner on a TTY
/// is a deliberate, documented divergence. The clear strings stay ungated so `-R`/`-p`
/// output matches Python byte for byte.
let stdoutIsTTY = isatty(FileHandle.standardOutput.fileDescriptor) != 0

// MARK: - Ctrl-C

// Python wraps main() in `except KeyboardInterrupt:` → print("") then a bare exit() (code 0).
// A DispatchSource handler is used rather than signal(2) because print()/exit() are not
// async-signal-safe.
signal(SIGINT, SIG_IGN)
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interruptSource.setEventHandler {
    emit("")
    exit(RNPathApp.Result.ok.rawValue)
}
interruptSource.resume()

// MARK: - Argument declarations

var parser = ArgumentParser(program: RNPathApp.appName,
                            overview: "Reticulum Path Management Utility")
parser.option(["--config"], metavar: "CONFIG", help: "path to alternative Reticulum config directory")
parser.flag(["--version"], help: "show program's version number and exit")
parser.flag(["-t", "--table"], help: "show all known paths")
parser.option(["-m", "--max"], metavar: "hops", help: "maximum hops to filter path table by")
parser.flag(["-r", "--rates"], help: "show announce rate info")
parser.flag(["-d", "--drop"], help: "remove the path to a destination")
parser.flag(["-D", "--drop-announces"], help: "drop all queued announces")
parser.flag(["-x", "--drop-via"], help: "drop all paths via specified transport instance")
parser.option(["-w"], metavar: "seconds", help: "timeout before giving up")
parser.option(["-R"], metavar: "hash", help: "transport identity hash of remote instance to manage")
parser.option(["-i"], metavar: "path", help: "path to identity used for remote management")
parser.option(["-W"], metavar: "seconds", help: "timeout before giving up on remote queries")
parser.flag(["-b", "--blackholed"], help: "list blackholed identities")
parser.flag(["-B", "--blackhole"], help: "blackhole identity")
parser.flag(["-U", "--unblackhole"], help: "unblackhole identity")
parser.option(["--duration"], metavar: "DURATION", help: "duration of blackhole enforcement in hours")
parser.option(["--reason"], metavar: "REASON", help: "reason for blackholing identity")
parser.flag(["-p", "--blackholed-list"], help: "view published blackhole list for remote transport instance")
parser.flag(["-j", "--json"], help: "output in JSON format")
parser.counted(["-v", "--verbose"], help: "")
parser.positional("destination", help: "hexadecimal hash of the destination", required: false)
parser.positional("list_filter", help: "filter for remote blackhole list view", required: false)

let parsed: ParsedArguments
do {
    parsed = try parser.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    // argparse exits 2 on any parse error, printing usage plus a diagnostic to stderr.
    emitError(String(RNPathApp.helpText.split(separator: "\n", omittingEmptySubsequences: false)
                        .prefix(4).joined(separator: "\n")))
    emitError("\(RNPathApp.appName): error: \(error)")
    exit(RNPathApp.Result.usageError.rawValue)
}

// `-h`/`--help` is argparse's own action: the block with NO surrounding blank lines,
// exit 0, before any Reticulum initialisation.
if parsed.wantsHelp {
    emit(RNPathApp.helpText)
    exit(RNPathApp.Result.ok.rawValue)
}

// `--version` prints `rnpath <RNS version>` and exits 0 before anything else.
if parsed.flag("--version") {
    emit(RNPathApp.versionString)
    exit(RNPathApp.Result.ok.rawValue)
}

// MARK: - Options

/// argparse's `type=int` / `type=float` conversion failures are parse errors → exit 2,
/// with the message argparse itself prints: "argument -m/--max: invalid int value: 'x'".
func requireNumber<T>(_ raw: String?, flag: String, typeName: String,
                      convert: (String) -> T?) -> T? {
    guard let raw else { return nil }
    guard let value = convert(raw) else {
        emitError("\(RNPathApp.appName): error: argument \(flag): invalid \(typeName) value: '\(raw)'")
        exit(RNPathApp.Result.usageError.rawValue)
    }
    return value
}

var options = RNPathOptions()
options.configDirectory = parsed.value("--config").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
options.table = parsed.flag("--table")
options.rates = parsed.flag("--rates")
options.drop = parsed.flag("--drop")
options.dropAnnounces = parsed.flag("--drop-announces")
options.dropVia = parsed.flag("--drop-via")
options.blackholed = parsed.flag("--blackholed")
options.blackhole = parsed.flag("--blackhole")
options.unblackhole = parsed.flag("--unblackhole")
options.blackholedList = parsed.flag("--blackholed-list")
options.json = parsed.flag("--json")
options.remote = parsed.value("-R")
options.managementIdentityPath = parsed.value("-i")
options.blackholeReason = parsed.value("--reason")
options.verbosity = parsed.count("--verbose")
options.destination = parsed.positionals.count > 0 ? parsed.positionals[0] : nil
options.listFilter = parsed.positionals.count > 1 ? parsed.positionals[1] : nil

if let hops: Int = requireNumber(parsed.value("--max"), flag: "-m/--max", typeName: "int",
                                 convert: { Int($0) }) {
    // argparse accepts any int; Transport filters on a UInt8. Clamping keeps a nonsensical
    // value from wrapping — Python has no analogue because it never narrows.
    options.maxHops = UInt8(clamping: hops)
}
if let seconds: Double = requireNumber(parsed.value("-w"), flag: "-w", typeName: "float",
                                       convert: { Double($0) }) {
    options.timeout = seconds
}
if let seconds: Double = requireNumber(parsed.value("-W"), flag: "-W", typeName: "float",
                                       convert: { Double($0) }) {
    options.remoteTimeout = seconds
}
if let hours: Double = requireNumber(parsed.value("--duration"), flag: "--duration",
                                     typeName: "float", convert: { Double($0) }) {
    options.blackholeDuration = hours
}

// argparse rejects a third positional with "unrecognized arguments:" and exit 2.
if parsed.positionals.count > 2 {
    emitError("\(RNPathApp.appName): error: unrecognized arguments: "
              + parsed.positionals.dropFirst(2).joined(separator: " "))
    exit(RNPathApp.Result.usageError.rawValue)
}

// Python: the no-mode help gate wraps the same block in blank lines and falls out of main()
// with an implicit exit 0 — program_setup is never called.
if options.shouldPrintHelp {
    emit("")
    emit(RNPathApp.helpText)
    emit("")
    exit(RNPathApp.Result.ok.rawValue)
}

// MARK: - Attach

// Python: `RNS.Reticulum(configdir=configdir, loglevel=3+verbosity)`. rnpath does NOT pass
// require_shared_instance, so it must attach opportunistically and must not fail when no
// daemon is running.
let logLevel = Reticulum.LogLevel(rawValue: min(max(3 + options.verbosity, 0), 8)) ?? .notice

let connection: InstanceConnection
do {
    connection = try InstanceConnection.attach(configDirectory: options.configDirectory,
                                               requireSharedInstance: false,
                                               logLevel: logLevel,
                                               synthesizeInterfaces: true)
} catch {
    emit("Could not connect to Reticulum: \(error)")
    exit(RNPathApp.Result.setupFailure.rawValue)
}

// Reticulum.applyConfig assigns globalLogLevel from the config file during start(), so the
// explicit -v level has to be re-applied afterwards. Python's explicit loglevel argument
// always wins over the config key (Reticulum.py:301-305, 454).
Reticulum.globalLogLevel = logLevel

let management = RNPathApp.makeManagementSource(for: connection)
let transport = connection.reticulum.transport
let resolver = TransportPathResolver(transport: transport)

// Swift's LocalInterface connects asynchronously (an NWConnection reaching `.ready`),
// whereas Python's LocalClientInterface performs a blocking socket connect inside
// `Reticulum.__init__`. Without this settle the default mode's path request is emitted on
// an interface that is not up yet, is silently dropped, and the spinner then runs out the
// full -w timeout even for a destination the daemon knows. Bounded so an interface that
// never comes up cannot hang the CLI.
let settleDeadline = Date().addingTimeInterval(2)
while Date() < settleDeadline, transport.interfaces.contains(where: { !$0.isOnline }) {
    Thread.sleep(forTimeInterval: 0.05)
}

func finish(_ result: RNPathApp.Result) -> Never {
    connection.stop()
    exit(result.rawValue)
}

// MARK: - Remote management link (-R)

var remoteLink: Link?
var remoteClient: RNPathRemoteClient?

if let remoteHex = options.remote {
    let client = RNPathRemoteClient(transport: transport, pathRequestTimeout: options.remoteTimeout)
    remoteClient = client
    do {
        // Python derives the destination hash from the RAW identity hash, not a recalled
        // Identity object — and uses the "Destination …" wording for a bad argument.
        let identityHash = try RNPathApp.parseDestination(remoteHex)
        guard let identityPath = options.managementIdentityPath else {
            // Python: expanduser(None) → TypeError → exit 20 printing the TypeError text.
            throw RNPathRemoteClient.RemoteError.identityUnavailable("None")
        }
        let expanded = (identityPath as NSString).expandingTildeInPath
        guard let identity = Identity.fromFile(URL(fileURLWithPath: expanded)) else {
            throw RNPathRemoteClient.RemoteError.identityUnavailable(identityPath)
        }
        let remoteHash = RNPathRemoteClient.destinationHash(purpose: .management,
                                                           identityHash: identityHash)
        remoteLink = try client.connect(destinationHash: remoteHash,
                                        authIdentity: identity,
                                        purpose: .management,
                                        progress: emitProgress)
    } catch let error as RNPathApp.ParseError {
        emit(error.message)
        finish(.setupFailure)
    } catch let error as RNPathRemoteClient.RemoteError {
        // The whole -R setup block funnels every exception to print(str(e)) + exit(20),
        // except the path-request timeout, which exits 12 from inside connect_remote.
        emitProgress(RNPathApp.outputResetString)
        emit(error.message)
        finish(error == .pathRequestTimedOut ? .remotePathTimeout : .setupFailure)
    } catch {
        emit("\(error)")
        finish(.setupFailure)
    }
}

// MARK: - Run

let runner = RNPathRunner(
    options: options,
    management: management,
    resolver: resolver,
    remoteLinkPresent: remoteLink != nil,
    remoteRequest: { path, value in
        guard let link = remoteLink, let client = remoteClient else {
            throw RNPathRemoteClient.RemoteError.requestFailed
        }
        return try client.request(over: link, path: path, value: value,
                                  timeout: options.remoteTimeout)
    },
    blackholeListFetch: {
        // Python reuses the already-established management link here when both -R and -p are
        // given, because `remote_link` is non-nil and its spin-wait returns instantly
        // (rnpath.py:127 then 150-151). A fresh blackhole link is established instead — a
        // deliberate divergence from that bug.
        guard let hex = options.destination else { return nil }
        let identityHash = try RNPathApp.parseHash(hex)
        let client = remoteClient
            ?? RNPathRemoteClient(transport: transport, pathRequestTimeout: options.remoteTimeout)
        let remoteHash = RNPathRemoteClient.destinationHash(purpose: .blackhole,
                                                           identityHash: identityHash)
        let link = try client.connect(destinationHash: remoteHash,
                                      authIdentity: nil,
                                      purpose: .blackhole,
                                      progress: emitProgress)
        let response = try client.request(over: link,
                                          path: RNPathApp.blackholeListRequestPath,
                                          value: .nil,
                                          timeout: options.remoteTimeout)
        return RNPathRemoteClient.decodeBlackholeList(response)
    },
    output: emit,
    progress: emitProgress,
    spinner: stdoutIsTTY ? emitProgress : nil
)

finish(runner.run())
