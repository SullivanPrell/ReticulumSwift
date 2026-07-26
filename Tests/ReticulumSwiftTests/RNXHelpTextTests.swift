import XCTest
@testable import ReticulumSwift

/// `rnx --help` must be byte-identical to argparse's output.
///
/// Golden value below was captured from the installed Python utility on this machine:
///     $ rnx --help
/// (RNS 1.4.0, `~/anaconda3/bin/rnx`). Every space in it is load-bearing.
final class RNXHelpTextTests: XCTestCase {

    /// Captured verbatim from `rnx --help`.
    private let golden = """
    usage: rnx [-h] [--config path] [-v] [-q] [-p] [-l] [-i identity] [-x] [-b]
               [-a allowed_hash] [-n] [-N] [-d] [-m] [-w seconds] [-W seconds]
               [--stdin STDIN] [--stdout STDOUT] [--stderr STDERR] [--version]
               [destination] [command]

    Reticulum Remote Execution Utility

    positional arguments:
      destination           hexadecimal hash of the listener
      command               command to be execute

    options:
      -h, --help            show this help message and exit
      --config path         path to alternative Reticulum config directory
      -v, --verbose         increase verbosity
      -q, --quiet           decrease verbosity
      -p, --print-identity  print identity and destination info and exit
      -l, --listen          listen for incoming commands
      -i identity           path to identity to use
      -x, --interactive     enter interactive mode
      -b, --no-announce     don't announce at program start
      -a allowed_hash       accept from this identity
      -n, --noauth          accept commands from anyone
      -N, --noid            don't identify to listener
      -d, --detailed        show detailed result output
      -m                    mirror exit code of remote command
      -w seconds            connect and request timeout before giving up
      -W seconds            max result download time
      --stdin STDIN         pass input to stdin
      --stdout STDOUT       max size in bytes of returned stdout
      --stderr STDERR       max size in bytes of returned stderr
      --version             show program's version number and exit

    """

    func testHelpMatchesPythonByteForByte() {
        XCTAssertEqual(RNXHelpText.help, golden)
    }

    func testHelpEndsWithExactlyOneNewline() {
        // argparse: `formatted.strip('\n') + '\n'`.
        XCTAssertTrue(RNXHelpText.help.hasSuffix("exit\n"))
        XCTAssertFalse(RNXHelpText.help.hasSuffix("\n\n"))
        XCTAssertEqual(RNXHelpText.help.components(separatedBy: "\n").count - 1, 32)
    }

    func testUsageWrapsWhereArgparseWraps() {
        // argparse wraps at width 78 and continues at len("usage: ")+len("rnx")+1 = 11.
        let lines = RNXHelpText.usage.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].hasPrefix("usage: rnx [-h]"))
        for line in lines.dropFirst() {
            XCTAssertTrue(line.hasPrefix(String(repeating: " ", count: 11)))
        }
        for line in lines { XCTAssertLessThanOrEqual(line.count, 78) }
        XCTAssertEqual(lines[3], String(repeating: " ", count: 11) + "[destination] [command]")
    }

    func testHelpColumnIsAt24() {
        // argparse: help_position = min(action_max_length + 2, 24); for rnx the longest
        // invocation is "-p, --print-identity" (20) + 2 indent = 22, so it lands on 24.
        XCTAssertEqual(RNXHelpText.helpPosition, 24)
        for line in RNXHelpText.help.components(separatedBy: "\n") where line.hasPrefix("  -") {
            let characters = Array(line)
            XCTAssertGreaterThan(characters.count, 24, "short option line: \(line)")
            XCTAssertEqual(characters[23], " ", "help column starts early in: \(line)")
            XCTAssertNotEqual(characters[24], " ", "help column starts late in: \(line)")
        }
    }

    func testPythonTypoInCommandHelpIsPreserved() {
        // Python's help string really is "command to be execute" (rnx.py:557).
        XCTAssertTrue(RNXHelpText.help.contains("command               command to be execute"))
    }
}
