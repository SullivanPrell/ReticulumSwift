import Foundation
import ReticulumSwift

// rncp — Reticulum File Transfer Utility.
//
// Python reference: RNS/Utilities/rncp.py.
//
// This file is deliberately thin: argument parsing, terminal rendering (ANSI erase, the
// Braille spinner, exact space counts), SIGINT handling and exit codes. Every protocol,
// file-system and formatting decision lives in ReticulumSwift's RNCopy* types so it can be
// unit-tested with no terminal and no network.

// MARK: - Terminal helpers

/// `erase_str = "\33[2K\r"` (rncp.py:73).
let ERASE = RNCopyApp.eraseString
/// `es = " "` — the single space appended by `print(end=es)` (rncp.py:72).
let ES = RNCopyApp.endSpace

/// `print(..., end=terminator)` + flush. Python flushes explicitly in every progress path.
func emit(_ text: String, terminator: String = "\n") {
    print(text, terminator: terminator)
    fflush(stdout)
}

/// One spinner cell, advanced modulo 7 exactly as Python does.
final class Spinner {
    private var index = 0
    var frame: Character { RNCopyApp.spinnerFrames[index] }
    func advance() { index = (index + 1) % RNCopyApp.spinnerFrames.count }
    /// Python: `print(("\b\b"+syms[i]+" "), end="")` — two backspaces, frame, space.
    func tick() {
        emit("\u{8}\u{8}\(frame) ", terminator: "")
        advance()
    }
}

let spinner = Spinner()

func prettyHex(_ hash: Data) -> String { RNSUtilities.prettyhexrep(hash) }

// MARK: - Argument parsing

let rawArguments = Array(CommandLine.arguments.dropFirst())
let parser = RNCopyApp.makeArgumentParser()

let arguments: ParsedArguments
do {
    arguments = try parser.parse(rawArguments)
} catch {
    // argparse writes usage + "prog: error: …" to stderr and exits 2.
    FileHandle.standardError.write(Data("\(RNCopyApp.helpText.split(separator: "\n\n")[0])\n".utf8))
    FileHandle.standardError.write(Data("rncp: error: \(error)\n".utf8))
    exit(2)
}

if arguments.wantsHelp {
    emit(RNCopyApp.helpText)
    exit(0)
}

if arguments.flag("--version") {
    emit("rncp \(Reticulum.version)")
    exit(0)
}

let verbosity = arguments.count("--verbose")
let quietness = arguments.count("--quiet")
let silent = arguments.flag("--silent")
let showPhyRates = arguments.flag("--phy-rates")
let noCompress = arguments.flag("--no-compress")
let allowOverwrite = arguments.flag("--overwrite")
let wantsListen = arguments.flag("--listen")
let wantsFetch = arguments.flag("--fetch")
let printIdentity = arguments.flag("--print-identity")
let noAuth = arguments.flag("--no-auth")
let allowFetch = arguments.flag("--allow-fetch")
let jailArgument = arguments.value("--jail")
let saveArgument = arguments.value("--save")
let identityArgument = arguments.value("-i")
let configArgument = arguments.value("--config")
// argparse: type=int, default=-1. A non-integer value would be a parser error upstream.
let announceInterval = Int(arguments.value("-b") ?? "-1") ?? -1
// argparse: type=float, default=RNS.Transport.PATH_REQUEST_TIMEOUT.
let timeout = Double(arguments.value("-w") ?? "") ?? Transport.pathRequestTimeout
// argparse: action="append". The shared parser has no append action, so collect by hand.
let allowedArguments = RNCopyApp.collectRepeatedOption("-a", in: rawArguments)

// Positionals are FILE first, DESTINATION second in every mode (in fetch mode FILE is the
// remote path on the listener).
let fileArgument: String? = arguments.positionals.count > 0 ? arguments.positionals[0] : nil
let destinationArgument: String? = arguments.positionals.count > 1 ? arguments.positionals[1] : nil

let fileSystem = RNCopyDiskFileSystem()
let logLevel = RNCopyApp.logLevel(verbosity: verbosity, quietness: quietness)

// MARK: - Shared bring-up

func printHelpAndExit() -> Never {
    // Python: print(""); parser.print_help(); print("")
    emit("")
    emit(RNCopyApp.helpText)
    emit("")
    exit(0)
}

