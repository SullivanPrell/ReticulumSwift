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

/// The node's answer to a peer removing one reference from a repository.
///
/// Python: `handle_delete` (`server.py:3102-3133`), which counts a removal the way it counts
/// a push.
public struct RNGitDeleteHandler {

  /// The groups the node serves, and what they grant.
  public var access: RNGitAccessControl

  /// Runs the `git` the removal is applied with.
  public var runner: RNGitCommandRunner

  /// The settings that say whether the node counts the removal.
  public var settings: RNGitNodeSettings

  /// The counters the node keeps.
  public var statistics: RNGitStatistics

  /// Creates a handler answering from `access`.
  public init(
    access: RNGitAccessControl, runner: RNGitCommandRunner,
    settings: RNGitNodeSettings = RNGitNodeSettings(),
    statistics: RNGitStatistics = RNGitStatistics()
  ) {
    self.access = access
    self.runner = runner
    self.settings = settings
    self.statistics = statistics
  }

  /// The answer a peer holding `identityHash` gets, or `nil` where it gets none.
  ///
  /// The reference is sanitised after the write gate and outside the `try` that covers the
  /// removal itself, so a request naming it with anything but a string sends nothing at all,
  /// while one from a peer without write access is refused before that can happen.
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

    let names = RNGitAccessControl.repositoryPath(requestedPath)
    guard access.allows(identityHash, names: names, permission: .write) else {
      guard access.allows(identityHash, names: names, permission: .read) else {
        return RNGitResponse(.notFound, "Not found")
      }
      return RNGitResponse(.disallowed, "Not allowed")
    }
    // Write access is granted only for a repository the node holds (`server.py:2314-2315`).
    guard let names, let path = access.groups[names.group]?.repositories[names.repository]?.path
    else { return RNGitResponse(.notFound, "Not found") }

    let reference = (fields["ref"] ?? .string("")).pythonReferenceName
    guard reference != .unusable else { return nil }
    guard case .valid(let name) = reference, name.hasPrefix("refs/") else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }

    guard let removed = runner.run("git", arguments: ["update-ref", "-d", name], in: path) else {
      return RNGitResponse(.remoteFailure, "Remote error")
    }
    guard removed.status == 0 else {
      return RNGitResponse(.remoteFailure, "Could not delete ref")
    }

    // Python: `push_succeeded` (`server.py:4774-4776`), which unlike its siblings does not
    // consult the identities statistics are ignored for.
    if settings.statsEnabled {
      statistics.recordPush(names.group, names.repository, on: RNGitStatsStore.day())
    }
    return RNGitResponse(.ok)
  }
}
