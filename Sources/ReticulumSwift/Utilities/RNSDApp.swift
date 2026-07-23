import Foundation

/// The command-line surface shared by `rnsd`, `rnir` and `rnpkg`.
///
/// Python reference: `RNS/Utilities/rnsd.py` (`main`, lines 62-88), `RNS/Utilities/rnir.py`
/// (lines 53-76) and `RNS/Utilities/rnpkg.py` (lines 51-76). All three build an
/// `argparse.ArgumentParser` from the same handful of declarations; `rnsd` additionally
/// declares `-s/--service` and `-i/--interactive`.
///
/// Parsing itself is delegated to the package's shared ``ArgumentParser``. What lives here is
/// everything `argparse` does around parsing that the shared parser deliberately does not:
/// the wrapped `usage:` block, the per-parser help gutter, the two help-less rows for
/// `-v`/`-q`, unambiguous-prefix expansion of long options, and the `prog: error: …` line.
/// The rendered text is byte-compared against real `argparse` output in `RNSDAppTests`.
///
/// Everything in this type is string-in / string-out — no terminal, no filesystem, no network.
public enum RNSDApp {

    // MARK: - Program identity

    /// Python: `rnsd.py` `parser = argparse.ArgumentParser(description=…)`, prog inferred from argv[0].
    public static let appName: String = "rnsd"
    public static let rnirAppName: String = "rnir"
    public static let rnpkgAppName: String = "rnpkg"

    /// Python: `rnsd.py:64`.
    public static let description: String = "Reticulum Network Stack Daemon"
    /// Python: `rnir.py:54`.
    public static let rnirDescription: String = "Reticulum Distributed Identity Resolver"
    /// Python: `rnpkg.py:53`.
    public static let rnpkgDescription: String = "Reticulum Meta Package Manager"

    // MARK: - Runtime constants

    /// Python: `RNS.logfile = Reticulum.configdir+"/logfile"` (`Reticulum.py:239`).
    public static let logFileName: String = "logfile"
    /// Python: `prevfile = logfile+".1"` (`RNS/__init__.py:147`).
    public static let rotatedLogSuffix: String = ".1"
    /// Python: `RNS.LOG_MAXSIZE = 5*1024*1024`.
    public static let logMaxSize: Int = Reticulum.logMaxSize

    /// Python's `rnpkg` defines its own one-line example config
    /// (`__example_rnpkg_config__`, `rnpkg.py:75`) — **not** the RNS config.
    /// 57 bytes including the trailing newline; `print()` makes stdout 58.
    public static let rnpkgExampleConfig: String = "# This is an example package manager configuration file.\n"

    /// Python: `time.sleep(1.5)` after writing a default config (`Reticulum.py:333`).
    public static let defaultConfigNoticeDelay: TimeInterval = 1.5

    // MARK: - Exit codes

    /// Python: bare `exit()` / `RNS.exit()` → 0; `argparse` errors → 2; `RNS.panic()` →
    /// `os._exit(255)`.
    public enum ExitCode: Int32, Equatable, CaseIterable {
        case ok = 0
        /// Reserved: the pre-parity Swift `rnsd` used 1 for stack bring-up failures. The port
        /// now panics with 255 instead, matching Python; 1 is kept only so callers can name it.
        case fatalError = 1
        case argumentError = 2
        case panic = 255
    }

    // MARK: - Options

    /// The parsed command line, in Python's `args` shape.
    public struct Options: Equatable {
        /// Python: `--config` — a config **directory**, not a file (`rnsd.py:65`).
        public var configDir: String?
        /// Python: `-v/--verbose`, `action='count', default=0`.
        public var verbose: Int
        /// Python: `-q/--quiet`, `action='count', default=0`.
        public var quiet: Int
        /// Python: `-s/--service`. `rnsd` only.
        public var service: Bool
        /// Python: `-i/--interactive`. `rnsd` only.
        public var interactive: Bool
        /// Python: `--exampleconfig`.
        public var exampleConfig: Bool
        /// Python: `--version` (an `action='version'` that prints and exits).
        public var version: Bool
        /// `argparse`'s implicit `-h/--help`.
        public var help: Bool

