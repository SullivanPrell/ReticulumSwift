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

/// What one key in a configuration section holds.
///
/// Python: a `configobj` section entry, which is a string, a list of strings, or a
/// subsection.
public enum RNGitConfigValue: Equatable, Sendable {

  /// One value, unquoted.
  case scalar(String)

  /// Several values, which the line separated with commas.
  case list([String])

  /// A subsection, which a deeper bracket marker opened.
  case section(RNGitConfigSection)
}

/// One section of a configuration file, in the order the file writes its keys.
///
/// Python: `configobj.Section` (`RNS/vendor/configobj.py:426-1060`).
public struct RNGitConfigSection: Equatable, Sendable {

  /// Every key this section holds, subsections included, in file order.
  public private(set) var keys: [String] = []

  private var entries: [String: RNGitConfigValue] = [:]

  /// Creates an empty section.
  public init() {}

  /// Creates a section holding `entries`, in the order given.
  public init(_ entries: [(key: String, value: RNGitConfigValue)]) {
    for entry in entries {
      keys.append(entry.key)
      self.entries[entry.key] = entry.value
    }
  }

  /// The value stored under `key`, or `nil` if the section has no such key.
  public subscript(key: String) -> RNGitConfigValue? { entries[key] }

  /// Whether the section holds `key`.
  public func has(_ key: String) -> Bool { entries[key] != nil }

  /// The one value `key` holds, or `nil` if it holds a list or a subsection.
  public func string(_ key: String) -> String? {
    guard case .scalar(let value) = entries[key] else { return nil }
    return value
  }

  /// The values `key` holds, taking one value as a list of one.
  ///
  /// Python: `Section.as_list` (`RNS/vendor/configobj.py:1011-1030`).
  public func list(_ key: String) -> [String]? {
    switch entries[key] {
    case .scalar(let value): return [value]
    case .list(let values): return values
    default: return nil
    }
  }

  /// The integer `key` holds, or `nil` if its value does not name one.
  ///
  /// Python: `Section.as_int`, which is `int()` over the string, so it takes a sign,
  /// surrounding whitespace and single underscores between digits.
  public func int(_ key: String) -> Int? {
    guard let text = string(key) else { return nil }
    return Self.integer(text)
  }

  /// The boolean `key` holds, or `nil` if its value names neither.
  ///
  /// Python: `Section.as_bool`, which reads the eight words of `ConfigObj._bools`
  /// (`RNS/vendor/configobj.py:1161-1165`) without regard to case, and raises otherwise.
  public func bool(_ key: String) -> Bool? {
    guard let text = string(key) else { return nil }
    return Self.booleans[text.lowercased()]
  }

  /// The subsection `key` opens, or `nil` if it holds a value.
  public func section(_ key: String) -> RNGitConfigSection? {
    guard case .section(let value) = entries[key] else { return nil }
    return value
  }

  private static let booleans: [String: Bool] = [
    "yes": true, "no": false, "on": true, "off": false,
    "1": true, "0": false, "true": true, "false": false,
  ]

  /// The integer `text` names, as Python's `int()` reads it.
  static func integer(_ text: String) -> Int? {
    var digits = ""
    var sign = 1
    var index = text.trimmedForMicron.startIndex
    let trimmed = text.trimmedForMicron

    if index < trimmed.endIndex, trimmed[index] == "+" || trimmed[index] == "-" {
      if trimmed[index] == "-" { sign = -1 }
      index = trimmed.index(after: index)
    }

    var previousWasUnderscore = true
    while index < trimmed.endIndex {
      let character = trimmed[index]
      if character == "_" {
        guard !previousWasUnderscore else { return nil }
        previousWasUnderscore = true
      } else {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
          scalar.properties.numericType == .decimal, let value = scalar.properties.numericValue
        else { return nil }
        digits.append(String(Int(value)))
        previousWasUnderscore = false
      }
      index = trimmed.index(after: index)
    }

    guard !previousWasUnderscore, let value = Int(digits) else { return nil }
    return sign * value
  }
}

