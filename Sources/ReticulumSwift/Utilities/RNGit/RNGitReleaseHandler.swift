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

/// The node's answer to a peer working on the releases a repository carries.
///
/// Three operations need only read access, and three need the release permission as well. A
/// release is built in three steps, and only a draft is still writable.
public struct RNGitReleaseHandler {

  /// The operations a peer with read access may ask for.
  static let reading: Set<String> = ["list", "view", "fetch"]

  /// The operations a peer needs the release permission for.
  static let managing: Set<String> = ["create", "delete", "latest"]

  /// The groups the node serves, and what they grant.
  public var access: RNGitAccessControl

  /// Runs the `git` a tag is verified with.
  public var runner: RNGitCommandRunner

  /// Answers the moment a release records.
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
  public func handle(_ request: MsgPack.Value, from identityHash: Data?) -> RNGitAnswer? {
    guard let identityHash else { return Self.refused(.disallowed, "Not identified") }
    guard let fields = RNGitRequestFields(request) else {
      return Self.refused(.invalidRequest, "Invalid request")
    }
    guard let requested = fields[RNGitRequestKey.repository] else {
      return Self.refused(.invalidRequest, "No repository specified")
    }
    let operation = fields["operation"] ?? .nil
    guard operation.pythonIsTruthy else {
      return Self.refused(.invalidRequest, "Invalid request")
    }

    guard let requestedPath = requested.asString else { return nil }
    let names = RNGitAccessControl.repositoryPath(requestedPath)
    let readable = access.allows(identityHash, names: names, permission: .read)
    let releasable = access.allows(identityHash, names: names, permission: .release)
    guard readable else { return Self.refused(.notFound, "Not found") }

    let name = operation.asString ?? ""
    let allowed = (Self.managing.contains(name) && releasable) || Self.reading.contains(name)
    guard allowed else { return Self.refused(.disallowed, "Not allowed") }

    // Read access is granted only for a repository the node holds.
    guard let names, let path = access.groups[names.group]?.repositories[names.repository]?.path
    else { return Self.refused(.notFound, "Not found") }
    let releases = RNGitReleaseStore.directory(forRepository: path)

    switch name {
    case "list": return list(releases)
    case "view": return view(releases, fields)
    case "fetch": return fetch(releases, fields)
    case "create": return create(releases, repository: path, fields, for: identityHash)
    case "delete": return remove(releases, fields)
    case "latest": return promote(releases, fields)
    default: return Self.refused(.invalidRequest, "Invalid request")
    }
  }

  /// Everything the repository has released.
  private func list(_ releases: String) -> RNGitAnswer {
    guard RNGitReleaseStore.isDirectory(releases) else {
      return .response(RNGitResponse(.ok, MsgPack.encode(.array([]))))
    }
    guard let listed = RNGitReleaseStore.listing(releases) else {
      return Self.refused(.remoteFailure, "Error listing releases")
    }
    return .response(
      RNGitResponse(
        .ok,
        MsgPack.encode(
          .map([
            (.string("releases"), .array(listed.releases)),
            (.string("latest"), listed.latest.map { MsgPack.Value.string($0) } ?? .nil),
          ]))))
  }

  /// Everything one release carries.
  private func view(_ releases: String, _ fields: RNGitRequestFields) -> RNGitAnswer {
    switch Self.read(
      fields["tag"] ?? .string(""), slashFirst: true, empty: "Invalid tag specified",
      slashed: "Invalid tag specified")
    {
    case .refused(let answer): return answer
    case .named(let named):
      guard let resolved = Self.resolve(Self.basename(named), under: releases) else {
        return Self.refused(.notFound, "No latest release found")
      }
      let directory = Self.joined(releases, resolved)
      guard RNGitReleaseStore.isDirectory(directory) else {
        return Self.refused(.notFound, "Release not found")
      }
      guard let details = RNGitReleaseStore.details(directory, tag: resolved) else {
        return Self.refused(.remoteFailure, "Error getting release data")
      }
      return .response(RNGitResponse(.ok, MsgPack.encode(details)))
    }
  }

