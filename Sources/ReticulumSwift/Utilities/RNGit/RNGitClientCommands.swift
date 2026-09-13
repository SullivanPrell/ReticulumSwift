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

/// The commands an `rngit` client runs against a node.
///
/// Each command opens a link to the destination its remote URL names, sends one request over it,
/// and closes it again. A command that cannot go on throws an ``RNGitClientAbort`` carrying what
/// the client says.
public struct RNGitClientCommands {

  /// The destination hash each alias names.
  public var aliases: [String: String]

  /// How long the client waits for a path, where the stack asks for no longer.
  public var pathTimeout: TimeInterval

  /// How the client dates a release.
  public var rendering: RNGitReleaseRendering

  let transport: RNGitClientTransport
  let output: RNGitClientOutput
  let input: RNGitClientInput?
  let editor: RNGitClientEditor?

  /// Creates the commands, which run over `transport`, write to `output` and read from `input`.
  ///
  /// A client with no `input` reads every prompt as though the user had typed nothing more, and
  /// one with no `editor` has none to run and so says so at every edit.
  public init(
    aliases: [String: String] = [:], pathTimeout: TimeInterval = 15,
    rendering: RNGitReleaseRendering = RNGitReleaseRendering(),
    transport: RNGitClientTransport, output: RNGitClientOutput, input: RNGitClientInput? = nil,
    editor: RNGitClientEditor? = nil
  ) {
    self.aliases = aliases
    self.pathTimeout = pathTimeout
    self.rendering = rendering
    self.transport = transport
    self.output = output
    self.input = input
    self.editor = editor
  }

  /// Asks the node at `remote` to create the repository the URL names.
  public func createRepository(remote: String?) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    try connect(to: remote)
    output.write("\r                       \r")
    defer { transport.teardown() }