/// Why a configuration file did not parse, with the line the reference blamed.
///
/// Python: the `NestingError`, `DuplicateError` and `ParseError` subclasses of
/// `ConfigObjError` (`RNS/vendor/configobj.py:158-208`). The reference collects every error
/// and raises at the end; this parser stops at the first, which is the one the reference
/// reports when a file has only one.
public enum RNGitConfigError: Error, Equatable, Sendable {

  /// A bracket marker whose depth does not follow the section before it.
  case nesting(line: Int)

  /// A second section or key under a name already taken.
  case duplicate(line: Int)

  /// A line that is neither a section marker nor a readable `key = value`.
  case parse(line: Int)
}

/// A configuration file read the way `configobj` reads one.
///
/// Python: `ConfigObj._parse` (`RNS/vendor/configobj.py:1528-1695`) with the default
/// options, which is how the `rngit` node and client load theirs.
public enum RNGitConfigFile {

  /// The configuration `text` spells out.
  public static func parse(_ text: String) throws -> RNGitConfigSection {
    let lines = text.pythonLines
    let root = Node()
    var stack = [root]
    var index = 0

    while index < lines.count {
      let line = lines[index]
      let stripped = line.trimmedForMicron
      if stripped.isEmpty || stripped.hasPrefix("#") {
        index += 1
        continue
      }

      if let groups = sectionMarker.match(line), let open = groups[2], let name = groups[3],
        let close = groups[4]
      {
        let depth = open.filter { $0 == "[" }.count
        guard depth == close.filter({ $0 == "]" }).count, depth >= 1, depth <= stack.count else {
          throw RNGitConfigError.nesting(line: index + 1)
        }

        let parent = stack[depth - 1]
        let sectionName = try unquote(name, line: index + 1)
        guard !parent.holds(sectionName) else {
          throw RNGitConfigError.duplicate(line: index + 1)
        }

        let node = Node()
        parent.add(.node(node), for: sectionName)
        stack = Array(stack.prefix(depth)) + [node]
        index += 1
        continue
      }

      guard let groups = keyword.match(line), let rawKey = groups[2], var value = groups[3] else {
        throw RNGitConfigError.parse(line: index + 1)
      }

      var parsed: RNGitConfigValue
      if value.hasPrefix("\"\"\"") || value.hasPrefix("'''") {
        let (text, consumed) = try multiline(value, lines: lines, from: index)
        value = text
        index = consumed
        parsed = .scalar(value)
      } else {
        parsed = try handle(value, line: index + 1)
      }

      let key = try unquote(rawKey, line: index + 1)
      let section = stack[stack.count - 1]
      guard !section.holds(key) else { throw RNGitConfigError.duplicate(line: index + 1) }
      section.add(.value(parsed), for: key)
      index += 1
    }

    return root.frozen()
  }

  /// The configuration the file at `url` spells out.
  public static func load(from url: URL) throws -> RNGitConfigSection {
    try parse(String(contentsOf: url, encoding: .utf8))
  }

  // MARK: - Line patterns

  private static let whitespace = MicronPattern.whitespace

  private static let keyword = MicronPattern(
    "^(\(whitespace)*)((?:\".*?\")|(?:'.*?')|(?:[^'\"=].*?))\(whitespace)*="
      + "\(whitespace)*(.*)$")

  private static let sectionMarker = MicronPattern(
    "^(\(whitespace)*)((?:\\[\(whitespace)*)+)"
      + "((?:\"\(whitespace)*[^\(whitespace)].*?\(whitespace)*\")"
      + "|(?:'\(whitespace)*[^\(whitespace)].*?\(whitespace)*')"
      + "|(?:[^'\"\(whitespace)].*?))"
      + "((?:\(whitespace)*\\])+)\(whitespace)*(\\#.*)?$")

  private static let valueExpression = MicronPattern(
    "^(?:(?:((?:(?:(?:\".*?\")|(?:'.*?')|(?:[^'\",\\#][^,\\#]*?))\(whitespace)*,"
      + "\(whitespace)*)*)((?:\".*?\")|(?:'.*?')|(?:[^'\",\\#\(whitespace)][^,]*?)"
      + "|(?:(?<!,)))?)|(,))\(whitespace)*(\\#.*)?$")

