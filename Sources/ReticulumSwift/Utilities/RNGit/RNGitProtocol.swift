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
///
/// Python: `PATH_*` on both classes (`server.py:285-295`, `server.py:1953-1963`).
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
///
/// Python: `RES_*` on both classes (`server.py:297-301`, `server.py:1965-1969`).
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
/// Python: `IDX_*` on both classes (`server.py:303-305`, `server.py:1971-1973`), which are
/// integers rather than strings; the requests that carry other fields key those by name.
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

/// A file a node answers with instead of bytes.
///
/// Python: `return open(path, "rb"), {IDX_RESULT_CODE: RES_OK}` (`server.py:2997`), which
/// sends the file as a resource. The directory holding it lives as long as the link the
/// request arrived on, which the node closes it with.
public struct RNGitFile: Equatable, Sendable {

  /// Where the file is.
  public let path: String

  /// The directory the node removes once the link closes.
  public let directory: String

  /// Creates an answer naming `path`, held in `directory`.
  public init(path: String, directory: String) {
    self.path = path
    self.directory = directory
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
/// Python: the `dict` a handler works on once `type(data) == dict` holds. A key is matched
/// as Python matches it, so a boolean or a float equal to an integer key finds that key, and
/// a later entry replaces an earlier one, as building the dictionary does.
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
  /// Python: `resolve_permission` given what `parse_request_repository_path` returned, which
  /// answers false for the pair it returns when it parsed nothing (`server.py:2314`).
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
/// Python: `san_sha` (`util.py:74-77`). Its `len` call sits outside the `try`, so a value
/// with no length raises out of the handler that called it rather than answering `None`.
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

  /// The keys a dictionary built from this map holds, in the order Python keeps them.
  private var pythonKeys: [MsgPack.Value] {
    guard case .map(let fields) = self else { return [] }
    var keys: [MsgPack.Value] = []
    for (key, _) in fields where !keys.contains(where: { $0.pythonEquals(key) }) {
      keys.append(key)
    }
    return keys
  }

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
