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

/// The groups and repositories a node reads from disk, as Python RNS 1.5.4 reads them.
///
/// Each group directory is built by the same steps the reference built it with, and every
/// expectation is what the reference read from that directory.
final class RNGitRepositoryStoreVectorTests: XCTestCase {

  private enum Kind {
    case git
    case rootGit
    case directory
    case file
    case program
    case remove
    case load
    case updateGroup
    case updateRepository
  }

  private struct Operation {
    let kind: Kind
    let target: String
    var steps: [[String]] = []
    var content: String = ""
  }

  private struct Repository {
    let fork: String?
    let mirror: String?
    let permissions: RNGitPermissionSet
  }

  private struct GroupRecord {
    let path: String
    let dynamicPermissions: Bool
    let permissions: RNGitPermissionSet
    let repositories: [String: Repository]
  }

  private struct Reload {
    let name: String
    let configuration: String
    let steps: [Operation]
    let groups: [String: GroupRecord]
  }

  private struct Refusal {
    let name: String
    let configuration: String
    let steps: [Operation]
  }

  private struct Configured {
    let name: String
    let configuration: String
    let steps: [Operation]
    let groups: [String: GroupRecord]
    var home = false
  }

  private struct Vector {
    let name: String
    let configuration: String
    let operations: [Operation]
    let groupAllowed: String?
    let groupProgram: String?
    let dynamicPermissions: Bool
    let permissions: RNGitPermissionSet
    let repositories: [String: Repository]
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

  private static let aliases = ["bob": "cccccccccccccccccccccccccccccccc"]

