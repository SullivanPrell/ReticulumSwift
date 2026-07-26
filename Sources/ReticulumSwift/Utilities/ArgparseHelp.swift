import Foundation

/// Byte-faithful reproduction of Python `argparse.HelpFormatter`'s layout.
///
/// The `rn*` utilities are all argparse programs, and their `--help` output is part of
/// their user-facing contract — column positions, the wrapped usage block and the
/// "invocation on its own line" rule for long flag spellings are all reproduced here so a
/// Swift port can be diffed byte-for-byte against the installed Python tool.
///
/// ``ArgumentParser/usage`` deliberately renders a simpler, hand-padded table; it predates
/// this type and is kept as-is so existing callers do not shift. New utilities that need
/// exact parity should render through ``ArgparseHelp`` instead.
///
/// Python reference: `Lib/argparse.py`, `HelpFormatter._format_usage`,
/// `HelpFormatter._format_action` and `HelpFormatter.format_help`.
///
/// Fidelity notes (all verified against CPython 3.12's argparse):
/// - `text_width` is `columns - 2`; argparse reads `COLUMNS`/`shutil.get_terminal_size()`,
///   which is 80 when stdout is not a terminal, hence the default of 78 here.
/// - `help_position = min(action_max_length + 2, max_help_position)` with
///   `max_help_position = 24` and `current_indent = 2`.
/// - The `options:` heading is the Python 3.10+ spelling; 3.9 and earlier said
///   `optional arguments:`. RNS 1.4.0 ships against 3.10+, so that is what is used.
public enum ArgparseHelp {

    /// One row of a help section: the flag/positional spelling and its help string.
    public struct Entry: Equatable {
        /// The rendered invocation, e.g. `"-s SIZE, --size SIZE"` or `"full_name"`.
        /// Python: `HelpFormatter._format_action_invocation`.
        public let invocation: String
        /// The help string, or `""` for an action declared without one (argparse then
        /// prints the invocation alone, which is why `-v, --verbose` has a bare line).
        public let help: String

        public init(invocation: String, help: String = "") {
            self.invocation = invocation
            self.help = help
        }
    }

    /// Python: `HelpFormatter._max_help_position` default.
    public static let maxHelpPosition = 24
    /// Python: `HelpFormatter._current_indent` after one `_indent()` call.
    public static let currentIndent = 2
    /// Python: `width = shutil.get_terminal_size().columns - 2`, 80 - 2 off a terminal.
    public static let defaultWidth = 78

    // MARK: - Usage

    /// Render the `usage: …` block, including its trailing blank line.
    ///
    /// Python: `HelpFormatter._format_usage`. When the single-line form does not fit in
    /// `width`, argparse wraps the optionals as one group and the positionals as another,
    /// each continuation line indented to `len("usage: ") + len(prog) + 1`.
    ///
    /// - Parameters:
    ///   - program: `parser.prog`.
    ///   - optionals: usage fragments for the flags, in declaration order, e.g. `"[-h]"`.
    ///   - positionals: usage fragments for the positionals, e.g. `"[full_name]"`.
    public static func usage(program: String,
                             optionals: [String],
                             positionals: [String],
                             width: Int = defaultWidth) -> String {
        let prefix = "usage: "
        let flat = ([program] + optionals + positionals).joined(separator: " ")

        // Python: `if len(prefix) + len(usage) > text_width:` — otherwise one line.
        guard prefix.count + flat.count > width else { return prefix + flat + "\n\n" }

        // Python: `if len(prefix) + len(prog) <= 0.75 * text_width:` — a short program
        // name lets the first group ride along on the `usage:` line.
        guard Double(prefix.count + program.count) <= 0.75 * Double(width) else {
            // Long program name: every group starts on its own indented line.
            let indent = String(repeating: " ", count: prefix.count)
            var lines = [program]
            lines += wrap(optionals, indent: indent, width: width)
            lines += wrap(positionals, indent: indent, width: width)
            return prefix + lines.joined(separator: "\n") + "\n\n"
        }

        let indent = String(repeating: " ", count: prefix.count + program.count + 1)
        var lines: [String]
        if !optionals.isEmpty {
            lines = wrap([program] + optionals, indent: indent, width: width, firstPrefix: prefix)
            lines += wrap(positionals, indent: indent, width: width)
        } else if !positionals.isEmpty {
            lines = wrap([program] + positionals, indent: indent, width: width, firstPrefix: prefix)
        } else {
            lines = [program]
        }
        return prefix + lines.joined(separator: "\n") + "\n\n"
    }

