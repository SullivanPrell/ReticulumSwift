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

/// Text read as Python RNS 1.5.4's interpreter reads it with `int`.
final class RNGitPythonIntegerTests: XCTestCase {

  /// Each text with what `int` answered for it, exactly and held to the range of `Int`.
  ///
  /// The exact answer is `nil` where `Int` cannot hold it, and both are `nil` where `int` raised.
  func testTextIsReadAsIntReadsIt() {
    let recorded: [(String, Int?, Int?)] = [
      ("0", 0, 0),
      ("42", 42, 42),
      ("-7", -7, -7),
      (" +5 ", 5, 5),
      ("1_000", 1000, 1000),
      ("1__0", nil, nil),
      ("_1", nil, nil),
      ("1_", nil, nil),
      ("\u{0663}", 3, 3),
      ("\u{FF11}\u{FF12}", 12, 12),
      ("\u{00A0}5\u{3000}", 5, 5),
      ("", nil, nil),
      ("-", nil, nil),
      ("+", nil, nil),
      ("0x10", nil, nil),
      ("1e3", nil, nil),
      ("2.5", nil, nil),
      ("9223372036854775807", .max, .max),
      ("9223372036854775808", nil, .max),
      ("-9223372036854775808", .min, .min),
      ("-9223372036854775809", nil, .min),
      ("99999999999999999999", nil, .max),
      ("-99999999999999999999", nil, .min),
      ("1_2_3", 123, 123),
      ("12a", nil, nil),
    ]
    for (text, exact, clamped) in recorded {
      XCTAssertEqual(text.pythonInteger, exact, text)
      XCTAssertEqual(text.pythonIntegerClamped, clamped, text)
    }
  }

  /// Text that runs past the range of `Int` is still refused where the rest of it is no number.
  func testTextPastTheRangeIsStillReadToItsEnd() {
    XCTAssertNil("99999999999999999999x".pythonIntegerClamped)
    XCTAssertNil("99999999999999999999__0".pythonIntegerClamped)
    XCTAssertNil("-99999999999999999999_".pythonIntegerClamped)
  }
}