/// Bring up the Reticulum stack the way `RNS.Reticulum(configdir=…, loglevel=…)` does.
func startReticulum() -> InstanceConnection {
    // Reticulum.Configuration.logLevel is stored but never applied by start(), so assign
    // the global here — exactly as Sources/rnsd/main.swift does.
    Reticulum.globalLogLevel = logLevel
    do {
        return try InstanceConnection.attach(
            configDirectory: configArgument.map { URL(fileURLWithPath: RNCopyApp.expandUser($0, home: fileSystem.homeDirectoryPath)) },
            requireSharedInstance: false,
            logLevel: logLevel,
            synthesizeInterfaces: true
        )
    } catch {
        emit("Could not start Reticulum: \(error)")
        exit(RNCopyApp.Result.generalError.code)
    }
}

/// Load or create the rncp identity. Python: `prepare_identity` (rncp.py:54-68).
func prepareIdentity(connection: InstanceConnection) -> Identity {
    let url: URL
    if let identityArgument {
        url = URL(fileURLWithPath: RNCopyApp.expandUser(identityArgument, home: fileSystem.homeDirectoryPath))
    } else {
        url = RNCopyApp.defaultIdentityPath(
            storagePath: InstanceConnection.storagePath(for: connection.configDirectory))
    }
    do {
        return try RNCopyApp.prepareIdentity(at: url)
    } catch let error as RNCopyApp.IdentityError {
        Reticulum.log(error.message, level: .error)
        exit(RNCopyApp.Result.identityError.code)
    } catch {
        Reticulum.log("\(error)", level: .error)
        exit(RNCopyApp.Result.identityError.code)
    }
}

/// Validate the `destination` positional. Python prints the ValueError text and exits 1.
func decodeDestination(_ value: String) -> Data {
    do {
        return try RNCopyApp.decodeDestinationArgument(value)
    } catch let error as RNCopyApp.AllowedIdentityError {
        emit(error.message)
        exit(RNCopyApp.Result.generalError.code)
    } catch {
        emit("\(error)")
        exit(RNCopyApp.Result.generalError.code)
    }
}

/// `--save` validation, shared by listen and fetch. Python: rncp.py:96-108 / 365-375.
func resolveSaveDirectory(_ value: String) -> String {
    switch RNCopyApp.resolveSaveDirectory(value, fileSystem: fileSystem) {
    case .ok(let path):
        return path
    case .notWritable:
        Reticulum.log("Output directory not writable", level: .error)
        exit(RNCopyApp.Result.outputDirNotWritable.code)
    case .notFound:
        Reticulum.log("Output directory not found", level: .error)
        exit(RNCopyApp.Result.outputDirNotFound.code)
    }
}

// MARK: - SIGINT

/// Python's handler prints "", cancels the resource, tears the link down and exits 0. It is
/// also an upstream bug: `resource` is not a module global, so it raises NameError. The
/// intended behaviour is implemented here.
final class InterruptTarget {
    var cancel: (() -> Void)?
}
let interruptTarget = InterruptTarget()
signal(SIGINT, SIG_IGN)
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
interruptSource.setEventHandler {
    emit("")
    interruptTarget.cancel?()
    exit(RNCopyApp.Result.ok.code)
}
interruptSource.resume()

// MARK: - listen()