    /// Python: the nested `get_lines(parts, indent, prefix=None)` inside `_format_usage`.
    private static func wrap(_ parts: [String],
                             indent: String,
                             width: Int,
                             firstPrefix: String? = nil) -> [String] {
        guard !parts.isEmpty else { return [] }
        var lines: [String] = []
        var line: [String] = []
        // Python seeds the running length with `len(prefix) - 1` (or `len(indent) - 1`),
        // because every part contributes `1 + len(part)` — the leading separator space.
        var lineLength = (firstPrefix?.count ?? indent.count) - 1

        for part in parts {
            if lineLength + 1 + part.count > width, !line.isEmpty {
                lines.append(indent + line.joined(separator: " "))
                line = []
                lineLength = indent.count - 1
            }
            line.append(part)
            lineLength += 1 + part.count
        }
        if !line.isEmpty { lines.append(indent + line.joined(separator: " ")) }
        // Python: `lines[0] = lines[0][len(indent):]` — the caller re-prepends `prefix`.
        if firstPrefix != nil, let first = lines.first {
            lines[0] = String(first.dropFirst(indent.count))
        }
        return lines
    }

    // MARK: - Full help

    /// Render the complete `--help` text, terminated by exactly one newline.
    ///
    /// Python: `ArgumentParser.format_help` — usage block, description, then each
    /// non-empty section. `format_help` collapses runs of blank lines and finishes with
    /// `formatted.strip('\n') + '\n'`, which is why there is no trailing blank line.
    public static func help(program: String,
                            description: String,
                            usageOptionals: [String],
                            usagePositionals: [String],
                            positionals: [Entry],
                            options: [Entry],
                            width: Int = defaultWidth) -> String {
        var out = usage(program: program,
                        optionals: usageOptionals,
                        positionals: usagePositionals,
                        width: width)

        if !description.isEmpty { out += description + "\n\n" }

        // Python: `action_max_length` spans EVERY action in the parser, so the two
        // sections share one help column.
        let allEntries = positionals + options
        let maxLength = allEntries.map { $0.invocation.count + currentIndent }.max() ?? 0
        let helpPosition = min(maxLength + 2, maxHelpPosition)

        if !positionals.isEmpty {
            out += "positional arguments:\n"
            out += positionals.map { format($0, helpPosition: helpPosition, width: width) }.joined()
            out += "\n"
        }
        if !options.isEmpty {
            out += "options:\n"
            out += options.map { format($0, helpPosition: helpPosition, width: width) }.joined()
            out += "\n"
        }

        // Python: `formatted.strip('\n') + '\n'`.
        while out.hasSuffix("\n") { out.removeLast() }
        return out + "\n"
    }

    /// Python: `HelpFormatter._format_action`.
    private static func format(_ entry: Entry, helpPosition: Int, width: Int) -> String {
        let indent = String(repeating: " ", count: currentIndent)
        let actionWidth = helpPosition - currentIndent - 2

        // Python: `if not action.help: tup = self._current_indent, '', action_header`
        guard !entry.help.isEmpty else { return indent + entry.invocation + "\n" }

        let helpWidth = max(width - helpPosition, 11)
        let helpLines = wrapText(entry.help, width: helpWidth)
        let continuation = String(repeating: " ", count: helpPosition)

        var out: String
        if entry.invocation.count <= actionWidth {
            // Python: `'%*s%-*s  ' % (indent, '', action_width, action_header)`.
            let padded = entry.invocation.padding(toLength: actionWidth, withPad: " ", startingAt: 0)
            out = indent + padded + "  " + (helpLines.first ?? "") + "\n"
        } else {
            out = indent + entry.invocation + "\n"
            out += continuation + (helpLines.first ?? "") + "\n"
        }
        for line in helpLines.dropFirst() { out += continuation + line + "\n" }
        return out
    }

    /// Greedy word wrap, matching `textwrap.wrap` for the single-space, no-hyphen text
    /// the utilities actually use for help strings.
    private static func wrapText(_ text: String, width: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [""] }
        var lines: [String] = []
        var current = ""
        for word in words {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}
