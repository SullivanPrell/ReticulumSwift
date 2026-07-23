import Foundation

// MARK: - Command-line interface
//
// Python: rnprobe.py:209-249. A thin facade over the in-library ``ArgumentParser`` plus
// ``ArgparseHelp`` for the exact argparse help layout. There is no swift-argument-parser
// dependency and there must never be one.

public extension NetworkProbe {

    enum Arguments {

        /// What the command line asked for.
        public enum Action: Equatable {
            /// Run a probe.
            case run(NetworkProbe.Options)
            /// Python: argparse's `-h`/`--help` action — `print_help()`, exit 0.
            case help
            /// Python: rnprobe.py:231-234 — a blank line, `print_help()`, another blank
            /// line, then main() falls off the end (exit 0). Reached when
            /// `destination_hash` is falsy, which includes "no arguments at all" and
            /// "one positional only", because both positionals are `nargs='?'`.
            ///
            /// Split out from ``help`` because the two print different bytes.
            case missingDestination
            /// Python: `--version` — `"rnprobe <version>"` on stdout, exit 0.
            case version
            /// Python: `parser.error(msg)` — the usage block then
            /// `rnprobe: error: <detail>` on stderr, exit 2.
            case usageError(String)
        }

        // MARK: - Declarations

        /// Python: `parser.description`.
        public static let description = "Reticulum Probe Utility"

        /// Python: the option strings in declaration order (rnprobe.py:213-222). `-h` is
        /// argparse's implicit first action; `-v` is declared last, after the positionals,
        /// which is why it sorts last in the option table.
        static let usageOptionals = [
            "[-h]", "[--config CONFIG]", "[-s SIZE]", "[-n PROBES]",
            "[-t seconds]", "[-w seconds]", "[--version]", "[-v]"
        ]

        /// Both positionals are `nargs='?'`, hence the brackets.
        static let usagePositionals = ["[full_name]", "[destination_hash]"]

        static let positionalEntries: [ArgparseHelp.Entry] = [
            .init(invocation: "full_name", help: "full destination name in dotted notation"),
            .init(invocation: "destination_hash", help: "hexadecimal hash of the destination")
        ]

        static let optionEntries: [ArgparseHelp.Entry] = [
            .init(invocation: "-h, --help", help: "show this help message and exit"),
            .init(invocation: "--config CONFIG", help: "path to alternative Reticulum config directory"),
            .init(invocation: "-s SIZE, --size SIZE", help: "size of probe packet payload in bytes"),
            .init(invocation: "-n PROBES, --probes PROBES", help: "number of probes to send"),
            .init(invocation: "-t seconds, --timeout seconds", help: "timeout before giving up"),
            .init(invocation: "-w seconds, --wait seconds", help: "time between each probe"),
            .init(invocation: "--version", help: "show program's version number and exit"),
            // Python declares -v/--verbose with no help string, which is why argparse
            // prints its invocation on a bare line.
            .init(invocation: "-v, --verbose", help: "")
        ]

        /// The configured house parser, exposed so tests can drive it directly.
        public static func makeParser() -> ArgumentParser {
            var parser = ArgumentParser(program: NetworkProbe.appName, overview: description)
            parser.option(["--config"], metavar: "CONFIG",
                          help: "path to alternative Reticulum config directory")
            parser.option(["-s", "--size"], metavar: "SIZE",
                          help: "size of probe packet payload in bytes")
            parser.option(["-n", "--probes"], metavar: "PROBES",
                          help: "number of probes to send")
            parser.option(["-t", "--timeout"], metavar: "seconds",
                          help: "timeout before giving up")
            parser.option(["-w", "--wait"], metavar: "seconds",
                          help: "time between each probe")
            parser.flag(["--version"], help: "show program's version number and exit")
            parser.counted(["-v", "--verbose"], help: "")
            parser.positional("full_name", help: "full destination name in dotted notation",
                              required: false)
            parser.positional("destination_hash", help: "hexadecimal hash of the destination",
                              required: false)
            return parser
        }

        // MARK: - Rendered text

        /// Exactly the text argparse emits for `--help`, terminated by one newline.
        public static var helpText: String {
            ArgparseHelp.help(program: NetworkProbe.appName,
                              description: description,
                              usageOptionals: usageOptionals,
                              usagePositionals: usagePositionals,
                              positionals: positionalEntries,
                              options: optionEntries)
        }

        /// The `usage:` block alone, as `parser.print_usage(sys.stderr)` writes it before
        /// an error message: no trailing blank line.
        public static var usageText: String {
            var block = ArgparseHelp.usage(program: NetworkProbe.appName,
                                           optionals: usageOptionals,
                                           positionals: usagePositionals)
            if block.hasSuffix("\n\n") { block.removeLast() }
            return block
        }

        /// Python: `'%(prog)s: error: %(message)s'` appended to the usage block.
        public static func usageErrorText(_ detail: String) -> String {
            usageText + "\(NetworkProbe.appName): error: \(detail)\n"
        }

