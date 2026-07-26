import Foundation

/// A small command-line argument parser covering the subset of Python `argparse`
/// behaviour the `rn*` utilities actually rely on.
///
/// The Python utilities are all built with `argparse`, and their flag spellings are part
/// of their user-facing contract — `rnstatus -A`, `rnid -e`, `rncp --allowed`, and so on.
/// ReticulumSwift takes no external SPM dependencies, so `swift-argument-parser` is not
/// available; this is the minimum needed to reproduce those interfaces faithfully.
///
/// Supported, matching `argparse`:
/// - `action="store_true"` → ``flag(_:help:)``
/// - `action="count"` → ``counted(_:help:)``, including bundled shorts (`-vv`) and repeats
/// - `action="store"` → ``option(_:metavar:help:default:)``, as `--name value` or `--name=value`
/// - positional arguments, collected in order
/// - `--` terminating option parsing
/// - `-h` / `--help` generating usage text
///
/// - `allow_abbrev=True` → any unambiguous prefix of a long option, including `--help`
///
/// Deliberately *not* supported (nothing in the utilities uses them): subparsers and
/// mutually exclusive groups.
public struct ArgumentParser {

    // MARK: - Declaration

    private enum Kind {
        case flag
        case counted
        case value(metavar: String, defaultValue: String?)
        /// `nargs="*"` — zero or more values, collected until the next option.
        case variadic(metavar: String)
        /// `nargs="?"` — an optional value; `const` is stored when the flag is given bare.
        case optionalValue(metavar: String, const: String?)
        /// Python: `action="append"` — the option may repeat and every value is kept.
        case appended(metavar: String)
    }

    private struct Declaration {
        let names: [String]
        let kind: Kind
        let help: String
        /// `help=argparse.SUPPRESS` — parsed, but omitted from usage and the option list.
        var hidden: Bool = false
    }

    /// A declared option, exposed so an external formatter can reproduce `argparse`'s own
    /// help layout. Python: the fields of an `argparse.Action`.
    public struct OptionSpec {
        /// Every spelling, in declaration order. Python: `action.option_strings`.
        public let names: [String]
        /// Python: `_format_args(action, metavar)` — `nil` for `store_true`/`count`.
        public let metavar: String?
        /// Python: `action.nargs`.
        public let nargs: Nargs
        public let help: String
        /// Python: `help == argparse.SUPPRESS`.
        public let hidden: Bool

        public enum Nargs: Equatable {
            case none       // store_true / count
            case one        // store
            case optional   // nargs="?"
            case any        // nargs="*"
        }
    }

    /// Program name, used in usage output. Python: `parser.prog`.
    public let program: String

    /// One-line description printed above the option list. Python: `description=`.
    public let overview: String

    private var declarations: [Declaration] = []
    private var positionalNames: [(name: String, help: String, required: Bool)] = []

    public init(program: String, overview: String) {
        self.program = program
        self.overview = overview
    }

    /// Declare a boolean flag. Python: `action="store_true"`.
    public mutating func flag(_ names: [String], help: String, hidden: Bool = false) {
        declarations.append(Declaration(names: names, kind: .flag, help: help, hidden: hidden))
    }

    /// Declare a repeatable counting flag. Python: `action="count", default=0`.
    public mutating func counted(_ names: [String], help: String, hidden: Bool = false) {
        declarations.append(Declaration(names: names, kind: .counted, help: help, hidden: hidden))
    }

    /// Declare an option that takes one value. Python: `action="store"`.
    public mutating func option(_ names: [String], metavar: String = "VALUE",
                                help: String, default defaultValue: String? = nil,
                                hidden: Bool = false) {
        declarations.append(Declaration(names: names,
                                        kind: .value(metavar: metavar, defaultValue: defaultValue),
                                        help: help, hidden: hidden))
    }

