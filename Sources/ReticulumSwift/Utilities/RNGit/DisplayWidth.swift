//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

/// How many terminal cells a string occupies.
///
/// `MarkdownToMicron` measures every table cell and wrapped line with this, so a column that
/// holds CJK or emoji lines up wherever the page is served. This ports `wcwidth` 0.8.2's
/// `wcwidth` and `wcswidth` against the tables in ``WidthTables``.
///
/// The `ambiguous_width` parameter is not carried, so East Asian Ambiguous code points are
/// always one cell, and neither is `wcstwidth`, the per-terminal variant.
public enum DisplayWidth {

  /// Zero-width joiner.
  private static let zeroWidthJoiner: UInt32 = 0x200D

  /// Variation selector 16, which asks for the emoji presentation of its base.
  private static let variationSelector16: UInt32 = 0xFE0F

  /// Variation selector 15, which asks for the text presentation of its base.
  private static let variationSelector15: UInt32 = 0xFE0E

  /// Returns whether `scalar` falls inside one of the inclusive ranges in the table.
  static func contains(_ table: [(UInt32, UInt32)], _ scalar: UInt32) -> Bool {
    guard let first = table.first, let last = table.last else { return false }
    if scalar < first.0 || scalar > last.1 { return false }

    var low = 0
    var high = table.count - 1
    while high >= low {
      let middle = (low + high) / 2
      if scalar > table[middle].1 {
        low = middle + 1
      } else if scalar < table[middle].0 {
        high = middle - 1
      } else {
        return true
      }
    }
    return false
  }

  /// The cells one code point occupies: 0, 1 or 2, or -1 when it is not printable.
  public static func cells(of scalar: Unicode.Scalar) -> Int {
    let value = scalar.value
    if (32..<0x7F).contains(value) { return 1 }
    if (value != 0 && value < 32) || (0x7F..<0xA0).contains(value) { return -1 }
    if contains(WidthTables.zeroWidth, value) { return 0 }
    if contains(WidthTables.wideEastAsian, value) { return 2 }
    return 1
  }

  /// The cells `text` occupies, or -1 when it holds a C0 or C1 control character.
  ///
  /// The walk is grapheme-aware rather than per-code-point: a ZWJ sequence, a base and its
  /// combining marks, a regional indicator pair and a virama conjunct each measure as one cluster.
  ///
  /// Python's pure-ASCII fast path is omitted; the walk returns the same width for those.
  public static func cells(of text: String) -> Int {
    let scalars = Array(text.unicodeScalars)
    let end = scalars.count

    var total = 0
    var index = 0

    // -2 blocks the variation selectors: no base has been measured yet.
    var lastMeasuredIndex = -2
    var lastMeasuredScalar: UInt32 = 0
    var lastMeasuredHasBase = false
    var lastMeasuredWidth = 0
    var previousWasVirama = false
    var clusterWidth = 0

    while index < end {
      let value = scalars[index].value

      if value == zeroWidthJoiner {
        if previousWasVirama {
          index += 1
        } else if index + 1 < end {
          lastMeasuredWidth = 0
          previousWasVirama = false
          index += 2
        } else {
          previousWasVirama = false
          index += 1
        }
        continue
      }

      if value == variationSelector16 && lastMeasuredIndex >= 0 {
        if lastMeasuredHasBase, contains(WidthTables.vs16NarrowToWide, lastMeasuredScalar) {
          clusterWidth = 2
        }
        lastMeasuredIndex = -2
        index += 1
        continue
      }

      if value == variationSelector15 && lastMeasuredIndex >= 0 {
        if lastMeasuredHasBase, contains(WidthTables.vs15WideToNarrow, lastMeasuredScalar),
          lastMeasuredWidth == 2
        {
          total -= 1
        }
        index += 1
        continue
      }

      if value > 0xFFFF {
        if contains(WidthTables.regionalIndicator, value) {
          // A second indicator joins the first into one flag rather than adding a cell.
          var indicatorsBefore = 0
          var scan = index - 1
          while scan >= 0, contains(WidthTables.regionalIndicator, scalars[scan].value) {
            indicatorsBefore += 1
            scan -= 1
          }
          if indicatorsBefore % 2 == 1 {
            lastMeasuredScalar = value
            lastMeasuredHasBase = true
            index += 1
            continue
          }
        } else if value >= WidthTables.fitzpatrick.0, value <= WidthTables.fitzpatrick.1,
          lastMeasuredHasBase, contains(WidthTables.emojiZWJ, lastMeasuredScalar)
        {
          index += 1
          continue
        }
      }

      let width = cells(of: scalars[index])
      if width < 0 { return -1 }

      if width > 0 {
        if previousWasVirama {
          clusterWidth = 2
        } else if clusterWidth != 0 {
          total += clusterWidth
          clusterWidth = width
        } else {
          clusterWidth = width
        }
        lastMeasuredIndex = index
        lastMeasuredScalar = value
        lastMeasuredHasBase = true
        lastMeasuredWidth = width
        previousWasVirama = false
      } else if contains(WidthTables.virama, value) {
        previousWasVirama = true
      } else if lastMeasuredIndex >= 0, contains(WidthTables.spacingCombiningMark, value) {
        clusterWidth = 2
        lastMeasuredIndex = -2
        previousWasVirama = false
      } else {
        previousWasVirama = false
      }
      index += 1
    }

    if clusterWidth != 0 { total += clusterWidth }
    return total
  }

  /// The cells `text` occupies, falling back to its code-point count when it is unmeasurable.
  public static func display(of text: String) -> Int {
    let width = cells(of: text)
    return width >= 0 ? width : text.unicodeScalars.count
  }
}