        /// Python: `targetverbosity = verbosity-quietness` (`rnsd.py:41`). May be negative.
        public var verbosityDelta: Int { verbose - quiet }

        /// Python: service mode sets `targetverbosity = None` (`rnsd.py:45`), discarding the
        /// delta entirely so the config file's `loglevel` is used verbatim.
        public var effectiveVerbosity: Int? { service ? nil : verbosityDelta }

        public init(configDir: String? = nil,
                    verbose: Int = 0,
                    quiet: Int = 0,
                    service: Bool = false,
                    interactive: Bool = false,
                    exampleConfig: Bool = false,
                    version: Bool = false,
                    help: Bool = false) {
            self.configDir = configDir
            self.verbose = verbose
            self.quiet = quiet
            self.service = service
            self.interactive = interactive
            self.exampleConfig = exampleConfig
            self.version = version
            self.help = help
        }
    }

    // MARK: - Option table

    /// One `parser.add_argument(...)` call, in declaration order.
    struct OptionSpec {
        enum Kind: Equatable {
            case flag
            case counted
            case value(metavar: String)
        }
        /// All accepted spellings, first one first — `argparse` uses the first for `usage:`.
        let names: [String]
        let kind: Kind
        /// `nil` means the declaration carries no `help=`, which `argparse` renders as a bare
        /// invocation row with no padding and no trailing whitespace.
        let help: String?

        var takesValue: Bool { if case .value = kind { return true }; return false }

        /// `argparse`'s `_format_action_invocation`: option strings joined with ", ",
        /// each followed by the metavar when the option takes a value.
        var invocation: String {
            switch kind {
            case .flag, .counted:
                return names.joined(separator: ", ")
            case .value(let metavar):
                return names.map { "\($0) \(metavar)" }.joined(separator: ", ")
            }
        }

        /// `argparse`'s `_format_actions_usage`: `[<first option string>]`, plus the metavar.
        var usagePart: String {
            switch kind {
            case .flag, .counted:
                return "[\(names[0])]"
            case .value(let metavar):
                return "[\(names[0]) \(metavar)]"
            }
        }
    }

    /// Swift-only back-compatibility spellings for `--config`, kept because the pre-parity
    /// Swift `rnsd` accepted them with exactly this meaning (a config *directory*).
    ///
    /// They are rewritten to `--config` before parsing, so they never appear in `usage:` or
    /// the options table and never participate in prefix abbreviation — `--conf` therefore
    /// resolves to `--config` as it does in Python, instead of becoming ambiguous.
    ///
    /// Python's own `-c` is **not** accepted (verified: `rnsd -c /tmp/x` → exit 2), and the
    /// pre-parity Swift `-c` meant a config *file*, so it is deliberately not carried over.
    static let configDirectoryAliases: [String] = ["--config-dir", "-d"]

    /// The declaration list, in `argparse` order. `-h/--help` is `argparse`'s implicit one and
    /// is always listed first.
    static func optionSpecs(allowServiceFlags: Bool) -> [OptionSpec] {
        var specs: [OptionSpec] = [
            OptionSpec(names: ["-h", "--help"], kind: .flag,
                       help: "show this help message and exit"),
            OptionSpec(names: ["--config"], kind: .value(metavar: "CONFIG"),
                       help: "path to alternative Reticulum config directory"),
            // Python declares no `help=` for these two, so their rows are bare.
            OptionSpec(names: ["-v", "--verbose"], kind: .counted, help: nil),
            OptionSpec(names: ["-q", "--quiet"], kind: .counted, help: nil),
        ]
        if allowServiceFlags {
            specs.append(OptionSpec(names: ["-s", "--service"], kind: .flag,
                                    help: "rnsd is running as a service and should log to file"))
            specs.append(OptionSpec(names: ["-i", "--interactive"], kind: .flag,
                                    help: "drop into interactive shell after initialisation"))
        }
        specs.append(OptionSpec(names: ["--exampleconfig"], kind: .flag,
                                help: "print verbose configuration example to stdout and exit"))
        specs.append(OptionSpec(names: ["--version"], kind: .flag,
                                help: "show program's version number and exit"))
        return specs
    }