  private static let listValueExpression = MicronPattern(
    "((?:\".*?\")|(?:'.*?')|(?:[^'\",\\#]?.*?))\(whitespace)*,\(whitespace)*")

  private static let tripleQuoted: [String: (one: MicronPattern, end: MicronPattern)] = [
    "'''": (
      MicronPattern("^'''(.*?)'''\(whitespace)*(#.*)?$"),
      MicronPattern("^(.*?)'''\(whitespace)*(#.*)?$")
    ),
    "\"\"\"": (
      MicronPattern("^\"\"\"(.*?)\"\"\"\(whitespace)*(#.*)?$"),
      MicronPattern("^(.*?)\"\"\"\(whitespace)*(#.*)?$")
    ),
  ]

  // MARK: - Values

  /// The value one `key = value` line holds, with its comment dropped.
  ///
  /// Python: `_handle_value` (`RNS/vendor/configobj.py:1840-1886`).
  private static func handle(_ value: String, line: Int) throws -> RNGitConfigValue {
    guard let groups = valueExpression.match(value) else {
      throw RNGitConfigError.parse(line: line)
    }
    let prefix = groups[1]
    var single = groups[2]

    guard prefix != "" || single != nil else { throw RNGitConfigError.parse(line: line) }
    if groups[3] != nil { return .list([]) }

    if let value = single {
      if !(prefix ?? "").isEmpty && value.isEmpty {
        single = nil
      } else {
        single = try unquote(value.isEmpty ? "\"\"" : value, line: line)
      }
    }

    guard let prefix, !prefix.isEmpty else { return .scalar(single ?? "") }

    var values = try listValueExpression.firstGroups(in: prefix).map {
      try unquote($0 ?? "", line: line)
    }
    if let single { values.append(single) }
    return .list(values)
  }

  /// The text a triple-quoted value holds, with the index of its last line.
  ///
  /// Python: `_multiline` (`RNS/vendor/configobj.py:1889-1920`).
  private static func multiline(
    _ value: String, lines: [String], from start: Int
  ) throws -> (String, Int) {
    let quote = String(value.prefix(3))
    // The three patterns are keyed by the two quote spellings the caller already tested for.
    guard let patterns = tripleQuoted[quote] else { throw RNGitConfigError.parse(line: start + 1) }
    if let groups = patterns.one.match(value) { return (groups[1] ?? "", start) }

    var text = String(value.dropFirst(3))
    guard !text.contains(quote) else { throw RNGitConfigError.parse(line: start + 1) }

    var index = start
    var closing: String? = nil
    while index < lines.count - 1 {
      index += 1
      text += "\n"
      if lines[index].contains(quote) {
        closing = lines[index]
        break
      }
      text += lines[index]
    }

    guard let closing, let groups = patterns.end.match(closing) else {
      throw RNGitConfigError.parse(line: start + 1)
    }
    return (text + (groups[1] ?? ""), index)
  }

  /// `value` without the pair of quotes around it.
  ///
  /// Python: `_unquote` (`RNS/vendor/configobj.py:1739-1746`), which refuses an empty string.
  private static func unquote(_ value: String, line: Int) throws -> String {
    guard let first = value.first, let last = value.last else {
      throw RNGitConfigError.parse(line: line)
    }
    guard first == last, first == "\"" || first == "'" else { return value }
    return String(value.dropFirst().dropLast())
  }

  // MARK: - Building

  private final class Node {
    enum Entry {
      case value(RNGitConfigValue)
      case node(Node)
    }

    private var order: [String] = []
    private var entries: [String: Entry] = [:]

    func holds(_ key: String) -> Bool { entries[key] != nil }

    func add(_ entry: Entry, for key: String) {
      order.append(key)
      entries[key] = entry
    }

    func frozen() -> RNGitConfigSection {
      RNGitConfigSection(
        order.compactMap { key in
          switch entries[key] {
          case .value(let value): return (key, value)
          case .node(let node): return (key, .section(node.frozen()))
          case nil: return nil
          }
        })
    }
  }
}
