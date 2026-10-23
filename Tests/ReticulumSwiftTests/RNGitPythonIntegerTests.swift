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

/// Text and byte strings read as Python 3.14.5 reads them with `int`, under RNS 1.5.7.
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
  /// Each byte string with what `int` answered for it, exactly and held to the range of `Int`.
  ///
  /// `int` reads bytes as ASCII text, stripping only the six ASCII whitespace characters, so the
  /// information separators, a no-break space and non-ASCII digits raise.
  func testByteStringsAreReadAsIntReadsThem() {
    let recorded: [([UInt8], Int?, Int?)] = [
      (Array("42".utf8), 42, 42),
      (Array(" 7 ".utf8), 7, 7),
      (Array("\t12\n".utf8), 12, 12),
      (Array("\r5\r".utf8), 5, 5),
      ([0x0B, 0x35], 5, 5),
      ([0x0C, 0x35], 5, 5),
      (Array("1_0".utf8), 10, 10),
      (Array("0_0".utf8), 0, 0),
      (Array("00_1".utf8), 1, 1),
      (Array("0005".utf8), 5, 5),
      (Array("-3".utf8), -3, -3),
      (Array("+5".utf8), 5, 5),
      (Array("9223372036854775807".utf8), .max, .max),
      (Array("-9223372036854775808".utf8), .min, .min),
      (Array("9223372036854775808".utf8), nil, .max),
      (Array("-9223372036854775809".utf8), nil, .min),
      ([], nil, nil),
      (Array("  ".utf8), nil, nil),
      (Array("- 5".utf8), nil, nil),
      (Array("+-5".utf8), nil, nil),
      (Array("5 5".utf8), nil, nil),
      (Array("1__0".utf8), nil, nil),
      (Array("_1".utf8), nil, nil),
      (Array("1_".utf8), nil, nil),
      ([0x34, 0x00, 0x32], nil, nil),
      (Array("0x10".utf8), nil, nil),
      (Array("1e3".utf8), nil, nil),
      (Array("12.0".utf8), nil, nil),
      ([0x1C, 0x35], nil, nil),
      ([0x1F, 0x35], nil, nil),
      ([0x35, 0x1C], nil, nil),
      ([0xC2, 0xA0, 0x35], nil, nil),
      ([0xD9, 0xA3], nil, nil),
      ([0xD9, 0xA1, 0xD9, 0xA2, 0xD9, 0xA3], nil, nil),
    ]
    for (bytes, exact, clamped) in recorded {
      let value = MsgPack.Value.bytes(Data(bytes))
      XCTAssertEqual(value.pythonInteger, exact, "\(bytes)")
      XCTAssertEqual(value.pythonIntegerClamped, clamped, "\(bytes)")
    }
  }

  /// A page number sent as a byte string reads as `int(page_str)` reads it (`pages.py:578`).
  func testAPageNumberSentAsBytesIsRead() {
    func page(_ value: MsgPack.Value) -> Int {
      RNGitPageRequest(.map([(.string("var_page"), value)])).page
    }
    XCTAssertEqual(page(.bytes(Data("3".utf8))), 3)
    XCTAssertEqual(page(.bytes(Data("99999999999999999999".utf8))), .max)
    XCTAssertEqual(page(.bytes(Data([0x1C, 0x33]))), 0)
  }
}