    /// The shared parser configured with this tool's declarations.
    ///
    /// Note the returned parser's own ``ArgumentParser/usage`` is *not* `argparse`-shaped —
    /// use ``helpText(program:description:allowServiceFlags:)`` for that.
    public static func parser(program: String,
                              description: String,
                              allowServiceFlags: Bool) -> ArgumentParser {
        var parser = ArgumentParser(program: program, overview: description)
        for spec in optionSpecs(allowServiceFlags: allowServiceFlags) {
            if spec.names.contains("-h") { continue }   // ArgumentParser injects -h/--help itself
            switch spec.kind {
            case .flag:
                parser.flag(spec.names, help: spec.help ?? "")
            case .counted:
                parser.counted(spec.names, help: spec.help ?? "")
            case .value(let metavar):
                parser.option(spec.names, metavar: metavar, help: spec.help ?? "")
            }
        }
        return parser
    }

    // MARK: - Parsing

    /// Parse argv (**without** the executable name) into ``Options``.
    ///
    /// - Parameter allowServiceFlags: `true` for `rnsd`; `false` for `rnir`/`rnpkg`, which do
    ///   not declare `-s` or `-i` and reject them as unrecognized arguments (exit 2).
    public static func parse(_ argv: [String], allowServiceFlags: Bool) throws -> Options {
        let specs = optionSpecs(allowServiceFlags: allowServiceFlags)
        let normalised = try normalise(argv, specs: specs)

        let argumentParser = parser(program: appName, description: description,
                                    allowServiceFlags: allowServiceFlags)

        let parsed: ParsedArguments
        do {
            parsed = try argumentParser.parse(normalised)
        } catch let error as ArgumentError {
            if case .unrecognisedOption = error {
                // Python reports *all* leftover tokens in one message, in argv order.
                throw ArgumentError.unrecognisedArguments(unconsumed(normalised, specs: specs))
            }
            throw error
        }

        // `argparse` declares no positionals for these tools, so any bare word is a leftover:
        // `rnsd extra` → "unrecognized arguments: extra", exit 2.
        if !parsed.positionals.isEmpty {
            throw ArgumentError.unrecognisedArguments(unconsumed(normalised, specs: specs))
        }

        // Python: `if args.config: configarg = args.config else: configarg = None` —
        // `--config ''` is falsy and falls back to the default search order (`rnsd.py:79-82`).
        let rawConfig = parsed.value("--config")
        let configDir = (rawConfig?.isEmpty == false) ? rawConfig : nil

        return Options(configDir: configDir,
                       verbose: parsed.count("--verbose"),
                       quiet: parsed.count("--quiet"),
                       service: allowServiceFlags && parsed.flag("--service"),
                       interactive: allowServiceFlags && parsed.flag("--interactive"),
                       exampleConfig: parsed.flag("--exampleconfig"),
                       version: parsed.flag("--version"),
                       help: parsed.wantsHelp)
    }

