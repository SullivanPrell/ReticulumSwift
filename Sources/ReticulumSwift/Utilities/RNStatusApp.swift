import Foundation

/// Constants and value types mirroring `RNS/Utilities/rnstatus.py`
/// (Reticulum Network Stack Status).
///
/// `rnstatus` prints the state of a running Reticulum instance: per-interface
/// traffic / announce / path-request / radio statistics, optional traffic totals, the link
/// count and a transport-instance footer — plus two side modes (`-d`/`-D` list discovered
/// interfaces, `-R` fetches status from a remote transport instance over a `Link`).
///
/// Everything terminal-facing (printing, `exit`, ANSI clear, SIGINT) lives in
/// `Sources/rnstatus/main.swift`. This type holds only the constants and the exit-code /
/// sort-key vocabulary, so the whole rendering layer stays unit-testable.
public enum RNStatusApp {

    // MARK: - Identity

    /// Executable name. Python: `argparse.ArgumentParser(prog=…)` defaults to `sys.argv[0]`.
    public static let appName: String = "rnstatus"

    /// One-line description printed above the option list.
    /// Python: `description="Reticulum Network Stack Status"` (rnstatus.py:689).
    public static let description: String = "Reticulum Network Stack Status"

    // MARK: - Remote management destination

    /// Dotted full name of the remote-management destination.
    /// Python: `RNS.Destination.hash_from_name_and_identity("rnstransport.remote.management", …)`
    /// (rnstatus.py:319).
    public static let remoteManagementFullName: String = "rnstransport.remote.management"

    /// App name half of the remote-management destination. Python: `Transport.APP_NAME`.
    public static let remoteManagementAppName: String = "rnstransport"

    /// Aspects half of the remote-management destination (rnstatus.py:137).
    public static let remoteManagementAspects: [String] = ["remote", "management"]

    /// Request path served by `Transport.remote_status_handler` (Transport.py:2849).
    public static let statusRequestPath: String = "/status"

    // MARK: - Timing

    /// Default `-w`. Python: `RNS.Transport.PATH_REQUEST_TIMEOUT` = 15 (Transport.py:79).
    public static let defaultRemoteTimeout: TimeInterval = Transport.pathRequestTimeout

    /// Default `-I`. Python: `default=1.0` (rnstatus.py:708).
    public static let defaultMonitorInterval: TimeInterval = 1.0

    /// Monitor-mode sleep floor. Python: `max(args.monitor_interval-td, 0.2)` (rnstatus.py:746).
    public static let minimumMonitorSleep: TimeInterval = 0.2

    // MARK: - Wire / display constants

    /// Required length of the `-R` argument, in hex characters.
    /// Python: `(RNS.Reticulum.TRUNCATED_HASHLENGTH//8)*2` = 32 (rnstatus.py:315).
    public static let destinationHexLength: Int = (Constants.truncatedHashLengthBits / 8) * 2

    /// The progress-erase sequence printed eight times while `-R` is negotiating.
    /// Python: `print("\r" + 58 spaces + "\r", end="")` (rnstatus.py:80, 90, 94, 98, 105, 124, 132, 151).
    public static let eraseSequence: String = "\r" + String(repeating: " ", count: 58) + "\r"

    /// Cursor-home + clear-screen emitted at the top of every monitor refresh.
    /// Python: `print("\033[H\033[2J", end="")` (rnstatus.py:742).
    public static let clearScreen: String = "\u{1b}[H\u{1b}[2J"

    /// Floor for the frequency/traffic column width. Python: `max(…, 10)` (rnstatus.py:618).
    public static let minimumColumnWidth: Int = 10

    /// Indent of every wrapped second line in the Path Rqs./Announces/Traffic blocks.
    /// Python: 16 literal spaces (rnstatus.py:628, 632, 640, 661).
    public static let continuationIndent: String = String(repeating: " ", count: 16)

    /// Width of the `-d` table's horizontal rule. Python: `print("-" * 89)` (rnstatus.py:266).
    public static let discoveredTableRuleWidth: Int = 89

    /// Width of the `-D` between-entry separator. Python: `"="*32` (rnstatus.py:234).
    public static let detailSeparatorWidth: Int = 32

    /// Base log level; the effective level is `baseLogLevel + verbosity`.
    /// Python: `loglevel=3+verbosity` where 3 is `RNS.LOG_NOTICE` (rnstatus.py:167).
    public static let baseLogLevel: Int = 3

    // MARK: - speed_str

    /// Human-readable bit rate, matching `speed_str` in rnstatus.py:760.
    ///
    /// This is deliberately **not** ``RNSUtilities/prettyspeed(_:)``: `speed_str` uses a
    /// lowercase `k` for kilo where `RNS.prettyspeed` (via `prettysize`) uses `K`, and it
    /// prints two decimals at every magnitude including the base unit. Verified against
    /// the live Python: `speed_str(9600) == "9.60 kbps"` but
    /// `RNS.prettyspeed(9600) == "9.60 Kbps"`.
    ///
    /// Forwards to ``UtilityFormatting/speedStr(_:suffix:)``, which is the shared
    /// implementation of the identical helper found in rnstatus, rncp and rnx.
    public static func speedStr(_ num: Double, suffix: String = "bps") -> String {
        UtilityFormatting.speedStr(num, suffix: suffix)
    }

    // MARK: - Command line

