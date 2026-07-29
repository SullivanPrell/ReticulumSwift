import Foundation
import ReticulumSwift

/// `rnsd` — the Reticulum Network Stack Daemon.
///
/// Python reference: `RNS/Utilities/rnsd.py`. This target does argument capture, printing,
/// signal handling and exit codes only; every decision it makes lives in
/// ``RNSDApp``, ``DaemonBootstrap`` and ``FileLogSink`` so it can be tested without a
/// terminal or a live network.

// MARK: - Output helpers

func writeStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

// MARK: - Argument handling

let argv = Array(CommandLine.arguments.dropFirst())

let options: RNSDApp.Options
do {
    options = try RNSDApp.parse(argv, allowServiceFlags: true)
} catch {
    // Python: argparse writes the usage block plus "prog: error: …" to stderr and exits 2.
    writeStderr(RNSDApp.errorText(program: RNSDApp.appName, allowServiceFlags: true, error: error))
    exit(RNSDApp.ExitCode.argumentError.rawValue)
}

if options.help {
    print(RNSDApp.helpText(program: RNSDApp.appName,
                           description: RNSDApp.description,
                           allowServiceFlags: true))
    exit(RNSDApp.ExitCode.ok.rawValue)
}

if options.version {
    print(RNSDApp.versionText(program: RNSDApp.appName))
    exit(RNSDApp.ExitCode.ok.rawValue)
}

// Python: handled before any Reticulum construction, before the config directory is even
// resolved, and before any directory is created (`rnsd.py:75-77`). `print()` adds the one
// newline that takes stdout to 14960 bytes.
if options.exampleConfig {
    print(Reticulum.exampleConfig)
    exit(RNSDApp.ExitCode.ok.rawValue)
}

// MARK: - program_setup

// Python: `targetverbosity = verbosity-quietness`, then `None` in service mode (`rnsd.py:41-47`).
let targetVerbosity = options.effectiveVerbosity

// `DaemonBootstrap.homeDirectory()` rather than `homeDirectoryForCurrentUser`, which
// ignores `$HOME`. Python resolves `~` with `os.path.expanduser`, which honours it.
let paths = DaemonBootstrap.Paths(
    configDir: DaemonBootstrap.resolveConfigDir(
        explicit: options.configDir,
        home: DaemonBootstrap.homeDirectory()))

// Python: `targetlogdest = RNS.LOG_FILE` under -s, otherwise `RNS.LOG_STDOUT` (`rnsd.py:43-47`).
// The log file lives at <configdir>/logfile, so the destination is chosen only once the
// config directory is known (`Reticulum.py:237-243`).
var fileSink: FileLogSink?
if options.service {
    let sink = FileLogSink(fileURL: paths.logFile)
    sink.install()
    fileSink = sink
} else {
    FileLogSink.installStdoutHandler()
}
_ = fileSink   // held for the process lifetime; the handler captures it weakly

// Python's module default until the config file is applied.
Reticulum.globalLogLevel = .notice

let bootstrapped: DaemonBootstrap.Bootstrapped
do {
    bootstrapped = try DaemonBootstrap.bootstrap(paths: paths, verbosity: targetVerbosity)
} catch {
    Reticulum.log("Could not create the Reticulum storage tree at \(paths.configDir.path): \(error)",
                  level: .error)
    Reticulum.log("Check your configuration file for errors!", level: .error)
    exit(RNSDApp.ExitCode.panic.rawValue)      // Python: RNS.panic() → os._exit(255)
}

if bootstrapped.createdDefaultConfig {
    // Python: `time.sleep(1.5)` so the operator sees the two notices (`Reticulum.py:333`).
    Thread.sleep(forTimeInterval: RNSDApp.defaultConfigNoticeDelay)
}

// Python: `Reticulum.py:337-338`, both newly visible once -v/-vv actually work.
// Python names its backend "internal" or "openssl"; this port is CryptoKit throughout.
Reticulum.log("Utilising cryptography backend \"cryptokit\"", level: .debug)
Reticulum.log("Configuration loaded from \(paths.configFile.path)", level: .verbose)

// MARK: - Bring up the stack

