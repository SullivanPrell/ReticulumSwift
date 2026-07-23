import Foundation
import ReticulumSwift
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// rnprobe — Reticulum Probe Utility.
//
// Python reference: RNS/Utilities/rnprobe.py, `main()` (rnprobe.py:209-249).
//
// This target does argument handling, stack bring-up, signal handling and exit codes and
// nothing else. Every byte of probe output, and all protocol work, lives in
// `NetworkProbe` inside the library, where it is drivable from XCTest with no terminal
// and no network.

/// Python: `--version` prints `rnprobe {RNS.__version__}`. The port prints the Swift
/// package version, following the rnsd precedent (Sources/rnsd/main.swift:47).
let VERSION = Reticulum.version
let APP_NAME = "rnprobe"

/// Retained so the SIGINT source can flip its cancellation flag.
/// Python: `except KeyboardInterrupt: print(""); exit()` (rnprobe.py:247-249).
nonisolated(unsafe) var runningProbe: NetworkProbe?

struct rnprobe {

    static func main() {
        let output = StandardProbeOutput()

        switch NetworkProbe.Arguments.parse(CommandLine.arguments) {

        case .help:
            // Python: argparse's -h action — print_help(), then exit 0.
            output.write(NetworkProbe.Arguments.helpText)
            output.flush()
            exit(0)

        case .missingDestination:
            // Python: rnprobe.py:231-234 — print(""), print_help(), print("").
            output.write("\n" + NetworkProbe.Arguments.helpText + "\n")
            output.flush()
            exit(0)

        case .version:
            output.write("\(APP_NAME) \(VERSION)\n")
            output.flush()
            exit(0)

        case .usageError(let detail):
            // Python: argparse's parser.error() — usage block then the message, on
            // stderr, exit 2. Note that 2 is also the packet-loss status; the collision
            // is inherited from Python and deliberately not "fixed".
            output.writeError(NetworkProbe.Arguments.usageErrorText(detail))
            output.flush()
            exit(2)

        case .run(let options):
            exit(run(options, output: output).rawValue)
        }
    }

    private static func run(_ options: NetworkProbe.Options,
                            output: StandardProbeOutput) -> NetworkProbe.Result {

        // Python validates the full name and the destination hash at rnprobe.py:45-67 —
        // all of it BEFORE `RNS.Reticulum(...)` at :77. Checking first here keeps a bad
        // command line from attaching to a running daemon at all.
        if let error = NetworkProbe.validate(options: options) {
            output.write(error.message + "\n")
            output.flush()
            return .ok
        }

        // Python: `RNS.Reticulum(configdir = configarg, loglevel = 3+verbosity)`, which
        // transparently becomes a local client when the shared-instance port is already
        // bound. `InstanceConnection` is the Swift equivalent of that opening move.
        let connection: InstanceConnection
        do {
            connection = try InstanceConnection.attach(configDirectory: options.configDir,
                                                       logLevel: options.logLevel)
        } catch {
            output.writeError("Could not start Reticulum: \(error)\n")
            output.flush()
            return .pathTimeout
        }

        // Apply the -v-derived level AFTER the stack is up: `Reticulum.start()` calls
        // `applyConfig()`, which overwrites `globalLogLevel` from the config file's
        // `loglevel` (default 4). Setting it beforehand is silently discarded.
        Reticulum.globalLogLevel = options.logLevel

        let network = TransportProbeNetwork(transport: connection.reticulum.transport,
                                            rpc: connection.rpc)
        let probe = NetworkProbe(network: network,
                                 clock: SystemProbeClock(),
                                 entropy: SecureProbeEntropy(),
                                 output: output)
        runningProbe = probe

        // Ctrl-C: flip the cooperative cancellation flag the wait loops poll. Signal
        // handling may only live here — the library must keep compiling for iOS, tvOS and
        // watchOS, where none of this exists.
        signal(SIGINT, SIG_IGN)
        let interrupts = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        interrupts.setEventHandler { runningProbe?.cancel() }
        interrupts.resume()

        // Python never shuts the stack down before exiting, and neither does this: the
        // jobs loop and any LocalInterface reconnect timer would otherwise delay process
        // exit. `exit()` in the caller tears everything down.
        return probe.run(options: options)
    }
}

rnprobe.main()
