//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import CryptoKit
import Foundation
import XCTest

@testable import ReticulumSwift

/// Verdicts recorded from the `rngit` node's permission resolvers in Python RNS 1.5.4.
///
/// The configurations cover each level granting nobody, everyone, one identity and nothing at
/// all, in every combination of group, repository and document, so the order the reference
/// consults them in is pinned rather than assumed.
final class RNGitAccessControlVectorTests: XCTestCase {

  private static let aliases: [String: String] = [
    "mark": "d31aeea49873006f13b3415520666a4e",
    "alice": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "loop": "loop",
    "short": "abcd",
    "all": "dddddddddddddddddddddddddddddddd",
    "none": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    "                                ": "cccccccccccccccccccccccccccccccc",
  ]

  /// Turns a recorded target into the value the resolvers compare.
  private static func target(_ text: String) -> RNGitPermissionTarget {
    switch text {
    case "none": return .nobody
    case "all": return .everyone
    default: return .identity(Data(pythonHex: text) ?? Data())
    }
  }

  /// Turns a recorded permission map into a set.
  private static func permissions(_ spec: [String: [String]]) -> RNGitPermissionSet {
    var set = RNGitPermissionSet()
    for (key, targets) in spec {
      let values = targets.map(target)
      switch key {
      case "read": set.read = values
      case "write": set.write = values
      case "create": set.create = values
      case "stats": set.stats = values
      case "release": set.release = values
      case "interact": set.interact = values
      case "propose": set.propose = values
      default: set.admin = values
      }
    }
    return set
  }

  private static let permissionCodes: [RNGitPermission] = [
    .read, .write, .readWrite, .create, .stats, .release, .interact, .propose, .admin,
  ]

  private static let identities = [
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "cccccccccccccccccccccccccccccccc", "dddddddddddddddddddddddddddddddd",
  ]

  /// Each configuration line with the grant the reference read from it.
  private static let grants: [(line: String, permission: RNGitPermission?, target: String?)] = [
    ("r:all", .read, "all"),
    ("read:all", .read, "all"),
    ("w:none", .write, "none"),
    ("write:nobody", .write, "none"),
    ("rw:a", .readWrite, "all"),
    ("readwrite:everyone", .readWrite, "all"),
    ("c:n", .create, "none"),
    ("create:a", .create, "all"),
    ("s:all", .stats, "all"),
    ("stats:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .stats, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    ("rel:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", .release, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
    ("release:all", .release, "all"),
    ("i:all", .interact, "all"),
    ("interact:cccccccccccccccccccccccccccccccc", .interact, "cccccccccccccccccccccccccccccccc"),
    ("p:all", .propose, "all"),
    ("propose:n", .propose, "none"),
    ("adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .admin, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    ("admin:all", .admin, "all"),
    ("R:ALL", .read, nil),
    ("Read:All", .read, nil),
    ("RW:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", .readWrite, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    ("x:all", nil, "all"),
    ("r:", .read, nil),
    (":all", nil, "all"),
    ("r", nil, nil),
    ("r:all:extra", nil, nil),
    ("", nil, nil),
    ("  ", nil, nil),
    ("r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .read, nil),
    ("r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaf", .read, nil),
    ("r:zzaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .read, nil),
    ("r:mark", .read, "d31aeea49873006f13b3415520666a4e"),
    ("r:alice", .read, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    ("r:loop", .read, nil),
    ("r:short", .read, nil),
    ("r:unknownalias", .read, nil),
    ("rw:mark", .readWrite, "d31aeea49873006f13b3415520666a4e"),
    ("adm:mark", .admin, "d31aeea49873006f13b3415520666a4e"),
    ("r:aa bb cc dd ee ff 00 11 22 33", .read, nil),
    ("r:                                ", .read, "cccccccccccccccccccccccccccccccc"),
    ("r:aabbccddeeff001122334455667788  ", .read, "aabbccddeeff001122334455667788"),
    ("r:aabbccddeeff0011223344556677 8 ", .read, nil),
    ("r:aabbccddeeff00112233445566778 9 ", .read, nil),
    ("r:\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t", .read, ""),
    ("r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t\n", .read, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    ("r:none", .read, "none"),
    ("r:NONE", .read, nil),
    ("r:Nobody", .read, nil),
    ("w:A", .write, nil),
    ("w:EVERYONE", .write, nil),
    ("r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .read, nil),
    ("r:aabb", .read, nil),
    ("r: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", .read, nil),
  ]

  /// Each `allowed` file with the targets the reference took from it.
  private static let allowed: [(input: String?, granted: [String: [String]])] = [
    (nil, [:]),
    ("", [:]),
    ("# just a comment\n", [:]),
    (
      "r:all\nw:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
      ["read": ["all"], "write": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]]
    ),
    (
      "rw:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nrw:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
      ["read": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"], "write": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]]
    ),
    ("  r:all  \n\t w:none \n", ["read": ["all"], "write": ["none"]]),
    ("#r:all\nr:none\n", ["read": ["none"]]),
    ("r:all\nbroken line\nw:all\n", ["read": ["all"], "write": ["all"]]),
    (
      "adm:mark\ns:all\nrel:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\ni:cccccccccccccccccccccccccccccccc\np:all\nc:none\n",
      [
        "create": ["none"], "stats": ["all"], "release": ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
        "interact": ["cccccccccccccccccccccccccccccccc"], "propose": ["all"],
        "admin": ["d31aeea49873006f13b3415520666a4e"],
      ]
    ),
    ("r:all\r\nw:all\r\n", ["read": ["all"], "write": ["all"]]),
    ("r:all\u{B}w:none\u{C}c:all\n", ["read": ["all"], "write": ["none"], "create": ["all"]]),
    ("readwrite:everyone\nread:nobody\n", ["read": ["all", "none"], "write": ["all"]]),
    ("r:                                \nw:all\n", ["write": ["all"]]),
    (
      "r:\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\taa\nc:all\n",
      ["read": ["aa"], "create": ["all"]]
    ),
  ]

  /// Group and repository configurations, in the order the digests fold them.
  private static let groupSpecs: [(group: [String: [String]], repository: [String: [String]])] = [
    ([:], [:]),
    (["read": ["all"]], [:]),
    ([:], ["read": ["all"]]),
    (["read": ["all"]], ["read": ["none"]]),
    (["read": ["none"]], ["read": ["all"]]),
    (["read": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]], [:]),
    ([:], ["read": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]]),
    (
      ["read": ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]], ["read": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]]
    ),
    (["admin": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]], [:]),
    ([:], ["admin": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]]),
    (
      [
        "read": ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"], "admin": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
      ], [:]
    ),
    (
      ["read": ["all"], "admin": ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]],
      ["read": ["cccccccccccccccccccccccccccccccc"]]
    ),
    (["write": ["all"]], ["read": ["all"]]),
    (["read": ["none"], "admin": ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]], ["read": ["all"]]),
    (["read": ["none", "all"]], [:]),
    ([:], ["read": ["all", "none"]]),
  ]

