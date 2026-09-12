//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest
@testable import ReticulumSwift

/// Command-line parity for `rnsd`, `rnir` and `rnpkg`.
///
/// Python reference: `RNS/Utilities/rnsd.py:62-88`, `rnir.py:53-76`, `rnpkg.py:51-76`.
///
/// The golden strings below were captured from the *installed* Python utilities on this
/// machine (`rnsd --help`, `rnir --help`, `rnpkg --help`, and the three `argparse` error
/// pages) under Python 3.11—not hand-written. Python 3.9 and older print
/// `optional arguments:` where 3.10+ prints `options:`; 3.10+ is the target.
final class RNSDAppTests: XCTestCase {

    // MARK: - Parsing

    func testParseEmptyArgvGivesDefaults() throws {
        let options = try RNSDApp.parse([], variant: .rnsd)
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
        XCTAssertEqual(try RNSDApp.parse(["-v"], variant: .rnsd).verbose, 1)
        XCTAssertEqual(try RNSDApp.parse(["-vv"], variant: .rnsd).verbose, 2)
        XCTAssertEqual(try RNSDApp.parse(["-vvv"], variant: .rnsd).verbose, 3)
        XCTAssertEqual(try RNSDApp.parse(["-v", "-v"], variant: .rnsd).verbose, 2)
        XCTAssertEqual(try RNSDApp.parse(["--verbose", "--verbose"], variant: .rnsd).verbose, 2)
    }

    func testQuietCountingAndDelta() throws {
        let quiet = try RNSDApp.parse(["-qq"], variant: .rnsd)
        XCTAssertEqual(quiet.quiet, 2)
        // Python: `targetverbosity = verbosity-quietness` (rnsd.py:41)—may be negative.
        XCTAssertEqual(quiet.verbosityDelta, -2)

        let mixed = try RNSDApp.parse(["-vvv", "-q"], variant: .rnsd)
        XCTAssertEqual(mixed.verbose, 3)
        XCTAssertEqual(mixed.quiet, 1)
        XCTAssertEqual(mixed.verbosityDelta, 2)
    }

    func testShortFlagClusters() throws {
        let vq = try RNSDApp.parse(["-vq"], variant: .rnsd)
        XCTAssertEqual(vq.verbose, 1)
        XCTAssertEqual(vq.quiet, 1)
        XCTAssertEqual(vq.verbosityDelta, 0)

        for argv in [["-vs"], ["-sv"]] {
            let parsed = try RNSDApp.parse(argv, variant: .rnsd)
            XCTAssertEqual(parsed.verbose, 1, "\(argv)")
            XCTAssertTrue(parsed.service, "\(argv)")
        }
    }

    func testServiceModeDiscardsVerbosity() throws {
        // Python: `if service: targetlogdest = RNS.LOG_FILE; targetverbosity = None` (rnsd.py:43-45)
        let options = try RNSDApp.parse(["-s", "-vvv"], variant: .rnsd)
        XCTAssertEqual(options.verbosityDelta, 3)
        XCTAssertNil(options.effectiveVerbosity)

        let noService = try RNSDApp.parse(["-vvv"], variant: .rnsd)
        XCTAssertEqual(noService.effectiveVerbosity, 3)
    }

    func testConfigTakesNextArgument() throws {
        for argv in [["--config", "/tmp/x"], ["--config=/tmp/x"]] {
            XCTAssertEqual(try RNSDApp.parse(argv, variant: .rnsd).configDir, "/tmp/x", "\(argv)")
        }
    }

    func testSwiftOnlyConfigDirectoryAliases() throws {
        // Not Python spellings—kept because the pre-parity Swift rnsd accepted them with
        // exactly this meaning. They're hidden from --help and from prefix abbreviation.
        for argv in [["--config-dir", "/tmp/x"], ["-d", "/tmp/x"], ["--config-dir=/tmp/x"]] {
            XCTAssertEqual(try RNSDApp.parse(argv, variant: .rnsd).configDir, "/tmp/x", "\(argv)")
        }
    }

    func testEmptyConfigBecomesNil() throws {
        // Python: `if args.config:` is falsy for '' → configarg stays None (rnsd.py:79-82).
        XCTAssertNil(try RNSDApp.parse(["--config", ""], variant: .rnsd).configDir)
    }

