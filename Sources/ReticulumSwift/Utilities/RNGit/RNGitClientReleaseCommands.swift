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

extension RNGitClientCommands {

  /// Asks the node at `remote` for the releases the repository the URL names carries.
  public func listReleases(remote: String?) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    try connect(to: remote)
    defer { transport.teardown() }

    let path = try repositoryPath(remote)
    let result = try requesting(.release, Self.releaseFields(path, "list"), timeout: 120)
    output.write("\r                       \r")

    let body = try answered(Self.listed.reading(result))
    var value = MsgPack.Value.array([])
    if !body.isEmpty {
      guard let decoded = try? MsgPack.decode(body) else {
        throw RNGitClientAbort("Error listing releases: unreadable data")
      }
      value = decoded
    }
    guard let text = rendering.listing(value) else {
      throw RNGitClientAbort("Invalid release data format from remote")
    }
    output.write(text)
  }

  /// Asks the node at `remote` for the release `target` names.
  public func viewRelease(remote: String?, target: String?) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let target, !target.isEmpty else { throw RNGitClientAbort("No target specified") }
    try connect(to: remote)
    defer { transport.teardown() }

    let path = try repositoryPath(remote)
    let result = try requesting(
      .release, Self.releaseFields(path, "view", tag: target), timeout: 300)
    output.write("\r                       \r")

    let body = try answered(Self.viewed.reading(result))
    guard !body.isEmpty else { throw RNGitClientAbort("Empty response from remote") }
    guard let value = try? MsgPack.decode(body) else {
      throw RNGitClientAbort("Error viewing release: unreadable data")
    }
    output.write(rendering.view(value, target: target))
  }

  /// Asks the node at `remote` to take the release `target` names away, once the user agrees.
  public func deleteRelease(remote: String?, target: String?) throws {
    try changeRelease(
      remote: remote, target: target, operation: "delete",
      prompt: { "Are you sure you want to delete release \($0)? [y/N]: " },
      cancelled: "Deletion cancelled\n", done: { "Release \($0) deleted\n" })
  }

  /// Asks the node at `remote` to hold the release `target` names as its latest.
  public func latestRelease(remote: String?, target: String?) throws {
    try changeRelease(
      remote: remote, target: target, operation: "latest",
      prompt: { "Are you sure you want to set \($0) as the latest release? [y/N]: " },
      cancelled: "Update cancelled\n", done: { "Release \($0) set as latest\n" })
  }

  /// How the client reads what listing releases answers.
  private static let listed = RNGitResponseReading(
    other: .sent(prefix: "Server error: ", fallback: ""))

  /// How the client reads what one release, and changing one, answer.
  private static let viewed = RNGitResponseReading(
    other: .sent(prefix: "Remote error: ", fallback: ""))

  /// The fields a release request naming `path` and `tag` carries.
  private static func releaseFields(_ path: String, _ operation: String, tag: String? = nil)
    -> MsgPack.Value
  {
    var entries: [(MsgPack.Value, MsgPack.Value)] = [
      (.uint(UInt64(RNGitRequestKey.repository)), .string(path)),
      (.string("operation"), .string(operation)),
    ]
    if let tag { entries.append((.string("tag"), .string(tag))) }
    return .map(entries)
  }

  /// Asks the node at `remote` to change which release `target` names, once the user agrees.
  private func changeRelease(
    remote: String?, target: String?, operation: String, prompt: (String) -> String,
    cancelled: String, done: (String) -> String
  ) throws {
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let target, !target.isEmpty else { throw RNGitClientAbort("No target specified") }
    try connect(to: remote, failure: "Failed to establish link")
    output.write("\r                       \r")
    defer { transport.teardown() }

    let path = try repositoryPath(remote)
    output.write(prompt(target))
    guard agrees() else {
      output.write(cancelled)
      return
    }

    let result = try requesting(
      .release, Self.releaseFields(path, operation, tag: target), timeout: 120)
    _ = try answered(Self.viewed.reading(result))
    output.write(done(target))
  }

  /// The bytes `answer` carries, as an abort where it carries none.
  private func answered(_ answer: RNGitClientAnswer) throws -> Data {
    switch answer {
    case .done(let body): return body
    case .failed(let message): throw RNGitClientAbort(message)
    }
  }

  /// Whether the user said yes to what was just asked.
  private func agrees() -> Bool {
    let typed = input.flatMap { $0.readLine() } ?? "n"
    return typed.pythonStripped.lowercased() == "y"
  }
}
