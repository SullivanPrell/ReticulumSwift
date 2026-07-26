import Foundation

/// Reproduces Python `argparse.HelpFormatter`'s `--help` layout for an ``ArgumentParser``.
///
/// The utilities' help text is part of their user-facing contract, and `argparse`'s layout
/// has several non-obvious rules that a naive "pad to 24 columns" renderer gets wrong. This
/// implements the ones that matter, verified against the captured output of the installed
/// `rnid` (`pyref/rnid_help.txt`):
///
/// - **Usage wrapping.** The usage line is broken into `[-x]`-style parts and greedily
///   packed into `width` columns; continuation lines are indented by
///   `len("usage: ") + len(prog) + 1`.
/// - **Invocation column.** An option's invocation goes on the same line as its help only
///   when it fits in `helpPosition - 4` characters (20 by default); otherwise the help starts
///   on the next line, indented to `helpPosition`.
/// - **Metavar repetition.** Python ≤ 3.12 renders `-i rid, --identity rid`, repeating the
///   metavar after every spelling. (Python 3.13 changed this to `-i, --identity rid`; the
///   reference output was captured from a ≤3.12 interpreter, so the older form is used.)
/// - **Help wrapping.** Help text is word-wrapped to `max(width - helpPosition, 11)` columns.
/// - **Suppressed options.** `help=argparse.SUPPRESS` options appear in neither the usage
///   line nor the option list.
///
/// `width` is fixed rather than read from the terminal so the output is deterministic;
/// `argparse` uses `shutil.get_terminal_size().columns - 2`, which is 78 in an 80-column
/// terminal — the value the reference output was captured at.
/// rnid's own argparse help renderer.
///
/// Distinct from ``ArgparseHelp`` (which rnprobe uses): that one models argparse's
/// `HelpFormatter` around its own `Entry` type, while this one renders from
/// ``ArgumentParser/OptionSpec``. Both reproduce argparse's layout byte-for-byte for
/// their own tool and are covered by their own tests. Consolidating them is worthwhile
/// but is a refactor in its own right, not a merge artefact to rush.
public enum RNIDArgparseHelp {

    /// Python: `HelpFormatter._max_help_position` default.
    public static let helpPosition = 24
    /// Python: `HelpFormatter(width=shutil.get_terminal_size().columns - 2)`.
    public static let defaultWidth = 78

    /// The implicit `-h, --help` action argparse adds first.
    public static let helpOption = ArgumentParser.OptionSpec(
        names: ["-h", "--help"], metavar: nil, nargs: .none,
        help: "show this help message and exit", hidden: false)

    /// Render the complete `--help` text, without a trailing newline.
    public static func render(program: String,
                              description: String,
                              options: [ArgumentParser.OptionSpec],
                              width: Int = defaultWidth) -> String {
        let all = [helpOption] + options
        let visible = all.filter { !$0.hidden }

        var out = usage(program: program, options: visible, width: width)
        out += "\n\n" + description
        out += "\n\noptions:\n"
        out += optionList(visible, width: width)
        return out
    }

    // MARK: - Usage

    /// Python: `HelpFormatter._format_usage`.
    public static func usage(program: String,
                             options: [ArgumentParser.OptionSpec],
                             width: Int = defaultWidth) -> String {
        let prefix = "usage: "
        let parts = options.map { usagePart($0) }
        let singleLine = ([program] + parts).joined(separator: " ")
        if prefix.count + singleLine.count <= width {
            return prefix + singleLine
        }

        // Python indents continuation lines under the program name.
        let indent = String(repeating: " ", count: prefix.count + program.count + 1)
        var lines: [String] = []
        var current: [String] = []
        var lineLength = prefix.count - 1

        for part in [program] + parts {
            if lineLength + 1 + part.count > width, !current.isEmpty {
                lines.append(indent + current.joined(separator: " "))
                current = []
                lineLength = indent.count - 1
            }
            current.append(part)
            lineLength += 1 + part.count
        }
        if !current.isEmpty { lines.append(indent + current.joined(separator: " ")) }
        // Python strips the indent from the first line, then prepends the prefix.
        if let first = lines.first { lines[0] = String(first.dropFirst(indent.count)) }
        return prefix + lines.joined(separator: "\n")
    }

    /// Python: the `[%s]` wrapping in `_format_actions_usage`.
    private static func usagePart(_ spec: ArgumentParser.OptionSpec) -> String {
        let name = spec.names[0]
        guard let arguments = argumentsString(spec) else { return "[\(name)]" }
        return "[\(name) \(arguments)]"
    }

    // MARK: - Option list

    /// Python: `HelpFormatter._format_action` for every action in the "options" group.
    private static func optionList(_ options: [ArgumentParser.OptionSpec], width: Int) -> String {
        // Python: action_width = help_position - current_indent - 2, with current_indent 2.
        let actionWidth = helpPosition - 4
        let helpWidth = max(width - helpPosition, 11)
        var lines: [String] = []

        for spec in options {
            let invocation = self.invocation(spec)
            let wrapped = wrap(spec.help, to: helpWidth)

            if invocation.count <= actionWidth {
                let padded = invocation.padding(toLength: actionWidth + 2, withPad: " ", startingAt: 0)
                lines.append("  " + padded + (wrapped.first ?? ""))
            } else {
                lines.append("  " + invocation)
                lines.append(String(repeating: " ", count: helpPosition) + (wrapped.first ?? ""))
            }
            for continuation in wrapped.dropFirst() {
                lines.append(String(repeating: " ", count: helpPosition) + continuation)
            }
        }
        // No trailing newline: callers `print` this, which supplies the final one, matching
        // argparse's `format_help()` + `_print_message` pair.
        return lines.joined(separator: "\n")
    }

    /// Python ≤ 3.12: `', '.join('%s %s' % (option_string, args_string) …)`.
    private static func invocation(_ spec: ArgumentParser.OptionSpec) -> String {
        guard let arguments = argumentsString(spec) else { return spec.names.joined(separator: ", ") }
        return spec.names.map { "\($0) \(arguments)" }.joined(separator: ", ")
    }

    /// Python: `HelpFormatter._format_args`. `nil` when the action takes no value.
    private static func argumentsString(_ spec: ArgumentParser.OptionSpec) -> String? {
        guard let metavar = spec.metavar else { return nil }
        switch spec.nargs {
        case .none:     return nil
        case .one:      return metavar
        case .optional: return "[\(metavar)]"
        case .any:      return "[\(metavar) ...]"
        }
    }

    // MARK: - Text wrapping

    /// Python: `textwrap.wrap(text, width)` — greedy, breaking only on whitespace.
    static func wrap(_ text: String, to width: Int) -> [String] {
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
