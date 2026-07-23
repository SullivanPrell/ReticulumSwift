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
/// Deliberately *not* supported (nothing in the utilities uses them): abbreviated long
/// options, `nargs` other than 0 or 1, subparsers, and mutually exclusive groups.
public struct ArgumentParser {

    // MARK: - Declaration

    private enum Kind {
        case flag
        case counted
        case value(metavar: String, defaultValue: String?)
    }

    private struct Declaration {
        let names: [String]
        let kind: Kind
        let help: String
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
    public mutating func flag(_ names: [String], help: String) {
        declarations.append(Declaration(names: names, kind: .flag, help: help))
    }

    /// Declare a repeatable counting flag. Python: `action="count", default=0`.
    public mutating func counted(_ names: [String], help: String) {
        declarations.append(Declaration(names: names, kind: .counted, help: help))
    }

    /// Declare an option that takes one value. Python: `action="store"`.
    public mutating func option(_ names: [String], metavar: String = "VALUE",
                                help: String, default defaultValue: String? = nil) {
        declarations.append(Declaration(names: names,
                                        kind: .value(metavar: metavar, defaultValue: defaultValue),
                                        help: help))
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
        var positionals: [String] = []

        var index = 0
        var optionsTerminated = false

        while index < arguments.count {
            let argument = arguments[index]
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
                guard case .value = declaration.kind else {
                    throw ArgumentError.unexpectedValue(name)
                }
                values[canonicalName(declaration)] = inlineValue
                continue
            }

            if let declaration = declaration(for: argument) {
                let key = canonicalName(declaration)
                switch declaration.kind {
                case .flag:
                    flags.insert(key)
                case .counted:
                    counts[key, default: 0] += 1
                case .value:
                    guard index < arguments.count else { throw ArgumentError.missingValue(argument) }
                    values[key] = arguments[index]
                    index += 1
                }
                continue
            }

            // Bundled single-character flags, e.g. "-vv" or "-qv". argparse accepts these
            // for any combination of single-character flag/count options.
            if !argument.hasPrefix("--"), argument.count > 2 {
                let letters = argument.dropFirst().map { "-\($0)" }
                let resolved = letters.map { declaration(for: $0) }
                if resolved.allSatisfy({ declaration in
                    guard let declaration else { return false }
                    switch declaration.kind {
                    case .flag, .counted: return true
                    case .value:          return false
                    }
                }) {
                    for declaration in resolved.compactMap({ $0 }) {
                        let key = canonicalName(declaration)
                        switch declaration.kind {
                        case .flag:    flags.insert(key)
                        case .counted: counts[key, default: 0] += 1
                        case .value:   break
                        }
                    }
                    continue
                }
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

        return ParsedArguments(flags: flags, counts: counts, values: values, positionals: positionals)
    }

    private func declaration(for name: String) -> Declaration? {
        declarations.first { $0.names.contains(name) }
    }

    /// The longest declared spelling, used as the lookup key so callers can ask by any alias.
    private func canonicalName(_ declaration: Declaration) -> String {
        declaration.names.max(by: { $0.count < $1.count }) ?? declaration.names[0]
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
        for declaration in declarations {
            var spelling = declaration.names.joined(separator: ", ")
            if case .value(let metavar, _) = declaration.kind { spelling += " \(metavar)" }
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

    /// Non-option arguments, in the order they appeared.
    public let positionals: [String]

    init(flags: Set<String>, counts: [String: Int], values: [String: String], positionals: [String]) {
        self.flags = flags
        self.counts = counts
        self.values = values
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

    public var description: String {
        switch self {
        case .unrecognisedOption(let name): return "unrecognized argument: \(name)"
        case .missingValue(let name):       return "argument \(name): expected one argument"
        case .unexpectedValue(let name):    return "argument \(name): ignored explicit argument"
        case .missingPositional(let name):  return "the following arguments are required: \(name)"
        }
    }
}
