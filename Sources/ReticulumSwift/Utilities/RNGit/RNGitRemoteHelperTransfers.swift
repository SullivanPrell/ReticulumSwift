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

extension RNGitRemoteHelper {

  /// Asks the node for the objects behind every ref git asked to fetch.
  ///
  /// A batch size of zero takes no refs out of the queue, so the queue never empties and the
  /// helper goes on asking for nothing until a request brings nothing back.
  func fetch(_ queue: [Wanted]) throws {
    guard !queue.isEmpty else { return }

    var have: [String] = []
    for reference in remoteReferences where ran("cat-file", "-t", reference.sha).status == 0 {
      have.append(reference.sha)
    }

    var remaining = queue[...]
    while !remaining.isEmpty {
      let batch = remaining.prefix(refBatchSize)
      remaining = remaining.dropFirst(refBatchSize)

      var refs: [MsgPack.Value] = []
      for wanted in batch {
        var entry: [(MsgPack.Value, MsgPack.Value)] = [
          (.string("sha"), .string(wanted.sha)), (.string("ref"), .string(wanted.ref)),
        ]
        let resolved = ran("rev-parse", wanted.ref)
        if resolved.status == 0 {
          let local = resolved.standardOutput.pythonStripped
          if local != wanted.sha { entry.append((.string("have"), .string(local))) }
        }
        refs.append(.map(entry))
      }

      var fields: [(MsgPack.Value, MsgPack.Value)] = [
        repositoryField, (.string("refs"), .array(refs)),
      ]
      if !have.isEmpty { fields.append((.string("have"), .array(have.map { .string($0) }))) }

      let answer = try requesting(.fetch, .map(fields))
      if case .bytes(let body) = answer.result, body.isEmpty {
        throw RNGitClientAbort("No data in fetch response for batch")
      }

      guard answer.metadata?.pythonIsTruthy == true else {
        guard case .bytes(let response) = answer.result else {
          throw RNGitClientAbort("Invalid fetch response for batch")
        }
        guard response[response.startIndex] != 0 else { continue }
        throw RNGitClientAbort(
          "Fetch failed for batch: " + Data(response.dropFirst()).utf8IgnoringInvalid)
      }

      guard let code = RNGitRequestFields(answer.metadata ?? .nil)?[RNGitRequestKey.resultCode]
      else { throw RNGitClientAbort("No result metadata on bundle response") }
      guard code.pythonEquals(.uint(0)) else {
        throw RNGitClientAbort("Unknown remote state for batch ref fetch")
      }
      guard case .file(let bundle) = answer.result else {
        throw RNGitAnswerShape.bytesWhereAFileIsNamed
      }

      if progressEnabled {
        let size = ((try? FileManager.default.attributesOfItem(atPath: bundle))?[.size] as? Int)
        stderr.write(
          "Transferring: 100% (" + RNSUtilities.prettysize(size ?? 0) + ")."
            + String(repeating: " ", count: 23) + "\n")
      }

      guard ran("bundle", "verify", "-q", bundle).status == 0 else {
        throw RNGitClientAbort("Bundle verification failed for batch")
      }

      var unbundle = ["bundle", "unbundle"]
      if progressEnabled { unbundle.append("--progress") }
      unbundle.append(bundle)
      let unbundled = ran(unbundle)
      if progressEnabled { stderr.write(unbundled.standardError) }
      guard unbundled.status == 0 else {
        throw RNGitClientAbort("Bundle unbundle failed for batch: Non-zero return code")
      }
    }
  }

  /// Sends the node every ref git asked to push, saying how each one went.
  func push(_ queue: [Sending]) throws {
    for sending in queue {
      let remote = sending.remote
      if sending.local.isEmpty {
        guard try delete(remote) else { continue }
        stdout.write("ok " + remote + "\n")
        continue
      }

      let forced = sending.local.hasPrefix("+")
      let local = forced ? String(sending.local.dropFirst()) : sending.local

      let resolved = ran("rev-parse", local)
      guard resolved.status == 0 else {
        write(error: "Could not resolve local ref " + local, for: remote)
        continue
      }
      let sha = resolved.standardOutput.pythonStripped

      switch try bundling(local, to: remote, forced: forced) {
      case .refused: continue
      case .sent: break
      case .empty:
        let answer = try requesting(
          .push,
          .map([
            repositoryField,
            (
              .string("operations"),
              .array([
                .map([
                  (.string("action"), .string("update_ref")), (.string("ref"), .string(remote)),
                  (.string("sha"), .string(sha)), (.string("force"), .bool(forced)),
                ])
              ])
            ),
          ]))
        guard accepted(answer, for: remote) else { continue }
      }

      stdout.write("ok " + remote + "\n")
    }
  }

  /// What building a bundle for one ref came to.
  enum Bundled {

    /// The bundle went to the node, which took it.
    case sent

    /// Everything the ref reaches already stands on the node.
    case empty

    /// The push did not go through, and git has been told so.
    case refused
  }

  /// Asks the node to drop `remote`, answering whether it did.
  private func delete(_ remote: String) throws -> Bool {
    let answer = try requesting(
      .delete, .map([repositoryField, (.string("ref"), .string(remote))]))
    return accepted(answer, for: remote)
  }

  /// Builds a bundle carrying everything `local` reaches that the node has not, and sends it.
  private func bundling(_ local: String, to remote: String, forced: Bool) throws -> Bundled {
    guard let directory = temporaryDirectory() else {
      write(error: "Bundle creation failed", for: remote)
      return .refused
    }
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = directory + "/push.bundle"

    var create = ["bundle", "create"]
    if progressEnabled { create.append("--progress") }
    create.append(path)
    create.append(local)
    for reference in remoteReferences where ran("cat-file", "-t", reference.sha).status == 0 {
      create.append("^" + reference.sha)
    }

    let created = ran(create)
    if created.status != 0 {
      guard created.standardError.lowercased().contains("empty bundle") else {
        if progressEnabled, !created.standardError.isEmpty { stderr.write(created.standardError) }
        write(error: "Bundle creation failed", for: remote)
        return .refused
      }
      return .empty
    }

    let bundle = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
    let answer = try requesting(
      .push,
      .map([
        repositoryField, (.string("local_ref"), .string(local)),
        (.string("remote_ref"), .string(remote)), (.string("force"), .bool(forced)),
        (.string("bundle"), .bytes(bundle)),
      ]))
    return accepted(answer, for: remote) ? .sent : .refused
  }

  /// Whether `answer` says the node did as it was asked, telling git where it did not.
  private func accepted(_ answer: RNGitClientResponse, for remote: String) -> Bool {
    guard case .bytes(let response) = answer.result, !response.isEmpty else {
      write(error: "No response from server", for: remote)
      return false
    }
    guard response[response.startIndex] == 0 else {
      write(error: Data(response.dropFirst()).utf8IgnoringInvalid, for: remote)
      return false
    }
    return true
  }

  /// Tells git that `remote` did not go through, and why.
  private func write(error message: String, for remote: String) {
    stdout.write("error " + remote + " " + Self.escapeForStdout(message) + "\n")
  }

  /// A new directory to build a bundle in, or `nil` where none could be made.
  private func temporaryDirectory() -> String? {
    let path = NSTemporaryDirectory() + "/rngit-" + UUID().uuidString
    guard
      (try? FileManager.default.createDirectory(
        atPath: path, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])) != nil
    else { return nil }
    return path
  }
}
