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

/// The references a node removes, as Python RNS 1.5.4 removes them.
///
/// Each vector is what the reference's own handler answered, along with every command it
/// would have run, recorded through a stand-in for its `subprocess` module.
final class RNGitDeleteHandlerVectorTests: XCTestCase {

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
    let request: MsgPack.Value
    let script: [Outcome?]
    let blocked: Bool
    let statsEnabled: Bool
    let statsIgnored: Bool
    let answer: String
    let calls: [Call]
    let pushes: Int
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
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: nil,
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "014e6f74206964656e746966696564",
      calls: [],
      pushes: 0),
    Vector(
      name: "request not a map",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .string("group/repo"),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "request nil",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .nil,
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "request a list",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .array([.string("group/repo")]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "request empty",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "024e6f207265706f7369746f727920737065636966696564",
      calls: [],
      pushes: 0),
    Vector(
      name: "repository not a string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .int(5)), (.string("ref"), .string("refs/heads/main"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0),
    Vector(
      name: "repository nil",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .nil), (.string("ref"), .string("refs/heads/main"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0),
    Vector(
      name: "write refused read granted",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "014e6f7420616c6c6f776564",
      calls: [],
      pushes: 0),
    Vector(
      name: "write and read refused",
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0),
    Vector(
      name: "write refused with a bad ref",
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .string("main"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0),
    Vector(
      name: "write refused with an unusable ref",
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .int(5))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0),
    Vector(
      name: "unknown repository",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/other")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0),
    Vector(
      name: "path without a group",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("repo")), (.string("ref"), .string("refs/heads/main"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0),
    Vector(
      name: "path with three parts",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("a/b/c")), (.string("ref"), .string("refs/heads/main"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0),
    Vector(
      name: "blocked identity",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: true,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0),
    Vector(
      name: "write granted by group",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [Call(["git", "update-ref", "-d", "refs/heads/main"], "<repo>")],
      pushes: 0),
    Vector(
      name: "write granted by admin",
      groupGrants: permissions(),
      repositoryGrants: permissions(admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [Call(["git", "update-ref", "-d", "refs/heads/main"], "<repo>")],
      pushes: 0),
    Vector(
      name: "write granted to another",
      groupGrants: permissions(),
      repositoryGrants: permissions(write: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0),
    Vector(
      name: "no ref given",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref empty",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .string(""))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .int(5))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref nil",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .nil)]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref bytes",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("ref"), .bytes(Data(pythonHex: "6162") ?? Data())),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref a list",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .array([.string("refs/heads/main")])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref a map",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .map([(.string("a"), .int(1))])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref true",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .bool(true))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref refused outright",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .string("-x/y"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref without a slash",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .string("main"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref outside refs",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .string("heads/main"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref beginning refs",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .string("refsx/main"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref padded",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("  refs/heads/main  ")),
      ]),
      script: [Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0),
    Vector(
      name: "ref a tag",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("ref"), .string("refs/tags/v1"))]),
      script: [Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [Call(["git", "update-ref", "-d", "refs/tags/v1"], "<repo>")],
      pushes: 0),
    Vector(
      name: "ref deleted",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [Call(["git", "update-ref", "-d", "refs/heads/main"], "<repo>")],
      pushes: 0),
    Vector(
      name: "delete failed",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [Outcome(128, "", "fatal: no\n")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff436f756c64206e6f742064656c65746520726566",
      calls: [Call(["git", "update-ref", "-d", "refs/heads/main"], "<repo>")],
      pushes: 0),
    Vector(
      name: "delete would not run",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [nil],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [Call(["git", "update-ref", "-d", "refs/heads/main"], "<repo>")],
      pushes: 0),
    Vector(
      name: "delete counted",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [Outcome(0, "", "")],
      blocked: false,
      statsEnabled: true,
      statsIgnored: false,
      answer: "00",
      calls: [Call(["git", "update-ref", "-d", "refs/heads/main"], "<repo>")],
      pushes: 1),
    Vector(
      name: "delete counted while ignored",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [Outcome(0, "", "")],
      blocked: false,
      statsEnabled: true,
      statsIgnored: true,
      answer: "00",
      calls: [Call(["git", "update-ref", "-d", "refs/heads/main"], "<repo>")],
      pushes: 1),
    Vector(
      name: "delete failed while counting",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("ref"), .string("refs/heads/main")),
      ]),
      script: [Outcome(128, "", "fatal: no\n")],
      blocked: false,
      statsEnabled: true,
      statsIgnored: false,
      answer: "ff436f756c64206e6f742064656c65746520726566",
      calls: [Call(["git", "update-ref", "-d", "refs/heads/main"], "<repo>")],
      pushes: 0),
  ]

  private static let identityA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  /// Every request is answered as the reference answered it, having run what it ran.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-delete-" + UUID().uuidString
      let path = root + "/repo"
      try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }

      var repository = RNGitRepository(name: "repo", path: path)
      repository.permissions = vector.repositoryGrants
      var group = RNGitGroup(name: "group", path: root)
      group.permissions = vector.groupGrants
      group.repositories["repo"] = repository
      let identity = try XCTUnwrap(Data(pythonHex: Self.identityA), vector.name)

      var settings = RNGitNodeSettings()
      settings.statsEnabled = vector.statsEnabled
      settings.statsIgnored = vector.statsIgnored ? [identity] : []

      let runner = ScriptedRunner(vector.script)
      var handler = RNGitDeleteHandler(
        access: RNGitAccessControl(
          groups: ["group": group], blockedIdentities: vector.blocked ? [identity] : []),
        runner: runner, settings: settings)

      let answer = handler.handle(
        vector.request, from: vector.identity.flatMap { Data(pythonHex: $0) })
      let described = answer.map { $0.encoded.hexString } ?? "RAISED"
      XCTAssertEqual(described, vector.answer, vector.name)
      XCTAssertEqual(Self.normalised(runner.calls, at: path), vector.calls, vector.name)

      let counters = handler.statistics.groups["group"]?.repositories["repo"]
      XCTAssertEqual(counters?.push[RNGitStatsStore.day()] ?? 0, vector.pushes, vector.name)
    }
  }

  /// The calls with the repository path replaced by the name the vectors use.
  private static func normalised(_ calls: [Call], at path: String) -> [Call] {
    calls.map { Call($0.argv, $0.directory == path ? "<repo>" : $0.directory) }
  }
}
