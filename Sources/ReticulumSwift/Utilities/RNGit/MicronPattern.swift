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

/// A regular expression written to behave as Python's `re` does on the same pattern.
///
/// Two defaults differ between the engines and both matter to `MarkdownToMicron`:
/// `useUnixLineSeparators` makes `.` and `$` treat only `\n` as a terminator, where ICU
/// would also stop at `\r` and `U+0085`; and ``whitespace`` spells out the class `\s`
/// carries in Python, which holds `U+000B`, `U+001C`-`U+001F` and `U+0085` that ICU's
/// `\s` does not.
struct MicronPattern {

  /// The characters Python's `\s` matches, and that `str.strip` removes.
  static let whitespace =
    "[\\u0009-\\u000D\\u001C-\\u0020\\u0085\\u00A0\\u1680\\u2000-\\u200A"
    + "\\u2028\\u2029\\u202F\\u205F\\u3000]"

  /// The set behind ``whitespace``, for trimming.
  static let whitespaceScalars: Set<UInt32> = {
    var set = Set<UInt32>()
    for range in [
      UInt32(0x09)...UInt32(0x0D), UInt32(0x1C)...UInt32(0x20), UInt32(0x2000)...UInt32(0x200A),
      UInt32(0x2028)...UInt32(0x2029),
    ] { set.formUnion(range) }
    set.formUnion([0x85, 0xA0, 0x1680, 0x202F, 0x205F, 0x3000])
    return set
  }()

  private let regex: NSRegularExpression

  init(_ pattern: String) {
    // The patterns are compile-time constants from the reference, so a failure here is a
    // transcription error rather than anything a caller can cause.
    guard
      let compiled = try? NSRegularExpression(
        pattern: pattern, options: [.useUnixLineSeparators])
    else { preconditionFailure("pattern does not compile: \(pattern)") }
    regex = compiled
  }

  /// The capture groups of the match anchored at the start of `text`, or `nil`.
  ///
  /// Python: `re.match`, which anchors at the start but not the end.
  func match(_ text: String) -> [String?]? {
    let subject = text as NSString
    guard
      let match = regex.firstMatch(
        in: text, options: [.anchored], range: NSRange(location: 0, length: subject.length))
    else { return nil }
    return Self.groups(of: match, in: subject)
  }

  /// Whether a match anchored at the start of `text` exists.
  func matches(_ text: String) -> Bool { match(text) != nil }

  /// Returns `text` with every match replaced by what `transform` returns for it.
  ///
  /// Python: `re.sub` with a function, which takes the replacement literally.
  func replacingMatches(in text: String, with transform: ([String?]) -> String) -> String {
    let subject = text as NSString
    let found = regex.matches(
      in: text, range: NSRange(location: 0, length: subject.length))
    guard !found.isEmpty else { return text }

    var result = ""
    var consumed = 0
    for match in found {
      result += subject.substring(
        with: NSRange(location: consumed, length: match.range.location - consumed))
      result += transform(Self.groups(of: match, in: subject))
      consumed = match.range.location + match.range.length
    }
    result += subject.substring(from: consumed)
    return result
  }

  /// `text` with every match removed.
  func removingMatches(in text: String) -> String {
    replacingMatches(in: text) { _ in "" }
  }

  private static func groups(of match: NSTextCheckingResult, in subject: NSString) -> [String?] {
    (0..<match.numberOfRanges).map { index in
      let range = match.range(at: index)
      return range.location == NSNotFound ? nil : subject.substring(with: range)
    }
  }
}

extension String {

  /// The characters Python treats as a line boundary, which ICU's `\R` does not match.
  private static let lineBoundaries: Set<UInt32> = [
    0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029,
  ]

  /// This string split at every line boundary, with no empty line after a trailing one.
  ///
  /// Python: `str.splitlines`, whose boundary set holds seven characters
  /// `components(separatedBy:)` would keep, and which takes a carriage return and line feed
  /// together as one boundary.
  var pythonLines: [String] {
    let scalars = Array(unicodeScalars)
    var lines: [String] = []
    var current = String.UnicodeScalarView()
    var index = 0

    while index < scalars.count {
      let scalar = scalars[index]
      if Self.lineBoundaries.contains(scalar.value) {
        lines.append(String(current))
        current = String.UnicodeScalarView()
        if scalar.value == 0x0D, index + 1 < scalars.count, scalars[index + 1].value == 0x0A {
          index += 1
        }
      } else {
        current.append(scalar)
      }
      index += 1
    }

    if !current.isEmpty { lines.append(String(current)) }
    return lines
  }

  /// This string without leading or trailing Python whitespace.
  ///
  /// Python: `str.strip`, whose set is the one ``MicronPattern/whitespace`` spells out.
  var trimmedForMicron: String {
    let scalars = Array(unicodeScalars)
    var start = 0
    var end = scalars.count
    while start < end, MicronPattern.whitespaceScalars.contains(scalars[start].value) { start += 1 }
    while end > start, MicronPattern.whitespaceScalars.contains(scalars[end - 1].value) { end -= 1 }
    var trimmed = String.UnicodeScalarView()
    for index in start..<end { trimmed.append(scalars[index]) }
    return String(trimmed)
  }
}
