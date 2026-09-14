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

/// What an `rngit` client says where Python RNS 1.5.4 says what its interpreter does.
///
/// Each command wraps its body so that a decoder refusing what a node sent aborts under the
/// wrapper's own prefix, carrying the decoder's description after it. The prefix is the same on
/// both sides; what follows it is whatever the decoder in hand says.
final class RNGitClientDivergenceTests: XCTestCase {

  /// Holds what the client wrote.
  private final class Recorder: RNGitClientOutput {
    var written = ""
    func write(_ text: String) { written += text }
  }

  /// Answers every request with the same bytes.
  private final class Stub: RNGitClientTransport {
    private let answer: RNGitRequestResult
    init(_ answer: RNGitRequestResult) { self.answer = answer }
    func mediumPathTimeout() -> TimeInterval { 1606 }
    func awaitPath(to destinationHash: Data, timeout: TimeInterval) -> Bool { true }
    func recallIdentity(for destinationHash: Data) -> Identity? { Identity() }
    func establishLink(to identity: Identity) -> Bool { true }
    func request(
      _ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval,
      progress: ((RNGitTransferProgress) -> Void)?
    ) -> RNGitClientResponse {
      RNGitClientResponse(result: answer)
    }
    func teardown() {}
  }

  private static let group = "rns://" + String(repeating: "aa", count: 16) + "/group"
  private static let repository = group + "/repo"

  /// Bytes a node answered with that carry msgpack's reserved code after an ok.
  private static let reserved = RNGitRequestResult.bytes(Data([0x00, 0xc1]))

  /// What `running` aborted with.
  private func aborting(_ running: () throws -> Void) -> String? {
    do {
      try running()
      return nil
    } catch let abort as RNGitClientAbort {
      return abort.message
    } catch {
      return String(describing: error)
    }
  }

  func testAListingThatCannotBeDecodedReadsAsUnreadable() {
    let commands = RNGitClientCommands(transport: Stub(Self.reserved), output: Recorder())
    XCTAssertEqual(
      aborting { try commands.listReleases(remote: Self.repository) },
      "Error listing releases: unreadable data")
  }

  func testAReleaseThatCannotBeDecodedReadsAsUnreadable() {
    let commands = RNGitClientCommands(transport: Stub(Self.reserved), output: Recorder())
    XCTAssertEqual(
      aborting { try commands.viewRelease(remote: Self.repository, target: "v1") },
      "Error viewing release: unreadable data")
  }

  func testGroupPermissionsThatCannotBeDecodedReadAsUnreadable() {
    let commands = RNGitClientCommands(transport: Stub(Self.reserved), output: Recorder())
    XCTAssertEqual(
      aborting { try commands.groupPermissions(remote: Self.group) },
      "Error editing permissions: unreadable data")
  }

  func testRepositoryPermissionsThatCannotBeDecodedReadAsUnreadable() {
    let commands = RNGitClientCommands(transport: Stub(Self.reserved), output: Recorder())
    XCTAssertEqual(
      aborting { try commands.repositoryPermissions(remote: Self.repository) },
      "Error editing permissions: unreadable data")
  }

  /// Hands back the same notes at every edit.
  private final class Scribe: RNGitClientEditor {
    func editor() -> String { "write" }
    func run(_ editor: String, over path: String) -> Int32 {
      (try? "Notes".write(toFile: path, atomically: true, encoding: .utf8)) == nil ? 1 : 0
    }
  }

  func testAClientWithNoEditorSaysThereIsNoneToRun() {
    let output = Recorder()
    let commands = RNGitClientCommands(
      transport: Stub(.bytes(Data([0x00]))), output: output)
    XCTAssertNil(aborting { try commands.groupPermissions(remote: Self.group) })
    XCTAssertTrue(
      output.written.hasSuffix(RNGitClientCommands.noEditor + "Edit cancelled\n"),
      output.written)
  }

  func testAManifestThatCannotBeWrittenReadsAsAGenerationFailure() throws {
    let manager = FileManager.default
    let directory = NSTemporaryDirectory() + "rngit-readonly-" + UUID().uuidString
    try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer {
      try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)
      try? manager.removeItem(atPath: directory)
    }
    try Data("body".utf8).write(to: URL(fileURLWithPath: directory + "/artifact.bin"))
    try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory)

    let commands = RNGitClientCommands(
      identity: Identity(), transport: Stub(.bytes(Data([0x00]))), output: Recorder(),
      editor: Scribe())
    let message = aborting {
      try commands.createRelease(
        remote: Self.repository, target: "1.0.0:" + directory, noUpload: true)
    }
    XCTAssertEqual(
      message?.hasPrefix("Release manifest generation failed: "), true, message ?? "no abort")
  }
}
