import Foundation

/// A port of CPython's `shlex.split(s)` — the exact call `rnx` uses to turn a command
/// string into an argv before handing it to `subprocess.Popen`.
///
/// Python reference: `RNS/Utilities/rnx.py:36, 179`, backed by CPython's
/// `shlex.split` / `shlex.shlex.read_token` in POSIX mode.
///
/// `shlex.split(s)` is `shlex(s, posix=True)` with `whitespace_split = True` and
/// `commenters` cleared, which produces a handful of behaviours that are easy to get
/// wrong and are all reproduced here:
///
/// - Only `space`, `tab`, `CR` and `LF` separate words. Vertical tab (0x0B) and form
///   feed (0x0C) are **ordinary characters**, so `"a\u{0B}b"` is a single token.
/// - An empty quoted string produces an **empty token**: `a '' b` → `["a", "", "b"]`.
/// - Inside single quotes everything is literal, *including backslashes*, so
///   `'it\'s'` raises ``ShellWordsError/noClosingQuotation(_:)``.
/// - Inside double quotes a backslash escapes only `"` and `\`; before anything else the
///   backslash survives, so `"a\nb"` is the four characters `a \ n b`.
/// - Outside quotes a backslash escapes the next character verbatim — including a
///   newline, which yields a **literal newline** rather than a line continuation.
/// - `#` is not a comment introducer (`commenters` is cleared), so
///   `echo # comment` → `["echo", "#", "comment"]`.
///
/// There is no shell involved: pipes, redirects, globs and `&&` all come out as plain
/// argv elements, exactly as in Python. Do not "fix" this — it is wire-visible behaviour.
public enum RNXShellWords {

    /// Python: `shlex.shlex.whitespace = ' \t\r\n'`. Deliberately excludes `\u{0B}`/`\u{0C}`.
    public static let whitespace: Set<Character> = [" ", "\t", "\r", "\n"]

    /// Python: `shlex.shlex.quotes = '\'"'`.
    private static let quotes: Set<Character> = ["'", "\""]

    /// Python: `shlex.shlex.escapedquotes = '"'` — backslash escaping only happens
    /// inside double quotes, never inside single quotes.
    private static let escapedQuotes: Set<Character> = ["\""]

    private static let escape: Character = "\\"

    public enum ShellWordsError: Error, Equatable {
        /// Python: `ValueError("No closing quotation")`. Carries the quote character that
        /// was left open, which CPython's message does not.
        case noClosingQuotation(Character)
        /// Python: `ValueError("No escaped character")` — a trailing lone backslash.
        case noEscapedCharacter
    }

    /// Which branch of `read_token`'s state machine we are in.
    /// Mirrors CPython's `self.state`, where the state is literally a character.
    private enum State: Equatable {
        case whitespace     // Python state ' '
        case word           // Python state 'a'
        case quoted(Character)
        case escaped(returningTo: EscapedState)
    }

    /// Python's `escapedstate`: either `'a'` (plain word) or the quote we were inside.
    private enum EscapedState: Equatable {
        case word
        case quote(Character)
    }

    /// Split `input` the way `shlex.split` does.
    ///
    /// - Throws: ``ShellWordsError`` for an unterminated quote or a trailing backslash,
    ///   matching the two `ValueError`s CPython raises.
    public static func split(_ input: String) throws -> [String] {
        var tokens: [String] = []
        let characters = Array(input)
        var index = 0

        // Python's read_token loop, called repeatedly until it returns None.
        while true {
            var token = ""
            var quoted = false
            var state: State = .whitespace
            var reachedEOF = false

            loop: while true {
                let next: Character? = index < characters.count ? characters[index] : nil
                if next != nil { index += 1 }

                switch state {
                case .whitespace:
                    guard let c = next else { reachedEOF = true; break loop }
                    if whitespace.contains(c) {
                        // Python: `if self.token or (self.posix and quoted): break`
                        if !token.isEmpty || quoted { break loop }
                        continue
                    } else if c == escape {
                        state = .escaped(returningTo: .word)
                    } else if quotes.contains(c) {
                        // POSIX mode does not keep the quote character itself.
                        state = .quoted(c)
                    } else {
                        // whitespace_split = True: any other character starts a word.
                        token.append(c)
                        state = .word
                    }

                case .quoted(let quote):
                    quoted = true
                    guard let c = next else { throw ShellWordsError.noClosingQuotation(quote) }
                    if c == quote {
                        state = .word
                    } else if c == escape, escapedQuotes.contains(quote) {
                        state = .escaped(returningTo: .quote(quote))
                    } else {
                        token.append(c)
                    }

                case .escaped(let escapedState):
                    guard let c = next else { throw ShellWordsError.noEscapedCharacter }
                    // Python: "In posix shells, only the quote itself or the escape
                    // character may be escaped by it." Anything else keeps the backslash.
                    if case .quote(let quote) = escapedState, c != escape, c != quote {
                        token.append(escape)
                    }
                    token.append(c)
                    switch escapedState {
                    case .word:            state = .word
                    case .quote(let q):    state = .quoted(q)
                    }

                case .word:
                    guard let c = next else { reachedEOF = true; break loop }
                    if whitespace.contains(c) {
                        state = .whitespace
                        if !token.isEmpty || quoted { break loop }
                        continue
                    } else if quotes.contains(c) {
                        state = .quoted(c)
                    } else if c == escape {
                        state = .escaped(returningTo: .word)
                    } else {
                        token.append(c)
                    }
                }
            }

            // Python: `if self.posix and not quoted and result == '': result = None`,
            // and a None result ends `list(lex)`. Inspecting read_token's break points
            // shows this can only happen at end of input, so it is the loop's exit.
            if token.isEmpty && !quoted { break }
            tokens.append(token)
            if reachedEOF { break }
        }

        return tokens
    }
}
