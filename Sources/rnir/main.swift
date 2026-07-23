import Foundation
import ReticulumSwift

/// `rnir` — the Reticulum Distributed Identity Resolver.
///
/// Python reference: `RNS/Utilities/rnir.py` (79 lines). The tool is trivial: parse five
/// flags, construct `RNS.Reticulum(...)` and immediately `exit(0)`. Because RNS registers an
/// `atexit` handler, that exit runs the full shutdown — so the net effect is "resolve or
/// create the config directory, storage tree and default config, start Transport, then
/// persist and stop".

func writeStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

let argv = Array(CommandLine.arguments.dropFirst())

let options: RNSDApp.Options
do {
    // Python: rnir declares no -s and no -i; both are rejected with exit 2.
    options = try RNSDApp.parse(argv, allowServiceFlags: false)
} catch {
    writeStderr(RNSDApp.errorText(program: RNSDApp.rnirAppName, allowServiceFlags: false, error: error))
    exit(RNSDApp.ExitCode.argumentError.rawValue)
}

if options.help {
    print(RNSDApp.helpText(program: RNSDApp.rnirAppName,
                           description: RNSDApp.rnirDescription,
                           allowServiceFlags: false))
    exit(RNSDApp.ExitCode.ok.rawValue)
}

if options.version {
    print(RNSDApp.versionText(program: RNSDApp.rnirAppName))
    exit(RNSDApp.ExitCode.ok.rawValue)
}

if options.exampleConfig {
    // DIVERGENCE: `rnir.py:64` prints `__example_rns_config__`, a name rnir never defines —
    // the real tool raises NameError, dumps a traceback and exits 1. The port prints the RNS
    // example config and exits 0 rather than reproducing the crash.
    print(Reticulum.exampleConfig)
    exit(RNSDApp.ExitCode.ok.rawValue)
}

// Python: `targetverbosity = verbosity-quietness`; `service` can never be set here, so the
// log destination is always LOG_STDOUT (`rnir.py:41-47`).
let paths = DaemonBootstrap.Paths(
    configDir: DaemonBootstrap.resolveConfigDir(
        explicit: options.configDir,
        home: FileManager.default.homeDirectoryForCurrentUser))

FileLogSink.installStdoutHandler()
Reticulum.globalLogLevel = .notice

let bootstrapped: DaemonBootstrap.Bootstrapped
do {
    bootstrapped = try DaemonBootstrap.bootstrap(paths: paths, verbosity: options.effectiveVerbosity)
} catch {
    Reticulum.log("Could not create the Reticulum storage tree at \(paths.configDir.path): \(error)",
                  level: .error)
    exit(RNSDApp.ExitCode.panic.rawValue)
}

if bootstrapped.createdDefaultConfig {
    Thread.sleep(forTimeInterval: RNSDApp.defaultConfigNoticeDelay)
}

Reticulum.log("Utilising cryptography backend \"cryptokit\"", level: .debug)
Reticulum.log("Configuration loaded from \(paths.configFile.path)", level: .verbose)

do {
    // `synthesizeInterfaces: false`: rnir constructs a stack and immediately tears it down,
    // so opening every configured interface — an AutoInterface, a listening TCP server —
    // only to close it a moment later would be disruptive for no benefit. Python's own gate
    // (`Reticulum.py:936`) already skips synthesis whenever an instance is already running.
    let connection = try InstanceConnection.attach(configDirectory: paths.configDir,
                                                   logLevel: bootstrapped.logLevel,
                                                   synthesizeInterfaces: false)
    Reticulum.globalLogLevel = bootstrapped.logLevel
    connection.stop()
} catch {
    Reticulum.log("Local shared instance appears to be running, but it could not be connected",
                  level: .error)
    Reticulum.log("The contained exception was: \(error)", level: .error)
    exit(RNSDApp.ExitCode.panic.rawValue)
}

// Python: `exit(0)` immediately after the constructor returns (`rnir.py:50`).
exit(RNSDApp.ExitCode.ok.rawValue)
