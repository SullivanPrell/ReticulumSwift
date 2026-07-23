import XCTest
@testable import ReticulumSwift

/// Parity table for ``RNXShellWords/split(_:)`` against CPython's `shlex.split`.
///
/// Python reference: RNS/Utilities/rnx.py:36, 179 — `subprocess.Popen(shlex.split(command))`.
///
/// Every expectation below was produced by running the real `shlex.split` on this machine
/// (Python 3.12), not derived from the docs — several of these cases are surprising.
final class RNXShellWordsTests: XCTestCase {

    private func assertSplit(_ input: String, _ expected: [String],
                             file: StaticString = #filePath, line: UInt = #line) {
        do {
            XCTAssertEqual(try RNXShellWords.split(input), expected, file: file, line: line)
        } catch {
            XCTFail("unexpected throw for \(input.debugDescription): \(error)", file: file, line: line)
        }
    }

    // MARK: - The ordinary cases

    func testSimpleSplit() {
        // Python: shlex.split("ls -la") == ['ls', '-la']
        assertSplit("ls -la", ["ls", "-la"])
    }

    func testSingleQuotedGroup() {
        // Python: shlex.split("echo 'a b'") == ['echo', 'a b']
        assertSplit("echo 'a b'", ["echo", "a b"])
    }

    func testDoubleQuotedGroup() {
        // Python: shlex.split('echo "a b"') == ['echo', 'a b']
        assertSplit("echo \"a b\"", ["echo", "a b"])
    }

    func testAdjacentFragmentsConcatenate() {
        // Python: shlex.split('a"b"c') == ['abc']
        assertSplit("a\"b\"c", ["abc"])
    }

    func testEmptyInput() {
        // Python: shlex.split("") == []
        assertSplit("", [])
    }

    func testWhitespaceOnlyInput() {
        // Python: shlex.split("   ") == []
        assertSplit("   ", [])
    }

    func testTabAndNewlineAreWhitespace() {
        // Python: shlex.split("a\tb\nc") == ['a', 'b', 'c']
        assertSplit("a\tb\nc", ["a", "b", "c"])
    }

    // MARK: - No shell

    func testPipeIsAnOrdinaryToken() {
        // Python: shlex.split("ls | grep x") == ['ls', '|', 'grep', 'x'].
        // Proves there is no shell: rnx cannot pipe, in Python or here.
        assertSplit("ls | grep x", ["ls", "|", "grep", "x"])
    }

    func testHashIsNotAComment() {
        // Python: shlex.split clears `commenters`, so shlex.split("echo # comment")
        // == ['echo', '#', 'comment'].
        assertSplit("echo # comment", ["echo", "#", "comment"])
        assertSplit("a#b", ["a#b"])
    }

    // MARK: - Escapes

    func testBackslashOutsideQuotesEscapesVerbatim() {
        // Python: shlex.split('echo \\"quoted\\"') == ['echo', '"quoted"']
        assertSplit("echo \\\"quoted\\\"", ["echo", "\"quoted\""])
    }

    func testBackslashEscapesBackslashInsideDoubleQuotes() {
        // Python: shlex.split('echo "a\\\\b"') == ['echo', 'a\\b']
        assertSplit("echo \"a\\\\b\"", ["echo", "a\\b"])
    }

    func testBackslashIsLiteralBeforeOtherCharactersInsideDoubleQuotes() {
        // Python: escapedquotes is '"' and only \" and \\ are escapes there, so
        // shlex.split('echo "a\\nb"') == ['echo', 'a\\nb'] — the backslash survives.
        assertSplit("echo \"a\\nb\"", ["echo", "a\\nb"])
    }

    func testBackslashBeforeSingleQuoteInsideDoubleQuotesKeepsBackslash() {
        // Python: shlex.split('echo "a\\\'b"') == ['echo', "a\\'b"].
        // NOTE the porting spec claimed ['echo', "a'b"] here; the real shlex disagrees,
        // because ' is not the enclosing quote and not the escape character.
        assertSplit("echo \"a\\'b\"", ["echo", "a\\'b"])
    }

    func testBackslashNewlineIsALiteralNewlineNotAContinuation() {
        // Python: shlex.split('echo a\\\nb') == ['echo', 'a\nb']
        assertSplit("echo a\\\nb", ["echo", "a\nb"])
    }

    // MARK: - Cases that are easy to get wrong

    func testEmptyQuotedStringsProduceEmptyTokens() {
        // Python: shlex.split("a '' b") == ['a', '', 'b'] and the same with "".
        // The token is kept because `quoted` is True even though the token is empty.
        assertSplit("a '' b", ["a", "", "b"])
        assertSplit("a \"\" b", ["a", "", "b"])
    }

    func testVerticalTabAndFormFeedAreNotWhitespace() {
        // Python: shlex.whitespace is ' \t\r\n' — 0x0B and 0x0C are ordinary characters.
        assertSplit("a\u{0B}b", ["a\u{0B}b"])
        assertSplit("a\u{0C}b", ["a\u{0C}b"])
    }

    func testCarriageReturnIsWhitespace() {
        // Python: '\r' IS in shlex.whitespace.
        assertSplit("a\rb", ["a", "b"])
    }

    func testWhitespaceSetMatchesPython() {
        XCTAssertEqual(RNXShellWords.whitespace, [" ", "\t", "\r", "\n"])
        XCTAssertFalse(RNXShellWords.whitespace.contains("\u{0B}"))
        XCTAssertFalse(RNXShellWords.whitespace.contains("\u{0C}"))
    }

    // MARK: - Errors

    func testUnterminatedSingleQuote() throws {
        // Python: ValueError("No closing quotation")
        XCTAssertThrowsError(try RNXShellWords.split("echo 'unterminated")) { error in
            XCTAssertEqual(error as? RNXShellWords.ShellWordsError, .noClosingQuotation("'"))
        }
    }

    func testUnterminatedDoubleQuote() throws {
        XCTAssertThrowsError(try RNXShellWords.split("echo \"open")) { error in
            XCTAssertEqual(error as? RNXShellWords.ShellWordsError, .noClosingQuotation("\""))
        }
    }

    func testTrailingBackslash() throws {
        // Python: ValueError("No escaped character")
        XCTAssertThrowsError(try RNXShellWords.split("echo trailing\\")) { error in
            XCTAssertEqual(error as? RNXShellWords.ShellWordsError, .noEscapedCharacter)
        }
        XCTAssertThrowsError(try RNXShellWords.split("\\")) { error in
            XCTAssertEqual(error as? RNXShellWords.ShellWordsError, .noEscapedCharacter)
        }
    }

    func testBackslashIsFullyLiteralInsideSingleQuotes() throws {
        // Python: shlex.split("echo 'it\\'s'") raises "No closing quotation", because the
        // backslash does not escape the closing quote inside single quotes.
        XCTAssertThrowsError(try RNXShellWords.split("echo 'it\\'s'")) { error in
            XCTAssertEqual(error as? RNXShellWords.ShellWordsError, .noClosingQuotation("'"))
        }
    }
}
