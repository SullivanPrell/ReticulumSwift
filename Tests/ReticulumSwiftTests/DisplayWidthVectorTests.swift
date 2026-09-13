//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import CryptoKit
import Foundation
import XCTest

@testable import ReticulumSwift

/// Widths captured from `wcwidth` 0.8.2, the package the Python side measures with.
///
/// A Swift-only test cannot see a table transcribed wrongly or a branch of the grapheme
/// walk ordered differently, so both halves here compare against recorded reference output
/// rather than against another Swift call.
final class DisplayWidthVectorTests: XCTestCase {

  /// Code points chosen to reach every branch of the walk: ASCII, Latin-1, NUL, combining
  /// marks, CJK, fullwidth, Devanagari and Tamil consonants with their viramas and vowel
  /// signs, Thai, ZWJ, both variation selectors with bases that each affects, emoji,
  /// Fitzpatrick modifiers and regional indicators.
  private static let alphabet: [UInt32] = [

    ]

  /// `wcswidth` of every ordered pair over alphabet, row-major.
  private static let pairWidths: [Int] = [

    ]

  /// Longer sequences, for the chains a pair cannot reach.
  private static let sequences: [([UInt32], Int)] = [

    ]

  /// Every ordered pair measures as the reference does.
  func testPairWidthsMatchTheReference() {
    let alphabet = Self.alphabet
    XCTAssertEqual(Self.pairWidths.count, alphabet.count * alphabet.count)

    for (first, leading) in alphabet.enumerated() {
      for (second, trailing) in alphabet.enumerated() {
        var text = ""
        text.unicodeScalars.append(Unicode.Scalar(leading)!)
        text.unicodeScalars.append(Unicode.Scalar(trailing)!)
        XCTAssertEqual(
          DisplayWidth.cells(of: text), Self.pairWidths[first * alphabet.count + second],
          String(format: "U+%04X U+%04X", leading, trailing))
      }
    }
  }

  /// Longer sequences measure as the reference does.
  func testSequenceWidthsMatchTheReference() {
    for (points, expected) in Self.sequences {
      var text = ""
      for point in points { text.unicodeScalars.append(Unicode.Scalar(point)!) }
      XCTAssertEqual(
        DisplayWidth.cells(of: text), expected,
        points.map { String(format: "U+%04X", $0) }.joined(separator: " "))
    }
  }

  /// Every code point measures as the reference does.
  ///
  /// The digest covers all 1,112,064 assignable scalars, so a single wrong bound anywhere in
  /// WidthTables/zeroWidth or WidthTables/wideEastAsian changes it. Surrogates are
  /// skipped: Swift has no `Unicode.Scalar` for them.
  func testEveryScalarWidthMatchesTheReferenceDigest() {
    var hasher = SHA256()
    var measured = 0
    for value in UInt32(0)..<UInt32(0x110000) {
      if value >= 0xD800 && value <= 0xDFFF { continue }
      let scalar = Unicode.Scalar(value)!
      hasher.update(data: Data("\(value):\(DisplayWidth.cells(of: scalar))\n".utf8))
      measured += 1
    }

    XCTAssertEqual(measured, 1_112_064)
    XCTAssertEqual(
      hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      "8168ee84ce0db5e33e7853a9d5a7f0cebabe4ee89fa31e9c7d9b44a43d371087")
  }
}
