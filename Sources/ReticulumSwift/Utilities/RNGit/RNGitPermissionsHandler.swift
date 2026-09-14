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

/// The node's answer to a peer reading or rewriting the `allowed` file of a group or a repository.
///
/// Both steps need read and administer access at the level they name. A rewrite is validated line
/// by line before anything is written, and refused outright where the file it would replace is one
/// the node runs.
public struct RNGitPermissionsHandler {

  /// The groups the node serves, which a rewrite is read back into.
  public var store: RNGitRepositoryStore

  /// Identities the node refuses before resolving anything.
  public var blockedIdentities: Set<Data>

  /// Creates a handler answering from `store`.
  public init(store: RNGitRepositoryStore, blockedIdentities: Set<Data> = []) {
    self.store = store
    self.blockedIdentities = blockedIdentities
  }

  /// What the store grants, as a resolver reads it.
  private var access: RNGitAccessControl {
    RNGitAccessControl(
      groups: store.groups, blockedIdentities: blockedIdentities,
      identityAliases: store.identityAliases)
  }

  /// The answer a peer identifying as `identity` gets.
  ///
  /// A rewrite that lands is applied to ``access`` before the answer goes out, so the next request
  /// is decided by the file just written.
  public mutating func handle(_ request: MsgPack.Value, from identity: RNGitRemoteIdentity?)
    -> RNGitResponse
  {
    guard let identity else { return RNGitResponse(.disallowed, "Not identified") }
    guard let fields = RNGitRequestFields(request) else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    let operation = fields["operation"] ?? .nil
    guard operation.pythonIsTruthy else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }

    switch operation.asString {
    case "gperms":
      guard let named = fields[RNGitRequestKey.group] else {
        return RNGitResponse(.invalidRequest, "No group specified")
      }
      guard let path = named.asString else { return RNGitResponse(.remoteFailure, "Remote error") }
      return group(RNGitAccessControl.groupPath(path), fields, identity)

    case "rperms":
      guard let named = fields[RNGitRequestKey.repository] else {
        return RNGitResponse(.invalidRequest, "No repository specified")
      }
      guard let path = named.asString else { return RNGitResponse(.remoteFailure, "Remote error") }
      let names = RNGitAccessControl.repositoryPath(path)
      let hash = identity.hash
      guard access.allows(hash, names: names, permission: .admin) else {
        return access.allows(hash, names: names, permission: .read)
          ? RNGitResponse(.disallowed, "Not allowed") : RNGitResponse(.notFound, "Not found")
      }
      return repository(names, fields, identity)

    default: return RNGitResponse(.invalidRequest, "Invalid request")
    }
  }

  /// The answer to a request naming a group, which `name` is `nil` for where it named none.
  private mutating func group(
    _ name: String?, _ fields: RNGitRequestFields, _ identity: RNGitRemoteIdentity
  ) -> RNGitResponse {
    let hash = identity.hash
    guard name.map({ access.allowsGroup(hash, group: $0, permission: .read) }) == true else {
      return RNGitResponse(.notFound, "Not found")
    }
    guard let name, access.allowsGroup(hash, group: name, permission: .admin) else {
      return RNGitResponse(.disallowed, "Not allowed")
    }

    switch step(fields) {
    case .missing: return RNGitResponse(.invalidRequest, "Invalid request")
    case .unknown: return RNGitResponse(.invalidRequest, "Invalid step")
    case .get: return read(store.groups[name]?.path)
    case .set:
      switch write(store.groups[name]?.path, fields) {
      case .refused(let answer): return answer
      case .wrote:
        store.updateGroupPermissions(named: name)
        return RNGitResponse(.ok)
      }
    }
  }

  /// The answer to a request naming a repository, which `names` is `nil` for where it named none.
  private mutating func repository(
    _ names: (group: String, repository: String)?, _ fields: RNGitRequestFields,
    _ identity: RNGitRemoteIdentity
  ) -> RNGitResponse {
    let hash = identity.hash
    guard access.allows(hash, names: names, permission: .read) else {
      return RNGitResponse(.notFound, "Not found")
    }
    guard let names, access.allows(hash, names: names, permission: .admin) else {
      return RNGitResponse(.disallowed, "Not allowed")
    }
    let path = store.groups[names.group]?.repositories[names.repository]?.path

    switch step(fields) {
    case .missing: return RNGitResponse(.invalidRequest, "Invalid request")
    case .unknown: return RNGitResponse(.invalidRequest, "Invalid step")
    case .get: return read(path)
    case .set:
      // A rewrite is decided at group level, where every other repository step is decided at
      // repository level.
      guard access.allowsGroup(hash, group: names.group, permission: .read) else {
        return RNGitResponse(.notFound, "Not found")
      }
      guard access.allowsGroup(hash, group: names.group, permission: .admin) else {
        return RNGitResponse(.disallowed, "Not allowed")
      }
      switch write(path, fields) {
      case .refused(let answer): return answer
      case .wrote:
        store.updateRepositoryPermissions(group: names.group, repository: names.repository)
        return RNGitResponse(.ok)
      }
    }
  }

  /// What the `allowed` file beside `path` holds, which is nothing where there is no file.
  private func read(_ path: String?) -> RNGitResponse {
    guard let path else { return RNGitResponse(.remoteFailure, "Error getting permissions") }
    var content = ""
    let allowed = path + ".allowed"
    if RNGitWorkStore.isFile(allowed) {
      guard let bytes = FileManager.default.contents(atPath: allowed),
        let text = String(data: bytes, encoding: .utf8)
      else { return RNGitResponse(.remoteFailure, "Error getting permissions") }
      content = text
    }
    return RNGitResponse(.ok, MsgPack.encode(.map([(.string("content"), .string(content))])))
  }

  /// What a rewrite came to.
  private enum Written {

    /// Nothing was written, and this is the answer saying why.
    case refused(RNGitResponse)

    /// The file was written.
    case wrote
  }

  /// Writes what the request carries to the `allowed` file beside `path`.
  private func write(_ path: String?, _ fields: RNGitRequestFields) -> Written {
    guard let text = (fields["content"] ?? .string("")).asString else {
      return .refused(RNGitResponse(.remoteFailure, "Remote error"))
    }
    if let refusal = Self.refusal(in: text, aliases: access.identityAliases) {
      return .refused(refusal)
    }

    guard let path else {
      return .refused(RNGitResponse(.remoteFailure, "Error setting permissions"))
    }
    let allowed = path + ".allowed"
    guard !FileManager.default.isExecutableFile(atPath: allowed) else {
      return .refused(
        RNGitResponse(
          .disallowed, "Executable permission resolvers can only be modified node-side"))
    }

    let temporary = allowed + ".tmp"
    guard (try? Data(text.utf8).write(to: URL(fileURLWithPath: temporary))) != nil else {
      return .refused(RNGitResponse(.remoteFailure, "Error setting permissions"))
    }
    try? FileManager.default.removeItem(atPath: allowed)
    guard (try? FileManager.default.moveItem(atPath: temporary, toPath: allowed)) != nil else {
      return .refused(RNGitResponse(.remoteFailure, "Error setting permissions"))
    }
    return .wrote
  }

  /// The answer refusing the first line of `text` that grants nothing, or `nil` where every line
  /// grants something.
  ///
  /// A line that is empty once trimmed, and one opening with `#`, grants nothing and is passed
  /// over.
  private static func refusal(in text: String, aliases: [String: String]) -> RNGitResponse? {
    for (offset, line) in text.pythonLines.enumerated() {
      let entry = line.pythonStripped
      guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }
      let grant = RNGitPermissionSet.grant(in: entry, aliases: aliases)
      guard grant.permission == nil || grant.target == nil else { continue }
      return RNGitResponse(
        .invalidRequest, "Invalid permission \"\(entry)\" on line \(offset + 1)")
    }
    return nil
  }

  /// What a request asks to be done with the file it names.
  private enum Step {

    /// Read it.
    case get

    /// Rewrite it.
    case set

    /// The request named no step.
    case missing

    /// The request named a step the node does not know.
    case unknown
  }

  /// The step a request names.
  private func step(_ fields: RNGitRequestFields) -> Step {
    let named = fields["step"] ?? .nil
    guard named.pythonIsTruthy else { return .missing }
    switch named.asString {
    case "get": return .get
    case "set": return .set
    default: return .unknown
    }
  }
}