  /// One artifact of one release, answered as the file it is.
  private func fetch(_ releases: String, _ fields: RNGitRequestFields) -> RNGitAnswer {
    let tag: String
    switch Self.read(
      fields["tag"] ?? .string(""), slashFirst: true, empty: "Invalid tag specified",
      slashed: "Invalid tag specified")
    {
    case .refused(let answer): return answer
    case .named(let named): tag = Self.basename(named)
    }

    let artifact: String
    switch Self.read(
      fields["artifact"] ?? .string(""), slashFirst: true, empty: "Invalid artifact specified",
      slashed: "Invalid artifact specified")
    {
    case .refused(let answer): return answer
    case .named(let named): artifact = Self.basename(named)
    }

    guard let resolved = Self.resolve(tag, under: releases) else {
      return Self.refused(.notFound, "No latest release found")
    }
    let directory = Self.joined(releases, resolved)
    guard RNGitReleaseStore.isDirectory(directory) else {
      return Self.refused(.notFound, "Release not found")
    }

    let path = Self.joined(Self.joined(directory, "artifacts"), artifact)
    guard FileManager.default.fileExists(atPath: path), !RNGitReleaseStore.isDirectory(path)
    else { return Self.refused(.notFound, "Artifact not found") }
    return .file(RNGitFile(path: path, metadata: .name(artifact)))
  }

  /// One step of building a release.
  private func create(
    _ releases: String, repository: String, _ fields: RNGitRequestFields, for identityHash: Data
  ) -> RNGitAnswer {
    let step = fields["step"] ?? .nil
    guard step.pythonIsTruthy else { return Self.refused(.invalidRequest, "Invalid request") }
    switch step.asString ?? "" {
    case "init": return initialize(releases, repository: repository, fields, for: identityHash)
    case "artifact": return store(releases, fields)
    case "finalize": return publish(releases, fields)
    default: return Self.refused(.invalidRequest, "Invalid request")
    }
  }

  /// The first step, which records a draft for a tag the repository holds.
  private func initialize(
    _ releases: String, repository: String, _ fields: RNGitRequestFields, for identityHash: Data
  ) -> RNGitAnswer {
    let tag: String
    switch Self.read(
      fields["tag"] ?? .string(""), slashFirst: false, empty: "Invalid tag specified",
      slashed: "Invalid tag specified")
    {
    case .refused(let answer): return answer
    case .named(let named): tag = Self.basename(named)
    }
    guard !tag.isEmpty, tag != ".", tag != ".." else {
      return Self.refused(.invalidRequest, "Invalid tag name")
    }

    guard
      let verified = runner.run(
        "git", arguments: ["rev-parse", "--verify", "refs/tags/" + tag], in: repository)
    else { return Self.remoteFailure }
    guard verified.status == 0 else {
      return Self.refused(.invalidRequest, "Tag '" + tag + "' does not exist in repository")
    }

    if !RNGitReleaseStore.isDirectory(releases) {
      guard Self.makeDirectory(releases) else { return Self.remoteFailure }
    }
    let directory = Self.joined(releases, tag)
    guard !RNGitReleaseStore.isDirectory(directory) else {
      return Self.refused(.disallowed, "Release already exists")
    }
    guard Self.makeDirectory(directory), Self.makeDirectory(directory + "/artifacts") else {
      return Self.remoteFailure
    }

    var meta = RNGitConfigSection()
    meta.set("tag", .scalar(tag))
    let hash = fields["hash"] ?? .nil
    if hash.pythonIsTruthy { meta.set("hash", .scalar(hash.pythonDescription)) }
    meta.set("created", .scalar(String(clock())))
    meta.set("status", .scalar("draft"))
    meta.set("created_by", .scalar(identityHash.map { String(format: "%02x", $0) }.joined()))
    guard let written = RNGitConfigFile.encode(meta),
      Self.place(Data(written.utf8), at: directory + "/META")
    else { return Self.remoteFailure }

    let notes = fields["notes"] ?? .string("")
    if notes.pythonIsTruthy {
      let format = (fields["notes_format"] ?? .string("markdown")).asString
      let name = format == "micron" ? "RELEASE.mu" : "RELEASE.md"
      guard let text = notes.asString else {
        _ = Self.place(Data(), at: directory + "/" + name)
        return Self.remoteFailure
      }
      guard Self.place(Data(text.utf8), at: directory + "/" + name) else {
        return Self.remoteFailure
      }
    }

    guard
      Self.place(
        MsgPack.encode(.map([(.string("count"), .uint(0))])), at: directory + "/THANKS")
    else { return Self.remoteFailure }
    return .response(RNGitResponse(.ok))
  }