func runListen() -> Never {
    let connection = startReticulum()

    // Python: fetch_jail = os.path.abspath(os.path.expanduser(jail))
    var fetchJail: String?
    if let jailArgument {
        let resolved = RNCopyApp.absolutePath(
            RNCopyApp.expandUser(jailArgument, home: fileSystem.homeDirectoryPath),
            cwd: fileSystem.currentDirectoryPath)
        fetchJail = resolved
        Reticulum.log("Restricting fetch requests to paths under \"\(resolved)\"", level: .verbose)
    }

    // This block runs BEFORE prepare_identity, so `-p -s /bad` exits 3/4 rather than
    // printing the identity.
    var savePath: String?
    if let saveArgument {
        let resolved = resolveSaveDirectory(saveArgument)
        savePath = resolved
        Reticulum.log("Saving received files in \"\(resolved)\"", level: .verbose)
    }

    let identity = prepareIdentity(connection: connection)

    let listener: RNCopyListener
    do {
        listener = try RNCopyListener(
            transport: connection.reticulum.transport,
            fileSystem: fileSystem,
            configuration: RNCopyListener.Configuration(identity: identity))
    } catch {
        emit("Could not create rncp destination: \(error)")
        exit(RNCopyApp.Result.generalError.code)
    }

    if printIdentity {
        // Python: print("Identity     : "+str(identity)) — str(identity) is prettyhexrep.
        emit("Identity     : " + prettyHex(identity.hash))
        emit("Listening on : " + prettyHex(listener.destination.hash))
        exit(RNCopyApp.Result.ok.code)
    }

    // ---- Allowed identities -------------------------------------------------------
    var allowAll = false
    var allowedIdentityHashes: Set<Data> = []

    if noAuth {
        // -n skips the entire allowed-identities block; no file is read at all.
        allowAll = true
    } else {
        // Python wraps locating/reading/parsing in one try/except that only logs and
        // continues; the merge, count and plural rules live in the library so they are
        // covered by RNCopyAllowedIdentitiesTests.
        let load = RNCopyApp.loadAllowedIdentities(commandLineEntries: allowedArguments,
                                                   fileSystem: fileSystem)
        if let failure = load.failure {
            Reticulum.log("Error while parsing allowed_identities file. The contained exception was: \(failure)",
                          level: .error)
        }
        if let message = load.logMessage { Reticulum.log(message, level: .verbose) }

        for entry in load.merged {
            do {
                allowedIdentityHashes.insert(try RNCopyApp.decodeAllowedIdentity(entry))
            } catch let error as RNCopyApp.AllowedIdentityError {
                Reticulum.log("Could not apply allowed identity: \(error.message)", level: .error)
                exit(RNCopyApp.Result.generalError.code)
            } catch {
                Reticulum.log("Could not apply allowed identity: \(error)", level: .error)
                exit(RNCopyApp.Result.generalError.code)
            }
        }
    }

    if allowedIdentityHashes.isEmpty && !noAuth {
        Reticulum.log("No allowed identities configured, rncp will not accept any files!",
                      level: .warning)
    }

    listener.configuration = RNCopyListener.Configuration(
        identity: identity,
        allowedIdentityHashes: allowedIdentityHashes,
        allowAll: allowAll,
        allowFetch: allowFetch,
        fetchAutoCompress: !noCompress,
        allowOverwriteOnReceive: allowOverwrite,
        fetchJail: fetchJail,
        savePath: savePath)

    listener.start()

    // Upstream quirk (rncp.py:86-87, 222-230): `-b` defaults to -1, which `listen()` turns
    // into Python `False`, and `False >= 0` is True — so the announce thread ALWAYS starts
    // and rncp always emits one announce at startup. Reproduced deliberately.
    DispatchQueue.global(qos: .utility).async {
        try? listener.announce()
        if announceInterval > 0 {
            while true {
                Thread.sleep(forTimeInterval: TimeInterval(announceInterval))
                try? listener.announce()
            }
        }
    }

    // Python: while True: time.sleep(1)
    dispatchMain()
}

// MARK: - send()

