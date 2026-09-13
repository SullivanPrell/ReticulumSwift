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

/// The repositories a node clones from elsewhere, as Python RNS 1.5.4 clones them.
///
/// Each vector is what the reference's own handler answered, along with every command it
/// would have run and what it left on disk, recorded through stand-ins for its
/// `subprocess`, `shutil` and `time` modules.
final class RNGitCloneHandlerVectorTests: XCTestCase {

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
    let kind: RNGitCloneKind
    let linked: Bool
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
    let temporaries: Int
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
      name: "link unknown",
      kind: .mirror,
      linked: false,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [],
      answer: "014e6f74206964656e746966696564",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "no identity",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: nil,
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [],
      answer: "014e6f74206964656e746966696564",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "request not a map",
      kind: .mirror,
      linked: true,
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
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "request empty",
      kind: .mirror,
      linked: true,
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
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "no source given",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      answer: "024e6f20736f7572636520737065636966696564",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "source empty",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("source"), .string(""))]),
      script: [],
      answer: "024e6f20736f7572636520737065636966696564",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "source an integer",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("source"), .int(5))]),
      script: [],
      answer: "02496e76616c696420736f757263652055524c",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "source without a protocol",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("source"), .string("source/repo"))]
      ),
      script: [],
      answer: "0150726f6869626974656420736f757263652055524c",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "source over file",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("file:///tmp/repo")),
      ]),
      script: [],
      answer: "0150726f6869626974656420736f757263652055524c",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "source without a separator",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("ssh:host/repo")),
      ]),
      script: [],
      answer: "0150726f6869626974656420736f757263652055524c",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "source over ssh",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "occupied",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("ssh://host/repo")),
      ]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: true,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "no source and repository not a string",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .int(5))]),
      script: [],
      answer: "024e6f20736f7572636520737065636966696564",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "source over https",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("HTTPS://host/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""),
        Outcome(0, "mirror\n", ""), Outcome(0, "mirror\n", ""),
        Outcome(0, "rns://source/repo\n", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "HTTPS://host/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "HTTPS://host/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "HTTPS://host/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.source"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      temporaries: 1,
      registered: true,
      fork: nil,
      mirror: "rns://source/repo",
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "repository not a string",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .int(5)), (.string("source"), .string("rns://source/repo"))]),
      script: [],
      answer: "RAISED",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "path without a group",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([(.int(0), .string("repo")), (.string("source"), .string("rns://source/repo"))]
      ),
      script: [],
      answer: "02496e76616c69642072657175657374",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "unknown group",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("other/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "group path missing",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "groupless",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "create refused",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "create refused read granted",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [],
      answer: "014e6f7420616c6c6f776564",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "registered read granted",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: true,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [],
      answer: "015265706f7369746f727920616c726561647920657869737473",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "registered read refused",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: true,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: false,
      temporaries: 0,
      registered: true,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "path already present",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "occupied",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [],
      answer: "034e6f7420666f756e64",
      calls: [],
      allowed: nil,
      directory: true,
      temporaries: 0,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "mirrored",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""),
        Outcome(0, "mirror\n", ""), Outcome(0, "mirror\n", ""),
        Outcome(0, "rns://source/repo\n", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.source"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      temporaries: 1,
      registered: true,
      fork: nil,
      mirror: "rns://source/repo",
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "forked",
      kind: .fork,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""),
        Outcome(0, "fork\n", ""), Outcome(0, "rns://source/repo\n", ""), Outcome(0, "fork\n", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "fork"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.source"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      temporaries: 1,
      registered: true,
      fork: "rns://source/repo",
      mirror: nil,
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "init refused",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [Outcome(128, "", "fatal: no\n")],
      answer: "ff4661696c656420746f20696e697469616c697a65207265706f7369746f7279",
      calls: [Call(["git", "init", "--bare"], "<staged>")],
      allowed: nil,
      directory: false,
      temporaries: 1,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "init would not run",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [nil],
      answer: "ff52656d6f7465206572726f72",
      calls: [Call(["git", "init", "--bare"], "<staged>")],
      allowed: nil,
      directory: false,
      temporaries: 1,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "fetch refused",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [Outcome(0, "", ""), Outcome(128, "", "fatal: no\n")],
      answer: "ff4661696c656420746f2066657463682066726f6d20736f757263653a20666174616c3a206e6f0a",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
      ],
      allowed: nil,
      directory: false,
      temporaries: 1,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "head update abandoned",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), nil, Outcome(0, "trunk\n", ""), Outcome(0, "", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, ".\n", ""),
        Outcome(0, "true\n", ""), Outcome(0, "mirror\n", ""), Outcome(0, "mirror\n", ""),
        Outcome(0, "rns://source/repo\n", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"],
          "<staged>"), Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.source"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      temporaries: 1,
      registered: true,
      fork: nil,
      mirror: "rns://source/repo",
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "head update refused",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""),
        Outcome(0, "mirror\n", ""), Outcome(0, "mirror\n", ""),
        Outcome(0, "rns://source/repo\n", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.source"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      temporaries: 1,
      registered: true,
      fork: nil,
      mirror: "rns://source/repo",
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Vector(
      name: "type refused",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"),
      ],
      answer:
        "ff4661696c656420746f20636f6e666967757265207265706f7369746f727920747970653a20666174616c3a206e6f0a",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
      ],
      allowed: nil,
      directory: false,
      temporaries: 1,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "upstream source refused",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(128, "", "fatal: source\n"),
      ],
      answer:
        "ff4661696c656420746f20636f6e666967757265207265706f7369746f727920757073747265616d20736f757263653a20666174616c3a20736f757263650a",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
      ],
      allowed: nil,
      directory: false,
      temporaries: 1,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "sync time refused",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "", "fatal: earlier\n"), Outcome(128, "", "fatal: no\n"),
      ],
      answer:
        "ff4661696c656420746f20636f6e666967757265207265706f7369746f727920747970653a20666174616c3a206561726c6965720a",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
      ],
      allowed: nil,
      directory: false,
      temporaries: 1,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "permissions unwritable",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "blocked",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "", ""),
      ],
      answer: "ff436f756c64206e6f7420696e697469616c697a65207265706f7369746f7279",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
      ],
      allowed: nil,
      directory: false,
      temporaries: 1,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "not a repository",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "", ""), Outcome(0, "/elsewhere/.git\n", ""),
      ],
      answer: "ff4661696c656420746f207265676973746572207265706f7369746f7279",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: false,
      temporaries: 1,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "deployment refused",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "immovable",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""),
        Outcome(0, "mirror\n", ""), Outcome(0, "mirror\n", ""),
        Outcome(0, "rns://source/repo\n", ""),
      ],
      answer: "ff436f756c64206e6f74207772697465207265706f7369746f7279",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: false,
      temporaries: 1,
      registered: false,
      fork: nil,
      mirror: nil,
      admin: []),
    Vector(
      name: "blocked identity clones",
      kind: .mirror,
      linked: true,
      groupGrants: permissions(read: ["everyone"], create: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      seeded: false,
      state: "ready",
      blocked: true,
      request: .map([
        (.int(0), .string("group/repo")), (.string("source"), .string("rns://source/repo")),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "", ""), Outcome(0, ".\n", ""), Outcome(0, "true\n", ""),
        Outcome(0, "mirror\n", ""), Outcome(0, "mirror\n", ""),
        Outcome(0, "rns://source/repo\n", ""),
      ],
      answer: "00",
      calls: [
        Call(["git", "init", "--bare"], "<staged>"),
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<staged>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<staged>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<staged>"),
        Call(["git", "config", "repository.rngit.type", "mirror"], "<staged>"),
        Call(
          ["git", "config", "repository.rngit.upstream.source", "rns://source/repo"], "<staged>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<staged>"),
        Call(["git", "rev-parse", "--git-dir"], "<repo>"),
        Call(["git", "config", "--bool", "core.bare"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.type"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.source"], "<repo>"),
      ],
      allowed: "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      directory: true,
      temporaries: 1,
      registered: true,
      fork: nil,
      mirror: "rns://source/repo",
      admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
  ]

  private static let identityA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  private static let link = "0102030405060708"
  private static let now = 1_700_000_000

  /// Every request is answered as the reference answered it, having run what it ran and
  /// left what it left.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-clone-" + UUID().uuidString
      let groupPath = root + "/group"
      let path = groupPath + "/repo"
      let staging = root + "/staging"
      try FileManager.default.createDirectory(
        atPath: groupPath, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(
        atPath: staging, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }

      switch vector.state {
      case "groupless": try FileManager.default.removeItem(atPath: groupPath)
      case "occupied":
        try FileManager.default.createDirectory(
          atPath: path, withIntermediateDirectories: true)
      case "blocked":
        try FileManager.default.createDirectory(
          atPath: path + ".allowed.tmp", withIntermediateDirectories: true)
      case "immovable":
        try FileManager.default.createSymbolicLink(
          atPath: path, withDestinationPath: path + ".missing")
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
      let link = try XCTUnwrap(Data(pythonHex: Self.link), vector.name)

      let runner = ScriptedRunner(vector.script)
      var handler = RNGitCloneHandler(
        store: RNGitRepositoryStore(runner: runner, groups: ["group": group]),
        runner: runner, activeLinks: vector.linked ? [link] : [],
        blockedIdentities: vector.blocked ? [identity] : [],
        temporaries: RNGitTemporaryDirectories(root: staging),
        clock: { Self.now })

      let answer = handler.handle(
        vector.request, from: vector.identity.flatMap { Data(pythonHex: $0) }, on: link,
        as: vector.kind)
      let described = answer.map { $0.encoded.hexString } ?? "RAISED"
      XCTAssertEqual(described, vector.answer, vector.name)
      XCTAssertEqual(
        Self.normalised(runner.calls, at: path, staging: staging), vector.calls, vector.name)

      XCTAssertEqual(
        FileManager.default.fileExists(atPath: path), vector.directory, vector.name)
      XCTAssertEqual(
        try? String(contentsOfFile: path + ".allowed", encoding: .utf8), vector.allowed,
        vector.name)

      XCTAssertEqual(
        handler.temporaries.held[link]?.count ?? 0, vector.temporaries, vector.name)

      let entry = handler.store.groups["group"]?.repositories["repo"]
      XCTAssertEqual(entry != nil, vector.registered, vector.name)
      XCTAssertEqual(entry?.fork, vector.fork, vector.name)
      XCTAssertEqual(entry?.mirror, vector.mirror, vector.name)
      XCTAssertEqual(entry?.permissions.admin ?? [], Self.targets(vector.admin), vector.name)
    }
  }

  /// The calls with the two repository paths replaced by the names the vectors use.
  private static func normalised(_ calls: [Call], at path: String, staging: String) -> [Call] {
    calls.map { call in
      guard let directory = call.directory else { return call }
      if directory == path { return Call(call.argv, "<repo>") }
      if directory.hasPrefix(staging) { return Call(call.argv, "<staged>") }
      return call
    }
  }
}
