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

/// The request paths a node registers a handler for.
public enum RNGitRequestPath: String, CaseIterable, Sendable {

  /// The references a repository holds.
  case list = "/git/list"

  /// A pack of the objects a peer asks for.
  case fetch = "/git/fetch"

  /// A pack a peer sends, with the references it updates.
  case push = "/git/push"

  /// Removing a repository.
  case delete = "/git/delete"

  /// Creating a repository.
  case create = "/git/create"

  /// Creating a repository from another the node serves.
  case fork = "/git/fork"

  /// Synchronizing a mirror with its upstream.
  case sync = "/git/sync"

  /// Creating a repository that mirrors an upstream.
  case mirror = "/git/mirror"

  /// The releases a repository carries, and their assets.
  case release = "/mgmt/release"

  /// The work documents a repository carries.
  case work = "/mgmt/work"

  /// The permissions a repository and its group grant.
  case perms = "/mgmt/perms"
}

/// The first byte of every answer a node sends.
public enum RNGitResponseCode: UInt8, CaseIterable, Sendable {

  /// The request succeeded, and the rest of the answer is its result.
  case ok = 0x00

  /// The peer may not make this request.
  case disallowed = 0x01

  /// The request is not one the handler can read.
  case invalidRequest = 0x02

  /// There is nothing at the path the request names, as far as the peer may know.
  case notFound = 0x03

  /// The node tried and failed.
  case remoteFailure = 0xFF
}

/// The keys a request map carries.
///
/// These are integers rather than strings; the requests that carry other fields key those by name.
public enum RNGitRequestKey {

  /// The `group/repository` path a request works on.
  public static let repository: UInt8 = 0x00

  /// The result code an answer carries.
  public static let resultCode: UInt8 = 0x01

  /// The group a request works on.
  public static let group: UInt8 = 0x02
}

/// One answer a node sends, as a result code and the bytes that follow it.
public struct RNGitResponse: Equatable, Sendable {

  /// The code the answer opens with.
  public let code: RNGitResponseCode

  /// Everything after the code.
  public let body: Data

  /// The answer as it goes on the wire.
  public var encoded: Data { Data([code.rawValue]) + body }

  /// Creates an answer carrying `body`.
  public init(_ code: RNGitResponseCode, _ body: Data = Data()) {
    self.code = code
    self.body = body
  }

  /// Creates an answer carrying `message` as UTF-8.
  public init(_ code: RNGitResponseCode, _ message: String) {
    self.init(code, Data(message.utf8))
  }
}

/// What rides alongside a file a node answers with.
public enum RNGitFileMetadata: Equatable, Sendable {

  /// The code an answer built for the peer carries.
  case resultCode(RNGitResponseCode)

  /// The name a file the node already held carries.
  case name(String)

  /// The metadata as it goes on the wire.
  public var encoded: MsgPack.Value {
    switch self {
    case .resultCode(let code):
      return .map([(.uint(UInt64(RNGitRequestKey.resultCode)), .uint(UInt64(code.rawValue)))])
    case .name(let name):
      return .map([(.string("name"), .bytes(Data(name.utf8)))])
    }
  }
}

/// A file a node answers with instead of bytes.
///
/// The file is sent as a resource. A file the node built for the request is held in a directory
/// that lives as long as the link the request arrived on, which the node closes it with; one the
/// node already held is answered where it lies.
public struct RNGitFile: Equatable, Sendable {

  /// Where the file is.
  public let path: String

  /// The directory the node removes once the link closes, where the file was built for the
  /// request.
  public let directory: String?

  /// What the answer carries beside the file.
  public let metadata: RNGitFileMetadata

  /// Creates an answer naming `path`, held in `directory`.
  public init(path: String, directory: String? = nil, metadata: RNGitFileMetadata) {
    self.path = path
    self.directory = directory
    self.metadata = metadata
  }
}

/// What a handler answers with.
public enum RNGitAnswer: Equatable, Sendable {

  /// Bytes the node sends as the response itself.
  case response(RNGitResponse)

  /// A file the node sends as a resource, under a result code of `ok`.
  case file(RNGitFile)
}

