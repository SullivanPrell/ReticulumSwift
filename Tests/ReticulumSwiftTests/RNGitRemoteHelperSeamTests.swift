//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest

@testable import ReticulumSwift

/// The seam the `git-remote-rns` helper reaches `git` through.
///
/// A helper built without a runner has no `git` to reach, a state the reference cannot be in.
final class RNGitRemoteHelperSeamTests: XCTestCase {

  /// Holds what the helper wrote.
  private final class Recorder: RNGitClientOutput {
    var written = ""
    func write(_ text: String) { written += text }
  }

  /// Hands the helper the lines git sent it.
  private final class Script: RNGitClientInput {
    private var lines: [String]
    init(_ script: String) { lines = script.components(separatedBy: "\n").dropLast() }
    func readLine() -> String? { lines.isEmpty ? nil : lines.removeFirst() }
  }

  /// Brings a link up and answers every request the same way.
  private final class Stub: RNGitClientTransport {
    var requests: [RNGitRequestPath] = []
    var fields: [String] = []
    func mediumPathTimeout() -> TimeInterval { 1606 }
    func awaitPath(to destinationHash: Data, timeout: TimeInterval) -> Bool { true }
    func recallIdentity(for destinationHash: Data) -> Identity? { Identity() }
    func establishLink(to identity: Identity) -> Bool { true }
    func request(
      _ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval,
      progress: ((RNGitTransferProgress) -> Void)?
    ) -> RNGitClientResponse {
      requests.append(path)
      self.fields.append(MsgPack.encode(fields).hexString)
      return RNGitClientResponse(result: .bytes(Data([0])))
    }
    func teardown() {}
  }

  /// A `git` that cannot be run answers as one that failed.
  func testAPushWithoutARunnerResolvesNoRef() throws {
    let stdout = Recorder()
    let transport = Stub()
    var helper = RNGitRemoteHelper(
      url: try RNGitHelperURL.reading("rns://" + String(repeating: "aa", count: 16) + "/g/r"),
      transport: transport, stdout: stdout, stderr: Recorder(),
      input: Script("push refs/heads/main:refs/heads/main\n\n"))

    try helper.run()

    XCTAssertEqual(
      stdout.written, "error refs/heads/main \"Could not resolve local ref refs/heads/main\"\n\n")
    XCTAssertEqual(transport.requests, [])
  }

  /// A fetch without a runner resolves no ref of its own, so it names the node nothing it has.
  func testAFetchWithoutARunnerNamesNothingItHas() throws {
    let stdout = Recorder()
    let transport = Stub()
    var helper = RNGitRemoteHelper(
      url: try RNGitHelperURL.reading("rns://" + String(repeating: "aa", count: 16) + "/g/r"),
      transport: transport, stdout: stdout, stderr: Recorder(),
      input: Script("fetch aaa111 refs/heads/main\n\n"))

    try helper.run()

    let expected = MsgPack.Value.map([
      (.uint(UInt64(RNGitRequestKey.repository)), .string("g/r")),
      (
        .string("refs"),
        .array([
          .map([
            (.string("sha"), .string("aaa111")), (.string("ref"), .string("refs/heads/main")),
          ])
        ])
      ),
    ])
    XCTAssertEqual(stdout.written, "\n")
    XCTAssertEqual(transport.requests, [.fetch])
    XCTAssertEqual(transport.fields, [MsgPack.encode(expected).hexString])
  }
}