    /// Rewrite the Swift-only `--config` aliases and expand unambiguous long-option prefixes.
    ///
    /// Python: `argparse`'s `allow_abbrev` defaults to `True`, so `--co`, `--conf` and
    /// `--confi` all set `config` and `--exam` sets `exampleconfig`, while `--ver` is a hard
    /// error because it matches both `--verbose` and `--version`. The shared ``ArgumentParser``
    /// documents abbreviation as unsupported, so it is done here instead.
    static func normalise(_ argv: [String], specs: [OptionSpec]) throws -> [String] {
        let longNames = specs.flatMap { $0.names }.filter { $0.hasPrefix("--") }
        var result: [String] = []
        var optionsTerminated = false

        for argument in argv {
            if optionsTerminated {
                result.append(argument)
                continue
            }
            if argument == "--" {
                optionsTerminated = true
                result.append(argument)
                continue
            }
            if configDirectoryAliases.contains(argument) {
                result.append("--config")
                continue
            }
            if let equals = argument.firstIndex(of: "="),
               configDirectoryAliases.contains(String(argument[argument.startIndex..<equals])) {
                result.append("--config" + String(argument[equals...]))
                continue
            }
            guard argument.hasPrefix("--"), argument.count > 2 else {
                result.append(argument)
                continue
            }

            let name: String
            let suffix: String
            if let equals = argument.firstIndex(of: "=") {
                name = String(argument[argument.startIndex..<equals])
                suffix = String(argument[equals...])
            } else {
                name = argument
                suffix = ""
            }

            if longNames.contains(name) {
                result.append(argument)       // exact match always wins over abbreviation
                continue
            }
            let candidates = longNames.filter { $0.hasPrefix(name) }
            switch candidates.count {
            case 0:
                result.append(argument)       // unknown; reported as unrecognized later
            case 1:
                result.append(candidates[0] + suffix)
            default:
                // Python: "rnsd: error: ambiguous option: --ver could match --verbose, --version"
                // — candidates listed in declaration order.
                throw ArgumentError.ambiguousOption(name, candidates)
            }
        }
        return result
    }

