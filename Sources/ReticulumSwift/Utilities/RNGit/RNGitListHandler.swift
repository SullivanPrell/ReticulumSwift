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

/// The node's answer to a request for the references a repository holds.
///
/// Python: `handle_list` (`server.py:2869-2928`).
public struct RNGitListHandler: Sendable {

  /// The groups the node serves, and what they grant.
  public let access: RNGitAccessControl

  /// Runs the `git` the answer is read from.
  public let runner: RNGitCommandRunner

  /// Creates a handler answering from `access`.
  public init(access: RNGitAccessControl, runner: RNGitCommandRunner) {
    self.access = access
    self.runner = runner
  }

  /// The answer a peer holding `identityHash` gets, or `nil` where the peer gets none.
  ///
  /// A request naming its repository with anything but a string leaves the reference raising
  /// out of the handler, which sends nothing at all (`Link.py:804-856`).
  public func handle(_ request: MsgPack.Value, from identityHash: Data?) -> RNGitResponse? {
    guard let identityHash else { return RNGitResponse(.disallowed, "Not identified") }
    guard case .map(let fields) = request else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    guard let requested = Self.field(RNGitRequestKey.repository, in: fields) else {
      return RNGitResponse(.invalidRequest, "No repository specified")
    }
    guard let requestedPath = requested.asString else { return nil }

    let names = RNGitAccessControl.repositoryPath(requestedPath)
    let readable = Self.allows(access, identityHash, names, .read)
    let writable = Self.allows(access, identityHash, names, .write)
    let forPush = Self.isTruthy(Self.field("for_push", in: fields))

    guard forPush ? writable : readable else {
      return RNGitResponse(.notFound, readable ? "Not allowed" : "Not found")
    }
    guard let names, let path = access.groups[names.group]?.repositories[names.repository]?.path
    else { return RNGitResponse(.notFound, "Not found") }
    return listing(at: path)
  }

  /// The references at `path`, with the branch its `HEAD` names.
  private func listing(at path: String) -> RNGitResponse {
    var head = "master"
    let headPath = path + "/HEAD"
    if FileManager.default.fileExists(atPath: headPath) {
      guard let content = FileManager.default.contents(atPath: headPath) else {
        return RNGitResponse(.remoteFailure, "Remote error")
      }
      if content.starts(with: Data("ref: ".utf8)) {
        head = Data(content.dropFirst(5)).pythonStripped.utf8IgnoringInvalid
      }
    }

    guard
      let result = runner.run(
        "git", arguments: ["for-each-ref", "--format", "%(objectname) %(refname)"], in: path)
    else { return RNGitResponse(.remoteFailure, "Remote error") }
    guard result.status == 0 else {
      return RNGitResponse(.remoteFailure, "Could not list refs")
    }

    var seen: Set<Substring> = []
    var lines: [String] = []
    for line in result.standardOutput.trimmedForMicron.components(separatedBy: "\n")
    where !line.trimmedForMicron.isEmpty {
      let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, seen.insert(parts[1]).inserted else { continue }
      lines.append(line)
    }

    let listed = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    return RNGitResponse(.ok, listed + "@\(head) HEAD\n")
  }

  /// Whether `identityHash` holds `permission` on the repository `names` points at.
  private static func allows(
    _ access: RNGitAccessControl, _ identityHash: Data,
    _ names: (group: String, repository: String)?, _ permission: RNGitPermission
  ) -> Bool {
    guard let names else { return false }
    return access.allows(
      identityHash, group: names.group, repository: names.repository, permission: permission)
  }

  /// The value `fields` holds for the integer key `key`.
  ///
  /// A later entry replaces an earlier one, as building the dictionary does, and a boolean
  /// key counts as the integer it equals in Python.
  private static func field(_ key: UInt8, in fields: [(MsgPack.Value, MsgPack.Value)])
    -> MsgPack.Value?
  {
    var found: MsgPack.Value?
    for (name, value) in fields where Self.names(name, key) { found = value }
    return found
  }

  /// The value `fields` holds for the named key `key`.
  private static func field(_ key: String, in fields: [(MsgPack.Value, MsgPack.Value)])
    -> MsgPack.Value?
  {
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

  /// Whether `value` is one Python reads as true.
  private static func isTruthy(_ value: MsgPack.Value?) -> Bool {
    switch value {
    case nil, .nil: return false
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

extension Data {

  /// These bytes as UTF-8, dropping every byte that is not part of a sequence.
  ///
  /// Python: `bytes.decode("utf-8", errors="ignore")`.
  var utf8IgnoringInvalid: String {
    var parser = UTF8.ForwardParser()
    var bytes = makeIterator()
    var scalars = String.UnicodeScalarView()
    decoding: while true {
      switch parser.parseScalar(from: &bytes) {
      case .valid(let encoded): scalars.append(UTF8.decode(encoded))
      case .error: continue
      case .emptyInput: break decoding
      }
    }
    return String(scalars)
  }

  /// These bytes without leading and trailing ASCII whitespace.
  ///
  /// Python: `bytes.strip`, whose set is space, tab, newline, carriage return, vertical tab
  /// and form feed.
  var pythonStripped: Data {
    let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C]
    var start = startIndex
    var end = endIndex
    while start < end, whitespace.contains(self[start]) { start = index(after: start) }
    while end > start, whitespace.contains(self[index(before: end)]) { end = index(before: end) }
    return Data(self[start..<end])
  }
}