        // MARK: - Parsing

        /// Parse `argv`. Element 0 is the program path and is ignored.
        public static func parse(_ argv: [String]) -> Action {
            let tokens = Array(argv.dropFirst())

            // argparse fires the help and version actions the moment it reaches them, and
            // an unknown optional only becomes an error *after* the whole vector has been
            // walked (`parse_known_args` collects it in `extras`). So `--bogus -h` prints
            // help and exits 0 in Python too. Scanning first reproduces that.
            // Known divergence: `-s x -h` errors in argparse, because the type conversion
            // runs at the point `-s` is consumed; here it prints help.
            for token in tokens {
                if token == "--" { break }
                if token == "-h" || token == "--help" { return .help }
                if token == "--version" { return .version }
            }

            let parser = makeParser()
            let parsed: ParsedArguments
            do {
                parsed = try parser.parse(tokens)
            } catch let error as ArgumentError {
                return .usageError(describe(error))
            } catch {
                return .usageError("\(error)")
            }

            // Both positionals are nargs='?', so a third one is "unrecognized arguments".
            // argparse joins the leftovers with a single space.
            if parsed.positionals.count > 2 {
                let extras = parsed.positionals.dropFirst(2).joined(separator: " ")
                return .usageError("unrecognized arguments: \(extras)")
            }

            var options = NetworkProbe.Options()
            options.fullName = parsed.positionals.count > 0 ? parsed.positionals[0] : nil
            options.destinationHexhash = parsed.positionals.count > 1 ? parsed.positionals[1] : nil

            // Python: `configarg = args.config if args.config else None` — a truthiness
            // test, so `--config ""` collapses to the default config directory.
            if let config = parsed.value("--config"), !config.isEmpty {
                options.configDir = URL(fileURLWithPath: config)
            }

            if let raw = parsed.value("--size") {
                guard let value = Int(raw) else {
                    return .usageError("argument -s/--size: invalid int value: '\(raw)'")
                }
                // Swift-only guard: Python's os.urandom raises ValueError (not OSError) on
                // a negative size, escaping rnprobe's `except OSError` as a traceback.
                guard value >= 0 else {
                    return .usageError("argument -s/--size: must not be negative")
                }
                options.size = value
            }

            if let raw = parsed.value("--probes") {
                guard let value = Int(raw) else {
                    return .usageError("argument -n/--probes: invalid int value: '\(raw)'")
                }
                // Swift-only guard: Python's `while probes:` divides by zero on -n 0 and
                // loops forever on a negative count.
                guard value >= 1 else {
                    return .usageError("argument -n/--probes: must be at least 1")
                }
                options.probes = value
            }

            if let raw = parsed.value("--timeout") {
                guard let value = Double(raw) else {
                    return .usageError("argument -t/--timeout: invalid float value: '\(raw)'")
                }
                options.timeout = value
            }

            if let raw = parsed.value("--wait") {
                guard let value = Double(raw) else {
                    return .usageError("argument -w/--wait: invalid float value: '\(raw)'")
                }
                // Swift-only guard: Python's time.sleep(negative) raises ValueError.
                guard value >= 0 else {
                    return .usageError("argument -w/--wait: must not be negative")
                }
                options.wait = value
            }

            options.verbosity = parsed.count("--verbose")

            // Python: `if not args.destination_hash:` — a FALSINESS test, so an explicitly
            // empty second positional takes the help path too.
            guard let hash = options.destinationHexhash, !hash.isEmpty else {
                return .missingDestination
            }
            return .run(options)
        }

        /// Map the house parser's errors onto argparse's exact wording.
        ///
        /// `ArgumentError.description` says "unrecognized argument:" (singular) and reports
        /// the spelling the user typed rather than the full `-x/--long` form, so the
        /// messages are rebuilt here instead of edited in the shared parser.
        private static func describe(_ error: ArgumentError) -> String {
            switch error {
            case .unrecognisedOption(let name):
                return "unrecognized arguments: \(name)"
            case .missingValue(let name):
                return "argument \(spelling(for: name)): expected one argument"
            case .unexpectedValue(let name):
                return "argument \(spelling(for: name)): ignored explicit argument"
            case .missingPositional(let name):
                return "the following arguments are required: \(name)"
            case .unrecognisedArguments(let names):
                return "unrecognized arguments: \(names.joined(separator: " "))"
            case .ambiguousOption(let given, let candidates):
                return "ambiguous option: \(given) could match \(candidates.joined(separator: ", "))"
            }
        }

        /// argparse names an option by every one of its strings, joined with "/".
        private static func spelling(for name: String) -> String {
            let groups = [["--config"],
                          ["-s", "--size"],
                          ["-n", "--probes"],
                          ["-t", "--timeout"],
                          ["-w", "--wait"],
                          ["--version"],
                          ["-v", "--verbose"]]
            for group in groups where group.contains(name) {
                return group.joined(separator: "/")
            }
            return name
        }
    }
}
