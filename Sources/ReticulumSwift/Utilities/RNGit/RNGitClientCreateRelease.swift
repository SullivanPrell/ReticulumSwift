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

  /// What the client offers the user to write release notes over.
  public static let releaseNotesTemplate =
    "# Enter release notes for {TAG}.\n"
    + "# Lines starting with '#' will be ignored.\n"
    + "# Save and exit the editor when done, or exit without saving to abort.\n"

  /// Signs everything in the directory `target` names and publishes it under the tag it names.
  ///
  /// `target` is a tag and an artifacts directory, written `1.0.0:./dist`. Every file in the
  /// directory is signed, a manifest carrying the release notes is written alongside them, and
  /// all of it goes to the node in one init, one request per artifact, and one finalize.
  public func createRelease(
    remote: String?, target: String?, signer: String? = nil, name: String? = nil,
    noUpload: Bool = false
  ) throws {
    let signing = try signerIdentity(signer)
    guard let remote, !remote.isEmpty else { throw RNGitClientAbort("No remote specified") }
    guard let target, !target.isEmpty else { throw RNGitClientAbort("No target specified") }
    guard let signing = signing ?? identity else {
      throw RNGitClientAbort("Error creating release: no identity to sign with")
    }
    var linked = false
    defer { if linked { transport.teardown() } }

    let named = try read { try RNGitRemoteURL.repository(remote, aliases: aliases) }
    let path = named.group + "/" + named.repository
    let when = Int(now().timeIntervalSince1970)

    let parts = target.components(separatedBy: ":")
    guard parts.count >= 2 else {
      throw RNGitClientAbort(
        "Invalid release specification\nDid you provide both a tag and artifacts path such as "
          + "\"1.0.0:./dist\"?")
    }
    let tag = parts[0]
    let directory = DaemonBootstrap.expandTilde(parts[1])
    let commit = commitHash(forTag: tag)
    if commit == nil {
      output.write(
        "Could not get commit hash for tag \(tag). Does the tag exist in the local repository?\n")
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw RNGitClientAbort("Specified artifacts directory does not exist") }

    var artifacts = try files(in: directory)
    guard !artifacts.isEmpty else {
      throw RNGitClientAbort("No files found in specified artifact directory")
    }

    output.write("Creating release \(tag)\n")
    guard let notes = releaseNotes(tag: tag) else {
      output.write("Release creation cancelled\n")
      return
    }

    let package = (name?.isEmpty == false ? name : nil) ?? named.repository
    artifacts = try signed(
      artifacts, in: directory, with: signing, notes: notes, at: when,
      meta: manifest(
        package: package, tag: tag, when: when, origin: named.destination, path: path,
        commit: commit))

    guard !noUpload else {
      output.write("Local release \(package):\(tag) generated successfully in \(target)\n")
      return
    }

    try connect(to: remote, failure: "Failed to establish link", opened: { linked = true })
    output.write("\r                       \r")

    output.write("Initializing release on remote...\n")
    let initialized = try requesting(
      .release,
      Self.createFields(
        path, tag: tag,
        extra: [
          ("hash", commit.map { .string($0) } ?? .nil), ("notes", .string(notes)),
          ("notes_format", .string("markdown")),
        ],
        step: "init"), timeout: 120)
    _ = try answered(Self.initializing.reading(initialized))
    output.write("Release initialized\n")

    output.write("\nSending \(artifacts.count) artifact\(artifacts.count == 1 ? "" : "s")...\n")
    for artifact in artifacts {
      let bytes =
        (try? Data(contentsOf: URL(fileURLWithPath: Self.joined(directory, artifact))))
        ?? Data()
      let result = try requesting(
        .release,
        Self.createFields(
          path, tag: tag,
          extra: [("artifact_name", .string(artifact)), ("artifact_data", .bytes(bytes))],
          step: "artifact"), timeout: 7200)
      switch Self.sending.reading(result) {
      case .done:
        output.write(
          "  \(artifact) (\(RNSUtilities.prettysize(bytes.count))) transferred"
            + String(repeating: " ", count: 33) + "\n")
      case .failed(let message): output.write("  Failed to send \(artifact): \(message)\n")
      }
    }

    output.write("\nFinalizing release...\n")
    let finalized = try requesting(
      .release, Self.createFields(path, tag: tag, extra: [], step: "finalize"), timeout: 300)
    _ = try answered(Self.finalizing.reading(finalized))
    output.write("Release \(tag) published\n")
  }

  /// The commit `tag` names in the repository at `directory`, or `nil` where it names none.
  public func commitHash(forTag tag: String, in directory: String = "./") -> String? {
    guard gitIsThere else { return nil }
    guard let result = runner?.run("git", arguments: ["rev-list", "-n", "1", tag], in: directory),
      result.status == 0
    else { return nil }
    let hash = result.standardOutput.pythonStripped
    return hash.isEmpty ? nil : hash
  }

  /// Whether there is a `git` to run.
  public var gitIsThere: Bool {
    runner?.run("git", arguments: ["--version"], in: nil)?.status == 0
  }

  /// What the user wrote for `tag`, with every commented line taken out, or `nil` where they
  /// wrote nothing that was not a comment.
  public func releaseNotes(tag: String = "this release") -> String? {
    let template = Self.releaseNotesTemplate.replacingOccurrences(of: "{TAG}", with: tag)
    guard let written = edited(template, suffix: ".md") else { return nil }
    let kept = written.components(separatedBy: "\n").filter {
      !$0.pythonStripped.hasPrefix("#")
    }
    let notes = kept.joined(separator: "\n").pythonStripped
    return notes.isEmpty ? nil : notes
  }

  /// How the client reads what initializing a release answers.
  private static let initializing = RNGitResponseReading(
    other: .sent(prefix: "Server error during init: ", fallback: ""))

  /// How the client reads what finalizing a release answers.
  private static let finalizing = RNGitResponseReading(
    other: .sent(prefix: "Server error during finalize: ", fallback: ""))

  /// How the client reads what sending one artifact answers.
  private static let sending = RNGitResponseReading(other: .sent(prefix: "", fallback: ""))

  /// The identity at `path`, or `nil` where the command was given no signer.
  private func signerIdentity(_ path: String?) throws -> Identity? {
    guard let path, !path.isEmpty else { return nil }
    let expanded = DaemonBootstrap.expandTilde(path)
    guard FileManager.default.fileExists(atPath: expanded) else {
      throw RNGitClientAbort("Signer identity \(expanded) does not exist")
    }
    guard let loaded = Identity.fromFile(URL(fileURLWithPath: path)) else {
      throw RNGitClientAbort("Could not load signer identity from \(expanded)")
    }
    return loaded
  }

  /// `directory` and `name` joined the way the reference joins a path, which leaves the
  /// separator alone where the directory already ends in one.
  private static func joined(_ directory: String, _ name: String) -> String {
    directory.hasSuffix("/") ? directory + name : directory + "/" + name
  }

  /// The names of the files that lie directly in `directory`.
  private func files(in directory: String) throws -> [String] {
    let manager = FileManager.default
    guard let named = try? manager.contentsOfDirectory(atPath: directory) else {
      throw RNGitClientAbort("Error creating release: could not read the artifacts directory")
    }
    return named.sorted().filter { name in
      var isDirectory: ObjCBool = false
      let exists = manager.fileExists(
        atPath: Self.joined(directory, name), isDirectory: &isDirectory)
      return exists && !isDirectory.boolValue
    }
  }

  /// The manifest metadata a release carries, but for the artifacts it names.
  private func manifest(
    package: String, tag: String, when: Int, origin: Data, path: String, commit: String?
  ) -> [(String, MsgPack.Value)] {
    [
      ("name", .string(package)), ("version", .string(tag)),
      ("released", .string(rendering.stamped(when))), ("timestamp", .uint(UInt64(when))),
      ("origin", .bytes(origin)), ("path", .string(path)),
      ("commit", commit.map { .string($0) } ?? .nil),
    ]
  }

  /// Signs each of `artifacts`, writes the manifest alongside them, and answers everything the
  /// client is to send.
  private func signed(
    _ artifacts: [String], in directory: String, with signer: Identity, notes: String, at when: Int,
    meta: [(String, MsgPack.Value)]
  ) throws -> [String] {
    var meta = meta
    var entries: [MsgPack.Value] = []
    var signatures: [String] = []
    var sent = artifacts

    do {
      for artifact in artifacts {
        if artifact.hasSuffix("." + Self.signatureExtension) { continue }
        if artifact.hasSuffix("." + Self.messageExtension) { continue }
        let file = Self.joined(directory, artifact)
        output.write("Signing \(file) with <\(signer.hash.hexString)>\n")
        let body = try Data(contentsOf: URL(fileURLWithPath: file))
        let signed = try RSG.create(
          signer: signer, message: .bytes(body), meta: [("timestamp", .uint(UInt64(when)))])
        guard case .binary(let rsg) = signed else { throw RSG.RSGError.invalidOutputFormat }
        try rsg.write(
          to: URL(fileURLWithPath: file + "." + Self.signatureExtension))
        entries.append(
          .map([(.string("name"), .string(artifact)), (.string("rsg"), .bytes(rsg))]))
        signatures.append(artifact + "." + Self.signatureExtension)
      }

      meta.append(("artifacts", .array(entries)))
      let manifest = try RSG.create(
        signer: signer, message: .text(notes), embed: true, meta: meta)
      guard case .binary(let bytes) = manifest else { throw RSG.RSGError.invalidOutputFormat }
      try bytes.write(
        to: URL(fileURLWithPath: Self.joined(directory, "manifest." + Self.messageExtension)))
    } catch {
      throw RNGitClientAbort("Release manifest generation failed: \(error)")
    }

    sent.append(contentsOf: signatures)
    sent.append("manifest." + Self.messageExtension)
    return sent
  }

  /// The fields one step of creating a release carries.
  private static func createFields(
    _ path: String, tag: String, extra: [(String, MsgPack.Value)], step: String
  ) -> MsgPack.Value {
    var entries: [(MsgPack.Value, MsgPack.Value)] = [
      (.uint(UInt64(RNGitRequestKey.repository)), .string(path)),
      (.string("operation"), .string("create")),
      (.string("step"), .string(step)),
      (.string("tag"), .string(tag)),
    ]
    entries.append(contentsOf: extra.map { (.string($0.0), $0.1) })
    return .map(entries)
  }
}
