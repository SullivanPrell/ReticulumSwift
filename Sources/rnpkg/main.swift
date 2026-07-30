import Foundation
import ReticulumSwift

/// `rnpkg` — the Reticulum Meta Package Manager.
///
/// Python reference: `RNS/Utilities/rnpkg.py` (78 lines). Identical to `rnir` apart from its
/// program name, its description and its `--exampleconfig`, which prints rnpkg's own one-line
/// package-manager config rather than the RNS config.

func writeStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

let argv = Array(CommandLine.arguments.dropFirst())

let options: RNSDApp.Options
do {
    // Python: rnpkg declares no -s and no -i; both are rejected with exit 2.
    options = try RNSDApp.parse(argv, allowServiceFlags: false)
} catch {
    writeStderr(RNSDApp.errorText(program: RNSDApp.rnpkgAppName, allowServiceFlags: false, error: error))
    exit(RNSDApp.ExitCode.argumentError.rawValue)
}

if options.help {
    print(RNSDApp.helpText(program: RNSDApp.rnpkgAppName,
                           description: RNSDApp.rnpkgDescription,
                           allowServiceFlags: false))
    exit(RNSDApp.ExitCode.ok.rawValue)
}

if options.version {
    print(RNSDApp.versionText(program: RNSDApp.rnpkgAppName))
    exit(RNSDApp.ExitCode.ok.rawValue)
}

if options.exampleConfig {
    // Python: `print(__example_rnpkg_config__)` (`rnpkg.py:75-76`) — a single comment line,
    // 57 bytes with its newline, 58 on stdout once print() adds another.
    print(RNSDApp.rnpkgExampleConfig)
    exit(RNSDApp.ExitCode.ok.rawValue)
}

let paths = DaemonBootstrap.Paths(
    configDir: DaemonBootstrap.resolveConfigDir(
        explicit: options.configDir,
        // See the note in `rnir` — `homeDirectoryForCurrentUser` ignores `$HOME` (`bugs/024`).
        home: DaemonBootstrap.homeDirectory()))

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
    // See rnir for why interface synthesis is skipped.
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

// Python: `exit(0)` immediately after the constructor returns (`rnpkg.py:49`).
exit(RNSDApp.ExitCode.ok.rawValue)