/// The fields a request map carries, read as Python reads them.
///
/// A key is matched the way a dictionary matches it, so a boolean or a float equal to an integer
/// key finds that key, and a later entry replaces an earlier one.
public struct RNGitRequestFields {

  private let fields: [(MsgPack.Value, MsgPack.Value)]

  /// The fields `request` carries, or `nil` where it is not a map.
  public init?(_ request: MsgPack.Value) {
    guard case .map(let entries) = request else { return nil }
    fields = entries
  }

  /// The value the integer key `key` holds, or `nil` where the request carries none.
  public subscript(key: UInt8) -> MsgPack.Value? {
    var found: MsgPack.Value?
    for (name, value) in fields where Self.names(name, key) { found = value }
    return found
  }

  /// The value the named key `key` holds, or `nil` where the request carries none.
  public subscript(key: String) -> MsgPack.Value? {
    var found: MsgPack.Value?
    for (name, value) in fields where name.asString == key { found = value }
    return found
  }

  /// Whether `key` is the integer `index`.
  private static func names(_ key: MsgPack.Value, _ index: UInt8) -> Bool {
    switch key {
    case .int, .uint: return key.asInt == Int(index)
    case .bool(let flag): return (flag ? 1 : 0) == Int(index)
    case .double(let value): return value == Double(index)
    default: return false
    }
  }
}

extension MsgPack.Value {

  /// Whether Python reads this value as true.
  ///
  /// Every container is true when it holds something, every number when it is not zero, and
  /// `nil` is false.
  public var pythonIsTruthy: Bool {
    switch self {
    case .nil: return false
    case .bool(let flag): return flag
    case .int(let number): return number != 0
    case .uint(let number): return number != 0
    case .double(let number): return number != 0
    case .string(let text): return !text.isEmpty
    case .bytes(let data): return !data.isEmpty
    case .array(let items): return !items.isEmpty
    case .map(let fields): return !fields.isEmpty
    }
  }
}

extension RNGitAccessControl {

  /// Whether `identityHash` may do `permission` on the repository `names` points at.
  ///
  /// Answers false for the pair ``RNGitAccessControl/repositoryPath(_:)`` returns when it parsed
  /// nothing.
  public func allows(
    _ identityHash: Data, names: (group: String, repository: String)?,
    permission: RNGitPermission
  ) -> Bool {
    guard let names else { return false }
    return allows(
      identityHash, group: names.group, repository: names.repository, permission: permission)
  }
}

/// What `san_sha` makes of one value a request carries.
///
/// A value with no length raises rather than answering `nil`.
public enum RNGitObjectID: Equatable, Sendable {

  /// A full-length hexadecimal object id.
  case valid(String)

  /// A value `san_sha` answers `None` for.
  case refused

  /// A value `len` raises for.
  case unmeasurable
}

extension MsgPack.Value {

  /// Whether Python holds this value and `other` to be one dictionary key.
  ///
  /// Numbers compare across their types, so `0`, `0.0` and `false` are the same key.
  public func pythonEquals(_ other: MsgPack.Value) -> Bool {
    if let left = Self.number(self), let right = Self.number(other) { return left == right }
    return self == other
  }

  /// This value as the number Python compares it by, or `nil` where it is not one.
  private static func number(_ value: MsgPack.Value) -> Double? {
    switch value {
    case .bool(let flag): return flag ? 1 : 0
    case .int(let number): return Double(number)
    case .uint(let number): return Double(number)
    case .double(let number): return number
    default: return nil
    }
  }

  /// The entries a dictionary built from this map holds.
  ///
  /// A repeated key keeps the place it first took and the value it last took, as building
  /// the dictionary entry by entry does.
  fileprivate var pythonItems: [(key: MsgPack.Value, value: MsgPack.Value)] {
    guard case .map(let fields) = self else { return [] }
    var items: [(key: MsgPack.Value, value: MsgPack.Value)] = []
    for (key, value) in fields {
      if let index = items.firstIndex(where: { $0.key.pythonEquals(key) }) {
        items[index].value = value
      } else {
        items.append((key, value))
      }
    }
    return items
  }

  /// The keys a dictionary built from this map holds, in the order Python keeps them.
  private var pythonKeys: [MsgPack.Value] { pythonItems.map(\.key) }

