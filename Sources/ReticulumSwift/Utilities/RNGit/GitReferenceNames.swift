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

/// The checks an `rngit` node applies to reference names and object ids a client sends.
///
/// These guard what reaches `git` on the serving side, so a name that fails is rejected rather than
/// corrected.
public enum GitReferenceNames {

  /// The lowest code point a reference may contain.
  ///
  /// The bound is the code point of `(`, so it refuses the control characters and also every
  /// punctuation mark below it.
  private static let lowestAllowedScalar: UInt32 = 40

  /// Returns `ref` when it is a usable reference name, and `nil` otherwise.
  public static func sanitise(_ ref: String) -> String? {
    if ref.hasPrefix("-") || ref.hasPrefix("/") { return nil }
    if ref.hasSuffix("/") || ref.hasSuffix(".") { return nil }

    if ref.contains(" ") { return nil }
    if !ref.contains("/") { return nil }
    if ref.contains("..") { return nil }
    if ref.contains("/.") { return nil }
    if ref.contains("//") { return nil }
    if ref.contains("\\") { return nil }

    for component in ref.split(separator: "/", omittingEmptySubsequences: false)
    where component.hasSuffix(".lock") {
      return nil
    }

    for scalar in ref.unicodeScalars where scalar.value < lowestAllowedScalar { return nil }
    if ref.contains("\u{7F}") { return nil }
    if ref.contains("~") { return nil }
    if ref.contains("^") { return nil }
    if ref.contains(":") { return nil }
    if ref.contains("?") { return nil }
    if ref.contains("*") { return nil }
    if ref.contains("[") { return nil }
    if ref.contains("@{") { return nil }
    // Unreachable: a bare `@` carries no `/` and is already refused above. Kept so the
    // refused set reads in full.
    if ref == "@" { return nil }

    return ref
  }

  /// Returns `refs` when every entry is a usable reference name, and `nil` otherwise.
  public static func sanitise(_ refs: [String]) -> [String]? {
    for ref in refs where sanitise(ref) == nil { return nil }
    return refs
  }

  /// Returns `sha` when it is a full-length hex object id, and `nil` otherwise.
  ///
  /// A length floor, and then a reading of the hexadecimal.
  ///
  /// The floor counts code points, as `len` does; `String.count` would count `\r\n` once.
  public static func sanitiseObjectID(_ sha: String) -> String? {
    guard sha.unicodeScalars.count >= 40, isHexBytes(sha) else { return nil }
    return sha
  }

  /// Whether `bytes.fromhex` would accept `text`.
  ///
  /// ASCII whitespace is skipped between bytes but never inside one, so `"aa bb"` is two
  /// bytes and `"a a"` is not hex at all, and the digits have to make whole bytes. Only
  /// ASCII hex counts: Swift's `hexDigitValue` also answers for the fullwidth forms, which
  /// `bytes.fromhex` refuses.
  private static func isHexBytes(_ text: String) -> Bool {
    func isSpace(_ scalar: Unicode.Scalar) -> Bool {
      scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
        || scalar == "\u{0B}" || scalar == "\u{0C}"
    }
    func isHex(_ scalar: Unicode.Scalar) -> Bool {
      ("0"..."9").contains(scalar) || ("a"..."f").contains(scalar) || ("A"..."F").contains(scalar)
    }

    let scalars = Array(text.unicodeScalars)
    var index = 0
    while index < scalars.count {
      while index < scalars.count, isSpace(scalars[index]) { index += 1 }
      if index == scalars.count { break }
      guard isHex(scalars[index]) else { return false }
      index += 1
      guard index < scalars.count, isHex(scalars[index]) else { return false }
      index += 1
    }
    return true
  }
}