let connection: InstanceConnection
do {
    // Bind the shared-instance port FIRST so Python clients always see us as the server
    // before they get a chance to bind it themselves. Python's __start_local_interface()
    // first tries to *become* the server; if that fails it falls back to connecting as a
    // client. Binding 37428 before interface synthesis eliminates the race where Python
    // grabs 37428 and then conflicts with our TCPServerInterface on 42422.
    //
    // Interface synthesis is deliberately deferred: Python gates it on
    // `is_shared_instance or is_standalone_instance` (Reticulum.py:936), so a process that
    // attached to somebody else's shared instance must bring up no config interfaces at all.
    connection = try InstanceConnection.attach(configDirectory: paths.configDir,
                                               logLevel: bootstrapped.logLevel,
                                               synthesizeInterfaces: false)
} catch {
    // Python: `__start_local_interface` logs these two lines (Reticulum.py:436-437). It then
    // degrades to a standalone instance; this port cannot re-drive the bring-up from here, so
    // it panics instead — see the release notes.
    Reticulum.log("Local shared instance appears to be running, but it could not be connected",
                  level: .error)
    Reticulum.log("The contained exception was: \(error)", level: .error)
    exit(RNSDApp.ExitCode.panic.rawValue)
}

// `Reticulum.applyConfig` overwrites globalLogLevel from the config file during `start()`,
// which would silently undo -v/-q. Python treats the verbosity as a delta *on* that value
// (Reticulum.py:452-458), so re-assert the level the arithmetic produced.
Reticulum.globalLogLevel = bootstrapped.logLevel

if connection.role != .localClient {
    // Python: LOG_VERBOSE fences around interface synthesis (Reticulum.py:937, 950).
    Reticulum.log("Bringing up system interfaces...", level: .verbose)
    // Python logs this per skipped entry from inside the synthesis loop (Reticulum.py:1045).
    for interface in bootstrapped.config.interfaces where !interface.enabled {
        Reticulum.log("Skipping disabled interface \"\(interface.name)\"", level: .debug)
    }
    do {
        try connection.reticulum.synthesizeInterfaces(from: bootstrapped.config)
    } catch {
        // Python: two LOG_ERROR lines then RNS.panic() (Reticulum.py:1047-1051).
        Reticulum.log("The interface could not be created. Check your configuration file for errors!",
                      level: .error)
        Reticulum.log("The contained exception was: \(error)", level: .error)
        exit(RNSDApp.ExitCode.panic.rawValue)
    }
    Reticulum.log("System interfaces are ready", level: .verbose)
}

// Python: `rnsd.py:50-56`.
if connection.isConnectedToSharedInstance {
    Reticulum.log("Started rnsd version \(Reticulum.version) connected to another shared local "
                  + "instance, this is probably NOT what you want!", level: .warning)
} else {
    Reticulum.log("Started rnsd version \(Reticulum.version)", level: .notice)
}

if options.interactive {
    // Python drops into `code.interact(local=globals())` (`rnsd.py:58`). There is no embedded
    // interpreter in a Swift binary and no SPM dependency may be added, so the flag is
    // accepted and the daemon loop runs instead.
    Reticulum.log("Interactive mode is not available in the Swift port; continuing in daemon mode",
                  level: .warning)
}

// MARK: - Periodic persistence

// Python: `Reticulum.__jobs` checkpoints paths, known destinations and the hashlist on a
// timer (`Reticulum.py:369-386`). ReticulumSwift otherwise persists only from `stop()`, so a
// daemon that is killed loses everything learned since process start.
let persistTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
persistTimer.schedule(deadline: .now() + Reticulum.graciousPersistInterval,
                      repeating: Reticulum.graciousPersistInterval)
persistTimer.setEventHandler {
    DaemonBootstrap.persistState(of: connection.reticulum)
}
persistTimer.resume()

// MARK: - Signals

// Python: `signal.signal(SIGINT, sigint_handler)` / `SIGTERM` (`Reticulum.py:359-360`), both
// of which detach interfaces and call `RNS.exit()` → exit code 0. `RNS.exit()` is one-shot
// via a module-global flag, and `exit_handler` has its own guard on top of that; a SIGINT and
// a SIGTERM arriving together must not run the shutdown twice.
let shutdownLock = NSLock()
var shutdownRan = false

func performShutdown() {
    shutdownLock.lock()
    if shutdownRan { shutdownLock.unlock(); return }
    shutdownRan = true
    shutdownLock.unlock()

    persistTimer.cancel()
    connection.stop()
    // Python: `exit_handler` sets `RNS.loglevel = LOG_NONE` last, so late daemon threads
    // cannot print after teardown.
    Reticulum.globalLogLevel = .none
    exit(RNSDApp.ExitCode.ok.rawValue)
}

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler { performShutdown() }
sigintSource.resume()
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler { performShutdown() }
sigtermSource.resume()

// Python: `while True: time.sleep(1)` (`rnsd.py:60`).
dispatchMain()
