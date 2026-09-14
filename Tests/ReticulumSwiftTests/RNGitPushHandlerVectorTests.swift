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

/// The pushes a node applies, as Python RNS 1.5.4 applies them.
///
/// Each vector is what the reference's own handler answered, along with every command it
/// would have run and the bundle it wrote, recorded through a stand-in for its `subprocess`
/// module.
final class RNGitPushHandlerVectorTests: XCTestCase {

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

  /// Answers what the reference's `subprocess` was scripted to answer, logging every call
  /// and the bundle it finds on disk the first time one is named.
  private final class ScriptedRunner: RNGitCommandRunner, @unchecked Sendable {
    let script: [Outcome?]
    var calls: [Call] = []
    var written: String?

    init(_ script: [Outcome?]) { self.script = script }

    func run(_ executable: String, arguments: [String], in directory: String?)
      -> RNGitCommandOutput?
    {
      for argument in arguments where argument.hasSuffix("/push.bundle") {
        if written == nil, let held = FileManager.default.contents(atPath: argument) {
          written = held.hexString
        }
      }
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
    let written: String?
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
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "014e6f74206964656e746966696564",
      calls: [],
      pushes: 0,
      written: nil),
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
      pushes: 0,
      written: nil),
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
      pushes: 0,
      written: nil),
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
      pushes: 0,
      written: nil),
    Vector(
      name: "repository not a string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .int(5))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "write refused read granted",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "014e6f7420616c6c6f776564",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "write and read refused",
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "unknown repository",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/other"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "path without a group",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("repo"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "blocked identity",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: true,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "write granted by group",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420726571756573742064617461",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "write granted by admin",
      groupGrants: permissions(),
      repositoryGrants: permissions(admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420726571756573742064617461",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "write granted to another",
      groupGrants: permissions(),
      repositoryGrants: permissions(write: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "034e6f7420666f756e64",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "local ref an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("local_ref"), .int(5))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "local ref nil",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("local_ref"), .nil)]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "local ref bytes",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("local_ref"), .bytes(Data(pythonHex: "6162") ?? Data())),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "remote ref a list",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .array([])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "RAISED",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "no branch taken",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420726571756573742064617461",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle empty",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "") ?? Data())),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420726571756573742064617461",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operations empty",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")), (.string("operations"), .array([])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c696420726571756573742064617461",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle empty operations given",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "") ?? Data())),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "1111111111111111111111111111111111111111\n", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle and operations",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle without refs",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "024d697373696e67207265662073706563696669636174696f6e",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle without a remote ref",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "024d697373696e67207265662073706563696669636174696f6e",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle with a refused local ref",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "024d697373696e67207265662073706563696669636174696f6e",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle with a refused remote ref",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("-x/y")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "024d697373696e67207265662073706563696669636174696f6e",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle applied",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle a string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .string("PACK\u{E9}")),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: "5041434bc3a9"),
    Vector(
      name: "bundle an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")), (.string("bundle"), .int(7)),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle true",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")), (.string("bundle"), .bool(true)),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle a list",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")), (.string("bundle"), .array([.int(1)])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle a map",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .map([(.string("a"), .int(1))])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "bundle verify failed",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [Outcome(128, "", "fatal: no\n")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff436f756c64206e6f74207665726966792062756e646c65",
      calls: [Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>")],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle verify would not run",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [nil],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>")],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle fetch failed",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [Outcome(0, "", ""), Outcome(128, "", "fatal: no\n")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff436f756c64206e6f74207665726966792062756e646c65",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle fetch would not run",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [Outcome(0, "", ""), nil],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle forced",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
        (.string("force"), .bool(true)),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(
          ["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main", "--force"],
          "<repo>"),
      ],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle force a string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
        (.string("force"), .string("no")),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(
          ["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main", "--force"],
          "<repo>"),
      ],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle force zero",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
        (.string("force"), .int(0)),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle differing refs",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/trunk")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/trunk"], "<repo>"),
      ],
      pushes: 0,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle counted",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: true,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main"], "<repo>"),
      ],
      pushes: 1,
      written: "5041434b2d64617461"),
    Vector(
      name: "bundle counted while ignored",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("local_ref"), .string("refs/heads/main")),
        (.string("remote_ref"), .string("refs/heads/main")),
        (.string("bundle"), .bytes(Data(pythonHex: "5041434b2d64617461") ?? Data())),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: true,
      statsIgnored: true,
      answer: "00",
      calls: [
        Call(["git", "bundle", "verify", "<tmp>/push.bundle"], "<repo>"),
        Call(["git", "fetch", "<tmp>/push.bundle", "refs/heads/main:refs/heads/main"], "<repo>"),
      ],
      pushes: 1,
      written: "5041434b2d64617461"),
    Vector(
      name: "operations a string",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("operations"), .string("x"))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c6964206461746120666f72206f7065726174696f6e73",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operations a map",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("operations"), .map([(.string("a"), .int(1))])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c6964206461746120666f72206f7065726174696f6e73",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operations an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([(.int(0), .string("group/repo")), (.string("operations"), .int(3))]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c6964206461746120666f72206f7065726174696f6e73",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation not a map",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")), (.string("operations"), .array([.string("x")])),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation applied",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "1111111111111111111111111111111111111111\n", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation without an action",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a20",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action unknown",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("delete_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a2064656c6574655f72"
        + "6566",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .int(5)), (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a2035",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action a float",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .double(1.5)), (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a20312e35",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action nil",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .nil), (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a204e6f6e65",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action true",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .bool(true)), (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a2054727565",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action bytes",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .bytes(Data(pythonHex: "617f27ff") ?? Data())),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a206222615c78376627"
        + "5c78666622",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action a list",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .array([.string("a'b"), .string("c\"d"), .int(2)])),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a205b22612762222c20"
        + "27632264272c20325d",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action a map",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .map([(.string("a"), .double(0.1)), (.int(1), .nil)])),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a207b2761273a20302e"
        + "312c20313a204e6f6e657d",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action unprintable",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .array([.string("a\u{1}b\u{2028}\u{1F600}")])),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a205b27615c78303162"
        + "5c7532303238f09f9880275d",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action quoted",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .array([.string("a b'c\"d")])),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a205b276120625c2763"
        + "2264275d",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action a format character",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .array([.string("\u{1D173}")])),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a205b275c5530303031"
        + "64313733275d",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action floats",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (
                .string("action"),
                .array([.double(1234567.0), .double(0.30000000000000004), .double(1e+20)])
              ), (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a205b31323334353637"
        + "2e302c20302e33303030303030303030303030303030342c2031652b"
        + "32305d",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation action keys repeated",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .map([(.int(1), .string("x")), (.bool(true), .string("y"))])),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02556e6b6e6f776e206f7065726174696f6e3a207b313a202779277d",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref beginning refs",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")), (.string("ref"), .string("refsx/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref wide padded sha",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""),
        Outcome(0, "\u{2003}\u{A0}1111111111111111111111111111111111111111\u{2028}", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("delete_ref")), (.string("ref"), .int(5)),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation sha an integer",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("delete_ref")),
              (.string("ref"), .string("refs/heads/main")), (.string("sha"), .int(5)),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation sha a list",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (
                .string("sha"),
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
      pushes: 0,
      written: nil),
    Vector(
      name: "operation without a ref",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref refused",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")), (.string("ref"), .string("main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref outside refs",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")), (.string("ref"), .string("heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation without a sha",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
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
      pushes: 0,
      written: nil),
    Vector(
      name: "operation sha short",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")), (.string("sha"), .string("abc")),
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
      pushes: 0,
      written: nil),
    Vector(
      name: "operation sha not hex",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")),
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
      pushes: 0,
      written: nil),
    Vector(
      name: "operation sha long",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (
                .string("sha"),
                .string("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
              ),
            ])
          ])
        ),
      ]),
      script: [Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(
          [
            "git", "cat-file", "-t",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          ], "<repo>"), Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          [
            "git", "update-ref", "refs/heads/main",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          ], "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation object absent",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [Outcome(128, "", "fatal: no\n")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff4f626a656374203131313131313131313131313131313131313131"
        + "313131313131313131313131313131313131313120646f6573206e6f"
        + "7420657869737420696e207265706f7369746f7279",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>")
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation cat-file would not run",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
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
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref at the same sha",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "1111111111111111111111111111111111111111\n", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref at another sha",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "2222222222222222222222222222222222222222\n", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "0152656620726566732f68656164732f6d61696e20616c7265616479"
        + "2065786973747320617420646966666572656e74205348412028666f"
        + "72636520726571756972656429",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref at another sha forced",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
              (.string("force"), .bool(true)),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "2222222222222222222222222222222222222222\n", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref at another sha top-level force",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ), (.string("force"), .bool(true)),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "2222222222222222222222222222222222222222\n", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "0152656620726566732f68656164732f6d61696e20616c7265616479"
        + "2065786973747320617420646966666572656e74205348412028666f"
        + "72636520726571756972656429",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref padded sha",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, " \t1111111111111111111111111111111111111111\r\n", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation ref rev-parse failed",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(0, "", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation rev-parse would not run",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [Outcome(0, "", ""), nil],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation update failed",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "1111111111111111111111111111111111111111\n", ""),
        Outcome(128, "", "fatal: no\n"),
      ],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff436f756c64206e6f74207570646174652072656673",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation update would not run",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "1111111111111111111111111111111111111111\n", ""), nil,
      ],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "ff52656d6f7465206572726f72",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "two operations",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ]),
            .map([
              (.string("action"), .string("update_ref")), (.string("ref"), .string("refs/tags/v1")),
              (.string("sha"), .string("3333333333333333333333333333333333333333")),
            ]),
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "1111111111111111111111111111111111111111\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""),
        Outcome(0, "3333333333333333333333333333333333333333\n", ""), Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: true,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
        Call(["git", "cat-file", "-t", "3333333333333333333333333333333333333333"], "<repo>"),
        Call(["git", "rev-parse", "refs/tags/v1"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/tags/v1", "3333333333333333333333333333333333333333"],
          "<repo>"),
      ],
      pushes: 1,
      written: nil),
    Vector(
      name: "second operation refused",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ]),
            .map([
              (.string("action"), .string("update_ref")), (.string("ref"), .string("v1")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ]),
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "1111111111111111111111111111111111111111\n", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "02496e76616c69642072657175657374",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 0,
      written: nil),
    Vector(
      name: "operation counted",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "1111111111111111111111111111111111111111\n", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: true,
      statsIgnored: false,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 1,
      written: nil),
    Vector(
      name: "operation counted while ignored",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
            ])
          ])
        ),
      ]),
      script: [
        Outcome(0, "", ""), Outcome(0, "1111111111111111111111111111111111111111\n", ""),
        Outcome(0, "", ""),
      ],
      blocked: false,
      statsEnabled: true,
      statsIgnored: true,
      answer: "00",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "update-ref", "refs/heads/main", "1111111111111111111111111111111111111111"],
          "<repo>"),
      ],
      pushes: 1,
      written: nil),
    Vector(
      name: "operation force zero",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], write: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      request: .map([
        (.int(0), .string("group/repo")),
        (
          .string("operations"),
          .array([
            .map([
              (.string("action"), .string("update_ref")),
              (.string("ref"), .string("refs/heads/main")),
              (.string("sha"), .string("1111111111111111111111111111111111111111")),
              (.string("force"), .int(0)),
            ])
          ])
        ),
      ]),
      script: [Outcome(0, "", ""), Outcome(0, "2222222222222222222222222222222222222222\n", "")],
      blocked: false,
      statsEnabled: false,
      statsIgnored: false,
      answer: "0152656620726566732f68656164732f6d61696e20616c7265616479"
        + "2065786973747320617420646966666572656e74205348412028666f"
        + "72636520726571756972656429",
      calls: [
        Call(["git", "cat-file", "-t", "1111111111111111111111111111111111111111"], "<repo>"),
        Call(["git", "rev-parse", "refs/heads/main"], "<repo>"),
      ],
      pushes: 0,
      written: nil),
  ]

  private static let identityA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  /// Every request is answered as the reference answered it, having run what it ran.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-push-" + UUID().uuidString
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
      var handler = RNGitPushHandler(
        access: RNGitAccessControl(
          groups: ["group": group], blockedIdentities: vector.blocked ? [identity] : []),
        runner: runner, settings: settings, temporaryRoot: root)

      let answer = handler.handle(
        vector.request, from: vector.identity.flatMap { Data(pythonHex: $0) })
      let described = answer.map { $0.encoded.hexString } ?? "RAISED"
      XCTAssertEqual(described, vector.answer, vector.name)
      XCTAssertEqual(Self.normalised(runner.calls, under: root), vector.calls, vector.name)
      XCTAssertEqual(runner.written, vector.written, vector.name)

      let counters = handler.statistics.groups["group"]?.repositories["repo"]
      XCTAssertEqual(counters?.push[RNGitStatsStore.day()] ?? 0, vector.pushes, vector.name)

      // The reference holds the bundle in a `TemporaryDirectory` context manager, which
      // takes the directory away again on every path out of the handler.
      let held = try FileManager.default.contentsOfDirectory(atPath: root)
      XCTAssertEqual(held.filter { $0.hasPrefix("rngit-") }, [], vector.name)
    }
  }

  /// The calls with the paths the handler chose replaced by the names the vectors use.
  private static func normalised(_ calls: [Call], under root: String) -> [Call] {
    calls.map { call in
      Call(
        call.argv.map { word in
          word.hasPrefix(root) && word.hasSuffix("/push.bundle") ? "<tmp>/push.bundle" : word
        },
        call.directory == root + "/repo" ? "<repo>" : call.directory)
    }
  }
}
