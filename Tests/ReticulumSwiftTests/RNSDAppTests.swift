import XCTest
@testable import ReticulumSwift

/// Command-line parity for `rnsd`, `rnir` and `rnpkg`.
///
/// Python reference: `RNS/Utilities/rnsd.py:62-88`, `rnir.py:53-76`, `rnpkg.py:51-76`.
///
/// The golden strings below were captured from the *installed* Python utilities on this
/// machine (`rnsd --help`, `rnir --help`, `rnpkg --help`, and the three `argparse` error
/// pages) under Python 3.11 — not hand-written. Python 3.9 and older print
/// `optional arguments:` where 3.10+ prints `options:`; 3.10+ is the target.
final class RNSDAppTests: XCTestCase {

    // MARK: - Parsing

    func testParseEmptyArgvGivesDefaults() throws {
        let options = try RNSDApp.parse([], allowServiceFlags: true)
        XCTAssertEqual(options, RNSDApp.Options())
        XCTAssertNil(options.configDir)
        XCTAssertEqual(options.verbose, 0)
        XCTAssertEqual(options.quiet, 0)
        XCTAssertFalse(options.service)
        XCTAssertFalse(options.interactive)
        XCTAssertFalse(options.exampleConfig)
        XCTAssertFalse(options.version)
        XCTAssertFalse(options.help)
    }

    func testVerbosityCounting() throws {
        // Python: `-v', '--verbose', action='count', default=0`.
        XCTAssertEqual(try RNSDApp.parse(["-v"], allowServiceFlags: true).verbose, 1)
        XCTAssertEqual(try RNSDApp.parse(["-vv"], allowServiceFlags: true).verbose, 2)
        XCTAssertEqual(try RNSDApp.parse(["-vvv"], allowServiceFlags: true).verbose, 3)
        XCTAssertEqual(try RNSDApp.parse(["-v", "-v"], allowServiceFlags: true).verbose, 2)
        XCTAssertEqual(try RNSDApp.parse(["--verbose", "--verbose"], allowServiceFlags: true).verbose, 2)
    }

    func testQuietCountingAndDelta() throws {
        let quiet = try RNSDApp.parse(["-qq"], allowServiceFlags: true)
        XCTAssertEqual(quiet.quiet, 2)
        // Python: `targetverbosity = verbosity-quietness` (rnsd.py:41) — may be negative.
        XCTAssertEqual(quiet.verbosityDelta, -2)

        let mixed = try RNSDApp.parse(["-vvv", "-q"], allowServiceFlags: true)
        XCTAssertEqual(mixed.verbose, 3)
        XCTAssertEqual(mixed.quiet, 1)
        XCTAssertEqual(mixed.verbosityDelta, 2)
    }

    func testShortFlagClusters() throws {
        let vq = try RNSDApp.parse(["-vq"], allowServiceFlags: true)
        XCTAssertEqual(vq.verbose, 1)
        XCTAssertEqual(vq.quiet, 1)
        XCTAssertEqual(vq.verbosityDelta, 0)

        for argv in [["-vs"], ["-sv"]] {
            let parsed = try RNSDApp.parse(argv, allowServiceFlags: true)
            XCTAssertEqual(parsed.verbose, 1, "\(argv)")
            XCTAssertTrue(parsed.service, "\(argv)")
        }
    }

    func testServiceModeDiscardsVerbosity() throws {
        // Python: `if service: targetlogdest = RNS.LOG_FILE; targetverbosity = None` (rnsd.py:43-45)
        let options = try RNSDApp.parse(["-s", "-vvv"], allowServiceFlags: true)
        XCTAssertEqual(options.verbosityDelta, 3)
        XCTAssertNil(options.effectiveVerbosity)

        let noService = try RNSDApp.parse(["-vvv"], allowServiceFlags: true)
        XCTAssertEqual(noService.effectiveVerbosity, 3)
    }

    func testConfigTakesNextArgument() throws {
        for argv in [["--config", "/tmp/x"], ["--config=/tmp/x"]] {
            XCTAssertEqual(try RNSDApp.parse(argv, allowServiceFlags: true).configDir, "/tmp/x", "\(argv)")
        }
    }