  /// The second step, which stores one artifact in a draft.
  private func store(_ releases: String, _ fields: RNGitRequestFields) -> RNGitAnswer {
    let requested = fields["tag"] ?? .string("")
    let named = fields["artifact_name"] ?? .nil
    guard requested.pythonIsTruthy, named.pythonIsTruthy else {
      return Self.refused(.invalidRequest, "Missing tag or artifact name")
    }
    switch Self.contains(requested, "/") {
    case nil: return Self.remoteFailure
    case .some(true): return Self.refused(.invalidRequest, "Invalid tag specified")
    case .some(false): break
    }
    let content = fields["artifact_data"] ?? .nil
    if case .nil = content { return Self.refused(.invalidRequest, "No artifact data") }

    // Both names are shortened before the release is looked for, so a name that cannot be
    // shortened ends the request whether or not the release is there.
    guard let tag = requested.asString else { return Self.remoteFailure }
    switch named {
    case .string, .bytes: break
    default: return Self.remoteFailure
    }

    let directory = Self.joined(releases, Self.basename(tag))
    guard RNGitReleaseStore.isDirectory(directory) else {
      return Self.refused(.notFound, "Release not found")
    }
    guard let meta = RNGitReleaseStore.metadata(at: directory + "/META") else {
      return Self.remoteFailure
    }
    guard meta.string("status") == "draft" else {
      return Self.refused(.disallowed, "Release was finalized and is not writable")
    }

    // The place the artifact takes is named before the directory holding it is made.
    let artifacts = directory + "/artifacts"
    guard case .string(let name) = named else { return Self.remoteFailure }
    let path = Self.joined(artifacts, Self.basename(name))
    if !RNGitReleaseStore.isDirectory(artifacts) {
      guard Self.makeDirectory(artifacts) else { return Self.remoteFailure }
    }

    var bytes = Data()
    switch content {
    case .string(let text): bytes = Data(text.utf8)
    case .bytes(let data): bytes = data
    default:
      _ = Self.place(Data(), at: path)
      return Self.remoteFailure
    }
    guard Self.place(bytes, at: path) else { return Self.remoteFailure }
    return .response(RNGitResponse(.ok))
  }

  /// The third step, which publishes a draft and makes it the latest release.
  private func publish(_ releases: String, _ fields: RNGitRequestFields) -> RNGitAnswer {
    let tag: String
    switch Self.read(
      fields["tag"] ?? .string(""), slashFirst: false, empty: "No tag specified",
      slashed: "Invalid tag specified")
    {
    case .refused(let answer): return answer
    case .named(let named): tag = Self.basename(named)
    }

    let directory = Self.joined(releases, tag)
    guard RNGitReleaseStore.isDirectory(directory) else {
      return Self.refused(.notFound, "Release not found")
    }
    guard var meta = RNGitReleaseStore.metadata(at: directory + "/META") else {
      return Self.remoteFailure
    }
    guard meta.string("status") == "draft" else {
      return Self.refused(.disallowed, "Release was finalized and is not writable")
    }
    meta.set("status", .scalar("published"))
    meta.set("published_at", .scalar(String(clock())))
    guard let written = RNGitConfigFile.encode(meta),
      Self.place(Data(written.utf8), at: directory + "/META")
    else { return Self.remoteFailure }

    // The moment the latest release is recorded is one the answer does not report on.
    _ = Self.point(releases, at: tag)
    return .response(RNGitResponse(.ok))
  }

  /// Removes one release, whatever it was.
  private func remove(_ releases: String, _ fields: RNGitRequestFields) -> RNGitAnswer {
    let tag: String
    switch Self.read(
      fields["tag"] ?? .string(""), slashFirst: false, empty: "No tag specified",
      slashed: "Invalid tag specified")
    {
    case .refused(let answer): return answer
    case .named(let named): tag = Self.basename(named)
    }
    let directory = Self.joined(releases, tag)
    guard RNGitReleaseStore.isDirectory(directory) else {
      return Self.refused(.notFound, "Release not found")
    }
    guard (try? FileManager.default.removeItem(atPath: directory)) != nil else {
      return Self.remoteFailure
    }
    return .response(RNGitResponse(.ok))
  }