    /// Declare an option collecting zero or more values. Python: `nargs="*"`.
    ///
    /// The empty case is meaningful and must survive to the caller: Python's bare `-e`
    /// yields `[]`, which is *falsy*, so the operation is skipped entirely **and** does not
    /// count toward `rnid`'s mutual-exclusion tally. ``ParsedArguments/values(_:)``
    /// distinguishes absent (`nil`) from present-but-empty (`[]`) for exactly that reason.
    public mutating func variadic(_ names: [String], metavar: String = "VALUE",
                                  help: String, hidden: Bool = false) {
        declarations.append(Declaration(names: names, kind: .variadic(metavar: metavar),
                                        help: help, hidden: hidden))
    }

    /// Declare an option whose value is optional. Python: `nargs="?", const=…`.
    ///
    /// When the flag appears without a value, `const` is stored — matching argparse, where
    /// `-a` alone yields `DEFAULT_ASPECTS`. A `nil` const stores nothing but still records
    /// the flag as provided (``ParsedArguments/wasProvided(_:)``).
    public mutating func optionalValue(_ names: [String], metavar: String = "VALUE",
                                       const: String? = nil, help: String,
                                       hidden: Bool = false) {
        declarations.append(Declaration(names: names,
                                        kind: .optionalValue(metavar: metavar, const: const),
                                        help: help, hidden: hidden))
    }

    /// Declare a repeatable option whose values accumulate. Python: `action="append"`.
    ///
    /// Needed by `rnx -a <hash>` and `rncp --allowed <hash>`, where every occurrence
    /// contributes an entry rather than overwriting the previous one. Unlike ``variadic``
    /// (`nargs="*"`), each occurrence consumes exactly one value.
    public mutating func appending(_ names: [String], metavar: String = "VALUE",
                                   help: String, hidden: Bool = false) {
        declarations.append(Declaration(names: names, kind: .appended(metavar: metavar),
                                        help: help, hidden: hidden))
    }

    /// Declare a positional argument, for usage output and arity checking.
    public mutating func positional(_ name: String, help: String, required: Bool = true) {
        positionalNames.append((name, help, required))
    }

    // MARK: - Parsing

