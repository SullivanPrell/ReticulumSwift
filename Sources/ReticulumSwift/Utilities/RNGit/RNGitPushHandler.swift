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

/// The node's answer to a peer sending objects and the references they update.
///
/// Python: `handle_push` (`server.py:3005-3101`). A request carries either a bundle to
/// fetch from or a list of reference updates to apply, and the handler takes the first of
/// those it finds something in.
public struct RNGitPushHandler {

  /// The groups the node serves, and what they grant.
  public var access: RNGitAccessControl

  /// Runs the `git` the push is applied with.
  public var runner: RNGitCommandRunner

  /// The settings that say whether the node counts the push.
  public var settings: RNGitNodeSettings

  /// The counters the node keeps.
  public var statistics: RNGitStatistics

  /// Where the node puts the directory it holds the bundle in.
  public var temporaryRoot: String

  /// Creates a handler answering from `access`.
  public init(
    access: RNGitAccessControl, runner: RNGitCommandRunner,
    settings: RNGitNodeSettings = RNGitNodeSettings(),
    statistics: RNGitStatistics = RNGitStatistics(),
    temporaryRoot: String = NSTemporaryDirectory()
  ) {
    self.access = access
    self.runner = runner
    self.settings = settings
    self.statistics = statistics
    self.temporaryRoot = temporaryRoot
  }

  /// The answer a peer holding `identityHash` gets, or `nil` where it gets none.
  ///
  /// The two reference names are sanitised before the handler picks a branch, and outside
  /// the `try` that covers the rest, so a request naming either with anything but a string
  /// raises and sends nothing at all. The repository path is read the same way.
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

    let local = (fields["local_ref"] ?? .string("")).pythonReferenceName
    let remote = (fields["remote_ref"] ?? .string("")).pythonReferenceName
    guard local != .unusable, remote != .unusable else { return nil }
    let forced = fields["force"]?.pythonIsTruthy ?? false

    if let bundle = fields["bundle"], bundle.pythonIsTruthy {
      return apply(bundle, local, remote, forced: forced, at: path, of: names)
    }
    if let operations = fields["operations"], operations.pythonIsTruthy {
      return update(operations, at: path, of: names)
    }
    return RNGitResponse(.invalidRequest, "Invalid request data")
  }

  /// Fetches `local` out of `bundle` into `remote` at `path`.
  private mutating func apply(
    _ bundle: MsgPack.Value, _ local: RNGitReferenceName, _ remote: RNGitReferenceName,
    forced: Bool, at path: String, of names: (group: String, repository: String)
  ) -> RNGitResponse {
    guard case .valid(let localName) = local, case .valid(let remoteName) = remote else {
      return RNGitResponse(.invalidRequest, "Missing ref specification")
    }
    guard let directory = makeTemporaryDirectory() else { return Self.remoteFailure }
    defer { try? FileManager.default.removeItem(atPath: directory) }

    let bundlePath = directory + "/push.bundle"
    guard let payload = Self.buffer(bundle),
      (try? payload.write(to: URL(fileURLWithPath: bundlePath))) != nil
    else { return Self.remoteFailure }

    guard let verified = runner.run("git", arguments: ["bundle", "verify", bundlePath], in: path)
    else { return Self.remoteFailure }
    guard verified.status == 0 else {
      return RNGitResponse(.remoteFailure, "Could not verify bundle")
    }

    var arguments = ["fetch", bundlePath, localName + ":" + remoteName]
    if forced { arguments.append("--force") }
    guard let fetched = runner.run("git", arguments: arguments, in: path) else {
      return Self.remoteFailure
    }
    guard fetched.status == 0 else {
      return RNGitResponse(.remoteFailure, "Could not verify bundle")
    }

    pushSucceeded(names)
    return RNGitResponse(.ok)
  }

  /// Applies every reference update `operations` lists at `path`.
  private mutating func update(
    _ operations: MsgPack.Value, at path: String,
    of names: (group: String, repository: String)
  ) -> RNGitResponse {
    guard case .array(let updates) = operations else {
      return RNGitResponse(.invalidRequest, "Invalid data for operations")
    }
    for update in updates {
      guard let fields = RNGitRequestFields(update) else { return Self.remoteFailure }
      let action = fields["action"] ?? .string("")
      let reference = (fields["ref"] ?? .string("")).pythonReferenceName
      let object = (fields["sha"] ?? .string("")).pythonObjectID
      let forced = fields["force"]?.pythonIsTruthy ?? false
      guard reference != .unusable, object != .unmeasurable else { return Self.remoteFailure }

      guard action == .string("update_ref") else {
        return RNGitResponse(.invalidRequest, "Unknown operation: " + action.pythonDescription)
      }
      guard case .valid(let name) = reference, name.hasPrefix("refs/") else {
        return RNGitResponse(.invalidRequest, "Invalid request")
      }
      guard case .valid(let digest) = object else {
        return RNGitResponse(.invalidRequest, "Invalid SHA")
      }

      guard let held = runner.run("git", arguments: ["cat-file", "-t", digest], in: path) else {
        return Self.remoteFailure
      }
      guard held.status == 0 else {
        return RNGitResponse(.remoteFailure, "Object \(digest) does not exist in repository")
      }

      guard let existing = runner.run("git", arguments: ["rev-parse", name], in: path) else {
        return Self.remoteFailure
      }
      if existing.status == 0, existing.standardOutput.pythonStripped != digest, !forced {
        return RNGitResponse(
          .disallowed, "Ref \(name) already exists at different SHA (force required)")
      }

      guard let written = runner.run("git", arguments: ["update-ref", name, digest], in: path)
      else { return Self.remoteFailure }
      guard written.status == 0 else {
        return RNGitResponse(.remoteFailure, "Could not update refs")
      }
    }

    pushSucceeded(names)
    return RNGitResponse(.ok)
  }

  /// A fresh directory to hold the bundle, or `nil` where the node could not make one.
  private func makeTemporaryDirectory() -> String? {
    let directory = temporaryRoot + "/rngit-" + UUID().uuidString
    guard
      (try? FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true)) != nil
    else { return nil }
    return directory
  }

  /// The bytes `bundle` writes to a file, or `nil` where writing it raises.
  ///
  /// A string is encoded first; everything else has to carry a buffer of its own, which
  /// leaves only a byte string.
  private static func buffer(_ bundle: MsgPack.Value) -> Data? {
    switch bundle {
    case .string(let text): return Data(text.utf8)
    case .bytes(let data): return data
    case .nil, .bool, .int, .uint, .double, .array, .map: return nil
    }
  }

  /// The answer the reference gives for everything its handler raises on.
  private static let remoteFailure = RNGitResponse(.remoteFailure, "Remote error")

  /// Counts one push, unless the settings leave every push out.
  ///
  /// Python: `push_succeeded` (`server.py:4774-4776`), which unlike its siblings does not
  /// consult the identities statistics are ignored for.
  private mutating func pushSucceeded(_ names: (group: String, repository: String)) {
    guard settings.statsEnabled else { return }
    statistics.recordPush(names.group, names.repository, on: RNGitStatsStore.day())
  }
}