    func testConfigMissingValueThrows() {
        XCTAssertThrowsError(try RNSDApp.parse(["--config"], variant: .rnsd)) { error in
            XCTAssertEqual(error as? ArgumentError, .missingValue("--config"))
            // Python: "rnsd: error: argument --config: expected one argument"
            XCTAssertEqual((error as? ArgumentError)?.description,
                           "argument --config: expected one argument")
        }
    }

    func testUnrecognizedArgumentThrows() {
        XCTAssertThrowsError(try RNSDApp.parse(["--bogus"], variant: .rnsd)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["--bogus"]))
        }
        // Python reports every leftover in one message, in argv order.
        XCTAssertThrowsError(try RNSDApp.parse(["--bogus", "extra"], variant: .rnsd)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["--bogus", "extra"]))
        }
        // …but only the leftovers: `-v` is consumed first.
        XCTAssertThrowsError(try RNSDApp.parse(["-v", "--bogus"], variant: .rnsd)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["--bogus"]))
        }
    }

    func testBarePositionalIsAnError() {
        // Python declares no positionals: `rnsd extra` → "unrecognized arguments: extra", exit 2.
        XCTAssertThrowsError(try RNSDApp.parse(["extra"], variant: .rnsd)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["extra"]))
        }
    }

    func testShortCIsRejectedLikePython() {
        // Verified against the real parser: `rnsd -c /tmp/x` → exit 2, "unrecognized arguments".
        // The pre-parity Swift rnsd accepted -c as a config *file*; that meaning is dropped.
        XCTAssertThrowsError(try RNSDApp.parse(["-c", "/tmp/x"], variant: .rnsd)) { error in
            XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments(["-c", "/tmp/x"]))
        }
    }

    func testPrefixAbbreviation() throws {
        // Python: argparse's allow_abbrev defaults to True.
        XCTAssertEqual(try RNSDApp.parse(["--conf", "/tmp/x"], variant: .rnsd).configDir, "/tmp/x")
        XCTAssertEqual(try RNSDApp.parse(["--co", "/tmp/x"], variant: .rnsd).configDir, "/tmp/x")
        XCTAssertEqual(try RNSDApp.parse(["--confi=/tmp/x"], variant: .rnsd).configDir, "/tmp/x")
        XCTAssertEqual(try RNSDApp.parse(["--verb"], variant: .rnsd).verbose, 1)
        XCTAssertTrue(try RNSDApp.parse(["--exam"], variant: .rnsd).exampleConfig)
    }

    func testAmbiguousAbbreviationThrows() {
        XCTAssertThrowsError(try RNSDApp.parse(["--ver"], variant: .rnsd)) { error in
            XCTAssertEqual(error as? ArgumentError,
                           .ambiguousOption("--ver", ["--verbose", "--version"]))
        }
        let text = RNSDApp.errorText(.rnsd,
                                     error: ArgumentError.ambiguousOption("--ver", ["--verbose", "--version"]))
        // Python: "rnsd: error: ambiguous option: --ver could match --verbose, --version"
        XCTAssertTrue(text.hasSuffix("rnsd: error: ambiguous option: --ver could match --verbose, --version"),
                      text)
    }

    func testServiceAndInteractiveRejectedForRnirAndRnpkg() throws {
        for variant in [RNSDApp.Variant.rnir, .rnpkg] {
            for argument in ["-s", "-i", "--service", "--interactive"] {
                XCTAssertThrowsError(try RNSDApp.parse([argument], variant: variant),
                                     "\(variant.appName) must reject \(argument)") { error in
                    XCTAssertEqual(error as? ArgumentError, .unrecognisedArguments([argument]))
                }
            }
        }
        XCTAssertTrue(try RNSDApp.parse(["-s"], variant: .rnsd).service)
        XCTAssertTrue(try RNSDApp.parse(["-i"], variant: .rnsd).interactive)
    }

    func testHelpAndVersionFlags() throws {
        XCTAssertTrue(try RNSDApp.parse(["-h"], variant: .rnsd).help)
        XCTAssertTrue(try RNSDApp.parse(["--help"], variant: .rnsd).help)
        // argparse recognises -h anywhere in argv.
        XCTAssertTrue(try RNSDApp.parse(["-v", "--help"], variant: .rnsd).help)
        XCTAssertTrue(try RNSDApp.parse(["--version"], variant: .rnsd).version)
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
    ///
    /// No `--exampleconfig`: `rnir.py:54-58`
    /// declares four arguments, and the real tool rejects it with exit 2.
    private static let pythonRnirHelp = """
usage: rnir [-h] [--config CONFIG] [-v] [-q] [--version]

Reticulum Distributed Identity Resolver

options:
  -h, --help       show this help message and exit
  --config CONFIG  path to alternative Reticulum config directory
  -v, --verbose
  -q, --quiet
  --version        show program's version number and exit
"""

    /// Byte-for-byte capture of `rnpkg --help`.
    ///
    /// Captured in full rather than derived from
    /// rnir's: the two pages differ by more than a name now (`rnpkg.py:57` keeps
    /// `--exampleconfig`), and a derived expectation would have hidden exactly that.
    private static let pythonRnpkgHelp = """
usage: rnpkg [-h] [--config CONFIG] [-v] [-q] [--exampleconfig] [--version]

Reticulum Meta Package Manager

options:
  -h, --help       show this help message and exit
  --config CONFIG  path to alternative Reticulum config directory
  -v, --verbose
  -q, --quiet
  --exampleconfig  print verbose configuration example to stdout and exit
  --version        show program's version number and exit
"""

    func testHelpTextMatchesPythonForRnsd() {
        XCTAssertEqual(RNSDApp.helpText(.rnsd), Self.pythonRnsdHelp)
    }

    func testHelpTextMatchesPythonForRnir() {
        XCTAssertEqual(RNSDApp.helpText(.rnir), Self.pythonRnirHelp)
    }

    func testHelpTextMatchesPythonForRnpkg() {
        XCTAssertEqual(RNSDApp.helpText(.rnpkg), Self.pythonRnpkgHelp)
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

        XCTAssertEqual(helpColumn(in: RNSDApp.helpText(.rnsd)), 21)
        XCTAssertEqual(helpColumn(in: RNSDApp.helpText(.rnir)), 19)
        XCTAssertEqual(helpColumn(in: RNSDApp.helpText(.rnpkg)), 19)
    }

    func testHelplessRowsHaveNoTrailingWhitespace() {
        // argparse's `if not action.help:` branch emits the bare invocation with no padding.
        let lines = RNSDApp.helpText(.rnsd)
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
        XCTAssertEqual(RNSDApp.usageText(.rnsd), """
usage: rnsd [-h] [--config CONFIG] [-v] [-q] [-s] [-i] [--exampleconfig]
            [--version]
""")
        // rnir's fits, so it stays on one line.
        XCTAssertEqual(RNSDApp.usageText(.rnir),
                       "usage: rnir [-h] [--config CONFIG] [-v] [-q] [--version]")
        XCTAssertEqual(RNSDApp.usageText(.rnpkg),
                       "usage: rnpkg [-h] [--config CONFIG] [-v] [-q] [--exampleconfig] [--version]")
    }

    func testErrorText() {
        let text = RNSDApp.errorText(.rnsd, error: ArgumentError.unrecognisedArguments(["--bogus"]))
        XCTAssertTrue(text.hasPrefix(RNSDApp.usageText(.rnsd)))
        XCTAssertTrue(text.hasSuffix("rnsd: error: unrecognized arguments: --bogus"), text)
    }

    func testErrorTextForRnirUsesItsOwnUsage() {
        let text = RNSDApp.errorText(.rnir, error: ArgumentError.unrecognisedArguments(["-s"]))
        XCTAssertEqual(text, """
usage: rnir [-h] [--config CONFIG] [-v] [-q] [--version]
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
        XCTAssertEqual(Reticulum.rnsProtocolVersion, "1.5.2")
    }

    // MARK: - rnpkg's own example config

    func testRnpkgExampleConfigByteLength() {
        // Python: `__example_rnpkg_config__` (rnpkg.py:75)—NOT the RNS config.
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