  private static let vectors: [Vector] = [
    Vector(
      name: "empty group",
      configuration: "",
      operations: [],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [:]),
    Vector(
      name: "one repository",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "two repositories",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(kind: .git, target: "two", steps: [["init", "--bare"]]),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions()),
        "two": Repository(
          fork: nil, mirror: nil,
          permissions: permissions()),
      ]),
    Vector(
      name: "work tree skipped",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(kind: .git, target: "tree", steps: [["init"]]),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "plain directory skipped",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(kind: .directory, target: "plain"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "file skipped",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(kind: .file, target: "note", content: "hello\n"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "work suffix skipped",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one.work", steps: [["init", "--bare"]])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [:]),
    Vector(
      name: "releases suffix skipped",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one.releases", steps: [["init", "--bare"]])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [:]),
    Vector(
      name: "fork recorded",
      configuration: "",
      operations: [
        Operation(
          kind: .git, target: "one",
          steps: [
            ["init", "--bare"], ["config", "repository.rngit.type", "fork"],
            [
              "config", "repository.rngit.upstream.source",
              "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
            ],
          ])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "mirror recorded",
      configuration: "",
      operations: [
        Operation(
          kind: .git, target: "one",
          steps: [
            ["init", "--bare"], ["config", "repository.rngit.type", "mirror"],
            [
              "config", "repository.rngit.upstream.source",
              "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
            ],
          ])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
          permissions: permissions())
      ]),
    Vector(
      name: "repository allowed",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(
          kind: .file, target: "one.allowed",
          content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nw:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions(
            read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
            write: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
          ))
      ]),
    Vector(
      name: "repository allowed comment",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(
          kind: .file, target: "one.allowed",
          content: "# r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nw:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions(write: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]))
      ]),
    Vector(
      name: "repository allowed readwrite",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(
          kind: .file, target: "one.allowed", content: "rw:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions(
            read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
            write: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
          ))
      ]),
    Vector(
      name: "repository allowed keywords",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(kind: .file, target: "one.allowed", content: "r:all\nw:nobody\n"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions(read: ["everyone"], write: ["nobody"]))
      ]),
    Vector(
      name: "repository allowed empty",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(kind: .file, target: "one.allowed", content: ""),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "repository allowed junk",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(kind: .file, target: "one.allowed", content: "not a permission\n"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "repository allowed program",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(
          kind: .program, target: "one.allowed",
          content: "#!/bin/sh\necho r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions(read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]))
      ]),
    Vector(
      name: "repository allowed program fails",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(
          kind: .program, target: "one.allowed",
          content: "#!/bin/sh\necho w:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\nexit 3\n"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions(write: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]))
      ]),
    Vector(
      name: "group allowed",
      configuration: "[access]\n",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nadm:cccccccccccccccccccccccccccccccc\n",
      groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(
        read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
        admin: ["cccccccccccccccccccccccccccccccc"]
      ),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "group allowed program",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: nil, groupProgram: "#!/bin/sh\necho s:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
      dynamicPermissions: true,
      permissions: permissions(stats: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "group from config",
      configuration: "[access]\ngroup = r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "group from config list",
      configuration:
        "[access]\ngroup = r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, w:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, adm:all\n",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(
        read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
        write: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
        admin: ["everyone"]
      ),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "group config other name",
      configuration: "[access]\nother = r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "group config and allowed",
      configuration: "[access]\ngroup = w:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(
        read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
        write: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
      ),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "group config duplicate",
      configuration:
        "[access]\ngroup = r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "group config alias",
      configuration: "[access]\ngroup = r:bob\n",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(read: ["cccccccccccccccccccccccccccccccc"]),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "group config junk",
      configuration: "[access]\ngroup = nonsense\n",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]])
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "repository alias",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(kind: .file, target: "one.allowed", content: "r:bob\n"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions(read: ["cccccccccccccccccccccccccccccccc"]))
      ]),
    Vector(
      name: "not bare skipped",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(
          kind: .git, target: "notbare",
          steps: [["init", "--bare"], ["config", "core.bare", "false"]]),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "bare parent skipped",
      configuration: "",
      operations: [
        Operation(kind: .rootGit, target: ".", steps: [["init", "--bare"]]),
        Operation(kind: .directory, target: "plain"),
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
    Vector(
      name: "repository allowed directory",
      configuration: "",
      operations: [
        Operation(kind: .git, target: "one", steps: [["init", "--bare"]]),
        Operation(kind: .directory, target: "one.allowed"),
      ],
      groupAllowed: nil, groupProgram: nil,
      dynamicPermissions: false,
      permissions: permissions(),
      repositories: [
        "one": Repository(
          fork: nil, mirror: nil,
          permissions: permissions())
      ]),
  ]

  private static let reloads: [Reload] = [
    Reload(
      name: "first path kept",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(kind: .directory, target: "other"),
        Operation(kind: .git, target: "other/two", steps: [["init", "--bare"]]),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(kind: .load, target: "group", content: "other"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "same path reloaded",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(kind: .load, target: "group", content: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "second group loaded",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(kind: .directory, target: "other"),
        Operation(kind: .git, target: "other/two", steps: [["init", "--bare"]]),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(kind: .load, target: "other", content: "other"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ]),
        "other": GroupRecord(
          path: "other", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "two": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ]),
      ]),
    Reload(
      name: "group allowed removed",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .file, target: "group.allowed", content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(kind: .remove, target: "group.allowed"),
        Operation(kind: .updateGroup, target: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "group program removed",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .program, target: "group.allowed",
          content: "#!/bin/sh\necho s:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(kind: .remove, target: "group.allowed"),
        Operation(kind: .updateGroup, target: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "group program rewritten",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .program, target: "group.allowed",
          content: "#!/bin/sh\necho s:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(
          kind: .file, target: "group.allowed", content: "r:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"),
        Operation(kind: .updateGroup, target: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: true,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "group program replaced by text",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .program, target: "group.allowed",
          content: "#!/bin/sh\necho s:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(kind: .remove, target: "group.allowed"),
        Operation(
          kind: .file, target: "group.allowed", content: "r:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"),
        Operation(kind: .updateGroup, target: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(read: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "group allowed replaced",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .file, target: "group.allowed", content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(
          kind: .file, target: "group.allowed", content: "w:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"),
        Operation(kind: .updateGroup, target: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(write: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "group allowed added",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(
          kind: .file, target: "group.allowed", content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .updateGroup, target: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "group config kept across reload",
      configuration: "[access]\ngroup = adm:cccccccccccccccccccccccccccccccc\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .file, target: "group.allowed", content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(kind: .remove, target: "group.allowed"),
        Operation(kind: .updateGroup, target: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(admin: ["cccccccccccccccccccccccccccccccc"]),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "repository allowed replaced",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .file, target: "group/one.allowed", content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(
          kind: .file, target: "group/one.allowed", content: "w:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"),
        Operation(kind: .updateRepository, target: "group", content: "one"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions(write: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]))
          ])
      ]),
    Reload(
      name: "repository allowed removed",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .file, target: "group/one.allowed", content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(kind: .remove, target: "group/one.allowed"),
        Operation(kind: .updateRepository, target: "group", content: "one"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "group allowed directory",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(kind: .directory, target: "group.allowed"),
        Operation(kind: .load, target: "group", content: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "group program not executable format",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .program, target: "group.allowed", content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "group program without shebang",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .program, target: "group.allowed",
          content: "echo r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Reload(
      name: "unknown group updated",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .updateGroup, target: "group"),
      ],
      groups: [:]),
    Reload(
      name: "unknown repository updated",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(kind: .load, target: "group", content: "group"),
        Operation(kind: .updateRepository, target: "group", content: "missing"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
  ]

  private static let configured: [Configured] = [
    Configured(
      name: "one group named",
      configuration: "[repositories]\ngroup = {root}/group\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Configured(
      name: "two groups named",
      configuration: "[repositories]\ngroup = {root}/group\nother = {root}/other\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(kind: .directory, target: "other"),
        Operation(kind: .git, target: "other/two", steps: [["init", "--bare"]]),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ]),
        "other": GroupRecord(
          path: "other", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "two": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ]),
      ]),
    Configured(
      name: "path naming nothing",
      configuration: "[repositories]\ngroup = {root}/missing\n",
      steps: [],
      groups: [:]),
    Configured(
      name: "path naming a file",
      configuration: "[repositories]\ngroup = {root}/note\n",
      steps: [
        Operation(kind: .file, target: "note", content: "hello\n")
      ],
      groups: [:]),
    Configured(
      name: "two names for one path",
      configuration: "[repositories]\ngroup = {root}/group\nother = {root}/group\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ]),
        "other": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ]),
      ]),
    Configured(
      name: "one name for two paths",
      configuration: "[repositories]\ngroup = {root}/group\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(kind: .directory, target: "other"),
        Operation(kind: .git, target: "other/two", steps: [["init", "--bare"]]),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Configured(
      name: "no section",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
      ],
      groups: [:]),
    Configured(
      name: "empty section",
      configuration: "[repositories]\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
      ],
      groups: [:]),
    Configured(
      name: "group with a permissions file",
      configuration: "[repositories]\ngroup = {root}/group\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .file, target: "group.allowed", content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(read: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Configured(
      name: "group the configuration also grants",
      configuration:
        "[repositories]\ngroup = {root}/group\n[access]\ngroup = adm:cccccccccccccccccccccccccccccccc\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(admin: ["cccccccccccccccccccccccccccccccc"]),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ]),
    Configured(
      name: "path written from the home directory",
      configuration: "[repositories]\ngroup = ~/group\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
      ],
      groups: [
        "group": GroupRecord(
          path: "group", dynamicPermissions: false,
          permissions: permissions(),
          repositories: [
            "one": Repository(
              fork: nil, mirror: nil,
              permissions: permissions())
          ])
      ], home: true),
  ]

  private static let broken: [Refusal] = [
    Refusal(
      name: "path written as a list",
      configuration: "[repositories]\ngroup = {root}/group, {root}/other\n",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .directory, target: "other"),
      ]),
    Refusal(
      name: "path written as a subsection",
      configuration: "[repositories]\n[[group]]\npath = {root}/group\n",
      steps: [
        Operation(kind: .directory, target: "group")
      ]),
  ]

  private static let refusals: [Refusal] = [
    Refusal(
      name: "repository program not executable format",
      configuration: "",
      steps: [
        Operation(kind: .directory, target: "group"),
        Operation(kind: .git, target: "group/one", steps: [["init", "--bare"]]),
        Operation(
          kind: .program, target: "group/one.allowed",
          content: "r:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"),
        Operation(kind: .load, target: "group", content: "group"),
      ])
  ]

  private let runner = RNGitProcessRunner()

  /// Every group reads as the reference read it.
  func testGroupsMatchTheReference() throws {
    for vector in Self.vectors {
      let root = try build(vector)
      defer { try? FileManager.default.removeItem(atPath: root) }

      let configuration = try RNGitConfigFile.parse(vector.configuration)
      var store = RNGitRepositoryStore(
        runner: runner, identityAliases: Self.aliases,
        access: configuration.section("access"))
      try store.loadGroup(named: "group", at: root + "/group")

      let group = try XCTUnwrap(store.groups["group"], vector.name)
      XCTAssertEqual(group.path, root + "/group", vector.name)
      XCTAssertEqual(group.dynamicPermissions, vector.dynamicPermissions, vector.name)
      XCTAssertEqual(group.permissions, vector.permissions, vector.name)
      XCTAssertEqual(
        Set(group.repositories.keys), Set(vector.repositories.keys), vector.name)

      for (name, expected) in vector.repositories {
        let repository = try XCTUnwrap(group.repositories[name], "\(vector.name): \(name)")
        XCTAssertEqual(repository.path, root + "/group/" + name, "\(vector.name): \(name)")
        XCTAssertEqual(repository.fork, expected.fork, "\(vector.name): \(name)")
        XCTAssertEqual(repository.mirror, expected.mirror, "\(vector.name): \(name)")
        XCTAssertEqual(
          repository.permissions, expected.permissions, "\(vector.name): \(name)")
      }
    }
  }

  /// Every group reads as the reference read it after the files it was read from changed.
  func testReloadedGroupsMatchTheReference() throws {
    for vector in Self.reloads {
      let root = NSTemporaryDirectory() + "rngit-reload-" + UUID().uuidString
      try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }

      let configuration = try RNGitConfigFile.parse(vector.configuration)
      var store = RNGitRepositoryStore(
        runner: runner, identityAliases: Self.aliases,
        access: configuration.section("access"))
      for step in vector.steps { try apply(step, to: &store, in: root, of: vector.name) }

      XCTAssertEqual(Set(store.groups.keys), Set(vector.groups.keys), vector.name)
      for (name, expected) in vector.groups {
        let label = "\(vector.name): \(name)"
        let group = try XCTUnwrap(store.groups[name], label)
        XCTAssertEqual(group.path, root + "/" + expected.path, label)
        XCTAssertEqual(group.dynamicPermissions, expected.dynamicPermissions, label)
        XCTAssertEqual(group.permissions, expected.permissions, label)
        XCTAssertEqual(Set(group.repositories.keys), Set(expected.repositories.keys), label)

        for (repositoryName, record) in expected.repositories {
          let item = "\(label)/\(repositoryName)"
          let repository = try XCTUnwrap(group.repositories[repositoryName], item)
          XCTAssertEqual(repository.fork, record.fork, item)
          XCTAssertEqual(repository.mirror, record.mirror, item)
          XCTAssertEqual(repository.permissions, record.permissions, item)
        }
      }
    }
  }

  /// Every group the configuration names reads as the reference read it.
  func testConfiguredGroupsMatchTheReference() throws {
    for vector in Self.configured {
      let root = try seeded(vector.steps, of: vector.name)
      defer { try? FileManager.default.removeItem(atPath: root) }

      let text = vector.configuration.replacingOccurrences(of: "{root}", with: root)
      let configuration = try RNGitConfigFile.parse(text)
      var store = RNGitRepositoryStore(
        runner: runner, identityAliases: Self.aliases,
        access: configuration.section("access"))

      let held = ProcessInfo.processInfo.environment["HOME"]
      if vector.home { setenv("HOME", root, 1) }
      defer { if let held, vector.home { setenv("HOME", held, 1) } }
      try store.loadGroups(from: configuration)

      XCTAssertEqual(Set(store.groups.keys), Set(vector.groups.keys), vector.name)
      for (name, expected) in vector.groups {
        let label = "\(vector.name): \(name)"
        let group = try XCTUnwrap(store.groups[name], label)
        XCTAssertEqual(group.path, root + "/" + expected.path, label)
        XCTAssertEqual(group.dynamicPermissions, expected.dynamicPermissions, label)
        XCTAssertEqual(group.permissions, expected.permissions, label)
        XCTAssertEqual(Set(group.repositories.keys), Set(expected.repositories.keys), label)

        for (repositoryName, record) in expected.repositories {
          let item = "\(label)/\(repositoryName)"
          let repository = try XCTUnwrap(group.repositories[repositoryName], item)
          XCTAssertEqual(repository.fork, record.fork, item)
          XCTAssertEqual(repository.mirror, record.mirror, item)
          XCTAssertEqual(repository.permissions, record.permissions, item)
        }
      }
    }
  }

  /// Every configuration the reference raised on is refused here.
  func testBrokenConfigurationsAreRefused() throws {
    for vector in Self.broken {
      let root = try seeded(vector.steps, of: vector.name)
      defer { try? FileManager.default.removeItem(atPath: root) }

      let text = vector.configuration.replacingOccurrences(of: "{root}", with: root)
      let configuration = try RNGitConfigFile.parse(text)
      var store = RNGitRepositoryStore(runner: runner, identityAliases: Self.aliases)
      XCTAssertThrowsError(try store.loadGroups(from: configuration), vector.name)
    }
  }

  /// A temporary directory the setup steps have been applied to.
  private func seeded(_ steps: [Operation], of name: String) throws -> String {
    let root = NSTemporaryDirectory() + "rngit-configured-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    var store = RNGitRepositoryStore(runner: runner)
    for step in steps { try apply(step, to: &store, in: root, of: name) }
    return root
  }

  /// Every sequence the reference refused is refused here.
  func testRefusedSequencesMatchTheReference() throws {
    for vector in Self.refusals {
      let root = NSTemporaryDirectory() + "rngit-refusal-" + UUID().uuidString
      try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }

      let configuration = try RNGitConfigFile.parse(vector.configuration)
      var store = RNGitRepositoryStore(
        runner: runner, identityAliases: Self.aliases,
        access: configuration.section("access"))

      var thrown: Error?
      for step in vector.steps {
        do { try apply(step, to: &store, in: root, of: vector.name) } catch {
          thrown = error
          break
        }
      }
      XCTAssertNotNil(thrown, vector.name)
    }
  }

  private func apply(
    _ step: Operation, to store: inout RNGitRepositoryStore, in root: String, of name: String
  ) throws {
    let target = root + "/" + step.target
    switch step.kind {
    case .load: try store.loadGroup(named: step.target, at: root + "/" + step.content)
    case .updateGroup: store.updateGroupPermissions(named: step.target)
    case .updateRepository:
      store.updateRepositoryPermissions(group: step.target, repository: step.content)
    case .remove: try FileManager.default.removeItem(atPath: target)
    case .directory:
      try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
    case .file: try step.content.write(toFile: target, atomically: false, encoding: .utf8)
    case .program: try write(step.content, toProgram: target)
    case .git:
      try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
      for recipe in step.steps {
        XCTAssertEqual(runner.run("git", arguments: recipe, in: target)?.status, 0, name)
      }
    case .rootGit:
      for recipe in step.steps {
        XCTAssertEqual(runner.run("git", arguments: recipe, in: root)?.status, 0, name)
      }
    }
  }

  private func build(_ vector: Vector) throws -> String {
    let root = NSTemporaryDirectory() + "rngit-store-" + UUID().uuidString
    let group = root + "/group"
    try FileManager.default.createDirectory(atPath: group, withIntermediateDirectories: true)

    for operation in vector.operations {
      let target = group + "/" + operation.target
      switch operation.kind {
      case .directory:
        try FileManager.default.createDirectory(
          atPath: target, withIntermediateDirectories: true)
      case .file:
        try operation.content.write(toFile: target, atomically: false, encoding: .utf8)
      case .program:
        try write(operation.content, toProgram: target)
      case .git:
        try FileManager.default.createDirectory(
          atPath: target, withIntermediateDirectories: true)
        for step in operation.steps {
          XCTAssertEqual(
            runner.run("git", arguments: step, in: target)?.status, 0,
            "\(vector.name): git \(step.joined(separator: " "))")
        }
      case .rootGit:
        for step in operation.steps {
          XCTAssertEqual(
            runner.run("git", arguments: step, in: root)?.status, 0,
            "\(vector.name): git \(step.joined(separator: " "))")
        }
      case .remove, .load, .updateGroup, .updateRepository:
        XCTFail("\(vector.name): \(operation.target) is not a setup step")
      }
    }

    if let allowed = vector.groupAllowed {
      try allowed.write(toFile: group + ".allowed", atomically: false, encoding: .utf8)
    }
    if let program = vector.groupProgram {
      try write(program, toProgram: group + ".allowed")
    }
    return root
  }

  private func write(_ content: String, toProgram path: String) throws {
    try content.write(toFile: path, atomically: false, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
  }
}

#endif
