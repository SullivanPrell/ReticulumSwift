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

/// Terminal cell widths, against `wcwidth` 0.8.2.
final class DisplayWidthTests: XCTestCase {

  /// Single code points, against `wcwidth.wcwidth`.
  func testSingleCodePointWidths() {
    XCTAssertEqual(DisplayWidth.cells(of: "a"), 1)
    XCTAssertEqual(DisplayWidth.cells(of: "~"), 1)
    XCTAssertEqual(DisplayWidth.cells(of: "\u{4E2D}"), 2)
    XCTAssertEqual(DisplayWidth.cells(of: "\u{0301}"), 0)
    XCTAssertEqual(DisplayWidth.cells(of: "\u{00E9}"), 1)
  }

  /// NUL is zero width; every other C0 and C1 control is unmeasurable.
  ///
  /// `ucs and ucs < 32 or 0x07F <= ucs < 0x0A0` (`_wcwidth.py`) leaves 0 to the zero-width
  /// table, which holds it.
  func testControlCharacterWidths() {
    XCTAssertEqual(DisplayWidth.cells(of: "\u{0000}"), 0)
    XCTAssertEqual(DisplayWidth.cells(of: "\u{0001}"), -1)
    XCTAssertEqual(DisplayWidth.cells(of: "\u{0009}"), -1)
    XCTAssertEqual(DisplayWidth.cells(of: "\u{001F}"), -1)
    XCTAssertEqual(DisplayWidth.cells(of: "\u{007F}"), -1)
    XCTAssertEqual(DisplayWidth.cells(of: "\u{009F}"), -1)
    XCTAssertEqual(DisplayWidth.cells(of: "\u{00A0}"), 1)
  }

  /// Strings, against widths captured from `wcwidth.wcswidth` 0.8.2.
  ///
  /// One case per branch of the grapheme walk: ZWJ chains, both variation selectors,
  /// regional indicator pairing, Fitzpatrick folding, virama conjuncts and spacing marks.
  func testStringWidthsMatchTheCapturedReference() {
    let vectors: [(String, Int)] = [
      ("", 0),
      ("hello world", 11),
      ("\u{4E2D}\u{6587}", 4),
      ("\u{65}\u{301}", 1),
      ("\u{61}\u{9}\u{62}", -1),
      ("\u{61}\u{0}\u{62}", 2),
      ("\u{E9}\u{301}\u{302}", 1),
      ("\u{1F600}", 2),
      ("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}", 2),
      ("\u{261D}\u{FE0F}", 2),
      ("\u{261D}\u{FE0E}", 1),
      ("\u{231A}\u{FE0E}", 1),
      ("\u{1F1E6}\u{1F1E8}", 2),
      ("\u{1F1E6}\u{1F1E8}\u{1F1E9}", 4),
      ("\u{1F44D}\u{1F3FD}", 2),
      ("\u{915}\u{94D}\u{937}", 2),
      ("\u{915}\u{93E}", 2),
      ("\u{FE0F}", 0),
      ("\u{1F468}\u{200D}", 2),
      ("caf\u{E9} \u{4E2D}", 7),
    ]

    for (text, expected) in vectors {
      XCTAssertEqual(
        DisplayWidth.cells(of: text), expected,
        "width of \(text.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " "))"
      )
    }
  }

  /// An unmeasurable string falls back to its code-point count.
  func testUnmeasurableStringsFallBackToLength() {
    XCTAssertEqual(DisplayWidth.cells(of: "a\u{9}b"), -1)
    XCTAssertEqual(DisplayWidth.display(of: "a\u{9}b"), 3)
    XCTAssertEqual(DisplayWidth.display(of: "\u{4E2D}\u{6587}"), 4)
  }

  /// The fallback counts code points, as `len` does.
  ///
  /// Python reads `e\u{301}\t` as three characters; `String.count` reads two, because the
  /// combining acute joins its base into one grapheme.
  func testTheFallbackCountsCodePoints() {
    let text = "e\u{301}\u{9}"
    XCTAssertEqual(text.count, 2)
    XCTAssertEqual(DisplayWidth.display(of: text), 3)
  }

  /// Every table is sorted and non-overlapping, as `bisearch` requires.
  func testTablesAreSearchable() {
    let tables: [(String, [(UInt32, UInt32)])] = [
      ("zeroWidth", WidthTables.zeroWidth),
      ("wideEastAsian", WidthTables.wideEastAsian),
      ("spacingCombiningMark", WidthTables.spacingCombiningMark),
      ("vs15WideToNarrow", WidthTables.vs15WideToNarrow),
      ("vs16NarrowToWide", WidthTables.vs16NarrowToWide),
      ("emojiZWJ", WidthTables.emojiZWJ),
      ("virama", WidthTables.virama),
      ("regionalIndicator", WidthTables.regionalIndicator),
    ]

    for (name, table) in tables {
      XCTAssertFalse(table.isEmpty, name)
      for range in table { XCTAssertLessThanOrEqual(range.0, range.1, name) }
      for index in 1..<table.count {
        XCTAssertLessThan(table[index - 1].1, table[index].0, "\(name) at \(index)")
      }
    }
  }
}
