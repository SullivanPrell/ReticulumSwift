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
import XCTest

@testable import ReticulumSwift

#if os(macOS)

/// What the node reads from a repository on disk, as Python RNS 1.5.4 reads it.
///
/// Each directory is built by the same `git` commands the reference built it with, and every
/// expectation is what the reference answered for that directory.
final class RNGitWorkingCopyVectorTests: XCTestCase {

  private struct Vector {
    let name: String
    let steps: [[String]]
    let isGitRepository: Bool
    let isBareRepository: Bool
    let fork: String?
    let mirror: String?
    let mirrorSynced: Int?
    let lastUpstreamSync: Int
  }

  private static let vectors: [Vector] = [
    Vector(
      name: "empty directory", steps: [],
      isGitRepository: false, isBareRepository: false,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare", steps: [["init", "--bare"]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "work tree", steps: [["init"]],
      isGitRepository: false, isBareRepository: false,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare not marked",
      steps: [["init", "--bare"], ["config", "--bool", "core.bare", "false"]],
      isGitRepository: true, isBareRepository: false,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare typed plain",
      steps: [["init", "--bare"], ["config", "repository.rngit.type", "plain"]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare fork",
      steps: [
        ["init", "--bare"], ["config", "repository.rngit.type", "fork"],
        [
          "config", "repository.rngit.upstream.source",
          "rns://aabbccddeeff00112233445566778899/group/repo",
        ],
      ],
      isGitRepository: true, isBareRepository: true,
      fork: "rns://aabbccddeeff00112233445566778899/group/repo", mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare fork no source",
      steps: [["init", "--bare"], ["config", "repository.rngit.type", "fork"]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare fork blank source",
      steps: [
        ["init", "--bare"], ["config", "repository.rngit.type", "fork"],
        ["config", "repository.rngit.upstream.source", ""],
      ],
      isGitRepository: true, isBareRepository: true,
      fork: "", mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare mirror",
      steps: [
        ["init", "--bare"], ["config", "repository.rngit.type", "mirror"],
        [
          "config", "repository.rngit.upstream.source",
          "rns://aabbccddeeff00112233445566778899/group/repo",
        ],
      ],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: "rns://aabbccddeeff00112233445566778899/group/repo",
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare mirror no source",
      steps: [["init", "--bare"], ["config", "repository.rngit.type", "mirror"]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare mirror synced",
      steps: [
        ["init", "--bare"], ["config", "repository.rngit.type", "mirror"],
        [
          "config", "repository.rngit.upstream.source",
          "rns://aabbccddeeff00112233445566778899/group/repo",
        ], ["config", "repository.rngit.upstream.sync", "1700000000"],
      ],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: "rns://aabbccddeeff00112233445566778899/group/repo",
      mirrorSynced: 1_700_000_000, lastUpstreamSync: 1_700_000_000),
    Vector(
      name: "bare mirror sync zero",
      steps: [["init", "--bare"], ["config", "repository.rngit.upstream.sync", "0"]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: 0, lastUpstreamSync: 0),
    Vector(
      name: "bare mirror sync blank",
      steps: [["init", "--bare"], ["config", "repository.rngit.upstream.sync", ""]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare mirror sync text",
      steps: [["init", "--bare"], ["config", "repository.rngit.upstream.sync", "soon"]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare sync underscored",
      steps: [["init", "--bare"], ["config", "repository.rngit.upstream.sync", "1_0"]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: 10, lastUpstreamSync: 10),
    Vector(
      name: "bare sync spaced",
      steps: [["init", "--bare"], ["config", "repository.rngit.upstream.sync", " 12 "]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: 12, lastUpstreamSync: 12),
    Vector(
      name: "bare sync negative",
      steps: [["init", "--bare"], ["config", "repository.rngit.upstream.sync", "-5"]],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: -5, lastUpstreamSync: -5),
    Vector(
      name: "bare typed fork uppercase",
      steps: [
        ["init", "--bare"], ["config", "repository.rngit.type", "Fork"],
        [
          "config", "repository.rngit.upstream.source",
          "rns://aabbccddeeff00112233445566778899/group/repo",
        ],
      ],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
    Vector(
      name: "bare source only",
      steps: [
        ["init", "--bare"],
        [
          "config", "repository.rngit.upstream.source",
          "rns://aabbccddeeff00112233445566778899/group/repo",
        ],
      ],
      isGitRepository: true, isBareRepository: true,
      fork: nil, mirror: nil,
      mirrorSynced: nil, lastUpstreamSync: 0),
  ]

  private let runner = RNGitProcessRunner()

  /// Every directory reads as the reference read it.
  func testDirectoriesMatchTheReference() throws {
    for vector in Self.vectors {
      let path = try build(vector)
      defer { try? FileManager.default.removeItem(atPath: path) }

      XCTAssertEqual(
        RNGitWorkingCopy.isGitRepository(path, runner: runner), vector.isGitRepository,
        vector.name)
      XCTAssertEqual(
        RNGitWorkingCopy.isBareRepository(path, runner: runner), vector.isBareRepository,
        vector.name)
      XCTAssertEqual(
        RNGitWorkingCopy.forkSource(of: path, runner: runner), vector.fork,
        vector.name)
      XCTAssertEqual(
        RNGitWorkingCopy.mirrorSource(of: path, runner: runner), vector.mirror,
        vector.name)
      XCTAssertEqual(
        RNGitWorkingCopy.mirrorSynced(path, runner: runner), vector.mirrorSynced,
        vector.name)
      XCTAssertEqual(
        RNGitWorkingCopy.lastUpstreamSync(path, runner: runner), vector.lastUpstreamSync,
        vector.name)
    }
  }

  /// Recording the sync time makes the node read back the moment it recorded.
  func testRecordingTheSyncTimeIsReadBack() throws {
    let path = try build(Self.vectors[1])
    defer { try? FileManager.default.removeItem(atPath: path) }

    XCTAssertTrue(RNGitWorkingCopy.setMirrorSynced(path, at: 1_700_000_001, runner: runner))
    XCTAssertEqual(RNGitWorkingCopy.lastUpstreamSync(path, runner: runner), 1_700_000_001)
  }

  /// The node finds git on a machine that has it.
  func testGitIsAvailable() {
    XCTAssertTrue(RNGitWorkingCopy.gitAvailable(runner: runner))
  }

  /// A directory that is not a repository records nothing.
  func testRecordingTheSyncTimeFailsOutsideARepository() throws {
    let path = try build(Self.vectors[0])
    defer { try? FileManager.default.removeItem(atPath: path) }

    XCTAssertFalse(RNGitWorkingCopy.setMirrorSynced(path, at: 1, runner: runner))
  }

  private func build(_ vector: Vector) throws -> String {
    let path = NSTemporaryDirectory() + "rngit-" + UUID().uuidString
    try FileManager.default.createDirectory(
      atPath: path, withIntermediateDirectories: true)
    for step in vector.steps {
      let output = runner.run("git", arguments: step, in: path)
      XCTAssertEqual(output?.status, 0, "\(vector.name): git \(step.joined(separator: " "))")
    }
    return path
  }
}

#endif
