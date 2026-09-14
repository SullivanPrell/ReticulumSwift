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

/// The forks and mirrors a node synchronizes, as Python RNS 1.5.4 synchronizes them.
///
/// Each vector is what the reference's own handler answered, along with every command it
/// would have run, recorded through a stand-in for its `subprocess` module. The moment the
/// node records as the last synchronization is fixed, as it is in the reference's own
/// `time`.
final class RNGitSyncHandlerVectorTests: XCTestCase {

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
    let repositoryGrants: RNGitPermissionSet
    let identity: String?
    let fork: String?
    let mirror: String?
    let request: MsgPack.Value
    let script: [Outcome?]
    let blocked: Bool
    let answer: String
    let calls: [Call]
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
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: nil,
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      answer: "014e6f74206964656e746966696564",
      calls: []),
    Vector(
      name: "request not a map",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .string("group/repo"),
      script: [],
      blocked: false,
      answer: "02496e76616c69642072657175657374",
      calls: []),
    Vector(
      name: "request nil",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .nil,
      script: [],
      blocked: false,
      answer: "02496e76616c69642072657175657374",
      calls: []),
    Vector(
      name: "request empty",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([]),
      script: [],
      blocked: false,
      answer: "024e6f207265706f7369746f727920737065636966696564",
      calls: []),
    Vector(
      name: "repository not a string",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .int(5))]),
      script: [],
      blocked: false,
      answer: "RAISED",
      calls: []),
    Vector(
      name: "read refused",
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      answer: "034e6f7420666f756e64",
      calls: []),
    Vector(
      name: "write refused",
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      answer: "014e6f7420616c6c6f776564",
      calls: []),
    Vector(
      name: "unknown repository",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/other"))]),
      script: [],
      blocked: false,
      answer: "034e6f7420666f756e64",
      calls: []),
    Vector(
      name: "path without a group",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("repo"))]),
      script: [],
      blocked: false,
      answer: "034e6f7420666f756e64",
      calls: []),
    Vector(
      name: "blocked identity",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: true,
      answer: "034e6f7420666f756e64",
      calls: []),
    Vector(
      name: "neither fork nor mirror",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: nil,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      answer: "025265706f7369746f7279206973206e65697468657220666f726b206e6f72206d6972726f72",
      calls: []),
    Vector(
      name: "mirror source empty",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      answer: "025265706f7369746f7279206973206e65697468657220666f726b206e6f72206d6972726f72",
      calls: []),
    Vector(
      name: "fork source empty",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: "",
      mirror: nil,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      answer: "025265706f7369746f7279206973206e65697468657220666f726b206e6f72206d6972726f72",
      calls: []),
    Vector(
      name: "mirror source blank",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: " ",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", " ", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", " ", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror synced",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror fetch failed",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(128, "", "fatal: no\n")],
      blocked: false,
      answer: "ff4d6972726f722073796e63206661696c6564",
      calls: [Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>")]),
    Vector(
      name: "mirror fetch would not run",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [nil],
      blocked: false,
      answer: "ff4d6972726f722073796e63206661696c6564",
      calls: [Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>")]),
    Vector(
      name: "mirror remote head refused",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(0, "trunk\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror remote head would not run",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), nil, Outcome(0, "trunk\n", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror remote head without a tab",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\n", ""), Outcome(0, "trunk\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror remote head not for HEAD",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tOTHER\n", ""),
        Outcome(0, "trunk\n", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror remote head not a branch",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/tags/v1\tHEAD\n", ""), Outcome(0, "trunk\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror remote head after another line",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""),
        Outcome(0, "x\nref: refs/heads/one\tHEAD\nref: refs/heads/two\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/one"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/one"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror remote head padded",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main \t HEAD\n", ""),
        Outcome(0, "trunk\n", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror remote head carriage returned",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\r\n", ""), Outcome(0, "", ""),
        Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror branch absent locally",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(128, "", "fatal: no\n"), Outcome(0, "trunk\n", ""), Outcome(0, "", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror branch check would not run",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""), nil,
        Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror fallback empty",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(0, "  \n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror fallback failed",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(128, "trunk\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror fallback would not run",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), nil, Outcome(0, "", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror fallback padded",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(0, " \t trunk \r\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror head update failed",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror head update would not run",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), nil, Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror sync time refused",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "mirror sync time would not run",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: nil,
      mirror: "rns://source/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), nil,
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "fork synced",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: "rns://source/repo",
      mirror: nil,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "fork fetch failed",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: "rns://source/repo",
      mirror: nil,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(128, "", "fatal: no\n")],
      blocked: false,
      answer: "ff466f726b2073796e63206661696c6564",
      calls: [Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>")]),
    Vector(
      name: "fork fetch would not run",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: "rns://source/repo",
      mirror: nil,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [nil],
      blocked: false,
      answer: "ff466f726b2073796e63206661696c6564",
      calls: [Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>")]),
    Vector(
      name: "fork sync time refused",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: "rns://source/repo",
      mirror: nil,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(0, "", ""), Outcome(128, "", "fatal: no\n")],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "fork sync time would not run",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: "rns://source/repo",
      mirror: nil,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(0, "", ""), nil],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "fork and mirror",
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: "rns://source/repo",
      mirror: "rns://other/repo",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://other/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://other/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "write granted by admin",
      repositoryGrants: permissions(
        read: ["everyone"], admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      fork: "rns://source/repo",
      mirror: nil,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      answer: "00",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
  ]

  private static let identityA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  private static let now = 1_700_000_000

  /// Every request is answered as the reference answered it, having run what it ran.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-sync-" + UUID().uuidString
      let path = root + "/repo"
      try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }

      var repository = RNGitRepository(name: "repo", path: path)
      repository.permissions = vector.repositoryGrants
      repository.fork = vector.fork
      repository.mirror = vector.mirror
      var group = RNGitGroup(name: "group", path: root)
      group.repositories["repo"] = repository
      let identity = try XCTUnwrap(Data(pythonHex: Self.identityA), vector.name)

      let runner = ScriptedRunner(vector.script)
      let handler = RNGitSyncHandler(
        access: RNGitAccessControl(
          groups: ["group": group], blockedIdentities: vector.blocked ? [identity] : []),
        runner: runner, clock: { Self.now })

      let answer = handler.handle(
        vector.request, from: vector.identity.flatMap { Data(pythonHex: $0) })
      let described = answer.map { $0.encoded.hexString } ?? "RAISED"
      XCTAssertEqual(described, vector.answer, vector.name)
      XCTAssertEqual(Self.normalised(runner.calls, at: path), vector.calls, vector.name)
    }
  }

  /// The calls with the repository path replaced by the name the vectors use.
  private static func normalised(_ calls: [Call], at path: String) -> [Call] {
    calls.map { Call($0.argv, $0.directory == path ? "<repo>" : $0.directory) }
  }
}
