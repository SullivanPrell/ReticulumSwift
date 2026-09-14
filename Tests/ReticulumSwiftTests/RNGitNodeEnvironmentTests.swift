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

/// Where a node keeps its files, as Python RNS 1.5.4 resolves them.
final class RNGitNodeEnvironmentTests: XCTestCase {

  /// One recorded resolution of the configuration directory.
  private struct Case {
    let given: String?
    /// What stands on disk before the resolution runs, as `directory:` and `file:` paths.
    let standing: [String]
    let directory: String
  }

  /// The home directory the reference resolved against.
  private static let home = "/home/u"

  /// Every resolution recorded from the reference.
  private static let cases: [Case] = [
    Case(
      given: nil,
      standing: [],
      directory: home + "/.rngit"),
    Case(
      given: nil,
      standing: ["file:" + home + "/.config/rngit/config"],
      directory: home + "/.rngit"),
    Case(
      given: nil,
      standing: ["directory:" + home + "/.config/rngit"],
      directory: home + "/.rngit"),
    Case(
      given: nil,
      standing: ["directory:" + home + "/.config/rngit", "file:" + home + "/.config/rngit/config"],
      directory: home + "/.rngit/reticulum"),
    Case(
      given: nil,
      standing: ["file:/etc/rngit/config"],
      directory: home + "/.rngit"),
    Case(
      given: nil,
      standing: ["file:/etc/rngit/config", "file:" + home + "/.config/rngit/config"],
      directory: home + "/.rngit"),
    Case(
      given: nil,
      standing: ["file:/etc/rngit/config", "directory:" + home + "/.config/rngit"],
      directory: home + "/.rngit"),
    Case(
      given: nil,
      standing: [
        "file:/etc/rngit/config", "directory:" + home + "/.config/rngit",
        "file:" + home + "/.config/rngit/config",
      ],
      directory: home + "/.rngit/reticulum"),
    Case(
      given: nil,
      standing: ["directory:/etc/rngit"],
      directory: home + "/.rngit"),
    Case(
      given: nil,
      standing: ["directory:/etc/rngit", "file:" + home + "/.config/rngit/config"],
      directory: home + "/.rngit"),
    Case(
      given: nil,
      standing: ["directory:/etc/rngit", "directory:" + home + "/.config/rngit"],
      directory: home + "/.rngit"),
    Case(
      given: nil,
      standing: [
        "directory:/etc/rngit", "directory:" + home + "/.config/rngit",
        "file:" + home + "/.config/rngit/config",
      ],
      directory: home + "/.rngit/reticulum"),
    Case(
      given: nil,
      standing: ["directory:/etc/rngit", "file:/etc/rngit/config"],
      directory: "/etc/rngit"),
    Case(
      given: nil,
      standing: [
        "directory:/etc/rngit", "file:/etc/rngit/config", "file:" + home + "/.config/rngit/config",
      ],
      directory: "/etc/rngit"),
    Case(
      given: nil,
      standing: [
        "directory:/etc/rngit", "file:/etc/rngit/config", "directory:" + home + "/.config/rngit",
      ],
      directory: "/etc/rngit"),
    Case(
      given: nil,
      standing: [
        "directory:/etc/rngit", "file:/etc/rngit/config", "directory:" + home + "/.config/rngit",
        "file:" + home + "/.config/rngit/config",
      ],
      directory: "/etc/rngit"),
    Case(
      given: "/given/dir",
      standing: [],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["file:" + home + "/.config/rngit/config"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["directory:" + home + "/.config/rngit"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["directory:" + home + "/.config/rngit", "file:" + home + "/.config/rngit/config"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["file:/etc/rngit/config"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["file:/etc/rngit/config", "file:" + home + "/.config/rngit/config"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["file:/etc/rngit/config", "directory:" + home + "/.config/rngit"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: [
        "file:/etc/rngit/config", "directory:" + home + "/.config/rngit",
        "file:" + home + "/.config/rngit/config",
      ],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["directory:/etc/rngit"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["directory:/etc/rngit", "file:" + home + "/.config/rngit/config"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["directory:/etc/rngit", "directory:" + home + "/.config/rngit"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: [
        "directory:/etc/rngit", "directory:" + home + "/.config/rngit",
        "file:" + home + "/.config/rngit/config",
      ],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: ["directory:/etc/rngit", "file:/etc/rngit/config"],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: [
        "directory:/etc/rngit", "file:/etc/rngit/config", "file:" + home + "/.config/rngit/config",
      ],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: [
        "directory:/etc/rngit", "file:/etc/rngit/config", "directory:" + home + "/.config/rngit",
      ],
      directory: "/given/dir"),
    Case(
      given: "/given/dir",
      standing: [
        "directory:/etc/rngit", "file:/etc/rngit/config", "directory:" + home + "/.config/rngit",
        "file:" + home + "/.config/rngit/config",
      ],
      directory: "/given/dir"),
  ]

  /// Every recorded resolution answers the directory the reference resolved.
  func testEveryResolutionMatchesTheReference() {
    for vector in Self.cases {
      let directories = Set(
        vector.standing.filter { $0.hasPrefix("directory:") }.map { String($0.dropFirst(10)) })
      let files = Set(
        vector.standing.filter { $0.hasPrefix("file:") }.map { String($0.dropFirst(5)) })
      let resolved = RNGitNodeEnvironment.directory(
        given: vector.given, home: Self.home,
        isDirectory: { directories.contains($0) }, isFile: { files.contains($0) })
      XCTAssertEqual(resolved, vector.directory, "given \(vector.given ?? "nothing")")
    }
  }

  /// The four files a node keeps are the ones the reference names.
  func testTheFourFileNamesMatchTheReference() {
    let directory = "/d"
    XCTAssertEqual(directory + "/" + RNGitNodeEnvironment.logFileName, "/d/server_log")
    XCTAssertEqual(directory + "/" + RNGitNodeEnvironment.configurationFileName, "/d/config")
    XCTAssertEqual(
      directory + "/" + RNGitNodeEnvironment.identityFileName, "/d/repositories_identity")
    XCTAssertEqual(directory + "/" + RNGitNodeEnvironment.statisticsFileName, "/d/stats")
  }

  /// The default configuration reads as the settings the reference took from it.
  ///
  /// Recorded at two verbosities, since the file's log level is offset by the verbosity the node
  /// was started with.
  func testTheDefaultConfigurationReadsAsTheReferenceReadIt() throws {
    let configuration = try RNGitConfigFile.parse(RNGitNodeEnvironment.defaultConfiguration)

    let plain = try RNGitNodeSettings(configuration: configuration)
    XCTAssertEqual(plain.nodeName, "Anonymous Git Node")
    XCTAssertEqual(plain.announceInterval, 21600)
    XCTAssertEqual(plain.mirrorInterval, 86400)
    XCTAssertFalse(plain.statsEnabled)
    XCTAssertFalse(plain.serveNomadNet)
    XCTAssertEqual(plain.logLevel, 4)
    XCTAssertEqual(plain.identityAliases, [:])
    XCTAssertEqual(plain.statsIgnored, [])
    XCTAssertEqual(plain.statsPushIgnored, [])
    XCTAssertEqual(plain.blockedIdentities, [])

    let verbose = try RNGitNodeSettings(configuration: configuration, verbosity: 2)
    XCTAssertEqual(verbose.logLevel, 6)
  }

  /// The default configuration names the three repository groups the reference ships.
  func testTheDefaultConfigurationNamesTheReferencesRepositoryGroups() throws {
    let configuration = try RNGitConfigFile.parse(RNGitNodeEnvironment.defaultConfiguration)
    let repositories = try XCTUnwrap(configuration.section("repositories"))
    XCTAssertEqual(repositories.keys, ["internal", "public", "showcase"])
    XCTAssertEqual(
      repositories.string("internal"), "/path/to/directory/with/git/repositories")

    let access = try XCTUnwrap(configuration.section("access"))
    XCTAssertEqual(access.list("public"), ["r:all", "w:9710b86ba12c42d1d8f30f74fe509286"])
    XCTAssertEqual(access.list("internal"), ["rw:9710b86ba12c42d1d8f30f74fe509286"])
  }

  /// The identity lines a node prints match the reference's, down to the padding.
  ///
  /// Both identities are recovered from fixed private keys, so the hashes are the reference's
  /// own.
  func testTheIdentityLinesMatchTheReference() throws {
    let node = try Identity(privateKeyBytes: Data(repeating: 0x11, count: 64))
    let client = try Identity(privateKeyBytes: Data(repeating: 0x22, count: 64))

    XCTAssertEqual(
      RNGitNodeEnvironment.identityLines(node: node, client: client, servingPages: false),
      [
        "Git Peer Identity         : <138b31508ad4e73d8c850d8029c8823e>",
        "Repository Node Identity  : <ef330a1940c70349459fc4401d273cb9>",
        "Repositories Destination  : <5387d73a0da489cd309f6df05c8dc10f>",
      ])
    XCTAssertEqual(
      RNGitNodeEnvironment.identityLines(node: node, client: client, servingPages: true),
      [
        "Git Peer Identity         : <138b31508ad4e73d8c850d8029c8823e>",
        "Repository Node Identity  : <ef330a1940c70349459fc4401d273cb9>",
        "Repositories Destination  : <5387d73a0da489cd309f6df05c8dc10f>",
        "Nomad Network Destination : <b0f520422ec3ac7f4c94bfe3b4e8cfb1>",
      ])
  }

  /// A missing configuration is written before it is read.
  func testAMissingConfigurationIsWrittenBeforeItIsRead() throws {
    let directory = NSTemporaryDirectory() + "/rngit-node-" + UUID().uuidString
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = directory + "/" + RNGitNodeEnvironment.configurationFileName

    _ = try RNGitNodeEnvironment.configuration(at: path, in: directory)
    XCTAssertEqual(
      try String(contentsOfFile: path, encoding: .utf8),
      RNGitNodeEnvironment.defaultConfiguration)
  }

  /// An identity is generated once and read back afterwards.
  func testAnIdentityIsGeneratedOnceAndReadBackAfterwards() throws {
    let directory = NSTemporaryDirectory() + "/rngit-node-" + UUID().uuidString
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let path = directory + "/" + RNGitNodeEnvironment.identityFileName

    let made = try RNGitNodeEnvironment.identity(at: path, in: directory)
    let read = try RNGitNodeEnvironment.identity(at: path, in: directory)
    XCTAssertEqual(made.hash, read.hash)
  }
}
