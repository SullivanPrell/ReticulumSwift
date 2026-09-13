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

/// The repositories a node makes for a peer, as Python RNS 1.5.4 makes them.
///
/// Each vector is what the reference's own handler answered, along with every command it
/// would have run and what it left on disk, recorded through a stand-in for its
/// `subprocess` module.
final class RNGitCreateHandlerVectorTests: XCTestCase {

  private struct Outcome {
    let status: Int32
    let standardOutput: String
    let standardError: String

    init(_ status: Int32, _ standardOutput: String, _ standardError: String) {
      self.status = status
      self.standardOutput = standardOutput
      self.standardError = standardError
    }
  }

  private struct Call: Equatable {
    let argv: [String]
    let directory: String?

    init(_ argv: [String], _ directory: String?) {
      self.argv = argv
      self.directory = directory
    }
  }

  /// Answers what the reference's `subprocess` was scripted to answer, logging every call.
  private final class ScriptedRunner: RNGitCommandRunner, @unchecked Sendable {
    let script: [Outcome?]
    var calls: [Call] = []

    init(_ script: [Outcome?]) { self.script = script }

    func run(_ executable: String, arguments: [String], in directory: String?)
      -> RNGitCommandOutput?
    {
      calls.append(Call([executable] + arguments, directory))
      let outcome =
        calls.count <= script.count ? script[calls.count - 1] : Outcome(0, "", "")
      guard let outcome else { return nil }
      return RNGitCommandOutput(
        status: outcome.status, standardOutput: outcome.standardOutput,
        standardError: outcome.standardError)
    }
  }

  private struct Vector {
    let name: String
    let groupGrants: RNGitPermissionSet
    let repositoryGrants: RNGitPermissionSet
    let identity: String?
    let seeded: Bool
    let state: String
    let blocked: Bool
    let request: MsgPack.Value
    let script: [Outcome?]
    let answer: String
    let calls: [Call]
    let allowed: String?
    let directory: Bool
    let registered: Bool
    let fork: String?
    let mirror: String?
    let admin: [String]
  }

  /// A permission set granting the named targets, which are keywords or identity hashes.
  private static func permissions(
    read: [String] = [], write: [String] = [], create: [String] = [], stats: [String] = [],
    release: [String] = [], interact: [String] = [], propose: [String] = [],
    admin: [String] = []
  ) -> RNGitPermissionSet {
    var permissions = RNGitPermissionSet()
    permissions.read = targets(read)
    permissions.write = targets(write)
    permissions.create = targets(create)
    permissions.stats = targets(stats)
    permissions.release = targets(release)
    permissions.interact = targets(interact)
    permissions.propose = targets(propose)
    permissions.admin = targets(admin)
    return permissions
  }

  private static func targets(_ names: [String]) -> [RNGitPermissionTarget] {
    names.compactMap { name in
      switch name {
      case "nobody": return .nobody
      case "everyone": return .everyone
      default: return Data(pythonHex: name).map { .identity($0) }
      }
    }
  }