    /// Parse an argument vector.
    ///
    /// - Parameter arguments: argv *without* the executable name. Pass
    ///   `Array(CommandLine.arguments.dropFirst())`.
    public func parse(_ arguments: [String]) throws -> ParsedArguments {
        var flags: Set<String> = []
        var counts: [String: Int] = [:]
        var values: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var provided: Set<String> = []
        var positionals: [String] = []

        var index = 0
        var optionsTerminated = false

        // argparse stops collecting `nargs="*"` values at the first token that looks like an
        // option. A bare "-" is a stdin placeholder, not an option.
        func looksLikeOption(_ token: String) -> Bool { token.hasPrefix("-") && token != "-" }

        while index < arguments.count {
            var argument = arguments[index]
            index += 1

            if optionsTerminated {
                positionals.append(argument)
                continue
            }

            if argument == "--" {
                optionsTerminated = true
                continue
            }

            // A bare "-" is a conventional stdin/stdout placeholder, not an option.
            guard argument.hasPrefix("-"), argument != "-" else {
                positionals.append(argument)
                continue
            }

            // argparse's `allow_abbrev`, which every RNS utility inherits: expand an
            // unambiguous long-option prefix to its full spelling before anything else
            // inspects the token, so the rest of the loop only ever sees canonical names.
            argument = try expandingAbbreviation(argument)

            // argparse adds -h/--help implicitly unless the program declares them itself.
            if (argument == "-h" || argument == "--help"), declaration(for: argument) == nil {
                flags.insert("--help")
                continue
            }

            // --name=value
            if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
                let name = String(argument[argument.startIndex..<equals])
                let inlineValue = String(argument[argument.index(after: equals)...])
                guard let declaration = declaration(for: name) else {
                    throw ArgumentError.unrecognisedOption(name)
                }
                switch declaration.kind {
                case .value, .optionalValue:
                    values[canonicalName(declaration)] = inlineValue
                    provided.insert(canonicalName(declaration))
                case .variadic, .appended:
                    lists[canonicalName(declaration), default: []].append(inlineValue)
                    provided.insert(canonicalName(declaration))
                case .flag, .counted:
                    throw ArgumentError.unexpectedValue(canonicalName(declaration))
                }
                continue
            }

            if let declaration = declaration(for: argument) {
                let key = canonicalName(declaration)
                provided.insert(key)
                switch declaration.kind {
                case .flag:
                    flags.insert(key)
                case .counted:
                    counts[key, default: 0] += 1
                case .value:
                    guard index < arguments.count else { throw ArgumentError.missingValue(key) }
                    values[key] = arguments[index]
                    index += 1
                case .optionalValue(_, let const):
                    if index < arguments.count, !looksLikeOption(arguments[index]) {
                        values[key] = arguments[index]
                        index += 1
                    } else if let const {
                        values[key] = const
                    }
                case .appended:
                    guard index < arguments.count else { throw ArgumentError.missingValue(key) }
                    lists[key, default: []].append(arguments[index])
                    index += 1
                case .variadic:
                    var collected = lists[key] ?? []
                    while index < arguments.count, !looksLikeOption(arguments[index]) {
                        collected.append(arguments[index])
                        index += 1
                    }
                    lists[key] = collected
                }
                continue
            }

            // A cluster of single-character short options. argparse walks the token left to
            // right: flag/count options are consumed one character at a time (so "-vv" is two
            // counts and "-qv" is quiet-then-verbose), and the FIRST value-taking option
            // consumes the REST of the token as its value ("-s16" is "-s 16", "-vvs16" is
            // "-v -v -s 16") — or, if it is the last character, the next argument ("-vs 16").
            // A bare "-h" anywhere in the cluster is the implicit help option. The whole token
            // is resolved before anything is applied, so an unrecognised character rejects the
            // entire argument (argparse reports the original token) rather than half-applying it.
            if !argument.hasPrefix("--"), argument.count > 2, let steps = shortCluster(argument) {
                for step in steps {
                    provided.insert(step.key)
                    if step.isHelp { flags.insert("--help"); continue }
                    switch step.kind {
                    case .flag:    flags.insert(step.key)
                    case .counted: counts[step.key, default: 0] += 1
                    case .value:
                        let value: String
                        if let attached = step.attached { value = attached }
                        else if index < arguments.count { value = arguments[index]; index += 1 }
                        else { throw ArgumentError.missingValue(step.key) }
                        values[step.key] = value
                    case .appended:
                        let value: String
                        if let attached = step.attached { value = attached }
                        else if index < arguments.count { value = arguments[index]; index += 1 }
                        else { throw ArgumentError.missingValue(step.key) }
                        lists[step.key, default: []].append(value)
                    case .optionalValue(_, let const):
                        if let attached = step.attached { values[step.key] = attached }
                        else if index < arguments.count, !looksLikeOption(arguments[index]) {
                            values[step.key] = arguments[index]; index += 1
                        } else if let const { values[step.key] = const }
                    case .variadic:
                        var collected = lists[step.key] ?? []
                        if let attached = step.attached { collected.append(attached) }
                        else {
                            while index < arguments.count, !looksLikeOption(arguments[index]) {
                                collected.append(arguments[index]); index += 1
                            }
                        }
                        lists[step.key] = collected
                    }
                }
                continue
            }

            throw ArgumentError.unrecognisedOption(argument)
        }

        // Fill in declared defaults for options the caller did not pass.
        for declaration in declarations {
            if case .value(_, let defaultValue) = declaration.kind,
               let defaultValue,
               values[canonicalName(declaration)] == nil {
                values[canonicalName(declaration)] = defaultValue
            }
        }

