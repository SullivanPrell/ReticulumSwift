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

/// The node's answer to a peer asking a fork or a mirror to catch up with its upstream.
///
/// Python: `handle_sync` (`server.py:3331-3360`), which gates read and write separately
/// rather than the way the push and delete handlers do.
public struct RNGitSyncHandler {

  /// The groups the node serves, and what they grant.
  public var access: RNGitAccessControl

  /// Runs the `git` the synchronization is done with.
  public var runner: RNGitCommandRunner

  /// Answers the moment the node records as the last synchronization.
  public var clock: @Sendable () -> Int

  /// Creates a handler answering from `access`.
  public init(
    access: RNGitAccessControl, runner: RNGitCommandRunner,
    clock: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }
  ) {
    self.access = access
    self.runner = runner
    self.clock = clock
  }

  /// The answer a peer holding `identityHash` gets, or `nil` where it gets none.
  ///
  /// A repository that is both a fork and a mirror is synchronized as a mirror.
  public func handle(
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

    let names = RNGitAccessControl.repositoryPath(requestedPath)
    guard access.allows(identityHash, names: names, permission: .read) else {
      return RNGitResponse(.notFound, "Not found")
    }
    guard access.allows(identityHash, names: names, permission: .write) else {
      return RNGitResponse(.disallowed, "Not allowed")
    }
    // Read access is granted only for a repository the node holds (`server.py:2314-2315`).
    guard let names, let repository = access.groups[names.group]?.repositories[names.repository]
    else { return RNGitResponse(.notFound, "Not found") }

    if let source = repository.mirror, !source.isEmpty {
      guard
        RNGitWorkingCopy.syncMirror(
          repository.path, from: source, runner: runner, now: clock)
      else { return RNGitResponse(.remoteFailure, "Mirror sync failed") }
      return RNGitResponse(.ok)
    }
    if let source = repository.fork, !source.isEmpty {
      guard
        RNGitWorkingCopy.syncFork(repository.path, from: source, runner: runner, now: clock)
      else { return RNGitResponse(.remoteFailure, "Fork sync failed") }
      return RNGitResponse(.ok)
    }
    return RNGitResponse(.invalidRequest, "Repository is neither fork nor mirror")
  }
}