  private static let vectors: [Vector] = [
    Vector(
      name: "no identity",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: nil,
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "014e6f74206964656e746966696564",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "request not a map",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .string("group/repo"),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "request nil",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .nil,
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "request empty",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([]),
      script: [],
      answer: "024e6f207265706f7369746f727920737065636966696564",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "repository not a string",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .int(5))]),
      script: [],
      answer: "RAISED",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "path without a group",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("repo"))]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "path with three parts",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/sub/repo"))]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "group name empty",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("/repo"))]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "repository name empty",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/"))]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "unknown group",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("other/repo"))]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "group path missing",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "groupless",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "group path missing read granted",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "groupless",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "create refused",
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "create refused read granted",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "014e6f7420616c6c6f776564",
      calls: [],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "registered read granted",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: true,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "015265706f7369746f727920616c726561647920657869737473",
      calls: [],
      allowed: nil,
      directory: false,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "registered read refused",
      groupGrants: permissions(create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: true,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "path already present",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "occupied",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: true,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "created",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""), Outcome(128, "", ""),
        Outcome(128, "", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<repo>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "created for a fork",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""),
        Outcome(0, "fork\n", ""), Outcome(0, "rns://source/repo\n", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<repo>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.source"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      registered: true,
      fork: "rns://source/repo",
      mirror: nil,
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "created for a mirror",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""), Outcome(128, "", ""),
        Outcome(0, "mirror\n", ""), Outcome(0, "rns://source/repo\n", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<repo>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.source"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      registered: true,
      fork: nil,
      mirror: "rns://source/repo",
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "created for a padded identity",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "0b1c1c1c1c1c1c1cd00e0e0e0e0e0e0e",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""), Outcome(128, "", ""),
        Outcome(128, "", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<repo>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
      ],
      allowed: "adm:0b1c1c1c1c1c1c1cd00e0e0e0e0e0e0e",
      directory: true,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: ["0b1c1c1c1c1c1c1cd00e0e0e0e0e0e0e"]),
    Vector(
      name: "permissions replaced",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "stale",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""), Outcome(128, "", ""),
        Outcome(128, "", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<repo>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "init refused",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(128, "", "fatal: no\n")],
      answer: "ff436f756c64206e6f7420696e697469616c697a65207265706f7369746f7279",
      calls: [Call(["git", "init", "--bare"], "<repo>")],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "init would not run",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [nil],
      answer: "ff52656d6f7465206572726f72",
      calls: [Call(["git", "init", "--bare"], "<repo>")],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "permissions unwritable",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "blocked",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(0, "", "")],
      answer: "ff436f756c64206e6f7420696e697469616c697a65207265706f7369746f7279",
      calls: [Call(["git", "init", "--bare"], "<repo>")],
      allowed: nil,
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "not a repository",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(0, "", ""), Outcome(0, "/elsewhere/.git\n", "")],
      answer: "ff4661696c656420746f207265676973746572207265706f7369746f7279",
      calls: [
        Call(["git", "init", "--bare"], "<repo>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "not bare",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "false\n", "")],
      answer: "ff4661696c656420746f207265676973746572207265706f7369746f7279",
      calls: [
        Call(["git", "init", "--bare"], "<repo>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: false,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "blocked identity creates",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: true,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""), Outcome(128, "", ""),
        Outcome(128, "", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<repo>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "blocked identity finds none",
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: true,
      state: "ready",
      blocked: true,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "grant by group admin",
      groupGrants: permissions(read: ["everyone"], admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""), Outcome(128, "", ""),
        Outcome(128, "", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<repo>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
  ]

  private static let identityA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  /// Every request is answered as the reference answered it, having run what it ran and
  /// left what it left.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-create-" + UUID().uuidString
      let groupPath = root + "/group"
      let path = groupPath + "/repo"
      try FileManager.default.createDirectory(
        atPath: groupPath, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }

      switch vector.state {
      case "groupless": try FileManager.default.removeItem(atPath: groupPath)
      case "occupied":
        try FileManager.default.createDirectory(
          atPath: path, withIntermediateDirectories: true)
      case "blocked":
        try FileManager.default.createDirectory(
          atPath: path + ".allowed.tmp", withIntermediateDirectories: true)
      case "stale":
        try "read:everyone\n".write(
          toFile: path + ".allowed", atomically: false, encoding: .utf8)
      default: break
      }

      var group = RNGitGroup(name: "group", path: groupPath)
      group.permissions = vector.groupGrants
      if vector.seeded {
        var repository = RNGitRepository(name: "repo", path: path)
        repository.permissions = vector.repositoryGrants
        group.repositories["repo"] = repository
      }
      let identity = try XCTUnwrap(Data(pythonHex: Self.identityA), vector.name)

      let runner = ScriptedRunner(vector.script)
      var handler = RNGitCreateHandler(
        store: RNGitRepositoryStore(runner: runner, groups: ["group": group]),
        runner: runner, blockedIdentities: vector.blocked ? [identity] : [])

      let answer = handler.handle(
        vector.request, from: vector.identity.flatMap { Data(pythonHex: $0) })
      let described = answer.map { $0.encoded.hexString } ?? "RAISED"
      XCTAssertEqual(described, vector.answer, vector.name)
      XCTAssertEqual(Self.normalised(runner.calls, at: path), vector.calls, vector.name)

      XCTAssertEqual(
        FileManager.default.fileExists(atPath: path), vector.directory, vector.name)
      XCTAssertEqual(
        try? String(contentsOfFile: path + ".allowed", encoding: .utf8), vector.allowed,
        vector.name)

      let entry = handler.store.groups["group"]?.repositories["repo"]
      XCTAssertEqual(entry != nil, vector.registered, vector.name)
      XCTAssertEqual(entry?.path, vector.registered ? path : nil, vector.name)
      XCTAssertEqual(entry?.fork, vector.fork, vector.name)
      XCTAssertEqual(entry?.mirror, vector.mirror, vector.name)
      XCTAssertEqual(entry?.permissions.admin ?? [], Self.targets(vector.admin), vector.name)
    }
  }

  /// The calls with the repository path replaced by the name the vectors use.
  private static func normalised(_ calls: [Call], at path: String) -> [Call] {
    calls.map { Call($0.argv, $0.directory == path ? "<repo>" : $0.directory) }
  }
}
