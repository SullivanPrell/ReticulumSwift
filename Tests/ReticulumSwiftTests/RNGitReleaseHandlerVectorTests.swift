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

/// The releases a node serves and records, as Python RNS 1.5.4 serves and records them.
///
/// Each vector is what the reference's own handler answered for a releases directory seeded
/// the same way, along with every command it would have run and everything it left behind,
/// recorded through stand-ins for its `subprocess` and `time` modules.
final class RNGitReleaseHandlerVectorTests: XCTestCase {

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

  /// One directory or file a vector starts from.
  private struct Entry {
    let kind: String
    let path: String
    let content: String

    init(_ kind: String, _ path: String, _ content: String = "") {
      self.kind = kind
      self.path = path
      self.content = content
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
    let registered: Bool
    let identity: String?
    let tree: [Entry]?
    let releasesAreAFile: Bool
    let request: MsgPack.Value
    let script: [Outcome?]
    let answer: String
    let calls: [Call]
    let left: [String]?
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
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: nil,
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer: "014e6f74206964656e746966696564",
      calls: [],
      left: []),
    Vector(
      name: "request not a map",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .string("group/repo"),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      left: []),
    Vector(
      name: "request nil",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .nil,
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      left: []),
    Vector(
      name: "no repository named",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.string("operation"), .string("list"))]),
      script: [],
      answer: "024e6f207265706f7369746f727920737065636966696564",
      calls: [],
      left: []),
    Vector(
      name: "operation missing",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      left: []),
    Vector(
      name: "operation empty",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string(""))]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      left: []),
    Vector(
      name: "operation nil",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .nil)]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      left: []),
    Vector(
      name: "repository not a string",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .int(5)), (.string("operation"), .string("list"))]),
      script: [],
      answer: "RAISED",
      calls: [],
      left: []),
    Vector(
      name: "read refused",
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      left: []),
    Vector(
      name: "release refused",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("create"))]),
      script: [],
      answer: "014e6f7420616c6c6f776564",
      calls: [],
      left: []),
    Vector(
      name: "delete refused",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("delete"))]),
      script: [],
      answer: "014e6f7420616c6c6f776564",
      calls: [],
      left: []),
    Vector(
      name: "latest refused",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("latest"))]),
      script: [],
      answer: "014e6f7420616c6c6f776564",
      calls: [],
      left: []),
    Vector(
      name: "operation unknown",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("frobnicate")),
      ]),
      script: [],
      answer: "014e6f7420616c6c6f776564",
      calls: [],
      left: []),
    Vector(
      name: "operation not a string",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .int(5))]),
      script: [],
      answer: "014e6f7420616c6c6f776564",
      calls: [],
      left: []),
    Vector(
      name: "repository not registered",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: false,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      left: []),
    Vector(
      name: "list without a releases directory",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer: "0090",
      calls: [],
      left: nil),
    Vector(
      name: "list an empty directory",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer: "0082a872656c656173657390a66c6174657374c0",
      calls: [],
      left: []),
    Vector(
      name: "list two releases",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"), Entry("d", "v2"),
        Entry("f", "v2/META", "tag = v2\ncreated = 200\nstatus = draft\n"),
        Entry("d", "v2/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739288a3746167a27632a468617368a0a763726561746564ccc8a6737461747573a56472616674aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea96172746966616374730088a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374a27631",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203", "d|v2",
        "b|v2/META|746167203d2076320a63726561746564203d203230300a737461747573203d2064726166740a",
        "d|v2/artifacts",
      ]),
    Vector(
      name: "list where latest is a draft",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v2\n"), Entry("d", "v2"),
        Entry("f", "v2/META", "tag = v2\ncreated = 200\nstatus = draft\n"),
        Entry("d", "v2/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739288a3746167a27632a468617368a0a763726561746564ccc8a6737461747573a56472616674aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea96172746966616374730088a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374c0",
      calls: [],
      left: [
        "b|latest|76320a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203", "d|v2",
        "b|v2/META|746167203d2076320a63726561746564203d203230300a737461747573203d2064726166740a",
        "d|v2/artifacts",
      ]),
    Vector(
      name: "list where latest is unknown",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v9\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374c0",
      calls: [],
      left: [
        "b|latest|76390a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "list skips a plain file",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
        Entry("f", "stray", "x"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374a27631",
      calls: [],
      left: [
        "b|latest|76310a", "b|stray|78", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "list skips a release without metadata",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"), Entry("d", "v3"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374a27631",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203", "d|v3",
      ]),
    Vector(
      name: "list skips metadata that is a directory",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"), Entry("d", "v3"),
        Entry("d", "v3/META"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374a27631",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203", "d|v3",
        "d|v3/META",
      ]),
    Vector(
      name: "list skips metadata that does not parse",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"), Entry("d", "v3"),
        Entry("f", "v3/META", "[[[broken\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374a27631",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203", "d|v3",
        "b|v3/META|5b5b5b62726f6b656e0a",
      ]),
    Vector(
      name: "list skips a creation moment that is not a number",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"), Entry("d", "v3"),
        Entry("f", "v3/META", "tag = v3\ncreated = soon\nstatus = published\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374a27631",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203", "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d20736f6f6e0a737461747573203d207075626c69736865640a",
      ]),
    Vector(
      name: "list a release with no creation moment",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\nstatus = published\n")],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27633a468617368a0a76372656174656400a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea961727469666163747300a66c6174657374c0",
      calls: [],
      left: ["d|v3", "b|v3/META|746167203d2076330a737461747573203d207075626c69736865640a"]),
    Vector(
      name: "list previews micron notes",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("f", "v3/RELEASE.mu", "# Title\n> quote\nbody line\nsecond line\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a66d6963726f6ea961727469666163747300a66c6174657374c0",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "b|v3/RELEASE.mu|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
      ]),
    Vector(
      name: "list previews text notes",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("f", "v3/RELEASE.txt", "# Title\n> quote\nbody line\nsecond line\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a474657874a961727469666163747300a66c6174657374c0",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "b|v3/RELEASE.txt|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
      ]),
    Vector(
      name: "list prefers markdown notes",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("f", "v3/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("f", "v3/RELEASE.mu", "other\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747300a66c6174657374c0",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "b|v3/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v3/RELEASE.mu|6f746865720a",
      ]),
    Vector(
      name: "list counts only artifact files",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("d", "v3/artifacts"), Entry("b", "v3/artifacts/one", "00"),
        Entry("d", "v3/artifacts/nested"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374c0",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "d|v3/artifacts", "d|v3/artifacts/nested", "b|v3/artifacts/one|00",
      ]),
    Vector(
      name: "list a release whose tag is a list",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = a, b\ncreated = 100\nstatus = published\n"),
        Entry("d", "v4"), Entry("f", "v4/META", "tag = v4\ncreated = 300\nstatus = published\n"),
        Entry("f", "latest", "v4\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739288a3746167a27634a468617368a0a763726561746564cd012ca6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea96172746966616374730088a374616792a161a162a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea961727469666163747300a66c6174657374a27634",
      calls: [],
      left: [
        "b|latest|76340a", "d|v3",
        "b|v3/META|746167203d20612c20620a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "d|v4",
        "b|v4/META|746167203d2076340a63726561746564203d203330300a737461747573203d207075626c69736865640a",
      ]),
    Vector(
      name: "list a release whose hash is a list",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"),
        Entry("f", "v3/META", "tag = v3\nhash = a, b\ncreated = 100\nstatus = published\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27633a46861736892a161a162a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea961727469666163747300a66c6174657374c0",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a68617368203d20612c20620a63726561746564203d203130300a737461747573203d207075626c69736865640a",
      ]),
    Vector(
      name: "list a release whose tag is a section",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"),
        Entry("f", "v3/META", "created = 100\nstatus = published\n[tag]\na = 1\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a374616781a161a131a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea961727469666163747300a66c6174657374c0",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|63726561746564203d203130300a737461747573203d207075626c69736865640a5b7461675d0a61203d20310a",
      ]),
    Vector(
      name: "list reads latest past its whitespace",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "  v1  \n\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374a27631",
      calls: [],
      left: [
        "b|latest|2020763120200a0a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "list where latest is a directory",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("d", "latest"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a770726576696577b5626f6479206c696e650a7365636f6e64206c696e65a6666f726d6174a86d61726b646f776ea961727469666163747301a66c6174657374c0",
      calls: [],
      left: [
        "d|latest", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "list a release with no tag or status recorded",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v3"), Entry("f", "v3/META", "created = 100\n")],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27633a468617368a0a76372656174656464a6737461747573a7756e6b6e6f776eaa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea961727469666163747300a66c6174657374c0",
      calls: [],
      left: ["d|v3", "b|v3/META|63726561746564203d203130300a"]),
    Vector(
      name: "list two releases created at the same moment",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 500\nstatus = published\n"),
        Entry("d", "v4"), Entry("f", "v4/META", "tag = v4\ncreated = 500\nstatus = published\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739288a3746167a27634a468617368a0a763726561746564cd01f4a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea96172746966616374730088a3746167a27633a468617368a0a763726561746564cd01f4a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea961727469666163747300a66c6174657374c0",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203530300a737461747573203d207075626c69736865640a",
        "d|v4",
        "b|v4/META|746167203d2076340a63726561746564203d203530300a737461747573203d207075626c69736865640a",
      ]),
    Vector(
      name: "list previews notes that do not decode",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("b", "v3/RELEASE.txt", "ff"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      script: [],
      answer:
        "0082a872656c65617365739188a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a770726576696577a0a6666f726d6174a86d61726b646f776ea961727469666163747300a66c6174657374c0",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "b|v3/RELEASE.txt|ff",
      ]),
    Vector(
      name: "view without a tag",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("view"))]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view a tag holding a separator",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("a/b")),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view a tag that is a number",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .int(5)),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view a tag that is zero",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .int(0)),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view a tag that is a list",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .array([.string("x")])),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view a tag that is an empty list",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .array([])),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view a tag that is a list holding a separator",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .array([.string("/")])),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view latest with none recorded",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("latest")),
      ]),
      script: [],
      answer: "034e6f206c61746573742072656c6561736520666f756e64",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view latest recorded as nothing",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("latest")),
      ]),
      script: [],
      answer: "034e6f206c61746573742072656c6561736520666f756e64",
      calls: [],
      left: [
        "b|latest|0a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view latest naming a draft",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v2\n"), Entry("d", "v2"),
        Entry("f", "v2/META", "tag = v2\ncreated = 200\nstatus = draft\n"),
        Entry("d", "v2/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("latest")),
      ]),
      script: [],
      answer:
        "0089a3746167a27632a468617368a0a763726561746564ccc8a6737461747573a56472616674aa637265617465645f6279a0a56e6f746573a0ac6e6f7465735f666f726d6174a474657874a961727469666163747390a67468616e6b7300",
      calls: [],
      left: [
        "b|latest|76320a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203", "d|v2",
        "b|v2/META|746167203d2076320a63726561746564203d203230300a737461747573203d2064726166740a",
        "d|v2/artifacts",
      ]),
    Vector(
      name: "view latest recorded as an absolute path",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "/usr\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("latest")),
      ]),
      script: [],
      answer: "ff4572726f722067657474696e672072656c656173652064617461",
      calls: [],
      left: [
        "b|latest|2f7573720a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view latest naming a missing release",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v9\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("latest")),
      ]),
      script: [],
      answer: "0352656c65617365206e6f7420666f756e64",
      calls: [],
      left: [
        "b|latest|76390a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view an unknown tag",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v9")),
      ]),
      script: [],
      answer: "0352656c65617365206e6f7420666f756e64",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view a release without metadata",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v3")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer: "ff4572726f722067657474696e672072656c656173652064617461",
      calls: [],
      left: ["d|v3"]),
    Vector(
      name: "view metadata that does not parse",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v3"), Entry("f", "v3/META", "[[[broken\n")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer: "ff4572726f722067657474696e672072656c656173652064617461",
      calls: [],
      left: ["d|v3", "b|v3/META|5b5b5b62726f6b656e0a"]),
    Vector(
      name: "view a creation moment that is not a number",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = soon\nstatus = published\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer: "ff4572726f722067657474696e672072656c656173652064617461",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d20736f6f6e0a737461747573203d207075626c69736865640a",
      ]),
    Vector(
      name: "view a full release",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer:
        "0089a3746167a27631a468617368a6616263313233a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279d9206161616161616161616161616161616161616161616161616161616161616161a56e6f746573d92623205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650aac6e6f7465735f666f726d6174a86d61726b646f776ea96172746966616374739182a46e616d65a5612e62696ea473697a6503a67468616e6b7307",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "view micron notes",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("f", "v3/RELEASE.mu", "# Title\n> quote\nbody line\nsecond line\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer:
        "0089a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a56e6f746573d92623205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650aac6e6f7465735f666f726d6174a66d6963726f6ea961727469666163747390a67468616e6b7300",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "b|v3/RELEASE.mu|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
      ]),
    Vector(
      name: "view prefers markdown notes",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("f", "v3/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("f", "v3/RELEASE.mu", "other\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer:
        "0089a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a56e6f746573d92623205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650aac6e6f7465735f666f726d6174a86d61726b646f776ea961727469666163747390a67468616e6b7300",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "b|v3/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v3/RELEASE.mu|6f746865720a",
      ]),
    Vector(
      name: "view a release with no notes",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer:
        "0089a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a56e6f746573a0ac6e6f7465735f666f726d6174a474657874a961727469666163747390a67468616e6b7300",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
      ]),
    Vector(
      name: "view thanks that do not parse",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("b", "v3/THANKS", "c1"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer:
        "0089a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a56e6f746573a0ac6e6f7465735f666f726d6174a474657874a961727469666163747390a67468616e6b7300",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "b|v3/THANKS|c1",
      ]),
    Vector(
      name: "view thanks holding no count",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("b", "v3/THANKS", "81a56f7468657201"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer:
        "0089a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a56e6f746573a0ac6e6f7465735f666f726d6174a474657874a961727469666163747390a67468616e6b7300",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "b|v3/THANKS|81a56f7468657201",
      ]),
    Vector(
      name: "view lists only artifact files",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = v3\ncreated = 100\nstatus = published\n"),
        Entry("d", "v3/artifacts"), Entry("b", "v3/artifacts/one", "00010203"),
        Entry("d", "v3/artifacts/nested"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer:
        "0089a3746167a27633a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a56e6f746573a0ac6e6f7465735f666f726d6174a474657874a96172746966616374739182a46e616d65a36f6e65a473697a6504a67468616e6b7300",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d2076330a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "d|v3/artifacts", "d|v3/artifacts/nested", "b|v3/artifacts/one|00010203",
      ]),
    Vector(
      name: "view a metadata tag that is a list",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"), Entry("f", "v3/META", "tag = a, b\ncreated = 100\nstatus = published\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer:
        "0089a374616792a161a162a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a56e6f746573a0ac6e6f7465735f666f726d6174a474657874a961727469666163747390a67468616e6b7300",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|746167203d20612c20620a63726561746564203d203130300a737461747573203d207075626c69736865640a",
      ]),
    Vector(
      name: "view a metadata tag that is a section",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v3"),
        Entry("f", "v3/META", "created = 100\nstatus = published\n[tag]\na = 1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("tag"), .string("v3")),
      ]),
      script: [],
      answer:
        "0089a374616781a161a131a468617368a0a76372656174656464a6737461747573a97075626c6973686564aa637265617465645f6279a0a56e6f746573a0ac6e6f7465735f666f726d6174a474657874a961727469666163747390a67468616e6b7300",
      calls: [],
      left: [
        "d|v3",
        "b|v3/META|63726561746564203d203130300a737461747573203d207075626c69736865640a5b7461675d0a61203d20310a",
      ]),
    Vector(
      name: "fetch without a tag",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("artifact"), .string("a.bin")),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch a tag holding a separator",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("a/b")), (.string("artifact"), .string("a.bin")),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch without an artifact",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "02496e76616c696420617274696661637420737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch an artifact holding a separator",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("v1")), (.string("artifact"), .string("a/b")),
      ]),
      script: [],
      answer: "02496e76616c696420617274696661637420737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch an artifact that is a number",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("v1")), (.string("artifact"), .int(5)),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch an artifact that is zero",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("v1")), (.string("artifact"), .int(0)),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch latest with none recorded",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("latest")), (.string("artifact"), .string("a.bin")),
      ]),
      script: [],
      answer: "034e6f206c61746573742072656c6561736520666f756e64",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch an unknown release",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("v9")), (.string("artifact"), .string("a.bin")),
      ]),
      script: [],
      answer: "0352656c65617365206e6f7420666f756e64",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch an unknown artifact",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("v1")), (.string("artifact"), .string("b.bin")),
      ]),
      script: [],
      answer: "034172746966616374206e6f7420666f756e64",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch an artifact that is a directory",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
        Entry("d", "v1/artifacts/nested"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("v1")), (.string("artifact"), .string("nested")),
      ]),
      script: [],
      answer: "034172746966616374206e6f7420666f756e64",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
        "d|v1/artifacts/nested",
      ]),
    Vector(
      name: "fetch an artifact",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("v1")), (.string("artifact"), .string("a.bin")),
      ]),
      script: [],
      answer: "FILE|v1/artifacts/a.bin|a.bin|010203|-",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "fetch the latest artifact",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("fetch")),
        (.string("tag"), .string("latest")), (.string("artifact"), .string("a.bin")),
      ]),
      script: [],
      answer: "FILE|v1/artifacts/a.bin|a.bin|010203|-",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "create without a step",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("create"))]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      left: []),
    Vector(
      name: "create with a step that is empty",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("")),
      ]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      left: []),
    Vector(
      name: "create with an unknown step",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("bogus")),
      ]),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      left: []),
    Vector(
      name: "init without a tag",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: []),
    Vector(
      name: "init with a tag holding a separator",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("a/b")),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: []),
    Vector(
      name: "init with a tag naming this directory",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string(".")),
      ]),
      script: [],
      answer: "02496e76616c696420746167206e616d65",
      calls: [],
      left: []),
    Vector(
      name: "init with a tag naming the directory above",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("..")),
      ]),
      script: [],
      answer: "02496e76616c696420746167206e616d65",
      calls: [],
      left: []),
    Vector(
      name: "init with a tag that is a number",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .int(5)),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: []),
    Vector(
      name: "init with a tag that is zero",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .int(0)),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: []),
    Vector(
      name: "init with a tag the repository does not hold",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
      ]),
      script: [Outcome(1, "", "fatal: Needed a single revision\n")],
      answer: "02546167202776312720646f6573206e6f7420657869737420696e207265706f7369746f7279",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: []),
    Vector(
      name: "init where git will not run",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
      ]),
      script: [nil],
      answer: "ff52656d6f7465206572726f72",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: []),
    Vector(
      name: "init where the release is already there",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = published\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "0152656c6561736520616c726561647920657869737473",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "init with notes",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
        (.string("notes"), .string("# Title\n> quote\nbody line\nsecond line\n")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "00",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7400", "d|v1/artifacts",
      ]),
    Vector(
      name: "init with micron notes",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
        (.string("notes"), .string("# Title\n> quote\nbody line\nsecond line\n")),
        (.string("notes_format"), .string("micron")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "00",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.mu|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7400", "d|v1/artifacts",
      ]),
    Vector(
      name: "init with notes in another markup",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
        (.string("notes"), .string("# Title\n> quote\nbody line\nsecond line\n")),
        (.string("notes_format"), .string("html")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "00",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7400", "d|v1/artifacts",
      ]),
    Vector(
      name: "init without notes",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "00",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/THANKS|81a5636f756e7400", "d|v1/artifacts",
      ]),
    Vector(
      name: "init with a hash",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
        (.string("hash"), .string("abc123")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "00",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/THANKS|81a5636f756e7400", "d|v1/artifacts",
      ]),
    Vector(
      name: "init with a hash that is a number",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
        (.string("hash"), .int(42)),
      ]),
      script: [Outcome(0, "", "")],
      answer: "00",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a68617368203d2034320a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/THANKS|81a5636f756e7400", "d|v1/artifacts",
      ]),
    Vector(
      name: "init with a hash that is bytes",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
        (.string("hash"), .bytes(Data(pythonHex: "00ff") ?? Data())),
      ]),
      script: [Outcome(0, "", "")],
      answer: "00",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a68617368203d202262275c7830305c78666627220a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/THANKS|81a5636f756e7400", "d|v1/artifacts",
      ]),
    Vector(
      name: "init with a hash that is not ASCII",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
        (.string("hash"), .string("r\u{E9}sum\u{E9}")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "ff52656d6f7465206572726f72",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: ["d|v1", "d|v1/artifacts"]),
    Vector(
      name: "init with notes that are a number",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
        (.string("notes"), .int(5)),
      ]),
      script: [Outcome(0, "", "")],
      answer: "ff52656d6f7465206572726f72",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|", "d|v1/artifacts",
      ]),
    Vector(
      name: "init where the releases path is a file",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: nil,
      releasesAreAFile: true,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "ff52656d6f7465206572726f72",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: nil),
    Vector(
      name: "init beside another release",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = published\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v2")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "00",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v2"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "d|v1/artifacts", "d|v2",
        "b|v2/META|746167203d2076320a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v2/THANKS|81a5636f756e7400", "d|v2/artifacts",
      ]),
    Vector(
      name: "init recorded under an identity holding a low byte",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "0b1c1c1c1c1c1c1cd00e0e0e0e0e0e0e",
      tree: nil,
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("init")), (.string("tag"), .string("v1")),
      ]),
      script: [Outcome(0, "", "")],
      answer: "00",
      calls: [Call(["git", "rev-parse", "--verify", "refs/tags/v1"], "<repo>")],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d20313730303030303030300a737461747573203d2064726166740a637265617465645f6279203d2030623163316331633163316331633163643030653065306530653065306530650a",
        "b|v1/THANKS|81a5636f756e7400", "d|v1/artifacts",
      ]),
    Vector(
      name: "artifact without a tag",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "024d697373696e6720746167206f72206172746966616374206e616d65",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "artifact without a name",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "024d697373696e6720746167206f72206172746966616374206e616d65",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "artifact with a tag holding a separator",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("a/b")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "artifact without data",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
      ]),
      script: [],
      answer: "024e6f2061727469666163742064617461",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "artifact with data that is nothing",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")), (.string("artifact_data"), .nil),
      ]),
      script: [],
      answer: "024e6f2061727469666163742064617461",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "artifact for a release that is not there",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "0352656c65617365206e6f7420666f756e64",
      calls: [],
      left: []),
    Vector(
      name: "artifact named as bytes for a release that is not there",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .bytes(Data(pythonHex: "612e62696e") ?? Data())),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "0352656c65617365206e6f7420666f756e64",
      calls: [],
      left: []),
    Vector(
      name: "artifact named as a number for a release that is not there",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .int(5)),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: []),
    Vector(
      name: "artifact named as bytes in a draft",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .bytes(Data(pythonHex: "612e62696e") ?? Data())),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "artifact for a published release",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = published\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer:
        "0152656c65617365207761732066696e616c697a656420616e64206973206e6f74207772697461626c65",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "artifact where metadata is missing",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v1")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer:
        "0152656c65617365207761732066696e616c697a656420616e64206973206e6f74207772697461626c65",
      calls: [],
      left: ["d|v1"]),
    Vector(
      name: "artifact where metadata does not parse",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v1"), Entry("f", "v1/META", "[[[broken\n")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: ["d|v1", "b|v1/META|5b5b5b62726f6b656e0a"]),
    Vector(
      name: "artifact stored as bytes",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "010203") ?? Data())),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "artifact stored as text",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.txt")), (.string("artifact_data"), .string("hello")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts", "b|v1/artifacts/a.txt|68656c6c6f",
      ]),
    Vector(
      name: "artifact stored as nothing at all",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "") ?? Data())),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts", "b|v1/artifacts/a.bin|",
      ]),
    Vector(
      name: "artifact stored under its last name",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("../evil")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts", "b|v1/artifacts/evil|0102",
      ]),
    Vector(
      name: "artifact stored under its last name past two separators",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a/b/c.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts", "b|v1/artifacts/c.bin|0102",
      ]),
    Vector(
      name: "artifact with data that is a list",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .array([.string("x")])),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts", "b|v1/artifacts/a.bin|",
      ]),
    Vector(
      name: "artifact where the artifacts directory is missing",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts", "b|v1/artifacts/a.bin|0102",
      ]),
    Vector(
      name: "artifact replacing one already stored",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "ffffffff"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("artifact")), (.string("tag"), .string("v1")),
        (.string("artifact_name"), .string("a.bin")),
        (.string("artifact_data"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts", "b|v1/artifacts/a.bin|0102",
      ]),
    Vector(
      name: "finalize without a tag",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")),
      ]),
      script: [],
      answer: "024e6f2074616720737065636966696564",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "finalize a tag holding a separator",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("a/b")),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d2064726166740a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "finalize a release that is not there",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "0352656c65617365206e6f7420666f756e64",
      calls: [],
      left: []),
    Vector(
      name: "finalize a published release",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = published\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer:
        "0152656c65617365207761732066696e616c697a656420616e64206973206e6f74207772697461626c65",
      calls: [],
      left: [
        "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d207075626c69736865640a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "finalize where metadata is missing",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v1")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer:
        "0152656c65617365207761732066696e616c697a656420616e64206973206e6f74207772697461626c65",
      calls: [],
      left: ["d|v1"]),
    Vector(
      name: "finalize where metadata does not parse",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v1"), Entry("f", "v1/META", "[[[broken\n")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: ["d|v1", "b|v1/META|5b5b5b62726f6b656e0a"]),
    Vector(
      name: "finalize a draft",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds a list",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = a, b\ncreated = 100\nstatus = draft\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d20612c20620a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds one value as a list",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v1"), Entry("f", "v1/META", "tag = a,\ncreated = 100\nstatus = draft\n")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d20612c0a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata opens a section",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "created = 100\nstatus = draft\n[extra]\na = 1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a5b65787472615d0a61203d20310a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds a value needing quotes",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = \" v1 \"\ncreated = 100\nstatus = draft\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d202220763120220a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds an empty value",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v1"), Entry("f", "v1/META", "tag =\ncreated = 100\nstatus = draft\n")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d2022220a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds an empty list",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v1"), Entry("f", "v1/META", "tag = ,\ncreated = 100\nstatus = draft\n")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d202c0a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds a value with a comma",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = \"a, b\"\ncreated = 100\nstatus = draft\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d2022612c2062220a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds a value with a number sign",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = \"a#b\"\ncreated = 100\nstatus = draft\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d2022612362220a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds a value over several lines",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry("f", "v1/META", "tag = \"\"\"a\nb\"\"\"\ncreated = 100\nstatus = draft\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d20272727610a622727270a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds a value holding triple quotes",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry("f", "v1/META", "tag = '''a\"\"\"b'''\ncreated = 100\nstatus = draft\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d2061222222620a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds both kinds of quote",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry("f", "v1/META", "tag = \"\"\"it's \"q\" \"\"\"\ncreated = 100\nstatus = draft\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d202727276974277320227122202727270a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata holds triple quotes over several lines",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry("f", "v1/META", "tag = '''a\"\"\"b\nc'''\ncreated = 100\nstatus = draft\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d2022222261222222620a632222220a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
      ]),
    Vector(
      name: "finalize a draft whose metadata opens a section within a section",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry("f", "v1/META", "created = 100\nstatus = draft\n[extra]\n[[inner]]\nb = 2\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a5b65787472615d0a5b5b696e6e65725d5d0a62203d20320a",
      ]),
    Vector(
      name: "finalize where the latest cannot be recorded",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"), Entry("d", "latest.tmp"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "d|latest.tmp", "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "finalize replacing the latest",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"), Entry("f", "v1/META", "tag = v1\ncreated = 100\nstatus = draft\n"),
        Entry("d", "v1/artifacts"), Entry("f", "latest", "v0\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("step"), .string("finalize")), (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7631", "d|v1",
        "b|v1/META|746167203d2076310a63726561746564203d203130300a737461747573203d207075626c69736865640a7075626c69736865645f6174203d20313730303030303030300a",
        "d|v1/artifacts",
      ]),
    Vector(
      name: "delete without a tag",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("delete"))]),
      script: [],
      answer: "024e6f2074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "delete a tag holding a separator",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("tag"), .string("a/b")),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "delete a release that is not there",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("tag"), .string("v9")),
      ]),
      script: [],
      answer: "0352656c65617365206e6f7420666f756e64",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "delete a release",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: ["b|latest|76310a"]),
    Vector(
      name: "delete a release that cannot be removed",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [Entry("d", "v1"), Entry("m", "", "500")],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: ["d|v1"]),
    Vector(
      name: "latest without a tag",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("latest"))]),
      script: [],
      answer: "024e6f2074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "latest for a tag holding a separator",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("latest")),
        (.string("tag"), .string("a/b")),
      ]),
      script: [],
      answer: "02496e76616c69642074616720737065636966696564",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "latest for a release that is not there",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("latest")),
        (.string("tag"), .string("v9")),
      ]),
      script: [],
      answer: "0352656c65617365206e6f7420666f756e64",
      calls: [],
      left: [
        "b|latest|76310a", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
    Vector(
      name: "latest for a draft",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"), Entry("d", "v2"),
        Entry("f", "v2/META", "tag = v2\ncreated = 200\nstatus = draft\n"),
        Entry("d", "v2/artifacts"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("latest")),
        (.string("tag"), .string("v2")),
      ]),
      script: [],
      answer: "00",
      calls: [],
      left: [
        "b|latest|7632", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203", "d|v2",
        "b|v2/META|746167203d2076320a63726561746564203d203230300a737461747573203d2064726166740a",
        "d|v2/artifacts",
      ]),
    Vector(
      name: "latest where it cannot be recorded",
      groupGrants: permissions(read: ["everyone"], release: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      tree: [
        Entry("d", "v1"),
        Entry(
          "f", "v1/META",
          "tag = v1\nhash = abc123\ncreated = 100\nstatus = published\ncreated_by = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
        ), Entry("d", "v1/artifacts"), Entry("b", "v1/artifacts/a.bin", "010203"),
        Entry("f", "v1/RELEASE.md", "# Title\n> quote\nbody line\nsecond line\n"),
        Entry("b", "v1/THANKS", "81a5636f756e7407"), Entry("f", "latest", "v1\n"),
        Entry("d", "latest.tmp"),
      ],
      releasesAreAFile: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("latest")),
        (.string("tag"), .string("v1")),
      ]),
      script: [],
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      left: [
        "b|latest|76310a", "d|latest.tmp", "d|v1",
        "b|v1/META|746167203d2076310a68617368203d206162633132330a63726561746564203d203130300a737461747573203d207075626c69736865640a637265617465645f6279203d2061616161616161616161616161616161616161616161616161616161616161610a",
        "b|v1/RELEASE.md|23205469746c650a3e2071756f74650a626f6479206c696e650a7365636f6e64206c696e650a",
        "b|v1/THANKS|81a5636f756e7407", "d|v1/artifacts", "b|v1/artifacts/a.bin|010203",
      ]),
  ]

  /// Every request is answered as the reference answered it, having run what it ran and
  /// left what it left.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-release-" + UUID().uuidString
      let groupPath = root + "/group"
      let repositoryPath = groupPath + "/repo"
      let releasesPath = repositoryPath + ".releases"
      try FileManager.default.createDirectory(
        atPath: repositoryPath, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }

      if vector.releasesAreAFile {
        try "not a directory\n".write(
          toFile: releasesPath, atomically: false, encoding: .utf8)
      } else if let tree = vector.tree {
        try Self.seed(releasesPath, tree)
      }

      var group = RNGitGroup(name: "group", path: groupPath)
      group.permissions = vector.groupGrants
      if vector.registered {
        var repository = RNGitRepository(name: "repo", path: repositoryPath)
        repository.permissions = vector.repositoryGrants
        group.repositories["repo"] = repository
      }

      let runner = ScriptedRunner(vector.script)
      let handler = RNGitReleaseHandler(
        access: RNGitAccessControl(groups: ["group": group]), runner: runner,
        clock: { 1_700_000_000 })

      let answer = handler.handle(
        vector.request, from: vector.identity.flatMap { Data(pythonHex: $0) })
      Self.relax(releasesPath, vector.tree)
      XCTAssertEqual(Self.described(answer, under: releasesPath), vector.answer, vector.name)
      XCTAssertEqual(
        Self.normalised(runner.calls, at: repositoryPath), vector.calls, vector.name)
      XCTAssertEqual(Self.snapshot(releasesPath), vector.left, vector.name)
    }
  }

  /// Builds `tree` under `root`, which the entries are named against.
  ///
  /// What an entry narrows the permissions to is set once the whole tree is in place.
  private static func seed(_ root: String, _ tree: [Entry]) throws {
    try FileManager.default.createDirectory(
      atPath: root, withIntermediateDirectories: true)
    for entry in tree {
      let path = root + "/" + entry.path
      switch entry.kind {
      case "d":
        try FileManager.default.createDirectory(
          atPath: path, withIntermediateDirectories: false)
      case "f": try entry.content.write(toFile: path, atomically: false, encoding: .utf8)
      case "m": break
      default:
        FileManager.default.createFile(
          atPath: path, contents: Data(pythonHex: entry.content) ?? Data())
      }
    }
    for entry in tree where entry.kind == "m" {
      try FileManager.default.setAttributes(
        [.posixPermissions: Int(entry.content, radix: 8) ?? 0o755],
        ofItemAtPath: named(root, entry.path))
    }
  }

  /// Puts back the permissions a tree narrowed, so what it left can be read and removed.
  private static func relax(_ root: String, _ tree: [Entry]?) {
    for entry in tree ?? [] where entry.kind == "m" {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: named(root, entry.path))
    }
  }

  /// `root` itself where `path` names nothing, and what it names otherwise.
  private static func named(_ root: String, _ path: String) -> String {
    path.isEmpty ? root : root + "/" + path
  }

  /// The answer as the vectors write it, with a file named against `root`.
  private static func described(_ answer: RNGitAnswer?, under root: String) -> String {
    switch answer {
    case .none: return "RAISED"
    case .response(let response): return response.encoded.hexString
    case .file(let file):
      let content = FileManager.default.contents(atPath: file.path) ?? Data()
      var name = ""
      if case .name(let named) = file.metadata { name = named }
      let relative =
        file.path.hasPrefix(root + "/")
        ? String(file.path.dropFirst(root.count + 1)) : file.path
      return "FILE|\(relative)|\(name)|\(content.hexString)|\(file.directory ?? "-")"
    }
  }

  /// Every directory and file under `root`, or `nil` where there is no directory at all.
  private static func snapshot(_ root: String) -> [String]? {
    guard RNGitReleaseStore.isDirectory(root) else { return nil }
    var found: [(path: String, kind: String, line: String)] = []
    var pending = [""]
    while let relative = pending.popLast() {
      let directory = relative.isEmpty ? root : root + "/" + relative
      guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory)
      else { continue }
      for entry in entries {
        let path = relative.isEmpty ? entry : relative + "/" + entry
        if RNGitReleaseStore.isDirectory(directory + "/" + entry) {
          found.append((path, "d", "d|" + path))
          pending.append(path)
        } else {
          let bytes = FileManager.default.contents(atPath: directory + "/" + entry) ?? Data()
          found.append((path, "b", "b|" + path + "|" + bytes.hexString))
        }
      }
    }
    return
      found
      .sorted { $0.path == $1.path ? $0.kind < $1.kind : $0.path < $1.path }
      .map(\.line)
  }

  /// The calls with the repository path replaced by the name the vectors use.
  private static func normalised(_ calls: [Call], at path: String) -> [Call] {
    calls.map { Call($0.argv, $0.directory == path ? "<repo>" : $0.directory) }
  }
}