  /// What `len` answers for this value, or `nil` where Python raises for it.
  public var pythonLength: Int? {
    switch self {
    case .string(let text): return text.unicodeScalars.count
    case .bytes(let data): return data.count
    case .array(let items): return items.count
    case .map: return pythonKeys.count
    case .nil, .bool, .int, .uint, .double: return nil
    }
  }

  /// The values Python walks this one with, or `nil` where it is not iterable.
  ///
  /// A string yields its code points, a byte string the integers it holds, and a map its
  /// keys.
  public var pythonIterated: [MsgPack.Value]? {
    switch self {
    case .string(let text): return text.unicodeScalars.map { .string(String($0)) }
    case .bytes(let data): return data.map { .uint(UInt64($0)) }
    case .array(let items): return items
    case .map: return pythonKeys
    case .nil, .bool, .int, .uint, .double: return nil
    }
  }

  /// The object id this value names, as `san_sha` reads it.
  ///
  /// The length is measured only to find the values Python raises for; the bound itself is
  /// `sanitiseObjectID`'s to apply.
  public var pythonObjectID: RNGitObjectID {
    guard pythonLength != nil else { return .unmeasurable }
    guard let digest = asString.flatMap(GitReferenceNames.sanitiseObjectID) else {
      return .refused
    }
    return .valid(digest)
  }
}

/// What `san_ref` makes of one value a request carries.
///
/// A value of any other type raises.
public enum RNGitReferenceName: Equatable, Sendable {

  /// A usable reference name.
  case valid(String)

  /// A name `san_ref` answers `None` for.
  case refused

  /// A value `san_ref` raises for.
  case unusable
}

extension MsgPack.Value {

  /// The reference name this value carries, as `san_ref` reads it.
  public var pythonReferenceName: RNGitReferenceName {
    guard let text = asString else { return .unusable }
    guard let name = GitReferenceNames.sanitise(text) else { return .refused }
    return .valid(name)
  }

  /// This value as Python writes it into a formatted string.
  ///
  /// A string is written as it stands; every other value is written the way a container writes what
  /// it holds.
  public var pythonDescription: String {
    if case .string(let text) = self { return text }
    return pythonRepresentation
  }

  /// This value as `repr` writes it.
  public var pythonRepresentation: String {
    switch self {
    case .nil: return "None"
    case .bool(let flag): return flag ? "True" : "False"
    case .int(let number): return String(number)
    case .uint(let number): return String(number)
    case .double(let number): return "\(number)"
    case .string(let text): return Self.quotedText(Array(text.unicodeScalars))
    case .bytes(let data): return Self.quotedBytes(data)
    case .array(let items):
      return "[" + items.map(\.pythonRepresentation).joined(separator: ", ") + "]"
    case .map:
      let written = pythonItems.map {
        $0.key.pythonRepresentation + ": " + $0.value.pythonRepresentation
      }
      return "{" + written.joined(separator: ", ") + "}"
    }
  }

  /// The quote `repr` puts around a string holding `hasApostrophe` and `hasQuotationMark`.
  ///
  /// The apostrophe is preferred, and gives way only to a string that holds one already and
  /// no quotation mark to give way to in turn.
  private static func quote(_ hasApostrophe: Bool, _ hasQuotationMark: Bool) -> Unicode.Scalar {
    hasApostrophe && !hasQuotationMark ? "\"" : "'"
  }

  /// `scalars` as `repr` writes a string.
  private static func quotedText(_ scalars: [Unicode.Scalar]) -> String {
    let quote = quote(scalars.contains("'"), scalars.contains("\""))
    var written = String(quote)
    for scalar in scalars {
      if let escape = escape(scalar, quote) {
        written += escape
      } else if isPrintable(scalar) {
        written.unicodeScalars.append(scalar)
      } else {
        written += hexEscape(scalar.value)
      }
    }
    return written + String(quote)
  }

  /// `data` as `repr` writes a byte string.
  ///
  /// Only the printable part of ASCII is written as itself; every other byte is written as
  /// a two-digit escape, whatever the code point of that value would be.
  private static func quotedBytes(_ data: Data) -> String {
    let quote = quote(data.contains(0x27), data.contains(0x22))
    var written = "b" + String(quote)
    for byte in data {
      let scalar = Unicode.Scalar(byte)
      if let escape = escape(scalar, quote) {
        written += escape
      } else if (0x20..<0x7F).contains(byte) {
        written.unicodeScalars.append(scalar)
      } else {
        written += hexEscape(UInt32(byte))
      }
    }
    return written + String(quote)
  }

