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

/// What the helper does before it reaches the stack.
final class RNGitHelperRuntimeTests: XCTestCase {

  /// Everything written to one stream.
  private final class Collected: RNGitClientOutput {
    var text = ""
    func write(_ piece: String) { text += piece }
  }

  /// A git that says nothing.
  private final class Silent: RNGitClientInput {
    func readLine() -> String? { nil }
  }

  private var standardOutput = Collected()
  private var standardError = Collected()

  override func setUp() {
    super.setUp()
    standardOutput = Collected()
    standardError = Collected()
  }

  /// A node that never comes within reach.
  private final class Unreachable: RNGitClientTransport {
    func mediumPathTimeout() -> TimeInterval { 0 }
    func awaitPath(to destinationHash: Data, timeout: TimeInterval) -> Bool { true }
    func recallIdentity(for destinationHash: Data) -> Identity? { Identity() }
    func establishLink(to identity: Identity) -> Bool { false }
    func request(
      _ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval,
      progress: ((RNGitTransferProgress) -> Void)?
    ) -> RNGitClientResponse {
      RNGitClientResponse(result: .none)
    }
    func teardown() {}
  }

  private func streams() -> RNGitHelperRuntime.Streams {
    RNGitHelperRuntime.Streams(
      standardOutput: standardOutput, standardError: standardError, standardInput: Silent())
  }

  private func run(_ arguments: [String], environment: [String: String] = [:]) -> Int32 {
    RNGitHelperRuntime.run(
      arguments: arguments, environment: environment, streams: streams())
  }

  func testArgumentsNamingNoURLStopBeforeAnythingIsBroughtUp() {
    XCTAssertEqual(run([]), 1)
    XCTAssertEqual(standardError.text, "Usage: git-remote-rns <remote-name> <url>\n")
    XCTAssertEqual(standardOutput.text, "")
  }

  func testAURLUnderAnotherSchemeStopsBeforeAnythingIsBroughtUp() {
    XCTAssertEqual(run(["origin", "https://example.org/g/r"]), 1)
    XCTAssertEqual(standardError.text, "Invalid URL scheme. Must be rns://\n")
    XCTAssertEqual(standardOutput.text, "")
  }

  func testAURLNamingNoRepositoryStopsBeforeAnythingIsBroughtUp() {
    XCTAssertEqual(run(["origin", "rns://aaaa/g"]), 1)
    XCTAssertEqual(standardError.text, "Invalid URL format. Use rns://<hash>/<group>/<repo>\n")
  }

  func testAConfigurationThatWillNotParseStopsBeforeTheStackIsBroughtUp() throws {
    let directory = NSTemporaryDirectory() + "/rngit-config-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    try "[[orphan]]\n".write(
      toFile: directory + "/" + RNGitClientEnvironment.configurationFileName, atomically: true,
      encoding: .utf8)

    let status = run(
      ["origin", "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/g/r"],
      environment: ["RNGIT_CONFIG": directory])
    XCTAssertEqual(status, 1)
    XCTAssertEqual(standardOutput.text, "")
  }

  func testAMissingConfigurationIsWrittenBeforeItIsRead() throws {
    let directory = NSTemporaryDirectory() + "/rngit-config-" + UUID().uuidString
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = directory + "/" + RNGitClientEnvironment.configurationFileName

    _ = try RNGitClientEnvironment.configuration(at: path, in: directory)
    XCTAssertEqual(
      try String(contentsOfFile: path, encoding: .utf8),
      RNGitClientEnvironment.defaultConfiguration)
  }

  func testTheHelperCarriesWhatTheConfigurationSpellsOut() throws {
    var configuration = RNGitClientEnvironment.defaultConfiguration
    configuration = configuration.replacingOccurrences(
      of: "ref_batch_size = 25", with: "ref_batch_size = 7")
    configuration = configuration.replacingOccurrences(
      of: "# my_node = 063d38912bffc850af4a1b8a270a9d85",
      with: "my_node = 063d38912bffc850af4a1b8a270a9d85")
    let settings = try RNGitHelperSettings(
      configuration: try RNGitConfigFile.parse(configuration))

    let helper = RNGitHelperRuntime.helper(
      setup: RNGitHelperProgramSetup(
        configDirectory: nil, rnsConfigDirectory: nil,
        url: try RNGitHelperURL.reading("rns://my_node/g/r")),
      settings: settings, transport: Unreachable(), streams: streams(),
      workingDirectory: "/tmp/work")

    XCTAssertEqual(helper.refBatchSize, 7)
    XCTAssertEqual(helper.aliases, ["my_node": "063d38912bffc850af4a1b8a270a9d85"])
    XCTAssertEqual(helper.destination, "my_node")
    XCTAssertEqual(helper.repositoryPath, "g/r")
    XCTAssertEqual(helper.workingDirectory, "/tmp/work")
  }

  func testARunThatGivesUpPartWayReportsWhatItGaveUpOver() throws {
    var helper = RNGitHelperRuntime.helper(
      setup: RNGitHelperProgramSetup(
        configDirectory: nil, rnsConfigDirectory: nil,
        url: try RNGitHelperURL.reading(
          "rns://" + String(repeating: "aa", count: 16) + "/g/r")),
      settings: RNGitHelperSettings(), transport: Unreachable(), streams: streams(),
      workingDirectory: ".")

    XCTAssertEqual(RNGitHelperRuntime.run(&helper, streams: streams()), 255)
    XCTAssertTrue(
      standardError.text.hasSuffix("git-remote-rns failed: Failed to establish link\n"),
      standardError.text)
    XCTAssertEqual(standardOutput.text, "")
  }

  func testAnIdentityIsGeneratedOnceAndReadBackAfterwards() throws {
    let directory = NSTemporaryDirectory() + "/rngit-identity-" + UUID().uuidString
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = directory + "/" + RNGitClientEnvironment.identityFileName

    let made = try RNGitClientEnvironment.identity(at: path, in: directory)
    let read = try RNGitClientEnvironment.identity(at: path, in: directory)
    XCTAssertEqual(made.hash, read.hash)
  }
}