func runSend(file: String, destination: String) -> Never {
    let destinationHash = decodeDestination(destination)
    let prettyDestination = prettyHex(destinationHash)

    // Python checks the local file BEFORE Reticulum is started.
    let filePath = RNCopyApp.expandUser(file, home: fileSystem.homeDirectoryPath)
    guard fileSystem.fileExists(atPath: filePath) else {
        emit("File not found")
        exit(RNCopyApp.Result.generalError.code)
    }

    // Python: print(f"{erase_str}", end="") — send only; fetch does not do this.
    emit(ERASE, terminator: "")

    let connection = startReticulum()
    let identity = prepareIdentity(connection: connection)

    let sender = RNCopySender(
        transport: connection.reticulum.transport,
        fileSystem: fileSystem,
        configuration: RNCopySender.Configuration(identity: identity,
                                                  destinationHash: destinationHash,
                                                  filePath: file,
                                                  timeout: timeout,
                                                  autoCompress: !noCompress))
    interruptTarget.cancel = { [weak sender] in sender?.cancel() }

    sender.onTick = { if !silent { spinner.tick() } }

    sender.onStage = { stage in
        switch stage {
        case .requestingPath:
            if silent { emit("Path to \(prettyDestination) requested") }
            else      { emit("Path to \(prettyDestination) requested  ", terminator: ES) }
        case .establishingLink:
            if silent { emit("Establishing link with \(prettyDestination)") }
            // NOTE: send appends ONE literal space here; fetch appends TWO.
            else      { emit("\(ERASE)Establishing link with \(prettyDestination) ", terminator: ES) }
        case .advertising:
            if silent { emit("Advertising file resource...") }
            else      { emit("\(ERASE)Advertising file resource  ", terminator: ES) }
        case .transferring:
            if silent { emit("Transferring file...") }
            else      { emit("\(ERASE)Transferring file  ", terminator: ES) }
        case .requestingFile, .waitingForTransfer:
            break
        }
    }

    sender.onProgress = { progress in
        guard !silent else { return }
        // Python's send-mode phy suffix is gated on `show_phy_rates and not resource_done`.
        let phy = (showPhyRates && !progress.done) ? progress.phySpeed : nil
        let stat = RNCopyApp.transferStat(progress: progress.fraction,
                                          totalSize: progress.totalBytes,
                                          speed: progress.speed,
                                          phySpeed: phy)
        // `progress_update` shadows the global `es` with a TWO-space local (rncp.py:754).
        if progress.done {
            emit("\(ERASE)Transfer complete  \(stat)", terminator: "  ")
        } else {
            emit("\(ERASE)Transferring file \(spinner.frame) \(stat)", terminator: "  ")
            spinner.advance()
        }
    }

    switch sender.run() {
    case .fileNotFound:
        emit("File not found")
        exit(RNCopyApp.Result.generalError.code)

    case .pathNotFound:
        if silent { emit("Path not found") } else { emit("\(ERASE)Path not found") }
        exit(RNCopyApp.Result.generalError.code)

    case .linkTimedOut:
        let message = "Link establishment with \(prettyDestination) timed out"
        if silent { emit(message) } else { emit("\(ERASE)\(message)") }
        exit(RNCopyApp.Result.generalError.code)

    case .noPathFound:
        let message = "No path found to \(prettyDestination)"
        if silent { emit(message) } else { emit("\(ERASE)\(message)") }
        exit(RNCopyApp.Result.generalError.code)

    case .identityUnknown:
        // Python raises an unhandled exception in Destination.__init__ here; reporting it
        // cleanly and exiting 1 is a deliberate improvement.
        let message = "No known identity for \(prettyDestination)"
        if silent { emit(message) } else { emit("\(ERASE)\(message)") }
        exit(RNCopyApp.Result.generalError.code)

    case .startFailed(let reason):
        emit("Could not start transfer: \(reason)")
        exit(RNCopyApp.Result.generalError.code)

    case .notAccepted:
        let message = "File was not accepted by \(prettyDestination)"
        if silent { emit(message) } else { emit("\(ERASE)\(message)") }
        exit(RNCopyApp.Result.generalError.code)

    case .transferFailed:
        if silent { emit("The transfer failed") } else { emit("\(ERASE)The transfer failed") }
        exit(RNCopyApp.Result.generalError.code)

    case .completed:
        // Python prints the LOCAL expanded path here (unlike fetch, which prints the remote).
        let message = "\(sender.expandedFilePath) copied to \(prettyDestination)"
        if silent { emit(message) } else { emit("\n" + message) }
        sender.teardown()
        Thread.sleep(forTimeInterval: 0.25)
        exit(RNCopyApp.Result.ok.code)
    }
}

// MARK: - fetch()