        return ParsedArguments(flags: flags, counts: counts, values: values,
                               lists: lists, provided: provided, positionals: positionals)
    }

    private func declaration(for name: String) -> Declaration? {
        declarations.first { $0.names.contains(name) }
    }

    /// One resolved character from a short-option cluster.
    private struct ClusterStep {
        let key: String
        let kind: Kind
        /// The value attached in the same token (the characters after a value-taking
        /// option). `nil` means "take the next argument", except for `isHelp`.
        let attached: String?
        let isHelp: Bool
    }

    /// Resolve a `-xyz…` token into its constituent short options, or `nil` if any
    /// character is not a known single-character option. The first value-taking option
    /// terminates the walk and claims the rest of the token as its (possibly empty)
    /// attached value; `-h` resolves to the implicit help option when the program has not
    /// declared its own. Mirrors argparse's `_parse_optional` / short-option consumption.
    private func shortCluster(_ token: String) -> [ClusterStep]? {
        let chars = Array(token.dropFirst())
        var steps: [ClusterStep] = []
        var i = 0
        while i < chars.count {
            let name = "-\(chars[i])"
            if let decl = declaration(for: name) {
                let key = canonicalName(decl)
                switch decl.kind {
                case .flag, .counted:
                    steps.append(ClusterStep(key: key, kind: decl.kind, attached: nil, isHelp: false))
                    i += 1
                case .value, .appended, .optionalValue, .variadic:
                    let rest = String(chars[(i + 1)...])
                    steps.append(ClusterStep(key: key, kind: decl.kind,
                                             attached: rest.isEmpty ? nil : rest, isHelp: false))
                    i = chars.count
                }
            } else if name == "-h", declaration(for: "--help") == nil {
                steps.append(ClusterStep(key: "--help", kind: .flag, attached: nil, isHelp: true))
                i += 1
            } else {
                return nil
            }
        }
        return steps
    }

    /// Expand a single `--abbrev` token to its unambiguous long-option name under
    /// `allow_abbrev`, or return it unchanged when it is not a long option, not a unique
    /// prefix, or ambiguous. Lets a tool that pre-scans for `--help`/`--version` before full
    /// parsing (e.g. rnprobe) honour abbreviations — `--hel`, `--vers` — exactly as argparse
    /// does, instead of only matching the spelled-out forms.
    public func expandedLongOption(_ argument: String) -> String {
        (try? expandingAbbreviation(argument)) ?? argument
    }

    /// Every declared option, for external help formatters. Python: `parser._actions`.
    public var optionSpecs: [OptionSpec] {
        declarations.map { declaration in
            switch declaration.kind {
            case .flag, .counted:
                return OptionSpec(names: declaration.names, metavar: nil, nargs: .none,
                                  help: declaration.help, hidden: declaration.hidden)
            case .value(let metavar, _):
                return OptionSpec(names: declaration.names, metavar: metavar, nargs: .one,
                                  help: declaration.help, hidden: declaration.hidden)
            case .optionalValue(let metavar, _):
                return OptionSpec(names: declaration.names, metavar: metavar, nargs: .optional,
                                  help: declaration.help, hidden: declaration.hidden)
            case .variadic(let metavar):
                return OptionSpec(names: declaration.names, metavar: metavar, nargs: .any,
                                  help: declaration.help, hidden: declaration.hidden)
            case .appended(let metavar):
                // argparse formats an `append` option exactly like `store`: one value.
                return OptionSpec(names: declaration.names, metavar: metavar, nargs: .one,
                                  help: declaration.help, hidden: declaration.hidden)
            }
        }
    }

    /// The longest declared spelling, used as the lookup key so callers can ask by any alias.
    private func canonicalName(_ declaration: Declaration) -> String {
        declaration.names.max(by: { $0.count < $1.count }) ?? declaration.names[0]
    }

    // MARK: - Long-option abbreviation

    /// Every long spelling the parser will answer to, in declaration order.
    ///
    /// `--help` joins the pool only when the program has not declared it itself, matching
    /// `argparse` adding its own help action in exactly that case.
    private var abbreviatableLongNames: [String] {
        var names = declarations.flatMap { $0.names }.filter { $0.hasPrefix("--") }
        if declaration(for: "--help") == nil { names.append("--help") }
        return names
    }

    /// Rewrite an abbreviated long option to its full spelling.
    ///
    /// Python: `argparse` defaults to `allow_abbrev=True` and none of the RNS utilities
    /// turn it off, so `rnstatus --j` runs as `--json` and `rnprobe --si 12` as `--size 12`.
    /// An exact match is never treated as an abbreviation, so a program declaring both
    /// `--log` and `--logfile` can still be given `--log`.
    ///
    /// Any token that is not a long option, or that matches nothing, is returned untouched —
    /// the caller then fails it the way it would have anyway.
    private func expandingAbbreviation(_ argument: String) throws -> String {
        guard argument.hasPrefix("--"), argument.count > 2 else { return argument }

        // Split "--conf=/tmp/x" so the prefix search sees only the name.
        let name: String
        let suffix: String
        if let equals = argument.firstIndex(of: "=") {
            name = String(argument[argument.startIndex..<equals])
            suffix = String(argument[equals...])
        } else {
            name = argument
            suffix = ""
        }

        let longNames = abbreviatableLongNames
        if longNames.contains(name) { return argument }      // exact match wins outright

        let candidates = longNames.filter { $0.hasPrefix(name) }
        switch candidates.count {
        case 0:  return argument                             // unknown; caller reports it
        case 1:  return candidates[0] + suffix
        default: throw ArgumentError.ambiguousOption(name, candidates)
        }
    }

    // MARK: - Error rendering

    /// The detail `argparse` prints after `prog: error: `.
    ///
    /// This lives on the parser rather than on ``ArgumentError`` because only the parser
    /// knows the declarations, and Python names a failing option by *every* one of its
    /// spellings: `argument -s/--sort: expected one argument`, never `argument -s:`.
    public func message(for error: ArgumentError) -> String {
        switch error {
        case .missingValue(let name):
            return "argument \(spelling(for: name)): expected one argument"
        case .unexpectedValue(let name):
            return "argument \(spelling(for: name)): ignored explicit argument"
        case .unrecognisedOption, .missingPositional,
             .unrecognisedArguments, .ambiguousOption:
            return error.description
        }
    }

    /// An option named the way `argparse` names it: all its spellings joined with "/".
    ///
    /// Public because a `type=`/`choices=` conversion failure is raised by the caller, not
    /// by ``parse(_:)``, and argparse names the option identically in those messages.
    public func spelling(for name: String) -> String {
        guard let declaration = declaration(for: name) else { return name }
        return declaration.names.joined(separator: "/")
    }

    // MARK: - Usage

    /// Usage text, in the same shape `argparse` prints for `--help`.
    public var usage: String {
        var lines: [String] = []
        let positionalUsage = positionalNames
            .map { $0.required ? $0.name : "[\($0.name)]" }
            .joined(separator: " ")
        lines.append("usage: \(program) [options] \(positionalUsage)".trimmingCharacters(in: .whitespaces))
        lines.append("")
        lines.append(overview)

        if !positionalNames.isEmpty {
            lines.append("")
            lines.append("positional arguments:")
            for positional in positionalNames {
                lines.append("  \(positional.name.padding(toLength: max(24, positional.name.count + 2), withPad: " ", startingAt: 0))\(positional.help)")
            }
        }

        lines.append("")
        lines.append("options:")
        lines.append("  \("-h, --help".padding(toLength: 24, withPad: " ", startingAt: 0))show this help message and exit")
        for declaration in declarations where !declaration.hidden {
            var spelling = declaration.names.joined(separator: ", ")
            switch declaration.kind {
            case .value(let metavar, _):        spelling += " \(metavar)"
            case .optionalValue(let metavar, _): spelling += " [\(metavar)]"
            case .variadic(let metavar):        spelling += " [\(metavar) ...]"
            case .appended(let metavar):        spelling += " \(metavar)"
            case .flag, .counted:               break
            }
            let padded = spelling.count < 24
                ? spelling.padding(toLength: 24, withPad: " ", startingAt: 0)
                : spelling + "\n" + String(repeating: " ", count: 26)
            lines.append("  \(padded)\(declaration.help)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - ParsedArguments

/// The result of ``ArgumentParser/parse(_:)``.
public struct ParsedArguments {
    private let flags: Set<String>
    private let counts: [String: Int]
    private let values: [String: String]
    private let lists: [String: [String]]
    private let provided: Set<String>

    /// Non-option arguments, in the order they appeared.
    public let positionals: [String]

    init(flags: Set<String>, counts: [String: Int], values: [String: String],
         lists: [String: [String]] = [:], provided: Set<String> = [],
         positionals: [String]) {
        self.flags = flags
        self.counts = counts
        self.values = values
        self.lists = lists
        self.provided = provided
        self.positionals = positionals
    }

    /// Whether a `store_true` flag was given. Accepts any declared spelling.
    public func flag(_ name: String) -> Bool { flags.contains(name) }

    /// How many times a `count` flag was given. Python's `default=0`.
    public func count(_ name: String) -> Int { counts[name] ?? 0 }

    /// The value of a `store` option, or its declared default, or `nil`.
    public func value(_ name: String) -> String? { values[name] }

    /// The value of a `store` option parsed as `Int`, or `nil` if absent or unparseable.
    public func int(_ name: String) -> Int? { values[name].flatMap(Int.init) }

    /// The value of a `store` option parsed as `Double`, or `nil`.
    public func double(_ name: String) -> Double? { values[name].flatMap(Double.init) }

    /// The values of an `nargs="*"` option.
    ///
    /// `nil` means the option was never given; `[]` means it was given with no values —
    /// Python's falsy empty list, which callers must treat as "skip this operation".
    public func values(_ name: String) -> [String]? { lists[name] }

    /// Whether an option appeared on the command line at all, regardless of its value.
    /// Needed for `nargs="?"` options declared without a `const`.
    public func wasProvided(_ name: String) -> Bool { provided.contains(name) }

    /// Whether help was requested. Handled outside the declaration list, as `argparse` does.
    public var wantsHelp: Bool { flags.contains("--help") }
}

// MARK: - Errors

public enum ArgumentError: Error, CustomStringConvertible, Equatable {
    /// An option that was not declared. Python: "unrecognized arguments".
    case unrecognisedOption(String)
    /// An option that takes a value was given none. Python: "expected one argument".
    case missingValue(String)
    /// `--flag=value` where `--flag` takes no value. Python: "ignored explicit argument".
    case unexpectedValue(String)
    /// A required positional was not supplied. Python: "the following arguments are required".
    case missingPositional(String)
    /// Every token `argparse` could not consume, in argv order. Python's `parse_args`
    /// reports all leftovers in one message: "unrecognized arguments: --bogus extra".
    /// Distinct from ``unrecognisedOption(_:)``, which names a single option and is what
    /// ``ArgumentParser/parse(_:)`` throws as soon as it hits one.
    case unrecognisedArguments([String])
    /// An abbreviated long option matching more than one declaration.
    /// Python: `allow_abbrev=True` → "ambiguous option: --ver could match --verbose, --version".
    case ambiguousOption(String, [String])

    public var description: String {
        switch self {
        // argparse always uses the plural, even when only one token was rejected.
        case .unrecognisedOption(let name): return "unrecognized arguments: \(name)"
        case .missingValue(let name):       return "argument \(name): expected one argument"
        case .unexpectedValue(let name):    return "argument \(name): ignored explicit argument"
        case .missingPositional(let name):  return "the following arguments are required: \(name)"
        case .unrecognisedArguments(let names):
            return "unrecognized arguments: \(names.joined(separator: " "))"
        case .ambiguousOption(let given, let candidates):
            return "ambiguous option: \(given) could match \(candidates.joined(separator: ", "))"
        }
    }
}
