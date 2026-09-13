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

/// The node's answer to a request for a bundle of the objects a peer is missing.
///
/// Python: `handle_fetch` (`server.py:2930-3003`).
public struct RNGitFetchHandler {

  /// The groups the node serves, and what they grant.
  public var access: RNGitAccessControl

  /// Runs the `git` the bundle is built with.
  public var runner: RNGitCommandRunner

  /// The settings that say whether the node counts the fetch.
  public var settings: RNGitNodeSettings

  /// The counters the node keeps.
  public var statistics: RNGitStatistics

  /// The links the node has open, by link identifier.
  public var activeLinks: Set<Data>

  /// Where the node puts the directories it holds a bundle in.
  public var temporaryRoot: String

  /// Creates a handler answering from `access`.
  public init(
    access: RNGitAccessControl, runner: RNGitCommandRunner,
    settings: RNGitNodeSettings = RNGitNodeSettings(),
    statistics: RNGitStatistics = RNGitStatistics(), activeLinks: Set<Data> = [],
    temporaryRoot: String = NSTemporaryDirectory()
  ) {
    self.access = access
    self.runner = runner
    self.settings = settings
    self.statistics = statistics
    self.activeLinks = activeLinks
    self.temporaryRoot = temporaryRoot
  }

  /// The answer a peer holding `identityHash` gets on `link`, or `nil` where it gets none.
  ///
  /// A request naming its repository with anything but a string leaves the reference raising
  /// before it reaches a handler of its own, which sends nothing at all.
  public mutating func handle(
    _ request: MsgPack.Value, from identityHash: Data?, on link: Data?
  ) -> RNGitAnswer? {
    guard let link, activeLinks.contains(link) else {
      return .response(RNGitResponse(.disallowed, "Not identified"))
    }
    guard identityHash != nil else {
      return .response(RNGitResponse(.disallowed, "Not identified"))
    }
    guard let fields = RNGitRequestFields(request) else {
      return .response(RNGitResponse(.invalidRequest, "Invalid request"))
    }
    guard let requested = fields[RNGitRequestKey.repository] else {
      return .response(RNGitResponse(.invalidRequest, "No repository specified"))
    }
    guard let identityHash, let requestedPath = requested.asString else { return nil }

    let names = RNGitAccessControl.repositoryPath(requestedPath)
    guard access.allows(identityHash, names: names, permission: .read) else {
      return .response(RNGitResponse(.notFound, "Not found"))
    }
    guard let names, let path = access.groups[names.group]?.repositories[names.repository]?.path
    else { return .response(RNGitResponse(.notFound, "Not found")) }

    let refs = fields["refs"] ?? .array([])
    guard refs.pythonIsTruthy else {
      return .response(RNGitResponse(.invalidRequest, "No refs specified"))
    }
    return bundle(refs, fields["have"], at: path, of: names, for: identityHash)
  }

  /// A bundle of what `refs` name at `path`, less what the peer says it holds.
  private mutating func bundle(
    _ refs: MsgPack.Value, _ have: MsgPack.Value?, at path: String,
    of names: (group: String, repository: String), for identityHash: Data
  ) -> RNGitAnswer? {
    guard let entries = refs.pythonIterated else { return Self.remoteFailure }
    var requested: [String] = []
    for entry in entries {
      guard let name = RNGitRequestFields(entry)?["ref"]?.asString else {
        return Self.remoteFailure
      }
      requested.append(name)
    }
    guard GitReferenceNames.sanitise(requested) != nil, !requested.isEmpty else {
      return .response(RNGitResponse(.invalidRequest, "Invalid request"))
    }

    let directory = temporaryRoot + "/rngit-" + UUID().uuidString
    guard
      (try? FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true)) != nil
    else { return Self.remoteFailure }
    let bundlePath = directory + "/fetch.bundle"

    var arguments = ["bundle", "create", "--no-progress", bundlePath]
    for entry in entries {
      let fields = RNGitRequestFields(entry)
      guard let name = fields?["ref"]?.asString, GitReferenceNames.sanitise(name) != nil else {
        return .response(RNGitResponse(.invalidRequest, "Invalid request"))
      }
      arguments.append(name)
      guard let held = fields?["have"], held.pythonIsTruthy else { continue }
      let excluded = exclusion(held, at: path)
      if let refusal = excluded.answer { return refusal }
      arguments.append(contentsOf: excluded.arguments)
    }

    guard let held = (have ?? .array([])).pythonIterated else { return Self.remoteFailure }
    for entry in held {
      let excluded = exclusion(entry, at: path)
      if let refusal = excluded.answer { return refusal }
      arguments.append(contentsOf: excluded.arguments)
    }

    guard let result = runner.run("git", arguments: arguments, in: path) else {
      return Self.remoteFailure
    }
    guard result.status == 0 else {
      guard result.standardError.lowercased().contains("empty bundle") else {
        return .response(RNGitResponse(.remoteFailure, "Could not fetch refs"))
      }
      return .response(RNGitResponse(.ok))
    }

    guard FileManager.default.fileExists(atPath: bundlePath) else { return Self.remoteFailure }
    fetchSucceeded(names, for: identityHash)
    return .file(RNGitFile(path: bundlePath, directory: directory))
  }

  /// What `held` adds to the bundle arguments, or the answer it earns instead.
  ///
  /// An object the repository does not hold is passed over with a warning, so it adds
  /// nothing and earns no answer.
  private func exclusion(_ held: MsgPack.Value, at path: String)
    -> (arguments: [String], answer: RNGitAnswer?)
  {
    switch held.pythonObjectID {
    case .refused: return ([], .response(RNGitResponse(.invalidRequest, "Invalid SHA")))
    case .unmeasurable: return ([], Self.remoteFailure)
    case .valid(let digest):
      guard let result = runner.run("git", arguments: ["cat-file", "-t", digest], in: path)
      else { return ([], Self.remoteFailure) }
      return (result.status == 0 ? ["^" + digest] : [], nil)
    }
  }

  /// The answer the reference gives for everything its handler raises on.
  private static let remoteFailure = RNGitAnswer.response(
    RNGitResponse(.remoteFailure, "Remote error"))

  /// Counts one fetch, unless the settings leave this peer or every fetch out.
  ///
  /// Python: `fetch_succeeded` (`server.py:4769-4772`).
  private mutating func fetchSucceeded(
    _ names: (group: String, repository: String), for identityHash: Data
  ) {
    guard !settings.statsIgnored.contains(identityHash), settings.statsEnabled else { return }
    statistics.recordFetch(names.group, names.repository, on: RNGitStatsStore.day())
  }
}