    /// Every token `argparse` would fail to consume, in argv order.
    ///
    /// Python's `parse_args` collects unrecognized options *and* surplus positionals into a
    /// single message: `rnsd --bogus extra` reports "--bogus extra", while `rnsd -v --bogus`
    /// reports only "--bogus".
    static func unconsumed(_ argv: [String], specs: [OptionSpec]) -> [String] {
        func spec(named name: String) -> OptionSpec? {
            specs.first { $0.names.contains(name) }
        }

        var leftovers: [String] = []
        var index = 0
        var optionsTerminated = false

        while index < argv.count {
            let argument = argv[index]
            index += 1

            if optionsTerminated { leftovers.append(argument); continue }
            if argument == "--" { optionsTerminated = true; continue }
            guard argument.hasPrefix("-"), argument != "-" else {
                leftovers.append(argument)      // a positional; these tools declare none
                continue
            }

            if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
                let name = String(argument[argument.startIndex..<equals])
                if spec(named: name) == nil { leftovers.append(argument) }
                continue
            }
            if let match = spec(named: argument) {
                if match.takesValue, index < argv.count { index += 1 }
                continue
            }
            // Bundled single-character flags, e.g. "-vq".
            if !argument.hasPrefix("--"), argument.count > 2 {
                let letters = argument.dropFirst().map { "-\($0)" }
                let bundled = letters.allSatisfy { letter in
                    guard let match = spec(named: letter) else { return false }
                    return !match.takesValue
                }
                if bundled { continue }
            }
            leftovers.append(argument)
        }
        return leftovers
    }

    // MARK: - argparse text rendering

    /// `argparse`'s default output width: `shutil.get_terminal_size().columns - 2` with the
    /// usual 80-column fallback.
    static let helpWidth: Int = 78

    /// The wrapped `usage:` block, without a trailing newline.
    ///
    /// `argparse` fills greedily to ``helpWidth`` and indents continuation lines to
    /// `len("usage: ") + len(prog) + 1`, which for `rnsd` is 12 columns.
    public static func usageText(program: String, allowServiceFlags: Bool) -> String {
        let prefix = "usage: "
        let indent = String(repeating: " ", count: prefix.count + program.count + 1)
        let parts = [program] + optionSpecs(allowServiceFlags: allowServiceFlags).map(\.usagePart)

        var lines: [String] = []
        var current: [String] = []
        // Python: `line_len = len(prefix) - 1` for the first line.
        var lineLength = prefix.count - 1

        for part in parts {
            if lineLength + 1 + part.count > helpWidth && !current.isEmpty {
                lines.append(indent + current.joined(separator: " "))
                current = []
                lineLength = indent.count - 1
            }
            current.append(part)
            lineLength += 1 + part.count
        }
        if !current.isEmpty { lines.append(indent + current.joined(separator: " ")) }

        // Python: `lines[0] = lines[0][len(indent):]`, then the prefix is prepended.
        lines[0] = String(lines[0].dropFirst(indent.count))
        return prefix + lines.joined(separator: "\n")
    }

    /// The full `--help` page, without a trailing newline: usage, blank line, description,
    /// blank line, then the `options:` table.
    ///
    /// The gutter is `argparse`'s: `help_position = min(max(len(invocation)) + 2 + 2, 24)`, so
    /// help text starts at column 21 for `rnsd` (longest invocation `-i, --interactive`, 17)
    /// and column 19 for `rnir`/`rnpkg` (longest `--config CONFIG`, 15).
    ///
    /// Python 3.10 and newer print `options:`; 3.9 and older print `optional arguments:`.
    /// The 3.10+ spelling is the target.
    public static func helpText(program: String,
                                description: String,
                                allowServiceFlags: Bool) -> String {
        let specs = optionSpecs(allowServiceFlags: allowServiceFlags)
        let invocations = specs.map(\.invocation)
        let actionMaxLength = (invocations.map(\.count).max() ?? 0) + 2   // + current_indent
        let helpPosition = min(actionMaxLength + 2, 24)
        let actionWidth = helpPosition - 2 - 2
        let helpTextWidth = max(helpWidth - helpPosition, 11)

        var lines: [String] = []
        lines.append(usageText(program: program, allowServiceFlags: allowServiceFlags))
        lines.append("")
        lines.append(description)
        lines.append("")
        lines.append("options:")

        for spec in specs {
            let invocation = spec.invocation
            guard let help = spec.help, !help.trimmingCharacters(in: .whitespaces).isEmpty else {
                // Python: `if not action.help:` comes first, so the row is just the
                // invocation — no padding, no trailing whitespace.
                lines.append("  " + invocation)
                continue
            }
            let wrapped = wrap(help, width: helpTextWidth)
            if invocation.count <= actionWidth {
                let padded = invocation.padding(toLength: actionWidth, withPad: " ", startingAt: 0)
                lines.append("  " + padded + "  " + wrapped[0])
            } else {
                lines.append("  " + invocation)
                lines.append(String(repeating: " ", count: helpPosition) + wrapped[0])
            }
            for continuation in wrapped.dropFirst() {
                lines.append(String(repeating: " ", count: helpPosition) + continuation)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// `argparse`'s `action='version'` output, without a trailing newline.
    ///
    /// Python emits `RNS.__version__` (1.4.0). The Swift port emits ``Reticulum/version`` —
    /// the port's own release — for consistency with the RetiOS About screen.
    /// ``Reticulum/rnsProtocolVersion`` carries the RNS release this build matches.
    public static func versionText(program: String, version: String = Reticulum.version) -> String {
        "\(program) \(version)"
    }

    /// The `argparse` error page, without a trailing newline: the usage block, then
    /// `prog: error: message`. Written to stderr; exit code 2.
    public static func errorText(program: String, allowServiceFlags: Bool, error: Error) -> String {
        let message: String
        if let argumentError = error as? ArgumentError {
            message = argumentError.description
        } else {
            message = "\(error)"
        }
        return usageText(program: program, allowServiceFlags: allowServiceFlags)
            + "\n\(program): error: \(message)"
    }

    /// Greedy word wrap, matching `textwrap.wrap` for the single-space, no-hyphenation case
    /// that every help string in these three tools falls into.
    static func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [""] : lines
    }
}
