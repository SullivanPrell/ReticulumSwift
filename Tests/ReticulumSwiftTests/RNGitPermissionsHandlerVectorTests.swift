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

/// The permission files a node reads and rewrites, as Python RNS 1.5.4 reads and rewrites them.
///
/// Each vector is what the reference's own handler answered for a tree seeded the same way,
/// along with everything it left behind. A vector carrying two requests answers the second one
/// from what the first wrote, which is how the refresh a rewrite triggers is recorded.
final class RNGitPermissionsHandlerVectorTests: XCTestCase {

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

  private struct Vector {
    let name: String
    let groupGrants: RNGitPermissionSet
    let repositoryGrants: RNGitPermissionSet
    let registered: Bool
    let configured: [String: [String]]
    let blocked: Bool
    let identity: String?
    let tree: [Entry]
    let requests: [MsgPack.Value]
    let answers: [String]
    let left: [String]
  }

  /// The names a permission line may stand an identity hash behind.
  private static let aliases = [
    "alice": "aca31af0441d81dbec71e82da0b4b5f5",
    "bob": "069092a03c194639207219dd05f9c840",
  ]

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
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity: nil,
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["014e6f74206964656e746966696564"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "request not a map",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [.string("group")],
      answers: ["02496e76616c69642072657175657374"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "request nil",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [.nil],
      answers: ["02496e76616c69642072657175657374"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "operation missing",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [.map([(.int(2), .string("group")), (.string("step"), .string("get"))])],
      answers: ["02496e76616c69642072657175657374"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "operation empty",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["02496e76616c69642072657175657374"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "operation nil",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .nil),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["02496e76616c69642072657175657374"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "operation unknown",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("frobnicate")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["02496e76616c69642072657175657374"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group permissions with no group named",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([(.string("operation"), .string("gperms")), (.string("step"), .string("get"))])
      ],
      answers: ["024e6f2067726f757020737065636966696564"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository permissions with no repository named",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([(.string("operation"), .string("rperms")), (.string("step"), .string("get"))])
      ],
      answers: ["024e6f207265706f7369746f727920737065636966696564"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group named with a separator",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group/repo")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group named past the length limit",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string(String(repeating: "g", count: 257))),
          (.string("operation"), .string("gperms")), (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group not a string",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .int(5)), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["ff52656d6f7465206572726f72"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository not a string",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .int(5)), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["ff52656d6f7465206572726f72"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository named with one component",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository named past the length limit",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (
            .int(0),
            .string(
              "group/rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr"
            )
          ), (.string("operation"), .string("rperms")), (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository read without administering",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["014e6f7420616c6c6f776564"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository neither read nor administered",
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group read without administering",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["014e6f7420616c6c6f776564"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group neither read nor administered",
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group administered without reading",
      groupGrants: permissions(admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group step missing",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [.map([(.int(2), .string("group")), (.string("operation"), .string("gperms"))])],
      answers: ["02496e76616c69642072657175657374"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group step empty",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("")),
        ])
      ],
      answers: ["02496e76616c69642072657175657374"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group step unknown",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("list")),
        ])
      ],
      answers: ["02496e76616c69642073746570"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group get with no permissions file",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["0081a7636f6e74656e74a0"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group get with a permissions file",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry(
          "f", "group.allowed",
          "r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
      ],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: [
        "0081a7636f6e74656e74d946723a61636133316166303434316438316462656337316538326461306234623566350a773a30363930393261303363313934363339323037323139646430356639633834300a"
      ],
      left: [
        "d|group",
        "b|group.allowed|723a61636133316166303434316438316462656337316538326461306234623566350a773a30363930393261303363313934363339323037323139646430356639633834300a",
        "d|group/repo",
      ]),
    Vector(
      name: "group get where the permissions file is a directory",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [Entry("d", "group.allowed")],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["0081a7636f6e74656e74a0"],
      left: ["d|group", "d|group.allowed", "d|group/repo"]),
    Vector(
      name: "group get where the permissions file is not text",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [Entry("b", "group.allowed", "ff")],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["ff4572726f722067657474696e67207065726d697373696f6e73"],
      left: ["d|group", "b|group.allowed|ff", "d|group/repo"]),
    Vector(
      name: "group get where the permissions file runs",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("f", "group.allowed", "#!/bin/sh\necho r:aca31af0441d81dbec71e82da0b4b5f5\n"),
        Entry("m", "group.allowed", "755"),
      ],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: [
        "0081a7636f6e74656e74d93223212f62696e2f73680a6563686f20723a61636133316166303434316438316462656337316538326461306234623566350a"
      ],
      left: [
        "d|group",
        "x|group.allowed|23212f62696e2f73680a6563686f20723a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set writes the permissions file",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string("r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
          ),
        ])
      ],
      answers: ["00"],
      left: [
        "d|group",
        "b|group.allowed|723a61636133316166303434316438316462656337316538326461306234623566350a773a30363930393261303363313934363339323037323139646430356639633834300a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set over an existing permissions file",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [Entry("f", "group.allowed", "r:everyone\n")],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("adm:aca31af0441d81dbec71e82da0b4b5f5\n")),
        ])
      ],
      answers: ["00"],
      left: [
        "d|group",
        "b|group.allowed|61646d3a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set with no content named",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [Entry("f", "group.allowed", "r:everyone\n")],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
        ])
      ],
      answers: ["00"],
      left: ["d|group", "b|group.allowed|", "d|group/repo"]),
    Vector(
      name: "group set with content that is not text",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")), (.string("content"), .int(5)),
        ])
      ],
      answers: ["ff52656d6f7465206572726f72"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group set with comments and blank lines",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("# a note\n\n   \nr:aca31af0441d81dbec71e82da0b4b5f5\n")),
        ])
      ],
      answers: ["00"],
      left: [
        "d|group",
        "b|group.allowed|232061206e6f74650a0a2020200a723a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set with a line holding no separator",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("r:aca31af0441d81dbec71e82da0b4b5f5\nnonsense\n")),
        ])
      ],
      answers: ["02496e76616c6964207065726d697373696f6e20226e6f6e73656e736522206f6e206c696e652032"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group set with a line holding two separators",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")), (.string("content"), .string("r:a:b\n")),
        ])
      ],
      answers: ["02496e76616c6964207065726d697373696f6e2022723a613a6222206f6e206c696e652031"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group set with an unknown permission",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("z:aca31af0441d81dbec71e82da0b4b5f5\n")),
        ])
      ],
      answers: [
        "02496e76616c6964207065726d697373696f6e20227a3a616361333161663034343164383164626563373165383264613062346235663522206f6e206c696e652031"
      ],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group set with a target of the wrong length",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")), (.string("content"), .string("r:abcd\n")),
        ])
      ],
      answers: ["02496e76616c6964207065726d697373696f6e2022723a6162636422206f6e206c696e652031"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group set with a target that is not hexadecimal",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("r:zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n")),
        ])
      ],
      answers: [
        "02496e76616c6964207065726d697373696f6e2022723a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a22206f6e206c696e652031"
      ],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group set where the permissions file runs",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("f", "group.allowed", "#!/bin/sh\necho r:aca31af0441d81dbec71e82da0b4b5f5\n"),
        Entry("m", "group.allowed", "755"),
      ],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string("r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
          ),
        ])
      ],
      answers: [
        "0145786563757461626c65207065726d697373696f6e207265736f6c766572732063616e206f6e6c79206265206d6f646966696564206e6f64652d73696465"
      ],
      left: [
        "d|group",
        "x|group.allowed|23212f62696e2f73680a6563686f20723a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set where the permissions file is a directory",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [Entry("d", "group.allowed")],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string("r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
          ),
        ])
      ],
      answers: [
        "0145786563757461626c65207065726d697373696f6e207265736f6c766572732063616e206f6e6c79206265206d6f646966696564206e6f64652d73696465"
      ],
      left: ["d|group", "d|group.allowed", "d|group/repo"]),
    Vector(
      name: "group set then get",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string("adm:aca31af0441d81dbec71e82da0b4b5f5\nr:aca31af0441d81dbec71e82da0b4b5f5\n")
          ),
        ]),
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ]),
      ],
      answers: [
        "00",
        "0081a7636f6e74656e74d94861646d3a61636133316166303434316438316462656337316538326461306234623566350a723a61636133316166303434316438316462656337316538326461306234623566350a",
      ],
      left: [
        "d|group",
        "b|group.allowed|61646d3a61636133316166303434316438316462656337316538326461306234623566350a723a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set takes away the access it was granted with",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")), (.string("content"), .string("")),
        ]),
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ]),
      ],
      answers: ["00", "034e6f7420666f756e64"],
      left: ["d|group", "b|group.allowed|", "d|group/repo"]),
    Vector(
      name: "group set keeps what the configuration grants",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: ["group": ["r:everyone", "adm:everyone"]],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")), (.string("content"), .string("")),
        ]),
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ]),
      ],
      answers: ["00", "0081a7636f6e74656e74a0"],
      left: ["d|group", "b|group.allowed|", "d|group/repo"]),
    Vector(
      name: "group set with every keyword",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string(
              "read:aca31af0441d81dbec71e82da0b4b5f5\nwrite:aca31af0441d81dbec71e82da0b4b5f5\nrw:aca31af0441d81dbec71e82da0b4b5f5\nc:aca31af0441d81dbec71e82da0b4b5f5\ns:aca31af0441d81dbec71e82da0b4b5f5\nrel:aca31af0441d81dbec71e82da0b4b5f5\ni:aca31af0441d81dbec71e82da0b4b5f5\np:aca31af0441d81dbec71e82da0b4b5f5\nadmin:aca31af0441d81dbec71e82da0b4b5f5\n"
            )
          ),
        ])
      ],
      answers: ["00"],
      left: [
        "d|group",
        "b|group.allowed|726561643a61636133316166303434316438316462656337316538326461306234623566350a77726974653a61636133316166303434316438316462656337316538326461306234623566350a72773a61636133316166303434316438316462656337316538326461306234623566350a633a61636133316166303434316438316462656337316538326461306234623566350a733a61636133316166303434316438316462656337316538326461306234623566350a72656c3a61636133316166303434316438316462656337316538326461306234623566350a693a61636133316166303434316438316462656337316538326461306234623566350a703a61636133316166303434316438316462656337316538326461306234623566350a61646d696e3a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set with everyone and nobody as targets",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("r:everyone\nw:nobody\nadm:all\ni:n\n")),
        ])
      ],
      answers: ["00"],
      left: [
        "d|group",
        "b|group.allowed|723a65766572796f6e650a773a6e6f626f64790a61646d3a616c6c0a693a6e0a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set with the permission written in capitals",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("R:aca31af0441d81dbec71e82da0b4b5f5\n")),
        ])
      ],
      answers: ["00"],
      left: [
        "d|group",
        "b|group.allowed|523a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set with the target written in capitals",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("r:ACA31AF0441D81DBEC71E82DA0B4B5F5\n")),
        ])
      ],
      answers: ["00"],
      left: [
        "d|group",
        "b|group.allowed|723a41434133314146303434314438314442454337314538324441304234423546350a",
        "d|group/repo",
      ]),
    Vector(
      name: "group set with an alias for the target",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")), (.string("content"), .string("r:alice\nw:bob\n")),
        ])
      ],
      answers: ["00"],
      left: ["d|group", "b|group.allowed|723a616c6963650a773a626f620a", "d|group/repo"]),
    Vector(
      name: "group set with a target that is only whitespace",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")), (.string("content"), .string("r: \n")),
        ])
      ],
      answers: ["02496e76616c6964207065726d697373696f6e2022723a22206f6e206c696e652031"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "group set where the content ends without a line break",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("r:aca31af0441d81dbec71e82da0b4b5f5")),
        ])
      ],
      answers: ["00"],
      left: [
        "d|group",
        "b|group.allowed|723a6163613331616630343431643831646265633731653832646130623462356635",
        "d|group/repo",
      ]),
    Vector(
      name: "repository blocked identity",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository get with no permissions file",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["0081a7636f6e74656e74a0"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository get with a permissions file",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry(
          "f", "group/repo.allowed",
          "r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
      ],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: [
        "0081a7636f6e74656e74d946723a61636133316166303434316438316462656337316538326461306234623566350a773a30363930393261303363313934363339323037323139646430356639633834300a"
      ],
      left: [
        "d|group", "d|group/repo",
        "b|group/repo.allowed|723a61636133316166303434316438316462656337316538326461306234623566350a773a30363930393261303363313934363339323037323139646430356639633834300a",
      ]),
    Vector(
      name: "repository step missing",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([(.int(0), .string("group/repo")), (.string("operation"), .string("rperms"))])
      ],
      answers: ["02496e76616c69642072657175657374"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository step unknown",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("list")),
        ])
      ],
      answers: ["02496e76616c69642073746570"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository set writes the permissions file",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string("r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
          ),
        ])
      ],
      answers: ["00"],
      left: [
        "d|group", "d|group/repo",
        "b|group/repo.allowed|723a61636133316166303434316438316462656337316538326461306234623566350a773a30363930393261303363313934363339323037323139646430356639633834300a",
      ]),
    Vector(
      name: "repository set where only the repository grants administering",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string("r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
          ),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository get where only the repository grants administering",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry(
          "f", "group/repo.allowed",
          "r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
      ],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: [
        "0081a7636f6e74656e74d946723a61636133316166303434316438316462656337316538326461306234623566350a773a30363930393261303363313934363339323037323139646430356639633834300a"
      ],
      left: [
        "d|group", "d|group/repo",
        "b|group/repo.allowed|723a61636133316166303434316438316462656337316538326461306234623566350a773a30363930393261303363313934363339323037323139646430356639633834300a",
      ]),
    Vector(
      name: "repository set with an invalid line",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("r:aca31af0441d81dbec71e82da0b4b5f5\nnonsense\n")),
        ])
      ],
      answers: ["02496e76616c6964207065726d697373696f6e20226e6f6e73656e736522206f6e206c696e652032"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository set where the permissions file runs",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("f", "group/repo.allowed", "#!/bin/sh\necho r:aca31af0441d81dbec71e82da0b4b5f5\n"),
        Entry("m", "group/repo.allowed", "755"),
      ],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string("r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
          ),
        ])
      ],
      answers: [
        "0145786563757461626c65207065726d697373696f6e207265736f6c766572732063616e206f6e6c79206265206d6f646966696564206e6f64652d73696465"
      ],
      left: [
        "d|group", "d|group/repo",
        "x|group/repo.allowed|23212f62696e2f73680a6563686f20723a61636133316166303434316438316462656337316538326461306234623566350a",
      ]),
    Vector(
      name: "repository set then get",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string("adm:aca31af0441d81dbec71e82da0b4b5f5\nr:aca31af0441d81dbec71e82da0b4b5f5\n")
          ),
        ]),
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ]),
      ],
      answers: [
        "00",
        "0081a7636f6e74656e74d94861646d3a61636133316166303434316438316462656337316538326461306234623566350a723a61636133316166303434316438316462656337316538326461306234623566350a",
      ],
      left: [
        "d|group", "d|group/repo",
        "b|group/repo.allowed|61646d3a61636133316166303434316438316462656337316538326461306234623566350a723a61636133316166303434316438316462656337316538326461306234623566350a",
      ]),
    Vector(
      name: "repository set takes away the access it was granted with",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("set")), (.string("content"), .string("")),
        ]),
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ]),
      ],
      answers: ["00", "0081a7636f6e74656e74a0"],
      left: ["d|group", "d|group/repo", "b|group/repo.allowed|"]),
    Vector(
      name: "repository not registered",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: false,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "blocked identity",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(2), .string("group")), (.string("operation"), .string("gperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["0081a7636f6e74656e74a0"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository administered where reading is refused to nobody",
      groupGrants: permissions(),
      repositoryGrants: permissions(read: ["nobody"], admin: ["aca31af0441d81dbec71e82da0b4b5f5"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry(
          "f", "group/repo.allowed",
          "r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
      ],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ])
      ],
      answers: ["034e6f7420666f756e64"],
      left: [
        "d|group", "d|group/repo",
        "b|group/repo.allowed|723a61636133316166303434316438316462656337316538326461306234623566350a773a30363930393261303363313934363339323037323139646430356639633834300a",
      ]),
    Vector(
      name: "repository set where the group grants reading only",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(admin: ["aca31af0441d81dbec71e82da0b4b5f5"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("set")),
          (
            .string("content"),
            .string("r:aca31af0441d81dbec71e82da0b4b5f5\nw:069092a03c194639207219dd05f9c840\n")
          ),
        ])
      ],
      answers: ["014e6f7420616c6c6f776564"],
      left: ["d|group", "d|group/repo"]),
    Vector(
      name: "repository set refusing its own reading",
      groupGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(read: ["everyone"], admin: ["everyone"]),
      registered: true,
      configured: [:],
      blocked: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      requests: [
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("set")),
          (.string("content"), .string("r:nobody\nadm:aca31af0441d81dbec71e82da0b4b5f5\n")),
        ]),
        .map([
          (.int(0), .string("group/repo")), (.string("operation"), .string("rperms")),
          (.string("step"), .string("get")),
        ]),
      ],
      answers: ["00", "034e6f7420666f756e64"],
      left: [
        "d|group", "d|group/repo",
        "b|group/repo.allowed|723a6e6f626f64790a61646d3a61636133316166303434316438316462656337316538326461306234623566350a",
      ]),
  ]

  /// Every request is answered as the reference answered it, having left what it left.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-perms-" + UUID().uuidString
      let groupPath = root + "/group"
      let repositoryPath = groupPath + "/repo"
      try FileManager.default.createDirectory(
        atPath: repositoryPath, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }

      try Self.seed(root, vector.tree)

      var group = RNGitGroup(name: "group", path: groupPath)
      group.permissions = vector.groupGrants
      if vector.registered {
        var repository = RNGitRepository(name: "repo", path: repositoryPath)
        repository.permissions = vector.repositoryGrants
        group.repositories["repo"] = repository
      }

      let identity = vector.identity.flatMap { key in
        Data(pythonHex: key).flatMap { Identity.fromBytes($0) }
      }
      XCTAssertEqual(identity == nil, vector.identity == nil, vector.name)

      var configured = RNGitConfigSection()
      for (name, entries) in vector.configured { configured.set(name, .list(entries)) }
      var handler = RNGitPermissionsHandler(
        store: RNGitRepositoryStore(
          runner: RNGitProcessRunner(), groups: ["group": group],
          identityAliases: Self.aliases,
          access: configured.keys.isEmpty ? nil : configured),
        blockedIdentities: vector.blocked && identity != nil ? [identity!.hash] : [])

      var answers: [String] = []
      for request in vector.requests {
        answers.append(handler.handle(request, from: identity).encoded.hexString)
      }
      Self.relax(root, vector.tree)
      XCTAssertEqual(answers, vector.answers, vector.name)
      XCTAssertEqual(Self.snapshot(root), vector.left, vector.name)
    }
  }

  /// Builds `tree` under `root`, which the entries are named against.
  private static func seed(_ root: String, _ tree: [Entry]) throws {
    for entry in tree {
      let path = root + "/" + entry.path
      switch entry.kind {
      case "d":
        try FileManager.default.createDirectory(
          atPath: path, withIntermediateDirectories: true)
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
        ofItemAtPath: root + "/" + entry.path)
    }
  }

  /// Puts back the permissions a tree narrowed, so what it left can be read and removed.
  private static func relax(_ root: String, _ tree: [Entry]) {
    for entry in tree where entry.kind == "m" {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: root + "/" + entry.path)
    }
  }

  /// Every directory and file under `root`, with a file the node would run marked apart.
  private static func snapshot(_ root: String) -> [String] {
    var found: [(path: String, kind: String, line: String)] = []
    var pending = [""]
    while let relative = pending.popLast() {
      let directory = relative.isEmpty ? root : root + "/" + relative
      guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory)
      else { continue }
      for entry in entries {
        let path = relative.isEmpty ? entry : relative + "/" + entry
        if RNGitWorkStore.isDirectory(directory + "/" + entry) {
          found.append((path, "d", "d|" + path))
          pending.append(path)
        } else {
          let bytes = FileManager.default.contents(atPath: directory + "/" + entry) ?? Data()
          let kind =
            FileManager.default.isExecutableFile(atPath: directory + "/" + entry) ? "x" : "b"
          found.append((path, kind, kind + "|" + path + "|" + bytes.hexString))
        }
      }
    }
    return
      found
      .sorted { $0.path == $1.path ? $0.kind < $1.kind : $0.path < $1.path }
      .map(\.line)
  }
}