func runFetch(file: String, destination: String) -> Never {
    // Python validates --save FIRST (rncp.py:365-375) and only then the destination
    // argument, so a bad directory exits 3/4 even when the destination is also invalid.
    var savePath: String?
    if let saveArgument { savePath = resolveSaveDirectory(saveArgument) }

    let destinationHash = decodeDestination(destination)
    let prettyDestination = prettyHex(destinationHash)

    let connection = startReticulum()
    let identity = prepareIdentity(connection: connection)

    let fetcher = RNCopyFetcher(
        transport: connection.reticulum.transport,
        fileSystem: fileSystem,
        configuration: RNCopyFetcher.Configuration(identity: identity,
                                                   destinationHash: destinationHash,
                                                   remotePath: file,
                                                   timeout: timeout,
                                                   savePath: savePath,
                                                   allowOverwrite: allowOverwrite))
    interruptTarget.cancel = { [weak fetcher] in fetcher?.cancel() }

    fetcher.onTick = { if !silent { spinner.tick() } }
    fetcher.onNotice = { emit($0) }

    fetcher.onStage = { stage in
        switch stage {
        case .requestingPath:
            if silent { emit("Path to \(prettyDestination) requested") }
            else      { emit("Path to \(prettyDestination) requested  ", terminator: ES) }
        case .establishingLink:
            if silent { emit("Establishing link with \(prettyDestination)") }
            // NOTE: fetch appends TWO literal spaces here; send appends ONE.
            else      { emit("\(ERASE)Establishing link with \(prettyDestination)  ", terminator: ES) }
        case .requestingFile:
            if silent { emit("Requesting file from remote...") }
            else      { emit("\(ERASE)Requesting file from remote  ", terminator: ES) }
        case .advertising, .transferring, .waitingForTransfer:
            break
        }
    }

    fetcher.onWaiting = {
        guard !silent else { return }
        emit("\(ERASE)Waiting for transfer to start \(spinner.frame) ", terminator: ES)
        spinner.advance()
    }

    fetcher.onProgress = { progress in
        guard !silent else { return }
        // Python's fetch-mode phy suffix has no "and not done" clause, unlike send.
        let phy = showPhyRates ? progress.phySpeed : nil
        if progress.done {
            let stat = RNCopyApp.transferStat(progress: progress.fraction,
                                              totalSize: progress.totalBytes,
                                              speed: progress.speed,
                                              phySpeed: phy,
                                              elapsed: progress.elapsed)
            emit("\(ERASE)Transfer complete  \(stat)", terminator: ES)
        } else {
            let stat = RNCopyApp.transferStat(progress: progress.fraction,
                                              totalSize: progress.totalBytes,
                                              speed: progress.speed,
                                              phySpeed: phy)
            emit("\(ERASE)Transferring file \(spinner.frame) \(stat)", terminator: ES)
            spinner.advance()
        }
    }

    /// Every failed-request branch erases, prints, tears down, sleeps 0.15 and exits **0**.
    func concludeRequestFailure(_ message: String) -> Never {
        if !silent { emit(ERASE, terminator: "") }
        emit(message)
        fetcher.teardown()
        Thread.sleep(forTimeInterval: 0.15)
        exit(RNCopyApp.Result.ok.code)
    }

    switch fetcher.run() {
    case .pathNotFound:
        if silent { emit("Path not found") } else { emit("\(ERASE)Path not found") }
        exit(RNCopyApp.Result.generalError.code)

    case .linkFailed:
        let message = "Could not establish link with \(prettyDestination)"
        if silent { emit(message) } else { emit("\(ERASE)\(message)") }
        exit(RNCopyApp.Result.generalError.code)

    case .identityUnknown:
        let message = "No known identity for \(prettyDestination)"
        if silent { emit(message) } else { emit("\(ERASE)\(message)") }
        exit(RNCopyApp.Result.generalError.code)

    case .requestFailed(let status):
        switch status {
        case .fetchNotAllowed:
            concludeRequestFailure("Fetch request failed, fetching the file \(file) was not allowed by the remote")
        case .notFound:
            concludeRequestFailure("Fetch request failed, the file \(file) was not found on the remote")
        case .remoteError:
            concludeRequestFailure("Fetch request failed due to an error on the remote system")
        case .unknown, .found:
            concludeRequestFailure("Fetch request failed due to an unknown error (probably not authorised)")
        }

    case .transferFailed:
        if silent { emit("The transfer failed") } else { emit("\(ERASE)The transfer failed") }
        exit(RNCopyApp.Result.generalError.code)

    case .saveFailed, .completed:
        // The resource itself completed. Python's save-failure paths early-return without
        // resolving and hang; the diagnostic has already been printed via onNotice, and the
        // intended final line is this one. Python prints the REMOTE path here.
        let message = "\(file) fetched from \(prettyDestination)"
        if silent { emit(message) } else { emit("\n" + message) }
        fetcher.teardown()
        Thread.sleep(forTimeInterval: 0.1)
        exit(RNCopyApp.Result.ok.code)
    }
}

// MARK: - main dispatch (rncp.py:822-877)

if wantsListen || printIdentity {
    runListen()
} else if wantsFetch {
    if let destinationArgument, let fileArgument {
        runFetch(file: fileArgument, destination: destinationArgument)
    } else {
        printHelpAndExit()
    }
} else if let destinationArgument, let fileArgument {
    runSend(file: fileArgument, destination: destinationArgument)
} else {
    printHelpAndExit()
}