    func testSwiftOnlyConfigDirectoryAliases() throws {
        // Not Python spellings — kept because the pre-parity Swift rnsd accepted them with
        // exactly this meaning. They are hidden from --help and from prefix abbreviation.
        for argv in [["--config-dir", "/tmp/x"], ["-d", "/tmp/x"], ["--config-dir=/tmp/x"]] {
            XCTAssertEqual(try RNSDApp.parse(argv, allowServiceFlags: true).configDir, "/tmp/x", "\(argv)")
        }
    }

    func testEmptyConfigBecomesNil() throws {
        // Python: `if args.config:` is falsy for '' → configarg stays None (rnsd.py:79-82).
        XCTAssertNil(try RNSDApp.parse(["--config", ""], allowServiceFlags: true).configDir)
    }

    func testConfigMissingValueThrows() {
        XCTAssertThrowsError(try RNSDApp.parse(["--config"], allowServiceFlags: true)) { error in
            XCTAssertEqual(error as? ArgumentError, .missingValue("--config"))
            // Python: "rnsd: error: argument --config: expected one argument"
            XCTAssertEqual((error as? ArgumentError)?.description,
                           "argument --config: expected one argument")
        }
    }

    func testUnrecognizedArgumentThrows() {
        XCTAssertThrowsError(try RNSDApp.parse(["--bogus"], allowServiceFlags: true)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["--bogus"]))
        }
        // Python reports every leftover in one message, in argv order.
        XCTAssertThrowsError(try RNSDApp.parse(["--bogus", "extra"], allowServiceFlags: true)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["--bogus", "extra"]))
        }
        // …but only the leftovers: `-v` is consumed first.
        XCTAssertThrowsError(try RNSDApp.parse(["-v", "--bogus"], allowServiceFlags: true)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["--bogus"]))
        }
    }

    func testBarePositionalIsAnError() {
        // Python declares no positionals: `rnsd extra` → "unrecognized arguments: extra", exit 2.
        XCTAssertThrowsError(try RNSDApp.parse(["extra"], allowServiceFlags: true)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["extra"]))
        }
    }

    func testShortCIsRejectedLikePython() {
        // Verified against the real parser: `rnsd -c /tmp/x` → exit 2, "unrecognized arguments".
        // The pre-parity Swift rnsd accepted -c as a config *file*; that meaning is dropped.
        XCTAssertThrowsError(try RNSDApp.parse(["-c", "/tmp/x"], allowServiceFlags: true)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["-c", "/tmp/x"]))
        }
    }

    func testPrefixAbbreviation() throws {
        // Python: argparse's allow_abbrev defaults to True.
        XCTAssertEqual(try RNSDApp.parse(["--conf", "/tmp/x"], allowServiceFlags: true).configDir, "/tmp/x")
        XCTAssertEqual(try RNSDApp.parse(["--co", "/tmp/x"], allowServiceFlags: true).configDir, "/tmp/x")
        XCTAssertEqual(try RNSDApp.parse(["--confi=/tmp/x"], allowServiceFlags: true).configDir, "/tmp/x")
        XCTAssertEqual(try RNSDApp.parse(["--verb"], allowServiceFlags: true).verbose, 1)
        XCTAssertTrue(try RNSDApp.parse(["--exam"], allowServiceFlags: true).exampleConfig)
    }

    func testAmbiguousAbbreviationThrows() {
        XCTAssertThrowsError(try RNSDApp.parse(["--ver"], allowServiceFlags: true)) { error in
            XCTAssertEqual(error as? ArgumentError,
                           .ambiguousOption("--ver", ["--verbose", "--version"]))
        }
        let text = RNSDApp.errorText(program: "rnsd", allowServiceFlags: true,
                                     error: ArgumentError.ambiguousOption("--ver", ["--verbose", "--version"]))
        // Python: "rnsd: error: ambiguous option: --ver could match --verbose, --version"
        XCTAssertTrue(text.hasSuffix("rnsd: error: ambiguous option: --ver could match --verbose, --version"),
                      text)
    }

    func testServiceAndInteractiveRejectedForRnirAndRnpkg() throws {
        for argument in ["-s", "-i", "--service", "--interactive"] {
            XCTAssertThrowsError(try RNSDApp.parse([argument], allowServiceFlags: false),
                                 "rnir must reject \(argument)") { error in
                XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments([argument]))
            }
        }
        XCTAssertTrue(try RNSDApp.parse(["-s"], allowServiceFlags: true).service)
        XCTAssertTrue(try RNSDApp.parse(["-i"], allowServiceFlags: true).interactive)
    }

    func testHelpAndVersionFlags() throws {
        XCTAssertTrue(try RNSDApp.parse(["-h"], allowServiceFlags: true).help)
        XCTAssertTrue(try RNSDApp.parse(["--help"], allowServiceFlags: true).help)
        // argparse recognises -h anywhere in argv.
        XCTAssertTrue(try RNSDApp.parse(["-v", "--help"], allowServiceFlags: true).help)
        XCTAssertTrue(try RNSDApp.parse(["--version"], allowServiceFlags: true).version)
    }

    // MARK: - Help text

    /// Byte-for-byte capture of `rnsd --help` from the installed Python utility.
    private static let pythonRnsdHelp = """
usage: rnsd [-h] [--config CONFIG] [-v] [-q] [-s] [-i] [--exampleconfig]
            [--version]

Reticulum Network Stack Daemon

options:
  -h, --help         show this help message and exit
  --config CONFIG    path to alternative Reticulum config directory
  -v, --verbose
  -q, --quiet
  -s, --service      rnsd is running as a service and should log to file
  -i, --interactive  drop into interactive shell after initialisation
  --exampleconfig    print verbose configuration example to stdout and exit
  --version          show program's version number and exit
"""

    /// Byte-for-byte capture of `rnir --help`.
    private static let pythonRnirHelp = """
usage: rnir [-h] [--config CONFIG] [-v] [-q] [--exampleconfig] [--version]

Reticulum Distributed Identity Resolver

options:
  -h, --help       show this help message and exit
  --config CONFIG  path to alternative Reticulum config directory
  -v, --verbose
  -q, --quiet
  --exampleconfig  print verbose configuration example to stdout and exit
  --version        show program's version number and exit
"""

    func testHelpTextMatchesPythonForRnsd() {
        let rendered = RNSDApp.helpText(program: RNSDApp.appName,
                                        description: RNSDApp.description,
                                        allowServiceFlags: true)
        XCTAssertEqual(rendered, Self.pythonRnsdHelp)
    }

    func testHelpTextMatchesPythonForRnir() {
        let rendered = RNSDApp.helpText(program: RNSDApp.rnirAppName,
                                        description: RNSDApp.rnirDescription,
                                        allowServiceFlags: false)
        XCTAssertEqual(rendered, Self.pythonRnirHelp)
    }

    func testHelpTextMatchesPythonForRnpkg() {
        // rnpkg's page is rnir's with the program name and description swapped.
        let expected = Self.pythonRnirHelp
            .replacingOccurrences(of: "usage: rnir", with: "usage: rnpkg")
            .replacingOccurrences(of: "Reticulum Distributed Identity Resolver",
                                  with: "Reticulum Meta Package Manager")
        let rendered = RNSDApp.helpText(program: RNSDApp.rnpkgAppName,
                                        description: RNSDApp.rnpkgDescription,
                                        allowServiceFlags: false)
        XCTAssertEqual(rendered, expected)
    }

    func testHelpGutterWidths() {
        // argparse: help_position = min(max(len(invocation)) + 2 + 2, 24).
        // rnsd's longest invocation is "-i, --interactive" (17) → column 21.
        // rnir/rnpkg's longest is "--config CONFIG" (15) → column 19.
        /// Column at which the `--config` row's help text starts.
        func helpColumn(in text: String) -> Int {
            // Anchored on the options-table row, not the usage line, which also mentions
            // "--config CONFIG".
            let row = text.split(separator: "\n").first { $0.hasPrefix("  --config CONFIG") }!
            guard let start = row.range(of: "path to alternative") else { return -1 }
            return row.distance(from: row.startIndex, to: start.lowerBound)
        }

        XCTAssertEqual(helpColumn(in: RNSDApp.helpText(program: "rnsd",
                                                       description: RNSDApp.description,
                                                       allowServiceFlags: true)), 21)
        XCTAssertEqual(helpColumn(in: RNSDApp.helpText(program: "rnir",
                                                       description: RNSDApp.rnirDescription,
                                                       allowServiceFlags: false)), 19)
    }

    func testHelplessRowsHaveNoTrailingWhitespace() {
        // argparse's `if not action.help:` branch emits the bare invocation with no padding.
        let lines = RNSDApp.helpText(program: "rnsd", description: RNSDApp.description,
                                     allowServiceFlags: true)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        XCTAssertTrue(lines.contains("  -v, --verbose"))
        XCTAssertTrue(lines.contains("  -q, --quiet"))
        for line in lines {
            XCTAssertFalse(line.hasSuffix(" "), "trailing whitespace in: \(line.debugDescription)")
        }
    }

    // MARK: - Usage and error text

    func testUsageWrapsLikeArgparse() {
        // rnsd's option list overflows 78 columns, so argparse wraps and indents the
        // continuation to len("usage: ") + len("rnsd") + 1 == 12.
        XCTAssertEqual(RNSDApp.usageText(program: "rnsd", allowServiceFlags: true), """
usage: rnsd [-h] [--config CONFIG] [-v] [-q] [-s] [-i] [--exampleconfig]
            [--version]
""")
        // rnir's fits, so it stays on one line.
        XCTAssertEqual(RNSDApp.usageText(program: "rnir", allowServiceFlags: false),
                       "usage: rnir [-h] [--config CONFIG] [-v] [-q] [--exampleconfig] [--version]")
    }

    func testErrorText() {
        let text = RNSDApp.errorText(program: "rnsd", allowServiceFlags: true,
                                     error: ArgumentError.unrecognisedArguments(["--bogus"]))
        XCTAssertTrue(text.hasPrefix(RNSDApp.usageText(program: "rnsd", allowServiceFlags: true)))
        XCTAssertTrue(text.hasSuffix("rnsd: error: unrecognized arguments: --bogus"), text)
    }

    func testErrorTextForRnirUsesItsOwnUsage() {
        let text = RNSDApp.errorText(program: "rnir", allowServiceFlags: false,
                                     error: ArgumentError.unrecognisedArguments(["-s"]))
        XCTAssertEqual(text, """
usage: rnir [-h] [--config CONFIG] [-v] [-q] [--exampleconfig] [--version]
rnir: error: unrecognized arguments: -s
""")
    }

    // MARK: - Version

    func testVersionText() {
        XCTAssertEqual(RNSDApp.versionText(program: "rnsd"), "rnsd \(Reticulum.version)")
        XCTAssertEqual(RNSDApp.versionText(program: "rnir"), "rnir \(Reticulum.version)")
        XCTAssertEqual(RNSDApp.versionText(program: "rnpkg"), "rnpkg \(Reticulum.version)")
        // Documented divergence: Python prints RNS.__version__. Keeping this assertion here
        // means the two versions can never drift silently.
        XCTAssertEqual(Reticulum.rnsProtocolVersion, "1.4.2")
    }

    // MARK: - rnpkg's own example config

    func testRnpkgExampleConfigByteLength() {
        // Python: `__example_rnpkg_config__` (rnpkg.py:75) — NOT the RNS config.
        XCTAssertEqual(RNSDApp.rnpkgExampleConfig,
                       "# This is an example package manager configuration file.\n")
        XCTAssertEqual(RNSDApp.rnpkgExampleConfig.utf8.count, 57)
        // `print()` adds one more newline → 58 bytes on stdout.
        XCTAssertEqual((RNSDApp.rnpkgExampleConfig + "\n").utf8.count, 58)
    }

    // MARK: - Exit codes

    func testExitCodes() {
        XCTAssertEqual(RNSDApp.ExitCode.ok.rawValue, 0)
        XCTAssertEqual(RNSDApp.ExitCode.argumentError.rawValue, 2)
        // Python: RNS.panic() is `os._exit(255)`.
        XCTAssertEqual(RNSDApp.ExitCode.panic.rawValue, 255)
    }
}