    let path = try repositoryPath(remote)
    let result = try requesting(.create, Self.fields(path), timeout: 120)
    switch Self.creating.reading(result) {
    case .done: output.write("Repository \(path) created\n")
    case .failed(let message): throw RNGitClientAbort(message)
    }
  }

  /// Asks the node at `target` to create the repository the URL names from the one at `source`.
  public func forkRepository(source: String?, target: String?) throws {
    guard let source, !source.isEmpty else { throw RNGitClientAbort("No source specified") }
    guard let target, !target.isEmpty else { throw RNGitClientAbort("No target specified") }
    try clone(source: source, target: target, sending: .fork, operation: "fork")
  }

  /// Asks the node at `target` to mirror the repository at `source` into the URL it names.
  public func mirrorRepository(source: String?, target: String?) throws {
    guard let source, !source.isEmpty else { throw RNGitClientAbort("No source specified") }
    guard let target, !target.isEmpty else { throw RNGitClientAbort("No target specified") }
    try clone(source: source, target: target, sending: .mirror, operation: "mirror")
  }

  /// Asks the node at `remote` to bring the repository the URL names up to its upstream.
  public func syncRepository(remote: String?) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    try connect(to: remote)
    output.write("\r                       \r")
    defer { transport.teardown() }

    let path = try repositoryPath(remote)
    output.write("Remote is syncing repository...\n")
    let result = try requesting(.sync, Self.fields(path), timeout: 7200)
    switch Self.cloning.reading(result) {
    case .done: output.write("Repository synced\n")
    case .failed(let message): throw RNGitClientAbort(message)
    }
  }

  /// How the client reads what creating a repository answers.
  private static let creating = RNGitResponseReading(
    named: [
      .disallowed: .sent(prefix: "", fallback: "Not allowed"),
      .invalidRequest: .text("Remote error: Invalid request"),
      .notFound: .text("Not found"),
    ],
    other: .sent(prefix: "Remote error: ", fallback: "Unknown error"))

  /// How the client reads what cloning and synchronizing a repository answer.
  private static let cloning = RNGitResponseReading(
    named: [
      .disallowed: .sent(prefix: "", fallback: "Not allowed"),
      .invalidRequest: .sent(prefix: "", fallback: "Invalid request"),
      .notFound: .sent(prefix: "", fallback: "Not found"),
    ],
    other: .sent(prefix: "Server error: ", fallback: "Unknown error"))

  /// How the client reads a code a node answers a management request with.
  static let remoteError = RNGitResponseReading(
    other: .sent(prefix: "Remote error: ", fallback: ""))

  /// How the client reads a code a node answers a listing with.
  static let serverError = RNGitResponseReading(
    other: .sent(prefix: "Server error: ", fallback: ""))

  /// The bytes `answer` carries, as an abort where it carries none.
  func answered(_ answer: RNGitClientAnswer) throws -> Data {
    switch answer {
    case .done(let body): return body
    case .failed(let message): throw RNGitClientAbort(message)
    }
  }

  /// Whether the user said yes to what was just asked.
  func agrees() -> Bool {
    let typed = input.flatMap { $0.readLine() } ?? "n"
    return typed.pythonStripped.lowercased() == "y"
  }

  /// What `path` answered, once the client has waited out the request.
  func requesting(_ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval) throws
    -> RNGitRequestResult
  {
    let result = transport.request(path, fields, timeout: timeout)
    if case .none = result { throw RNGitClientAbort(Self.noResult) }
    return result
  }

  /// What the client says where the request it sent brought nothing back at all.
  static let noResult = "Request failed or timed out"

  /// What the client says where it has no editor to run.
  static let noEditor = "No editor found. Please set $EDITOR environment variable.\n"

  /// What the user made of `template`, handed to them in a file named with `suffix`, or `nil`
  /// where they came back with nothing.
  func edited(_ template: String, suffix: String) -> String? {
    guard let editor else {
      output.write(Self.noEditor)
      return nil
    }

    let program = editor.editor()
    guard !program.isEmpty else {
      output.write(Self.noEditor)
      return nil
    }

    let path = NSTemporaryDirectory() + "/rngit-" + UUID().uuidString + suffix
    guard
      FileManager.default.createFile(
        atPath: path, contents: Data(template.utf8), attributes: [.posixPermissions: 0o600])
    else { return nil }

    let code = editor.run(program, over: path)
    guard code == 0 else {
      output.write("Editor exited with error code \(code)\n")
      try? FileManager.default.removeItem(atPath: path)
      return nil
    }

    let made = try? String(contentsOfFile: path, encoding: .utf8)
    try? FileManager.default.removeItem(atPath: path)
    return made
  }

  /// The fields a request naming `path`, and taking `source` where it has one, carries.
  private static func fields(_ path: String, source: String? = nil) -> MsgPack.Value {
    var entries: [(MsgPack.Value, MsgPack.Value)] = [
      (.uint(UInt64(RNGitRequestKey.repository)), .string(path))
    ]
    if let source { entries.append((.string("source"), .string(source))) }
    return .map(entries)
  }

  /// Asks the node at `target` to take the repository at `source` in, however `operation` says.
  private func clone(
    source: String, target: String, sending request: RNGitRequestPath, operation: String
  ) throws {
    let source = try resolvingAliases(in: source)
    try connect(to: target)
    output.write("\r                       \r")
    defer { transport.teardown() }

    let path = try repositoryPath(target)
    output.write("Remote is \(operation)ing repository to \(path)...\n")
    let result = try requesting(request, Self.fields(path, source: source), timeout: 7200)
    switch Self.cloning.reading(result) {
    case .done: output.write("Repository \(operation)ed to \(path)\n")
    case .failed(let message): throw RNGitClientAbort(message)
    }
  }

  /// Opens a link to the destination `remote` names, saying `failure` where none comes up.
  func connect(to remote: String, failure: String = "Link establishment failed") throws {
    let destination = try read { try RNGitRemoteURL.destination(remote, aliases: aliases) }

    output.write("Requesting path... ")
    let timeout = max(pathTimeout, transport.mediumPathTimeout())
    guard transport.awaitPath(to: destination, timeout: timeout) else {
      output.write("\n")
      throw RNGitClientAbort(
        "Could not resolve path to " + RNSUtilities.prettyhexrep(destination))
    }
    output.write("\rPath resolved      ")

    guard let identity = transport.recallIdentity(for: destination) else {
      throw RNGitClientAbort("Could not recall remote identity")
    }

    output.write("\rEstablishing link... ")
    guard transport.establishLink(to: identity) else { throw RNGitClientAbort(failure) }
    output.write("\rLink established     ")
  }

  /// The `group/repository` path `remote` names.
  func repositoryPath(_ remote: String) throws -> String {
    let named = try read { try RNGitRemoteURL.repository(remote, aliases: aliases) }
    return named.group + "/" + named.repository
  }

  /// `url` with the destination it names written out, where it is a remote URL.
  ///
  /// Anything else is left as it stands, so a path or a URL of another protocol reaches the node
  /// as the client was given it.
  private func resolvingAliases(in url: String) throws -> String {
    guard url.lowercased().hasPrefix(RNGitRemoteURL.protocolSpecifier) else { return url }
    let named = try read { try RNGitRemoteURL.repository(url, aliases: aliases) }
    guard !named.destination.isEmpty, !named.group.isEmpty, !named.repository.isEmpty else {
      throw RNGitClientAbort("Invalid source URL")
    }
    return RNGitRemoteURL.protocolSpecifier + named.destination.hexString + "/" + named.group + "/"
      + named.repository
  }

  /// What `reading` answered, as an abort where it refused the URL.
  func read<Named>(_ reading: () throws -> Named) throws -> Named {
    do {
      return try reading()
    } catch let error as RNGitRemoteURLError {
      throw RNGitClientAbort(error.message)
    }
  }
}