  /// Makes one release the latest, whether or not it was published.
  private func promote(_ releases: String, _ fields: RNGitRequestFields) -> RNGitAnswer {
    let tag: String
    switch Self.read(
      fields["tag"] ?? .string(""), slashFirst: false, empty: "No tag specified",
      slashed: "Invalid tag specified")
    {
    case .refused(let answer): return answer
    case .named(let named): tag = Self.basename(named)
    }
    guard RNGitReleaseStore.isDirectory(Self.joined(releases, tag)) else {
      return Self.refused(.notFound, "Release not found")
    }
    guard Self.point(releases, at: tag) else { return Self.remoteFailure }
    return .response(RNGitResponse(.ok))
  }

  /// What a request names as the thing to work on.
  private enum Name {

    /// The tag the request named.
    case named(String)

    /// The answer the request gets instead.
    case refused(RNGitAnswer)

  }

  /// The name `value` carries, refused where it holds a path separator or nothing.
  ///
  /// The two tests run in the order the operation runs them, which decides what a value that is
  /// falsy and cannot be looked through is answered with.
  private static func read(
    _ value: MsgPack.Value, slashFirst: Bool, empty: String, slashed: String
  ) -> Name {
    if !slashFirst, !value.pythonIsTruthy { return .refused(refused(.invalidRequest, empty)) }
    switch contains(value, "/") {
    case nil: return .refused(remoteFailure)
    case .some(true): return .refused(refused(.invalidRequest, slashed))
    case .some(false): break
    }
    if slashFirst, !value.pythonIsTruthy { return .refused(refused(.invalidRequest, empty)) }
    guard let text = value.asString else { return .refused(remoteFailure) }
    return .named(text)
  }

  /// The tag a request for the latest release resolves to, or `nil` where there is none.
  private static func resolve(_ tag: String, under releases: String) -> String? {
    guard tag == "latest" else { return tag }
    guard let named = RNGitReleaseStore.latestTag(under: releases), !named.isEmpty else {
      return nil
    }
    return named
  }

  /// Records `tag` as the latest release under `releases`, answering whether it landed.
  private static func point(_ releases: String, at tag: String) -> Bool {
    let staged = releases + "/latest.tmp"
    guard place(Data(tag.utf8), at: staged) else { return false }
    try? FileManager.default.removeItem(atPath: releases + "/latest")
    return (try? FileManager.default.moveItem(atPath: staged, toPath: releases + "/latest"))
      != nil
  }

  /// Writes `bytes` at `path`, answering whether they landed.
  private static func place(_ bytes: Data, at path: String) -> Bool {
    FileManager.default.createFile(atPath: path, contents: bytes)
  }

  /// Makes the directory at `path`, answering whether it landed.
  private static func makeDirectory(_ path: String) -> Bool {
    (try? FileManager.default.createDirectory(
      atPath: path, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o755])) != nil
  }

  /// Whether `value` holds `needle`, or `nil` where it cannot be looked through.
  private static func contains(_ value: MsgPack.Value, _ needle: String) -> Bool? {
    switch value {
    case .string(let text): return text.contains(needle)
    case .array(let items): return items.contains(.string(needle))
    case .map(let fields): return fields.contains { $0.0 == .string(needle) }
    default: return nil
    }
  }

  /// The last component of `path`, which is everything after its last separator.
  private static func basename(_ path: String) -> String {
    guard let separator = path.lastIndex(of: "/") else { return path }
    return String(path[path.index(after: separator)...])
  }

  /// `path` joined to `component`, which replaces it where it opens with a separator.
  private static func joined(_ path: String, _ component: String) -> String {
    if component.hasPrefix("/") { return component }
    if path.isEmpty || path.hasSuffix("/") { return path + component }
    return path + "/" + component
  }

  /// The answer a refusal carries.
  private static func refused(_ code: RNGitResponseCode, _ message: String) -> RNGitAnswer {
    .response(RNGitResponse(code, message))
  }

  /// The answer anything unexpected gets.
  private static let remoteFailure = RNGitAnswer.response(
    RNGitResponse(.remoteFailure, "Remote error"))
}
