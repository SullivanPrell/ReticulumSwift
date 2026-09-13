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

/// The node's answer to a request for the references a repository holds.
public struct RNGitListHandler: Sendable {

  /// The groups the node serves, and what they grant.
  public let access: RNGitAccessControl

  /// Runs the `git` the answer is read from.
  public let runner: RNGitCommandRunner

  /// Creates a handler answering from `access`.
  public init(access: RNGitAccessControl, runner: RNGitCommandRunner) {
    self.access = access
    self.runner = runner
  }

  /// The answer a peer holding `identityHash` gets, or `nil` where the peer gets none.
  ///
  /// A request naming its repository with anything but a string is answered with nothing at
  /// all.
  public func handle(_ request: MsgPack.Value, from identityHash: Data?) -> RNGitResponse? {
    guard let identityHash else { return RNGitResponse(.disallowed, "Not identified") }
    guard let fields = RNGitRequestFields(request) else {
      return RNGitResponse(.invalidRequest, "Invalid request")
    }
    guard let requested = fields[RNGitRequestKey.repository] else {
      return RNGitResponse(.invalidRequest, "No repository specified")
    }
    guard let requestedPath = requested.asString else { return nil }

    let names = RNGitAccessControl.repositoryPath(requestedPath)
    let readable = access.allows(identityHash, names: names, permission: .read)
    let writable = access.allows(identityHash, names: names, permission: .write)
    let forPush = fields["for_push"]?.pythonIsTruthy ?? false

    guard forPush ? writable : readable else {
      return RNGitResponse(.notFound, readable ? "Not allowed" : "Not found")
    }
    guard let names, let path = access.groups[names.group]?.repositories[names.repository]?.path
    else { return RNGitResponse(.notFound, "Not found") }
    return listing(at: path)
  }

  /// The references at `path`, with the branch its `HEAD` names.
  private func listing(at path: String) -> RNGitResponse {
    var head = "master"
    let headPath = path + "/HEAD"
    if FileManager.default.fileExists(atPath: headPath) {
      guard let content = FileManager.default.contents(atPath: headPath) else {
        return RNGitResponse(.remoteFailure, "Remote error")
      }
      if content.starts(with: Data("ref: ".utf8)) {
        head = Data(content.dropFirst(5)).pythonStripped.utf8IgnoringInvalid
      }
    }

    guard
      let result = runner.run(
        "git", arguments: ["for-each-ref", "--format", "%(objectname) %(refname)"], in: path)
    else { return RNGitResponse(.remoteFailure, "Remote error") }
    guard result.status == 0 else {
      return RNGitResponse(.remoteFailure, "Could not list refs")
    }

    var seen: Set<Substring> = []
    var lines: [String] = []
    for line in result.standardOutput.trimmedForMicron.components(separatedBy: "\n")
    where !line.trimmedForMicron.isEmpty {
      let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, seen.insert(parts[1]).inserted else { continue }
      lines.append(line)
    }

    let listed = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    return RNGitResponse(.ok, listed + "@\(head) HEAD\n")
  }

}

extension Data {

  /// These bytes as UTF-8, dropping every byte that is not part of a sequence.
  var utf8IgnoringInvalid: String {
    var parser = UTF8.ForwardParser()
    var bytes = makeIterator()
    var scalars = String.UnicodeScalarView()
    decoding: while true {
      switch parser.parseScalar(from: &bytes) {
      case .valid(let encoded): scalars.append(UTF8.decode(encoded))
      case .error: continue
      case .emptyInput: break decoding
      }
    }
    return String(scalars)
  }

  /// These bytes without leading and trailing ASCII whitespace.
  ///
  /// The set is space, tab, newline, carriage return, vertical tab and form feed.
  var pythonStripped: Data {
    let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C]
    var start = startIndex
    var end = endIndex
    while start < end, whitespace.contains(self[start]) { start = index(after: start) }
    while end > start, whitespace.contains(self[index(before: end)]) { end = index(before: end) }
    return Data(self[start..<end])
  }
}