  private static let documentSpecs: [String] = [
    "",
    "r:all\n",
    "r:none\n",
    "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
    "adm:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
    "w:all\n",
  ]

  /// Verdicts the reference gave where a name matches nothing, or the identity is blocked.
  private static let missing: [(label: String, allowed: Bool)] = [
    ("no repository", false),
    ("no group", false),
    ("group only", true),
    ("group missing", false),
    ("blocked", false),
    ("not blocked", true),
    ("blocked group", true),
  ]

  private static let repositoryPaths: [(path: String, group: String?, repository: String?)] = [
    ("g/repo", "g", "repo"),
    ("g", nil, nil),
    ("g/repo/extra", nil, nil),
    ("", nil, nil),
    ("/", "", ""),
    ("a/", "a", ""),
    ("/a", "", "a"),
    (
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/y",
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "y"
    ),
    (
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/y",
      nil, nil
    ),
    (
      "y/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      nil, nil
    ),
    (
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      nil, nil
    ),
    (
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      nil, nil
    ),
    ("a//b", nil, nil),
  ]

  private static let groupPaths: [(path: String, group: String?)] = [
    ("g/repo", nil),
    ("g", "g"),
    ("g/repo/extra", nil),
    ("", ""),
    ("/", nil),
    ("a/", nil),
    ("/a", nil),
    (
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/y",
      nil
    ),
    (
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/y",
      nil
    ),
    (
      "y/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      nil
    ),
    (
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    ),
    (
      "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
      nil
    ),
    ("a//b", nil),
  ]

  private static func control(_ index: Int, blocked: Set<Data> = []) -> RNGitAccessControl {
    let spec = groupSpecs[index]
    let repository = RNGitRepository(
      name: "repo", path: "/g/repo.git", permissions: permissions(spec.repository))
    let group = RNGitGroup(
      name: "g", path: "/g", repositories: ["repo": repository],
      permissions: permissions(spec.group))
    return RNGitAccessControl(
      groups: ["g": group], blockedIdentities: blocked, identityAliases: aliases)
  }

  /// Every configuration line parses to the grant the reference read from it.
  func testPermissionLinesMatchTheReference() {
    for vector in Self.grants {
      let grant = RNGitPermissionSet.grant(in: vector.line, aliases: Self.aliases)
      XCTAssertEqual(grant.permission, vector.permission, vector.line.debugDescription)
      XCTAssertEqual(
        grant.target.map(Self.describe), vector.target, vector.line.debugDescription)
    }
  }

  /// Every `allowed` file parses to the targets the reference took from it.
  func testAllowedFilesMatchTheReference() {
    for vector in Self.allowed {
      let parsed = RNGitPermissionSet.parsing(vector.input, aliases: Self.aliases)
      XCTAssertEqual(
        parsed, Self.permissions(vector.granted), (vector.input ?? "nil").debugDescription)
    }
  }