  /// The escape `repr` always writes `scalar` as, or `nil` where it writes it some other way.
  private static func escape(_ scalar: Unicode.Scalar, _ quote: Unicode.Scalar) -> String? {
    switch scalar {
    case quote, "\\": return "\\" + String(scalar)
    case "\n": return "\\n"
    case "\r": return "\\r"
    case "\t": return "\\t"
    default: return nil
    }
  }

  /// The numeric escape `repr` writes the code point `value` as.
  private static func hexEscape(_ value: UInt32) -> String {
    if value < 0x100 { return String(format: "\\x%02x", value) }
    if value < 0x10000 { return String(format: "\\u%04x", value) }
    return String(format: "\\U%08x", value)
  }

  /// Whether `str.isprintable` answers true for `scalar`.
  ///
  /// The space is printable, and every other separator is not, along with every category that
  /// carries no glyph of its own.
  private static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
    if scalar == " " { return true }
    switch scalar.properties.generalCategory {
    case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator,
      .paragraphSeparator, .spaceSeparator:
      return false
    default: return true
    }
  }
}

extension String {

  /// This string with the whitespace Python strips taken off both ends.
  ///
  /// Every character that is whitespace is taken off. That is a wider set than
  /// ``Foundation/Data/pythonStripped``, and holds the separators and the four information
  /// separators alongside the familiar ASCII whitespace.
  public var pythonStripped: String {
    var scalars = Array(unicodeScalars)[...]
    while let first = scalars.first, Self.pythonWhitespace.contains(first) {
      scalars = scalars.dropFirst()
    }
    while let last = scalars.last, Self.pythonWhitespace.contains(last) {
      scalars = scalars.dropLast()
    }
    return String(String.UnicodeScalarView(scalars))
  }

  /// This string parted at every run of whitespace, taking at most `limit` parts.
  ///
  /// Whitespace at either end parts nothing, so a string holding only whitespace parts into
  /// nothing at all, and the last field carries everything left once `limit` parts are taken.
  public func pythonSplit(limit: Int = .max) -> [String] {
    var fields: [String] = []
    var scalars = Array(unicodeScalars)[...]
    while true {
      while let first = scalars.first, Self.pythonWhitespace.contains(first) {
        scalars = scalars.dropFirst()
      }
      guard !scalars.isEmpty else { return fields }
      guard fields.count < limit else {
        fields.append(String(String.UnicodeScalarView(scalars)))
        return fields
      }
      var field = String.UnicodeScalarView()
      while let first = scalars.first, !Self.pythonWhitespace.contains(first) {
        field.append(first)
        scalars = scalars.dropFirst()
      }
      fields.append(String(field))
    }
  }

  /// Every scalar Python reads as whitespace.
  private static let pythonWhitespace: Set<Unicode.Scalar> = [
    "\u{09}", "\u{0A}", "\u{0B}", "\u{0C}", "\u{0D}", "\u{1C}", "\u{1D}", "\u{1E}", "\u{1F}",
    "\u{20}", "\u{85}", "\u{A0}", "\u{1680}", "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}",
    "\u{2004}", "\u{2005}", "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}",
    "\u{2028}", "\u{2029}", "\u{202F}", "\u{205F}", "\u{3000}",
  ]
}

extension String {

  /// Whether `isdigit` answers true for this string.
  ///
  /// Every scalar must carry a digit value, which covers the decimal digits of every script along
  /// with the forms, such as the superscripts, that stand for a digit without being one.
  public var pythonIsDigit: Bool {
    guard !isEmpty else { return false }
    return unicodeScalars.allSatisfy {
      $0.properties.numericType == .decimal || $0.properties.numericType == .digit
    }
  }

