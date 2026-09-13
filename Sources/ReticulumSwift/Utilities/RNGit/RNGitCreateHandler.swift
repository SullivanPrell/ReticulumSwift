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

/// The node's answer to a peer asking for a repository of its own.
///
/// Resolves what the group grants rather than what the repository grants, so an identity the node
/// blocks is refused nothing here.
public struct RNGitCreateHandler {

  /// The groups the node serves, and the repositories it holds them in.
  public var store: RNGitRepositoryStore

  /// Identities the node refuses before resolving what a repository grants.
  public var blockedIdentities: Set<Data>

  /// Runs the `git` the repository is made with.
  public var runner: RNGitCommandRunner

  /// Creates a handler registering into `store`.
  public init(
    store: RNGitRepositoryStore, runner: RNGitCommandRunner, blockedIdentities: Set<Data> = []
  ) {
    self.store = store
    self.runner = runner
    self.blockedIdentities = blockedIdentities
  }

  /// What the store grants, read the way the node's access control reads it.
  private var access: RNGitAccessControl {
    RNGitAccessControl(
      groups: store.groups, blockedIdentities: blockedIdentities,
      identityAliases: store.identityAliases)
  }

  /// The answer a peer holding `identityHash` gets, or `nil` where it gets none.
  public mutating func handle(
    _ request: MsgPack.Value, from identityHash: Data?
  ) -> RNGitResponse? {
    guard let identityHash else { return RNGitResponse(.disallowed, "Not identified") }
    guard let fields = RNGitRequestFields(request) else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    guard let requested = fields[RNGitRequestKey.repository] else {
      return RNGitResponse(.invalidRequest, "No repository specified")
    }
    guard let requestedPath = requested.asString else { return nil }

    guard let names = RNGitAccessControl.repositoryPath(requestedPath),
      !names.group.isEmpty, !names.repository.isEmpty
    else { return RNGitResponse(.invalidRequest, "Invalid request") }
    guard let group = store.groups[names.group] else {
      return RNGitResponse(.notFound, "Not found")
    }

    let control = access
    let read = control.allowsGroup(identityHash, group: names.group, permission: .read)
    let create = control.allowsGroup(identityHash, group: names.group, permission: .create)

    guard FileManager.default.fileExists(atPath: group.path) else {
      return RNGitResponse(.notFound, "Not found")
    }
    guard create else {
      guard read else { return RNGitResponse(.notFound, "Not found") }
      return RNGitResponse(.disallowed, "Not allowed")
    }

    let path = group.path + "/" + names.repository
    guard group.repositories[names.repository] == nil,
      !FileManager.default.fileExists(atPath: path)
    else {
      guard
        control.allows(
          identityHash, group: names.group, repository: names.repository, permission: .read)
      else { return RNGitResponse(.notFound, "Not found") }
      return RNGitResponse(.disallowed, "Repository already exists")
    }

    return initialize(path, in: names.group, for: identityHash)
  }

  /// Makes a bare repository at `path` and registers it, clearing up after a step that fails.
  ///
  /// The `allowed` file sits beside the repository rather than inside it, so a failure after
  /// it is written leaves it where it is.
  private mutating func initialize(
    _ path: String, in group: String, for identityHash: Data
  ) -> RNGitResponse {
    guard
      (try? FileManager.default.createDirectory(
        atPath: path, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755])) != nil
    else { return RNGitResponse(.remoteFailure, "Remote error") }

    guard let initialized = runner.run("git", arguments: ["init", "--bare"], in: path) else {
      discard(path)
      return RNGitResponse(.remoteFailure, "Remote error")
    }
    guard initialized.status == 0 else {
      discard(path)
      return RNGitResponse(.remoteFailure, "Could not initialize repository")
    }

    guard place(RNGitPermissionSet.creationLine(for: identityHash), at: path + ".allowed") else {
      discard(path)
      return RNGitResponse(.remoteFailure, "Could not initialize repository")
    }

    do {
      guard try store.loadRepository(into: group, at: path) else {
        discard(path)
        return RNGitResponse(.remoteFailure, "Failed to register repository")
      }
    } catch {
      discard(path)
      return RNGitResponse(.remoteFailure, "Remote error")
    }
    return RNGitResponse(.ok)
  }

  /// Writes `text` into place at `path` through a neighbouring file, answering whether it
  /// landed.
  private func place(_ text: String, at path: String) -> Bool {
    let staged = path + ".tmp"
    guard (try? text.write(toFile: staged, atomically: false, encoding: .utf8)) != nil else {
      return false
    }
    try? FileManager.default.removeItem(atPath: path)
    return (try? FileManager.default.moveItem(atPath: staged, toPath: path)) != nil
  }

  /// Removes the directory at `path`, leaving whatever it cannot remove.
  private func discard(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
  }
}
