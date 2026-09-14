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

/// Where a client keeps its files, and what it writes where it finds no configuration.
final class RNGitClientEnvironmentTests: XCTestCase {

  /// One recorded resolution of the configuration directory.
  private struct Case {
    let name: String
    /// What stands under the home directory before the resolution runs.
    let standing: [String]
    let given: String?
    let directory: String
    /// Whether `directory` is read as a path under the home directory.
    let underHome: Bool
  }

  /// Every resolution recorded from the reference.
  private static let cases: [Case] = [
    Case(
      name: "a directory that was named",
      standing: [],
      given: "/tmp/named",
      directory: "/tmp/named",
      underHome: false),
    Case(
      name: "nothing under the user's home",
      standing: [],
      given: nil,
      directory: "/.rngit",
      underHome: true),
    Case(
      name: "a node directory holding no configuration",
      standing: ["directory:.config/rngit"],
      given: nil,
      directory: "/.rngit",
      underHome: true),
    Case(
      name: "a node directory holding a configuration",
      standing: ["directory:.config/rngit", "file:.config/rngit/config"],
      given: nil,
      directory: "/.rngit/reticulum",
      underHome: true),
    Case(
      name: "a file where the node directory would be",
      standing: ["directory:.config", "file:.config/rngit"],
      given: nil,
      directory: "/.rngit",
      underHome: true),
    Case(
      name: "a directory where the node's configuration would be",
      standing: ["directory:.config/rngit/config"],
      given: nil,
      directory: "/.rngit",
      underHome: true),
    Case(
      name: "a name that is empty",
      standing: [],
      given: "",
      directory: "",
      underHome: false),
  ]

  func testEveryConfigurationDirectoryMatchesTheReference() throws {
    let manager = FileManager.default
    for recorded in Self.cases {
      let home = NSTemporaryDirectory() + "/rngit-home-" + UUID().uuidString
      try manager.createDirectory(atPath: home, withIntermediateDirectories: true)
      defer { try? manager.removeItem(atPath: home) }

      for entry in recorded.standing {
        let parts = entry.split(separator: ":", maxSplits: 1)
        let path = home + "/" + String(parts[1])
        if parts[0] == "directory" {
          try manager.createDirectory(atPath: path, withIntermediateDirectories: true)
        } else {
          XCTAssertTrue(manager.createFile(atPath: path, contents: Data()), recorded.name)
        }
      }

      let read = RNGitClientEnvironment.directory(given: recorded.given, home: home)
      let wanted = recorded.underHome ? home + recorded.directory : recorded.directory
      XCTAssertEqual(read, wanted, recorded.name)
    }
  }

  func testTheThreeFileNamesMatchTheReference() {
    XCTAssertEqual(RNGitClientEnvironment.logFileName, "client_log")
    XCTAssertEqual(RNGitClientEnvironment.configurationFileName, "client_config")
    XCTAssertEqual(RNGitClientEnvironment.identityFileName, "client_identity")
  }

  func testADirectoryIsNoFileAndAFileIsNoDirectory() throws {
    let manager = FileManager.default
    let root = NSTemporaryDirectory() + "/rngit-kind-" + UUID().uuidString
    try manager.createDirectory(atPath: root + "/directory", withIntermediateDirectories: true)
    defer { try? manager.removeItem(atPath: root) }
    XCTAssertTrue(manager.createFile(atPath: root + "/file", contents: Data()))

    XCTAssertTrue(RNGitClientEnvironment.isDirectory(root + "/directory"))
    XCTAssertFalse(RNGitClientEnvironment.isDirectory(root + "/file"))
    XCTAssertFalse(RNGitClientEnvironment.isDirectory(root + "/nothing"))

    XCTAssertTrue(RNGitClientEnvironment.isFile(root + "/file"))
    XCTAssertFalse(RNGitClientEnvironment.isFile(root + "/directory"))
    XCTAssertFalse(RNGitClientEnvironment.isFile(root + "/nothing"))
  }

  func testDefaultConfigurationMatchesTheReference() {
    XCTAssertEqual(
      RNGitClientEnvironment.defaultConfiguration,
      "# This is the default rngit client config file.\n\n[client]\n\n# You can control the batch size of ref transfers\n# using the ref_batch_size directive:\n\nref_batch_size = 25\n\n\n[aliases]\n\n# You can define aliases for commonly used destination\n# hashes in this section. Each line must be in the format\n# aliased_name = DESTINATION_HASH\n#\n# These hashes are used for resolving remote destinations.\n# For rngit node permissions and identity resolution,\n# aliases must be defined in ~/.rngit/config.\n\n# my_node = 063d38912bffc850af4a1b8a270a9d85\n# bobs_node = 714981d03e41deda0e4468cb274414cc\n\n\n[logging]\n# Valid log levels are 0 through 7:\n#   0: Log only critical information\n#   1: Log errors and lower log levels\n#   2: Log warnings and lower log levels\n#   3: Log notices and lower log levels\n#   4: Log info and lower (this is the default)\n#   5: Verbose logging\n#   6: Debug logging\n#   7: Extreme logging\n\nloglevel = 4\n"
    )
  }

  func testDefaultConfigurationReadsBackAsTheSettingsItSpellsOut() throws {
    let section = try RNGitConfigFile.parse(RNGitClientEnvironment.defaultConfiguration)
    let settings = try RNGitHelperSettings(configuration: section)
    XCTAssertEqual(settings.refBatchSize, 25)
    XCTAssertEqual(settings.client.logLevel, 4)
    XCTAssertEqual(settings.client.destinationAliases, [:])
  }
}
