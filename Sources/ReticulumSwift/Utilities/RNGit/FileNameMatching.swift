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

/// Shell-style name matching, as a release fetch selects the artifacts it wants.
///
/// A pattern matches a whole name and nothing less. `*` stands for any run of characters,
/// `?` for one of them, and `[abc]` for one of the characters it holds, which `[!abc]` turns
/// around. A range is written `[a-z]`, and a `-` at either end of a set is one of its
/// characters. A `[` that nothing closes is a character like any other.
public enum FileNameMatching {

  /// Whether `name` is what `pattern` describes.
  public static func matches(_ name: String, _ pattern: String) -> Bool {
    matching(Array(name.unicodeScalars), Array(pattern.unicodeScalars))
  }

  /// One term of a pattern.
  private enum Term {

    /// Any run of characters, however long.
    case run

    /// One character, of the class this term names.
    case one(CharacterClass)
  }

  /// The characters one term of a pattern stands for.
  private enum CharacterClass {

    /// Any one character.
    case any

    /// This character and no other.
    case literal(Unicode.Scalar)

    /// One of the characters this set holds, or one it does not where it is turned around.
    case set(members: [ClosedRange<UInt32>], negated: Bool)

    /// Whether `scalar` is one of the characters this class stands for.
    func holds(_ scalar: Unicode.Scalar) -> Bool {
      switch self {
      case .any: return true
      case .literal(let other): return scalar == other
      case .set(let members, let negated):
        return members.contains { $0.contains(scalar.value) } != negated
      }
    }
  }

  /// Whether `name` is what the terms of `pattern` describe.
  private static func matching(_ name: [Unicode.Scalar], _ pattern: [Unicode.Scalar]) -> Bool {
    let terms = reading(pattern)
    var index = 0
    var term = 0
    var runIndex: Int?
    var runTerm = 0

    while index < name.count {
      if term < terms.count, case .run = terms[term] {
        runTerm = term
        term += 1
        runIndex = index
        continue
      }
      if term < terms.count, case .one(let one) = terms[term], one.holds(name[index]) {
        term += 1
        index += 1
        continue
      }
      guard let held = runIndex else { return false }
      runIndex = held + 1
      index = held + 1
      term = runTerm + 1
    }

    while term < terms.count, case .run = terms[term] { term += 1 }
    return term == terms.count
  }

  /// The terms `pattern` is written in.
  private static func reading(_ pattern: [Unicode.Scalar]) -> [Term] {
    var terms: [Term] = []
    var index = 0
    while index < pattern.count {
      let scalar = pattern[index]
      index += 1
      switch scalar {
      case "*":
        if case .run? = terms.last { continue }
        terms.append(.run)
      case "?": terms.append(.one(.any))
      case "[":
        guard let (term, next) = set(in: pattern, from: index) else {
          terms.append(.one(.literal("[")))
          continue
        }
        terms.append(.one(term))
        index = next
      default: terms.append(.one(.literal(scalar)))
      }
    }
    return terms
  }

  /// The set that opens at `start`, and where the pattern goes on after it, or `nil` where
  /// nothing closes it.
  private static func set(in pattern: [Unicode.Scalar], from start: Int)
    -> (CharacterClass, Int)?
  {
    var end = start
    if end < pattern.count, pattern[end] == "!" { end += 1 }
    if end < pattern.count, pattern[end] == "]" { end += 1 }
    while end < pattern.count, pattern[end] != "]" { end += 1 }
    guard end < pattern.count else { return nil }

    var held = Array(pattern[start..<end])
    let negated = held.first == "!"
    if negated { held.removeFirst() }

    var members: [ClosedRange<UInt32>] = []
    var index = 0
    while index < held.count {
      if index + 2 < held.count, held[index + 1] == "-" {
        let lower = held[index].value
        let upper = held[index + 2].value
        if lower <= upper { members.append(lower...upper) }
        index += 3
        continue
      }
      members.append(held[index].value...held[index].value)
      index += 1
    }
    return (.set(members: members, negated: negated), end + 1)
  }
}
