import Foundation

/// The `rnx --help` output, byte-identical to what `argparse` prints.
///
/// Python reference: the parser built in `RNS/Utilities/rnx.py:555-576`, rendered by
/// `argparse.HelpFormatter`.
///
/// ``ArgumentParser`` (the shared in-library argparse subset) drives *parsing*, but its
/// `usage` property emits a simplified `usage: rnx [options] …` line and pads the flag
/// column to 26 rather than argparse's 24. Reproducing the real layout here — rather than
/// rewriting the shared formatter that every sibling utility also renders through — keeps
/// `rnx --help` diff-clean against the installed Python utility.
///
/// The layout rules implemented below are argparse's own:
/// - terminal width 78 (`shutil.get_terminal_size().columns - 2`, 80 when not a tty);
/// - usage lines wrap at 78 and continue at `len("usage: ") + len(prog) + 1` = 11 columns,
///   with optionals and positionals wrapped as two separate groups;
/// - `help_position = min(action_max_length + 2, 24)`, which for rnx is exactly 24;
/// - each entry is two spaces, the invocation left-justified to 20, then two spaces.
public enum RNXHelpText {

    /// Python: `argparse` derives this from `sys.argv[0]`; the installed script is `rnx`.
    public static let program = "rnx"

    /// Python: `ArgumentParser(description="Reticulum Remote Execution Utility")`.
    public static let description = "Reticulum Remote Execution Utility"

    /// Python: `shutil.get_terminal_size().columns - 2`, i.e. 78 for a non-tty.
    static let width = 78

    /// Python: `HelpFormatter._max_help_position` resolved against rnx's longest
    /// invocation ("-p, --print-identity", 20 + 2 indent = 22 → min(24, 24)).
    static let helpPosition = 24

    struct Entry {
        let invocation: String
        let help: String
    }

    /// Order matches `add_argument` calls, which is the order argparse prints.
    static let positionals: [Entry] = [
        Entry(invocation: "destination", help: "hexadecimal hash of the listener"),
        // Python's help string really does read "command to be execute" — reproduced verbatim.
        Entry(invocation: "command", help: "command to be execute"),
    ]

    static let options: [Entry] = [
        Entry(invocation: "-h, --help", help: "show this help message and exit"),
        Entry(invocation: "--config path", help: "path to alternative Reticulum config directory"),
        Entry(invocation: "-v, --verbose", help: "increase verbosity"),
        Entry(invocation: "-q, --quiet", help: "decrease verbosity"),
        Entry(invocation: "-p, --print-identity", help: "print identity and destination info and exit"),
        Entry(invocation: "-l, --listen", help: "listen for incoming commands"),
        Entry(invocation: "-i identity", help: "path to identity to use"),
        Entry(invocation: "-x, --interactive", help: "enter interactive mode"),
        Entry(invocation: "-b, --no-announce", help: "don't announce at program start"),
        Entry(invocation: "-a allowed_hash", help: "accept from this identity"),
        Entry(invocation: "-n, --noauth", help: "accept commands from anyone"),
        Entry(invocation: "-N, --noid", help: "don't identify to listener"),
        Entry(invocation: "-d, --detailed", help: "show detailed result output"),
        Entry(invocation: "-m", help: "mirror exit code of remote command"),
        Entry(invocation: "-w seconds", help: "connect and request timeout before giving up"),
        Entry(invocation: "-W seconds", help: "max result download time"),
        Entry(invocation: "--stdin STDIN", help: "pass input to stdin"),
        Entry(invocation: "--stdout STDOUT", help: "max size in bytes of returned stdout"),
        Entry(invocation: "--stderr STDERR", help: "max size in bytes of returned stderr"),
        Entry(invocation: "--version", help: "show program's version number and exit"),
    ]

    /// Usage-line fragments for the optionals, in declaration order. argparse uses only
    /// the first option string of each action, and `dest.upper()` when no metavar is set.
    static let usageOptionals: [String] = [
        "[-h]", "[--config path]", "[-v]", "[-q]", "[-p]", "[-l]", "[-i identity]",
        "[-x]", "[-b]", "[-a allowed_hash]", "[-n]", "[-N]", "[-d]", "[-m]",
        "[-w seconds]", "[-W seconds]", "[--stdin STDIN]", "[--stdout STDOUT]",
        "[--stderr STDERR]", "[--version]",
    ]

    /// `nargs="?"` renders as `[name]`.
    static let usagePositionals: [String] = ["[destination]", "[command]"]

    /// The `usage:` block, with no trailing newline.
    public static var usage: String {
        let prefix = "usage: "
        let indent = String(repeating: " ", count: prefix.count + program.count + 1)
        var lines = wrap([program] + usageOptionals, indent: indent, prefix: prefix)
        lines.append(contentsOf: wrap(usagePositionals, indent: indent, prefix: nil))
        return prefix + lines.joined(separator: "\n")
    }

    /// The complete `--help` output, ending in exactly one newline — what
    /// `parser.print_help()` writes.
    public static var help: String {
        var lines: [String] = []
        lines.append(contentsOf: usage.components(separatedBy: "\n"))
        lines.append("")
        lines.append(description)
        lines.append("")
        lines.append("positional arguments:")
        for entry in positionals { lines.append(contentsOf: format(entry)) }
        lines.append("")
        lines.append("options:")
        for entry in options { lines.append(contentsOf: format(entry)) }
        // argparse: `formatted.strip('\n') + '\n'`.
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - argparse layout primitives

    /// Faithful port of the nested `get_lines` inside `HelpFormatter._format_usage`.
    private static func wrap(_ parts: [String], indent: String, prefix: String?) -> [String] {
        var lines: [String] = []
        var line: [String] = []
        var lineLength = (prefix.map { $0.count } ?? indent.count) - 1

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
        if prefix != nil, !lines.isEmpty { lines[0] = String(lines[0].dropFirst(indent.count)) }
        return lines
    }

    /// argparse `_format_action`: `'%*s%-*s  ' % (indent, '', action_width, header)` when
    /// the header fits, otherwise the header alone and the help on the following line
    /// indented to `help_position`.
    private static func format(_ entry: Entry) -> [String] {
        let currentIndent = 2
        let actionWidth = helpPosition - currentIndent - 2      // 20
        let helpWidth = max(width - helpPosition, 11)           // 54
        let wrappedHelp = wordWrap(entry.help, width: helpWidth)

        var lines: [String] = []
        if entry.invocation.count <= actionWidth {
            let padded = entry.invocation.padding(toLength: actionWidth, withPad: " ", startingAt: 0)
            lines.append(String(repeating: " ", count: currentIndent) + padded + "  " + (wrappedHelp.first ?? ""))
            for extra in wrappedHelp.dropFirst() {
                lines.append(String(repeating: " ", count: helpPosition) + extra)
            }
        } else {
            lines.append(String(repeating: " ", count: currentIndent) + entry.invocation)
            for extra in wrappedHelp {
                lines.append(String(repeating: " ", count: helpPosition) + extra)
            }
        }
        return lines
    }

    private static func wordWrap(_ text: String, width: Int) -> [String] {
        guard !text.isEmpty else { return [""] }
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: true) {
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
        return lines
    }
}
