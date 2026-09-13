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

/// The references a node lists for a repository, as Python RNS 1.5.4 lists them.
///
/// Each repository directory is built by the same steps the reference built it with, and
/// every answer is the bytes the reference's own handler returned for that request.
final class RNGitListHandlerVectorTests: XCTestCase {

  private enum Step {
    case initialize
    case reference(String, String)
    case head(String)
    case removeHead
    case directoryHead
    case packed(String)
    case packedBytes(String)
    case remove
  }

  private struct Vector {
    let name: String
    let steps: [Step]
    let groupGrants: RNGitPermissionSet
    let repositoryGrants: RNGitPermissionSet
    let identity: String?
    let blocked: Bool
    let request: MsgPack.Value
    let response: String?
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
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: nil,
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "014e6f74206964656e746966696564"),
    Vector(
      name: "request not a map",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .string("group/repo"),
      response: "02496e76616c69642072657175657374"),
    Vector(
      name: "request a list",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .array([.string("group/repo")]),
      response: "02496e76616c69642072657175657374"),
    Vector(
      name: "request nil",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .nil,
      response: "02496e76616c69642072657175657374"),
    Vector(
      name: "request empty",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([]),
      response: "024e6f207265706f7369746f727920737065636966696564"),
    Vector(
      name: "request other key",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(2), .string("group"))]),
      response: "024e6f207265706f7369746f727920737065636966696564"),
    Vector(
      name: "unknown repository",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/other"))]),
      response: "034e6f7420666f756e64"),
    Vector(
      name: "unknown group",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("other/repo"))]),
      response: "034e6f7420666f756e64"),
    Vector(
      name: "path without a group",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("repo"))]),
      response: "034e6f7420666f756e64"),
    Vector(
      name: "path with three parts",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("a/b/c"))]),
      response: "034e6f7420666f756e64"),
    Vector(
      name: "path too long",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([
        (
          .int(0),
          .string(
            "group/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
          )
        )
      ]),
      response: "034e6f7420666f756e64"),
    Vector(
      name: "read refused",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["nobody"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "034e6f7420666f756e64"),
    Vector(
      name: "read granted to another",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "034e6f7420666f756e64"),
    Vector(
      name: "read granted by hash",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "read granted by group",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      repositoryGrants: permissions(),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "read granted by admin",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(admin: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "push without write",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("for_push"), .bool(true))]),
      response: "034e6f7420616c6c6f776564"),
    Vector(
      name: "push with write",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(
        read: ["everyone"], write: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("for_push"), .bool(true))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "push without read",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(write: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("for_push"), .bool(true))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "push flag false",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("for_push"), .bool(false))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "push flag truthy string",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("for_push"), .string("no"))]),
      response: "034e6f7420616c6c6f776564"),
    Vector(
      name: "push flag zero",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("for_push"), .int(0))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "push flag one",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("for_push"), .int(1))]),
      response: "034e6f7420616c6c6f776564"),
    Vector(
      name: "no refs",
      steps: [.initialize],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "0040726566732f68656164732f6d61696e20484541440a"),
    Vector(
      name: "one ref",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "three refs",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .reference("refs/heads/topic", "2222222222222222222222222222222222222222"),
        .reference("refs/tags/v1", "3333333333333333333333333333333333333333"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a3232323232323232323232323232323232323232323232323232323232323232323232323232323220726566732f68656164732f746f7069630a3333333333333333333333333333333333333333333333333333333333333333333333333333333320726566732f746167732f76310a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "packed refs",
      steps: [
        .initialize,
        .packed(
          "# pack-refs with: peeled fully-peeled sorted \n1111111111111111111111111111111111111111 refs/heads/main\n2222222222222222222222222222222222222222 refs/tags/v1\n"
        ),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a3232323232323232323232323232323232323232323232323232323232323232323232323232323220726566732f746167732f76310a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "loose over packed",
      steps: [
        .initialize, .packed("2222222222222222222222222222222222222222 refs/heads/main\n"),
        .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "head missing",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .removeHead,
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "ff436f756c64206e6f74206c6973742072656673"),
    Vector(
      name: "head empty",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .head(""),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "ff436f756c64206e6f74206c6973742072656673"),
    Vector(
      name: "head detached",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .head("313131313131313131313131313131313131313131313131313131313131313131313131313131310a"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a406d617374657220484541440a"
    ),
    Vector(
      name: "head other branch",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .head("7265663a20726566732f68656164732f7472756e6b0a"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f7472756e6b20484541440a"
    ),
    Vector(
      name: "head padded",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .head("7265663a20726566732f68656164732f6d61696e2020090a"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "head not utf8",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .head("7265663a20726566732f68656164732fff6d61696e0a"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "head short",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .head("7265663a"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "ff436f756c64206e6f74206c6973742072656673"),
    Vector(
      name: "head is a directory",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .directoryHead,
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "ff52656d6f7465206572726f72"),
    Vector(
      name: "repository removed",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .remove,
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "ff52656d6f7465206572726f72"),
    Vector(
      name: "blocked identity",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: true,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "034e6f7420666f756e64"),
    Vector(
      name: "repository not a string",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .int(5))]),
      response: nil),
    Vector(
      name: "repository bytes",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .bytes(Data(pythonHex: "67726f75702f7265706f") ?? Data()))]),
      response: nil),
    Vector(
      name: "repository nil",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .nil)]),
      response: nil),
    Vector(
      name: "repository key false",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.bool(false), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "repository key repeated",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/other")), (.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "push flag empty string",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo")), (.string("for_push"), .string(""))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "push flag repeated",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([
        (.int(0), .string("group/repo")), (.string("for_push"), .bool(true)),
        (.string("for_push"), .bool(false)),
      ]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "repository key a float",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.double(0.0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "duplicate packed refs",
      steps: [
        .initialize,
        .packed(
          "# pack-refs with: peeled fully-peeled sorted \n1111111111111111111111111111111111111111 refs/heads/main\n2222222222222222222222222222222222222222 refs/heads/main\n"
        ),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "packed duplicate under a loose ref",
      steps: [
        .initialize,
        .packed(
          "# pack-refs with: peeled fully-peeled sorted \n2222222222222222222222222222222222222222 refs/heads/main\n3333333333333333333333333333333333333333 refs/heads/main\n"
        ), .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "refs sharing one object",
      steps: [
        .initialize, .reference("refs/heads/main", "1111111111111111111111111111111111111111"),
        .reference("refs/heads/topic", "1111111111111111111111111111111111111111"),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response:
        "003131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f6d61696e0a3131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732f746f7069630a40726566732f68656164732f6d61696e20484541440a"
    ),
    Vector(
      name: "reference name not utf8",
      steps: [
        .initialize,
        .packedBytes(
          "3131313131313131313131313131313131313131313131313131313131313131313131313131313120726566732f68656164732fff6d61696e0a"
        ),
      ],
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"]),
      identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      blocked: false,
      request: .map([(.int(0), .string("group/repo"))]),
      response: "ff52656d6f7465206572726f72"),
  ]

  private let runner = RNGitProcessRunner()

  /// Every request is answered with the bytes the reference answered it with.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-list-" + UUID().uuidString
      let path = root + "/repo"
      try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }
      for step in vector.steps { try apply(step, at: path, of: vector.name) }

      var repository = RNGitRepository(name: "repo", path: path)
      repository.permissions = vector.repositoryGrants
      var group = RNGitGroup(name: "group", path: root)
      group.permissions = vector.groupGrants
      group.repositories["repo"] = repository
      let blocked = vector.blocked ? Set([Data(pythonHex: Self.blockedIdentity) ?? Data()]) : []
      let handler = RNGitListHandler(
        access: RNGitAccessControl(groups: ["group": group], blockedIdentities: blocked),
        runner: runner)

      let identity = vector.identity.flatMap { Data(pythonHex: $0) }
      let answer = handler.handle(vector.request, from: identity)
      XCTAssertEqual(answer?.encoded.hexString, vector.response, vector.name)
    }
  }

  private static let blockedIdentity = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  private func apply(_ step: Step, at path: String, of name: String) throws {
    switch step {
    case .initialize:
      XCTAssertEqual(
        runner.run("git", arguments: ["init", "--bare", "."], in: path)?.status,
        0, name)
    case .reference(let reference, let digest):
      let full = path + "/" + reference
      try FileManager.default.createDirectory(
        atPath: (full as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)
      try (digest + "\n").write(toFile: full, atomically: false, encoding: .utf8)
    case .head(let content):
      try XCTUnwrap(Data(pythonHex: content) ?? Data(), name)
        .write(to: URL(fileURLWithPath: path + "/HEAD"))
    case .removeHead:
      try FileManager.default.removeItem(atPath: path + "/HEAD")
    case .directoryHead:
      try FileManager.default.removeItem(atPath: path + "/HEAD")
      try FileManager.default.createDirectory(
        atPath: path + "/HEAD", withIntermediateDirectories: true)
    case .packed(let content):
      try content.write(toFile: path + "/packed-refs", atomically: false, encoding: .utf8)
    case .packedBytes(let content):
      try XCTUnwrap(Data(pythonHex: content), name)
        .write(to: URL(fileURLWithPath: path + "/packed-refs"))
    case .remove:
      try FileManager.default.removeItem(atPath: path)
    }
  }
}

#endif