  /// What `int` answers for this string, or `nil` where Python raises for it.
  ///
  /// Whitespace surrounds an optional sign and the digits, which are the decimal digits of any
  /// script and may be parted singly by underscores.
  public var pythonInteger: Int? {
    var scalars = Array(pythonStripped.unicodeScalars)[...]
    var negative = false
    if let first = scalars.first, first == "+" || first == "-" {
      negative = first == "-"
      scalars = scalars.dropFirst()
    }

    var value = 0
    var afterDigit = false
    for scalar in scalars {
      if scalar == "_" {
        guard afterDigit else { return nil }
        afterDigit = false
        continue
      }
      guard scalar.properties.numericType == .decimal,
        let digit = scalar.properties.numericValue
      else { return nil }
      let (scaled, scaledOver) = value.multipliedReportingOverflow(by: 10)
      guard !scaledOver else { return nil }
      let (added, addedOver) = scaled.addingReportingOverflow(Int(digit))
      guard !addedOver else { return nil }
      value = added
      afterDigit = true
    }

    guard afterDigit else { return nil }
    return negative ? -value : value
  }
}

extension MsgPack.Value {

  /// What `int` answers for this value, or `nil` where Python raises for it.
  ///
  /// A byte string is refused, as `int` refuses one given no base to read it in.
  public var pythonInteger: Int? {
    switch self {
    case .bool(let flag): return flag ? 1 : 0
    case .int(let number): return Int(number)
    case .uint(let number): return Int(exactly: number)
    case .double(let number):
      guard number.isFinite else { return nil }
      let truncated = number.rounded(.towardZero)
      guard truncated >= -9_223_372_036_854_775_808, truncated < 9_223_372_036_854_775_808 else {
        return nil
      }
      return Int(truncated)
    case .string(let text): return text.pythonInteger
    case .nil, .bytes, .array, .map: return nil
    }
  }

  /// What `hexrep` writes for this value with no delimiter, or `nil` where Python raises.
  ///
  /// A value that cannot be walked is written as though it were the one value it holds.
  public var pythonHexrep: String? {
    var written = ""
    for item in pythonIterated ?? [self] {
      guard let number = item.pythonWholeNumber else { return nil }
      written += Self.hexadecimal(number)
    }
    return written
  }

  /// This value as a format specification for an integer reads it, or `nil` where it is not one.
  private var pythonWholeNumber: Int? {
    switch self {
    case .bool(let flag): return flag ? 1 : 0
    case .int(let number): return Int(number)
    case .uint(let number): return Int(exactly: number)
    default: return nil
    }
  }

  /// `number` as the two-digit hexadecimal format writes it, padded after the sign.
  private static func hexadecimal(_ number: Int) -> String {
    let sign = number < 0 ? "-" : ""
    var digits = String(number.magnitude, radix: 16)
    while sign.count + digits.count < 2 { digits = "0" + digits }
    return sign + digits
  }

  /// Whether Python orders this value before `other`, or `nil` where it raises comparing them.
  ///
  /// Numbers compare across their types, and a sequence compares by its members and then by how
  /// many it holds. Nothing else compares to anything but its own kind.
  public func pythonPrecedes(_ other: MsgPack.Value) -> Bool? {
    if let left = Self.magnitude(self), let right = Self.magnitude(other) { return left < right }
    switch (self, other) {
    case (.string(let left), .string(let right)):
      return Self.precedes(
        Array(left.unicodeScalars).map { UInt32($0.value) },
        Array(right.unicodeScalars).map { UInt32($0.value) })
    case (.bytes(let left), .bytes(let right)):
      return Self.precedes(left.map { UInt32($0) }, right.map { UInt32($0) })
    case (.array(let left), .array(let right)):
      for (first, second) in zip(left, right) {
        if first == second { continue }
        return first.pythonPrecedes(second)
      }
      return left.count < right.count
    default: return nil
    }
  }

  /// This value as the number it compares by, or `nil` where it is not one.
  private static func magnitude(_ value: MsgPack.Value) -> Double? {
    switch value {
    case .bool(let flag): return flag ? 1 : 0
    case .int(let number): return Double(number)
    case .uint(let number): return Double(number)
    case .double(let number): return number
    default: return nil
    }
  }

  /// Whether `left` orders before `right` member by member, and then by how many each holds.
  private static func precedes(_ left: [UInt32], _ right: [UInt32]) -> Bool {
    for (first, second) in zip(left, right) where first != second { return first < second }
    return left.count < right.count
  }
}
