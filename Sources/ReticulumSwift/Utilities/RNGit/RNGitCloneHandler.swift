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

/// What a node makes of a repository it clones from elsewhere.
///
/// Any other value is refused.
public enum RNGitCloneKind: String, Sendable {

  /// A repository whose maintainer moves HEAD themselves.
  case fork

  /// A repository following the upstream's own default branch.
  case mirror
}

/// The node's answer to a peer asking it to clone a repository from elsewhere.
///
/// The only handler that reads the link a request arrived over. It builds the repository in a
/// directory belonging to that link, so a clone that fails leaves what it built until the link
/// closes.
public struct RNGitCloneHandler {

  /// The protocols a source may be named over.
  public static let protocols: Set<String> = ["rns", "http", "https", "ssh"]

  /// The groups the node serves, and the repositories it holds them in.
  public var store: RNGitRepositoryStore

  /// Identities the node refuses before resolving what a repository grants.
  public var blockedIdentities: Set<Data>

  /// The links the node is answering over.
  public var activeLinks: Set<Data>

  /// Runs the `git` the clone is made with.
  public var runner: RNGitCommandRunner

  /// Where the node builds a clone before it deploys it.
  public var temporaries: RNGitTemporaryDirectories

  /// Answers the moment a synchronization is recorded at.
  public var clock: @Sendable () -> Int

  /// Creates a handler registering into `store`.
  public init(
    store: RNGitRepositoryStore, runner: RNGitCommandRunner, activeLinks: Set<Data> = [],
    blockedIdentities: Set<Data> = [],
    temporaries: RNGitTemporaryDirectories = RNGitTemporaryDirectories(),
    clock: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }
  ) {
    self.store = store
    self.runner = runner
    self.activeLinks = activeLinks
    self.blockedIdentities = blockedIdentities
    self.temporaries = temporaries
    self.clock = clock
  }

  /// What the store grants, read the way the node's access control reads it.
  private var access: RNGitAccessControl {
    RNGitAccessControl(
      groups: store.groups, blockedIdentities: blockedIdentities,
      identityAliases: store.identityAliases)
  }

  /// The answer a peer holding `identityHash` gets, or `nil` where it gets none.
  public mutating func handle(
    _ request: MsgPack.Value, from identityHash: Data?, on link: Data?, as kind: RNGitCloneKind
  ) -> RNGitResponse? {
    guard let link, activeLinks.contains(link) else {
      return RNGitResponse(.disallowed, "Not identified")
    }
    guard let identityHash else { return RNGitResponse(.disallowed, "Not identified") }
    guard let fields = RNGitRequestFields(request) else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    guard let requested = fields[RNGitRequestKey.repository] else {
      return RNGitResponse(.invalidRequest, "No repository specified")
    }

    let given = fields["source"] ?? .string("")
    guard given.pythonIsTruthy else {
      return RNGitResponse(.invalidRequest, "No source specified")
    }
    guard case .string(let source) = given else {
      return RNGitResponse(.invalidRequest, "Invalid source URL")
    }
    let scheme = source.lowercased().components(separatedBy: "://")[0]
    guard Self.protocols.contains(scheme) else {
      return RNGitResponse(.disallowed, "Prohibited source URL")
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

    return clone(
      source, to: path, in: names.group, as: kind, on: link, for: identityHash)
  }

  /// Builds the clone in a directory belonging to `link` and moves it into the group.
  private mutating func clone(
    _ source: String, to path: String, in group: String, as kind: RNGitCloneKind,
    on link: Data, for identityHash: Data
  ) -> RNGitResponse {
    guard let root = temporaries.make(for: link) else { return abandon(path) }
    let staged = root + "/" + (path as NSString).lastPathComponent
    guard
      (try? FileManager.default.createDirectory(
        atPath: staged, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755])) != nil
    else { return abandon(path) }

    guard let initialized = runner.run("git", arguments: ["init", "--bare"], in: staged) else {
      return abandon(path)
    }
    guard initialized.status == 0 else {
      return RNGitResponse(.remoteFailure, "Failed to initialize repository")
    }

    guard
      let fetched = runner.run(
        "git", arguments: ["fetch", source, "+refs/*:refs/*"], in: staged)
    else { return abandon(path) }
    guard fetched.status == 0 else {
      return RNGitResponse(
        .remoteFailure, "Failed to fetch from source: " + fetched.standardError)
    }

    _ = RNGitWorkingCopy.updateHeadToSourceDefault(staged, from: source, runner: runner)

    guard
      let typed = runner.run(
        "git", arguments: ["config", "repository.rngit.type", kind.rawValue], in: staged)
    else { return abandon(path) }
    guard typed.status == 0 else {
      return RNGitResponse(
        .remoteFailure, "Failed to configure repository type: " + typed.standardError)
    }

    guard
      let sourced = runner.run(
        "git", arguments: ["config", "repository.rngit.upstream.source", source], in: staged)
    else { return abandon(path) }
    guard sourced.status == 0 else {
      return RNGitResponse(
        .remoteFailure,
        "Failed to configure repository upstream source: " + sourced.standardError)
    }

    // The moment is recorded through a routine that keeps its own result to itself, so the
    // message carries what the command before it said.
    guard RNGitWorkingCopy.setMirrorSynced(staged, at: clock(), runner: runner) else {
      return RNGitResponse(
        .remoteFailure, "Failed to configure repository type: " + sourced.standardError)
    }

    guard place(RNGitPermissionSet.creationLine(for: identityHash), at: path + ".allowed")
    else { return RNGitResponse(.remoteFailure, "Could not initialize repository") }

    guard (try? FileManager.default.moveItem(atPath: staged, toPath: path)) != nil else {
      return RNGitResponse(.remoteFailure, "Could not write repository")
    }

    do {
      guard try store.loadRepository(into: group, at: path) else {
        try? FileManager.default.removeItem(atPath: path)
        return RNGitResponse(.remoteFailure, "Failed to register repository")
      }
    } catch { return abandon(path) }
    return RNGitResponse(.ok)
  }

  /// Answers the failure given for anything unexpected, having removed what it had
  /// deployed.
  private func abandon(_ path: String) -> RNGitResponse {
    try? FileManager.default.removeItem(atPath: path)
    return RNGitResponse(.remoteFailure, "Remote error")
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
}