  /// Repository and group verdicts fold to the digest the reference produced.
  func testResolutionsMatchTheReferenceDigest() {
    var hasher = SHA256()

    for index in Self.groupSpecs.indices {
      let control = Self.control(index)
      for identity in Self.identities {
        let hash = Data(pythonHex: identity) ?? Data()
        for permission in Self.permissionCodes {
          let repository = control.allows(
            hash, group: "g", repository: "repo", permission: permission)
          let group = control.allowsGroup(hash, group: "g", permission: permission)
          hasher.update(
            data: Data(
              ("\(index):\(identity):\(permission.rawValue):\(repository ? 1 : 0)"
                + ":\(group ? 1 : 0)\n").utf8))
        }
      }
    }

    XCTAssertEqual(
      hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      "d58b12123c0eeaf5eeefedad48ea2e1795a5867e69b409abc1da8c6d8263478b")
  }

  /// Document verdicts fold to the digest the reference produced.
  func testDocumentResolutionsMatchTheReferenceDigest() {
    var hasher = SHA256()

    for (document, text) in Self.documentSpecs.enumerated() {
      let documentPermissions = RNGitPermissionSet.parsing(text, aliases: Self.aliases)
      for index in Self.groupSpecs.indices {
        let control = Self.control(index)
        for identity in Self.identities {
          let hash = Data(pythonHex: identity) ?? Data()
          for permission in Self.permissionCodes {
            let allowed = control.allowsDocument(
              hash, group: "g", repository: "repo", permission: permission,
              documentPermissions: documentPermissions)
            hasher.update(
              data: Data(
                ("\(document):\(index):\(identity):\(permission.rawValue)"
                  + ":\(allowed ? 1 : 0)\n").utf8))
          }
        }
      }
    }

    XCTAssertEqual(
      hasher.finalize().map { String(format: "%02x", $0) }.joined(),
      "dc8617b624b653ee3b85462c1ca9d39cd15d4ed3f5b8683ba5c1b419c3e8e23f")
  }

  /// A document with no `allowed` file of its own falls through to the repository and group.
  func testDocumentWithoutItsOwnFileMatchesTheReference() {
    let repository = RNGitRepository(name: "repo", path: "/g/repo.git")
    let group = RNGitGroup(
      name: "g", path: "/g", repositories: ["repo": repository],
      permissions: Self.permissions(["read": ["all"]]))
    let control = RNGitAccessControl(groups: ["g": group])
    XCTAssertEqual(
      control.allowsDocument(
        Data(pythonHex: Self.identities[0]) ?? Data(), group: "g", repository: "repo",
        permission: .read, documentPermissions: RNGitPermissionSet()),
      true)
  }

  /// A name matching nothing, and a blocked identity, give the verdicts the reference gave.
  func testMissingAndBlockedMatchTheReference() {
    let first = Data(pythonHex: Self.identities[0]) ?? Data()
    let second = Data(pythonHex: Self.identities[1]) ?? Data()
    let open = Self.permissions(["read": ["all"]])

    let empty = RNGitAccessControl(groups: [
      "g": RNGitGroup(name: "g", path: "/g", permissions: open)
    ])
    let served = RNGitAccessControl(
      groups: [
        "g": RNGitGroup(
          name: "g", path: "/g",
          repositories: [
            "repo": RNGitRepository(
              name: "repo", path: "/g/repo.git",
              permissions: open)
          ], permissions: open)
      ], blockedIdentities: [first])

    let verdicts: [(String, Bool)] = [
      ("no repository", empty.allows(first, group: "g", repository: "repo", permission: .read)),
      ("no group", empty.allows(first, group: "x", repository: "repo", permission: .read)),
      ("group only", empty.allowsGroup(first, group: "g", permission: .read)),
      ("group missing", empty.allowsGroup(first, group: "x", permission: .read)),
      ("blocked", served.allows(first, group: "g", repository: "repo", permission: .read)),
      ("not blocked", served.allows(second, group: "g", repository: "repo", permission: .read)),
      ("blocked group", served.allowsGroup(first, group: "g", permission: .read)),
    ]

    XCTAssertEqual(verdicts.count, Self.missing.count)
    for (verdict, expected) in zip(verdicts, Self.missing) {
      XCTAssertEqual(verdict.0, expected.label)
      XCTAssertEqual(verdict.1, expected.allowed, expected.label)
    }
  }

  /// Every request path splits the way the reference splits it.
  func testRequestPathsMatchTheReference() {
    for vector in Self.repositoryPaths {
      let parsed = RNGitAccessControl.repositoryPath(vector.path)
      XCTAssertEqual(parsed?.group, vector.group, vector.path.debugDescription)
      XCTAssertEqual(parsed?.repository, vector.repository, vector.path.debugDescription)
    }
    for vector in Self.groupPaths {
      XCTAssertEqual(
        RNGitAccessControl.groupPath(vector.path), vector.group, vector.path.debugDescription)
    }
  }

  private static func describe(_ target: RNGitPermissionTarget) -> String {
    switch target {
    case .nobody: return "none"
    case .everyone: return "all"
    case .identity(let hash): return hash.map { String(format: "%02x", $0) }.joined()
    }
  }
}
