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

/// Which options each of the three `RNSDApp` tools declares.
///
/// `rnsd`, `rnpkg` and `rnir` share a parser but not an option set, and they differ along
/// two independent axes:
///
/// | tool    | `-s`/`-i` | `--exampleconfig` |
/// |---------|-----------|-------------------|
/// | `rnsd`  | yes       | yes               |
/// | `rnpkg` | no        | yes               |
/// | `rnir`  | no        | no                |
///
/// A single `allowServiceFlags: Bool` could only express one axis, so `rnir` inherited
/// `rnpkg`'s `--exampleconfig` and drifted from `rnir.py:54-58`, which declares four
/// arguments and no more. One extra option rewraps the usage line, and every `tri-test`
/// abbreviation, help and error assertion for `rnir` compares that line.
///
/// The golden strings here come from the real utilities in `tri-test/.venv`
/// (RNS 1.5.2, Python 3.14.5), captured rather than written.
final class RNSDAppVariantTests: XCTestCase {

    // MARK: - The option set per tool

    func testRnirDeclaresExactlyPythonsFourArguments() throws {
        let names = RNSDApp.optionSpecs(.rnir).flatMap(\.names)
        XCTAssertEqual(names, ["-h", "--help", "--config", "-v", "--verbose",
                               "-q", "--quiet", "--version"],
                       "rnir.py:54-58 declares --config, -v/--verbose, -q/--quiet and "
                       + "--version, in that order, and nothing else")
    }

    func testRnirRejectsExampleConfig() {
        // The real tool: `rnir: error: unrecognized arguments: --exampleconfig`, exit 2.
        XCTAssertThrowsError(try RNSDApp.parse(["--exampleconfig"], variant: .rnir))
    }

    func testRnpkgAndRnsdKeepExampleConfig() throws {
        XCTAssertTrue(try RNSDApp.parse(["--exampleconfig"], variant: .rnpkg).exampleConfig)
        XCTAssertTrue(try RNSDApp.parse(["--exampleconfig"], variant: .rnsd).exampleConfig)
    }

    func testOnlyRnsdTakesTheServiceFlags() throws {
        XCTAssertTrue(try RNSDApp.parse(["-s", "-i"], variant: .rnsd).service)
        XCTAssertThrowsError(try RNSDApp.parse(["-s"], variant: .rnpkg))
        XCTAssertThrowsError(try RNSDApp.parse(["-s"], variant: .rnir))
    }

    // MARK: - Rendered text

    func testRnirUsageLineMatchesTheRealTool() {
        XCTAssertEqual(RNSDApp.usageText(.rnir),
                       "usage: rnir [-h] [--config CONFIG] [-v] [-q] [--version]")
    }

    func testRnirHelpMatchesTheRealTool() {
        XCTAssertEqual(RNSDApp.helpText(.rnir), """
usage: rnir [-h] [--config CONFIG] [-v] [-q] [--version]

Reticulum Distributed Identity Resolver

options:
  -h, --help       show this help message and exit
  --config CONFIG  path to alternative Reticulum config directory
  -v, --verbose
  -q, --quiet
  --version        show program's version number and exit
""")
    }

    func testRnirUnrecognisedArgumentErrorMatchesTheRealTool() {
        let text = RNSDApp.errorText(.rnir, error: ArgumentError.unrecognisedArguments(["--exampleconfig"]))
        XCTAssertEqual(text, """
usage: rnir [-h] [--config CONFIG] [-v] [-q] [--version]
rnir: error: unrecognized arguments: --exampleconfig
""")
    }

    // MARK: - The variant carries its own identity

    func testEachVariantKnowsItsNameAndDescription() {
        // Passing a program name alongside the variant would let the two disagree, which is
        // how `rnir` came to render `rnpkg`'s option set under its own name.
        XCTAssertEqual(RNSDApp.Variant.rnsd.appName, "rnsd")
        XCTAssertEqual(RNSDApp.Variant.rnir.appName, "rnir")
        XCTAssertEqual(RNSDApp.Variant.rnpkg.appName, "rnpkg")
        XCTAssertEqual(RNSDApp.Variant.rnsd.toolDescription, "Reticulum Network Stack Daemon")
        XCTAssertEqual(RNSDApp.Variant.rnir.toolDescription, "Reticulum Distributed Identity Resolver")
        XCTAssertEqual(RNSDApp.Variant.rnpkg.toolDescription, "Reticulum Meta Package Manager")
    }
}
