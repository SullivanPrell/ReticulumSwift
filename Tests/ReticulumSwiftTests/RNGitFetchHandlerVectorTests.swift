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

/// The bundles a node builds for a fetch, as Python RNS 1.5.4 builds them.
///
/// Each vector is what the reference's own handler answered, along with every command it
/// would have run, recorded through a stand-in for its `subprocess` module.
final class RNGitFetchHandlerVectorTests: XCTestCase {

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
      if outcome.status == 0, arguments.starts(with: ["bundle", "create"]) {
        FileManager.default.createFile(atPath: arguments[3], contents: Data("bundle".utf8))
      }
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
    let link: String
    let request: MsgPack.Value
    let script: [Outcome?]
    let blocked: Bool
    let statsEnabled: Bool
    let statsIgnored: Bool
    let answer: String?
    let calls: [Call]
    let fetches: Int
    let temporaries: Int
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
      name: "link unknown",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "dddddddddddddddd",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "014e6f74206964656e746966696564",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "no identity",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: nil,
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "014e6f74206964656e746966696564",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "request not a map",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .string("group/repo"),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "request nil",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .nil,
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "request empty",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "024e6f207265706f7369746f727920737065636966696564",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "repository not a string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .int(5)),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "read refused",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["nobody"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "unknown repository",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/other")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "path without a group",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "blocked identity",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: true,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "no refs field",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "024e6f207265667320737065636966696564",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "refs empty",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([(.int(0), .string("group/repo")), (.string("refs"), .array([]))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "024e6f207265667320737065636966696564",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "refs empty string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([(.int(0), .string("group/repo")), (.string("refs"), .string(""))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "024e6f207265667320737065636966696564",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "refs a string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")), (.string("refs"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "refs an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([(.int(0), .string("group/repo")), (.string("refs"), .int(3))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "refs names only",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")), (.string("refs"), .array([.string("refs/heads/main")])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "refs a map",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .map([(.string("refs/heads/main"), .int(1))])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "ref entry without a name",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([.map([(.string("have"), .string("1111111111111111111111111111111111111111"))])])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "ref name not a string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .int(5))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "ref name refused",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("-x/y"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "ref name without a slash",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      fetches: 0,
      temporaries: 0),
    Vector(
      name: "one ref",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: true,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>")
      ],
      fetches: 1,
      temporaries: 1),
    Vector(
      name: "three refs",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([(.string("ref"), .string("refs/heads/main"))]),
            .map([(.string("ref"), .string("refs/heads/topic"))]),
            .map([(.string("ref"), .string("refs/tags/v1"))]),
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: true,
      statsIgnored: true,
      answer: "FILE",
      calls: [
        Call(
          [
            "git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main",
            "refs/heads/topic", "refs/tags/v1",
          ], "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have held",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (.string("have"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [Outcome(0, "commit", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(
          [
            "git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main",
            "^1111111111111111111111111111111111111111",
          ], "<repo>"),
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have absent",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (.string("have"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [Outcome(128, "", "fatal: Not a valid object name\n")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>"),
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have short",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([(.string("ref"), .string("refs/heads/main")), (.string("have"), .string("abc"))])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420534841",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([.map([(.string("ref"), .string("refs/heads/main")), (.string("have"), .int(5))])])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have false",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([(.string("ref"), .string("refs/heads/main")), (.string("have"), .bool(false))])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have empty",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([(.string("ref"), .string("refs/heads/main")), (.string("have"), .string(""))])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have bytes",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (
                .string("have"),
                .bytes(
                  Data(
                    pythonHex:
                      "31313131313131313131313131313131313131313131313131313131313131313131313131313131"
                  ) ?? Data())
              ),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420534841",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have a list",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (
                .string("have"),
                .array([
                  .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1),
                  .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1),
                  .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1),
                  .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1), .int(1),
                  .int(1), .int(1), .int(1), .int(1),
                ])
              ),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420534841",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have not hex",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (.string("have"), .string("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420534841",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have odd length",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (.string("have"), .string("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420534841",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have spaced hex",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (
                .string("have"),
                .string("aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb ")
              ),
            ])
          ])
        ),
      ]),
      script: [Outcome(0, "commit", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(
          [
            "git", "cat-file", "-t", "aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb ",
          ], "<repo>"),
        Call(
          [
            "git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main",
            "^aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb aa bb ",
          ], "<repo>"),
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "ref have and global have",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (.string("have"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ), (.string("have"), .array([.string("2222222222222222222222222222222222222222")])),
      ]),
      script: [Outcome(0, "commit", ""), Outcome(0, "commit", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "cat-file", "-t", "2222222222222222222222222222222222222222"], "<repo>"),
        Call(
          [
            "git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main",
            "^1111111111111111111111111111111111111111",
            "^2222222222222222222222222222222222222222",
          ], "<repo>"),
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "global have absent",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
        (.string("have"), .array([.string("2222222222222222222222222222222222222222")])),
      ]),
      script: [Outcome(128, "", "fatal: Not a valid object name\n")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(["git", "cat-file", "-t", "2222222222222222222222222222222222222222"], "<repo>"),
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>"),
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "global have empty",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
        (.string("have"), .array([])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "global have a string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
        (.string("have"), .string("1111111111111111111111111111111111111111")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420534841",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "global have an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
        (.string("have"), .int(7)),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "global have bytes",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
        (.string("have"), .bytes(Data(pythonHex: "0102") ?? Data())),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "global have false",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
        (.string("have"), .bool(false)),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "global have a map",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
        (.string("have"), .map([(.string("1111111111111111111111111111111111111111"), .int(1))])),
      ]),
      script: [Outcome(0, "commit", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(
          [
            "git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main",
            "^1111111111111111111111111111111111111111",
          ], "<repo>"),
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "bundle empty",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [Outcome(128, "", "fatal: Refusing to create empty bundle.\n")],
      blocked: false,
      statsEnabled: true,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "bundle empty mixed case",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [Outcome(128, "", "fatal: Refusing to create EMPTY BUNDLE.\n")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "bundle failed",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [Outcome(128, "", "fatal: bad revision\n")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff436f756c64206e6f742066657463682072656673",
      calls: [
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "bundle would not run",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [nil],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "cat-file would not run",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("refs"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (.string("have"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [nil],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "read granted by group",
      groupGrants: permissions(read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "FILE",
      calls: [
        Call(
          ["git", "bundle", "create", "--no-progress", "<tmp>/fetch.bundle", "refs/heads/main"],
          "<repo>")
      ],
      fetches: 0,
      temporaries: 1),
    Vector(
      name: "read granted to another",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      link: "cccccccccccccccc",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("refs"), .array([.map([(.string("ref"), .string("refs/heads/main"))])])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      fetches: 0,
      temporaries: 0),
  ]

  private static let identityA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  /// Every request is answered as the reference answered it, having run what it ran.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-fetch-" + UUID().uuidString
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
      var handler = RNGitFetchHandler(
        access: RNGitAccessControl(
          groups: ["group": group], blockedIdentities: vector.blocked ? [identity] : []),
        runner: runner, settings: settings,
        activeLinks: [try XCTUnwrap(Data(pythonHex: "cccccccccccccccc"))],
        temporaryRoot: root)

      let answer = handler.handle(
        vector.request, from: vector.identity.flatMap { Data(pythonHex: $0) },
        on: Data(pythonHex: vector.link))
      XCTAssertEqual(Self.describe(answer, under: root), vector.answer, vector.name)
      XCTAssertEqual(Self.normalised(runner.calls, under: root), vector.calls, vector.name)

      let held = try FileManager.default.contentsOfDirectory(atPath: root)
      XCTAssertEqual(
        held.filter { $0.hasPrefix("rngit-") }.count, vector.temporaries, vector.name)

      let counters = handler.statistics.groups["group"]?.repositories["repo"]
      XCTAssertEqual(
        counters?.fetch[RNGitStatsStore.day()] ?? 0, vector.fetches, vector.name)

      if case .file(let file) = answer {
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), vector.name)
        XCTAssertEqual(
          (file.path as NSString).deletingLastPathComponent, file.directory,
          vector.name)
      }
    }
  }

  /// The answer as the recorded vector spells it: the response bytes, or what it was.
  private static func describe(_ answer: RNGitAnswer?, under root: String) -> String {
    switch answer {
    case nil: return "RAISED"
    case .file: return "FILE"
    case .response(let response): return response.encoded.hexString
    }
  }

  /// The calls with the paths the handler chose replaced by the names the vectors use.
  private static func normalised(_ calls: [Call], under root: String) -> [Call] {
    calls.map { call in
      Call(
        call.argv.map { word in
          word.hasPrefix(root) && word.hasSuffix("/fetch.bundle")
            ? "<tmp>/fetch.bundle" : word
        },
        call.directory == root + "/repo" ? "<repo>" : call.directory)
    }
  }
}