    /// The `rnstatus` option table, built on the house ``ArgumentParser``.
    ///
    /// Every spelling here is part of the user-facing contract and is asserted in
    /// `RNStatusAppTests`. `-D`, `-R`, `-i` and `-w` deliberately have no long form,
    /// matching Python.
    public static func makeParser() -> ArgumentParser {
        var parser = ArgumentParser(program: appName, overview: description)
        parser.option(["--config"], metavar: "CONFIG", help: "path to alternative Reticulum config directory")
        parser.flag(["--version"], help: "show program's version number and exit")
        parser.flag(["-a", "--all"], help: "show all interfaces")
        parser.flag(["-A", "--announce-stats"], help: "show announce stats")
        parser.flag(["-P", "--pr-stats"], help: "show path request stats")
        parser.flag(["-l", "--link-stats"], help: "show link stats")
        parser.flag(["-B", "--burst"], help: "only show interfaces with active bursts")
        parser.flag(["-t", "--totals"], help: "display traffic totals")
        parser.option(["-s", "--sort"], metavar: "SORT",
                      help: "sort interfaces by [rate, traffic, rx, tx, rxs, txs, announces, arx, atx, prx, ptx, held]")
        parser.flag(["-r", "--reverse"], help: "reverse sorting")
        parser.flag(["-j", "--json"], help: "output in JSON format")
        parser.option(["-R"], metavar: "hash",
                      help: "transport identity hash of remote instance to get status from")
        parser.option(["-i"], metavar: "path", help: "path to identity used for remote management")
        parser.option(["-w"], metavar: "seconds", help: "timeout before giving up on remote queries")
        parser.flag(["-d", "--discovered"], help: "list discovered interfaces")
        parser.flag(["-D"], help: "show details and config entries for discovered interfaces")
        parser.flag(["-m", "--monitor"], help: "continuously monitor status")
        parser.option(["-I", "--monitor-interval"], metavar: "seconds",
                      help: "refresh interval for monitor mode (default: 1)")
        parser.counted(["-v", "--verbose"], help: "")
        parser.positional("filter", help: "only display interfaces with names including filter", required: false)
        return parser
    }

    /// `--help` output, transcribed byte for byte from the installed Python utility.
    ///
    /// The house ``ArgumentParser`` generates a usage block of its own, but its layout is
    /// not argparse's (it pads the option column to 26 rather than 24 and does not wrap the
    /// `usage:` line across the declared flags). Since the help text is user-facing output
    /// like everything else in this port, it is reproduced literally instead.
    public static let helpText: String = """
    usage: rnstatus [-h] [--config CONFIG] [--version] [-a] [-A] [-P] [-l] [-B]
                    [-t] [-s SORT] [-r] [-j] [-R hash] [-i path] [-w seconds] [-d]
                    [-D] [-m] [-I seconds] [-v]
                    [filter]

    Reticulum Network Stack Status

    positional arguments:
      filter                only display interfaces with names including filter

    options:
      -h, --help            show this help message and exit
      --config CONFIG       path to alternative Reticulum config directory
      --version             show program's version number and exit
      -a, --all             show all interfaces
      -A, --announce-stats  show announce stats
      -P, --pr-stats        show path request stats
      -l, --link-stats      show link stats
      -B, --burst           only show interfaces with active bursts
      -t, --totals          display traffic totals
      -s SORT, --sort SORT  sort interfaces by [rate, traffic, rx, tx, rxs, txs,
                            announces, arx, atx, prx, ptx, held]
      -r, --reverse         reverse sorting
      -j, --json            output in JSON format
      -R hash               transport identity hash of remote instance to get
                            status from
      -i path               path to identity used for remote management
      -w seconds            timeout before giving up on remote queries
      -d, --discovered      list discovered interfaces
      -D                    show details and config entries for discovered
                            interfaces
      -m, --monitor         continuously monitor status
      -I seconds, --monitor-interval seconds
                            refresh interval for monitor mode (default: 1)
      -v, --verbose
    """

    /// The `usage:` block alone, as `parser.print_usage(sys.stderr)` writes it ahead of an
    /// error. Taken from ``helpText`` rather than restated, so the two cannot drift.
    public static var usageText: String {
        helpText.components(separatedBy: "\n\n")[0]
    }

    /// The whole `argparse` error page: the usage block, then `rnstatus: error: detail`.
    /// Written to stderr, followed by exit 2.
    public static func errorText(_ detail: String) -> String {
        "\(usageText)\n\(appName): error: \(detail)"
    }

    // MARK: - Exit codes

    /// Process exit codes. Python calls `exit(n)` directly at each site.
    public enum Result: Int32, Equatable, CaseIterable {
        /// Success — also `--version`, `--help`, `-j`, `-d`/`-D` and `KeyboardInterrupt`.
        case ok = 0
        /// "No shared RNS instance available to get status from" (rnstatus.py:171).
        case noSharedInstance = 1
        /// `stats` came back nil: "Could not get RNS status…" (rnstatus.py:683).
        case noStatus = 2
        /// Remote link closed abnormally: timeout / server-closed / unexpected (rnstatus.py:100).
        case linkFailed = 10
        /// Path request to the remote management destination timed out (rnstatus.py:82).
        case pathRequestTimeout = 12
        /// Remote setup error — missing `-i`, bad `-R`, unloadable identity (rnstatus.py:332).
        case remoteError = 20
    }

    // MARK: - Sort keys

    /// Accepted `-s` values. Python lowercases the argument and runs a chain of
    /// independent `if`s (rnstatus.py:362-387); an unrecognised token is silently ignored,
    /// which `Sort(rawValue:)` reproduces by returning nil.
    ///
    /// `bitrate` and `announce` are accepted aliases that the `--help` text does not list.
    public enum Sort: String, Equatable, CaseIterable {
        case rate, bitrate
        case rx, tx, rxs, txs
        case traffic
        case announces, announce
        case arx, atx
        case prx, ptx
        case held
    }
}
