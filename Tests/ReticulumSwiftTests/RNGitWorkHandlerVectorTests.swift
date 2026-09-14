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

/// The work documents a node serves and records, as Python RNS 1.5.4 serves and records them.
///
/// Each vector is what the reference's own handler answered for a work directory seeded the
/// same way, along with everything it left behind, recorded through a stand-in for its `time`
/// module. The two peers are built from fixed private keys, so what they sign and what a
/// document records of them is the same on both sides.
final class RNGitWorkHandlerVectorTests: XCTestCase {

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
    let identity: String?
    let tree: [Entry]?
    let request: MsgPack.Value
    let answer: String
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
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity: nil,
      tree: [],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer: "014e6f74206964656e746966696564",
      left: []),
    Vector(
      name: "request not a map",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .string("group/repo"),
      answer: "02496e76616c69642072657175657374",
      left: []),
    Vector(
      name: "request nil",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .nil,
      answer: "02496e76616c69642072657175657374",
      left: []),
    Vector(
      name: "no repository named",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.string("operation"), .string("list"))]),
      answer: "024e6f207265706f7369746f727920737065636966696564",
      left: []),
    Vector(
      name: "operation missing",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.int(0), .string("group/repo"))]),
      answer: "02496e76616c69642072657175657374",
      left: []),
    Vector(
      name: "operation empty",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string(""))]),
      answer: "02496e76616c69642072657175657374",
      left: []),
    Vector(
      name: "operation nil",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .nil)]),
      answer: "02496e76616c69642072657175657374",
      left: []),
    Vector(
      name: "operation not a string",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .int(5))]),
      answer: "014e6f7420616c6c6f776564",
      left: []),
    Vector(
      name: "operation unknown",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("frobnicate")),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: []),
    Vector(
      name: "repository not a string",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.int(0), .int(5)), (.string("operation"), .string("list"))]),
      answer: "RAISED",
      left: []),
    Vector(
      name: "repository path with one component",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.int(0), .string("group")), (.string("operation"), .string("list"))]),
      answer: "034e6f7420666f756e64",
      left: []),
    Vector(
      name: "read refused",
      groupGrants: permissions(),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer: "034e6f7420666f756e64",
      left: []),
    Vector(
      name: "repository not registered",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: false,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer: "034e6f7420666f756e64",
      left: []),
    Vector(
      name: "comment without interact",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(1)), (.string("content"), .string("Hi")),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "propose without propose access",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("propose")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: []),
    Vector(
      name: "create without manage",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: []),
    Vector(
      name: "perms without admin",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("get")), (.string("doc_id"), .int(1)),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view with a document id that will not convert",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .array([.string("x")])),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a document that denies reading it",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "1.allowed", "r:nobody\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "b|1.allowed|723a6e6f626f64790a", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a document an administrator may still read",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "1.allowed", "r:nobody\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e747390a46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "b|1.allowed|723a6e6f626f64790a", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view where the document id is falsy",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "0.allowed", "r:nobody\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(0)),
      ]),
      answer: "034e6f7420666f756e64",
      left: [
        "b|0.allowed|723a6e6f626f64790a", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment where only the document grants interacting",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "f", "1.allowed",
          "i:aca31af0441d81dbec71e82da0b4b5f5\nw:aca31af0441d81dbec71e82da0b4b5f5\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(1)), (.string("content"), .string("Hi")),
      ]),
      answer: "0081a2696401",
      left: [
        "b|1.allowed|693a61636133316166303434316438316462656337316538326461306234623566350a773a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|active", "d|active/1",
        "b|active/1/1|82a7636f6e74656e74a24869a46d65746186a6666f726d6174a86d61726b646f776ea57469746c65c0a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a97369676e6174757265c0a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit where only the document grants writing",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "f", "1.allowed",
          "i:aca31af0441d81dbec71e82da0b4b5f5\nw:aca31af0441d81dbec71e82da0b4b5f5\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)), (.string("title"), .string("Renamed")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "00",
      left: [
        "b|1.allowed|693a61636133316166303434316438316462656337316538326461306234623566350a773a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a752656e616d6564a76372656174656464a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4400351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09a86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
      ]),
    Vector(
      name: "comment with a document id that will not convert",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .array([.string("x")])), (.string("content"), .string("Hi")),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit with a document id that will not convert",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .array([.string("x")])), (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list without a work directory",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: nil,
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer: "0083a661637469766590a9636f6d706c6574656490a870726f706f73656490",
      left: nil),
    Vector(
      name: "list an empty work directory",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer: "0083a661637469766590a9636f6d706c6574656490a870726f706f73656490",
      left: []),
    Vector(
      name: "list one active document",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list every scope",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "completed"), Entry("d", "completed/2"),
        Entry(
          "b", "completed/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "proposed"), Entry("d", "proposed/3"),
        Entry(
          "b", "proposed/3/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("list")),
        (.string("scope"), .string("all")),
      ]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c657465649187a2696402a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a870726f706f7365649187a2696403a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|completed", "d|completed/2",
        "b|completed/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|proposed", "d|proposed/3",
        "b|proposed/3/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list the completed scope",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "completed"), Entry("d", "completed/2"),
        Entry(
          "b", "completed/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("list")),
        (.string("scope"), .string("completed")),
      ]),
      answer:
        "0083a661637469766590a9636f6d706c657465649187a2696402a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|completed", "d|completed/2",
        "b|completed/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list a scope that is not a string",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("list")),
        (.string("scope"), .int(5)),
      ]),
      answer: "0083a661637469766590a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list a scope no folder is named for",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("list")),
        (.string("scope"), .string("everything")),
      ]),
      answer: "0083a661637469766590a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list skips a plain file in a scope",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "active/stray", "x"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/stray|78",
      ]),
    Vector(
      name: "list skips a directory not named for a number",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/notes"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/notes",
      ]),
    Vector(
      name: "list skips a document with no root",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/2"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
      ]),
    Vector(
      name: "list skips a root that does not decode",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"), Entry("f", "active/2/root", "not msgpack"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2", "b|active/2/root|6e6f74206d73677061636b",
      ]),
    Vector(
      name: "list skips a root with bytes left over",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"),
        Entry(
          "b", "active/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f505"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659287a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e74730087a2696402a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
        "b|active/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f505",
      ]),
    Vector(
      name: "list skips a root that is a mapping with a number for a key",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"), Entry("b", "active/2/root", "8101a161"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659287a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e74730087a2696402a57469746c65a8556e7469746c6564a76372656174656400a665646974656400a6617574686f72a0a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2", "b|active/2/root|8101a161",
      ]),
    Vector(
      name: "list skips a root holding nothing",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"), Entry("b", "active/2/root", "80"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2", "b|active/2/root|80",
      ]),
    Vector(
      name: "list skips a root that is not a mapping",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"), Entry("b", "active/2/root", "920102"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2", "b|active/2/root|920102",
      ]),
    Vector(
      name: "list skips a root whose metadata is not a mapping",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"),
        Entry("b", "active/2/root", "81a46d657461a4666c6174"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2", "b|active/2/root|81a46d657461a4666c6174",
      ]),
    Vector(
      name: "list a document recording nothing",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/2"),
        Entry("b", "active/2/root", "82a7636f6e74656e74a178a46d65746180"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696402a57469746c65a8556e7469746c6564a76372656174656400a665646974656400a6617574686f72a0a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: ["d|active", "d|active/2", "b|active/2/root|82a7636f6e74656e74a178a46d65746180"]),
    Vector(
      name: "list a document whose author is text",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/2"),
        Entry("b", "active/2/root", "81a46d65746181a6617574686f72a3616263"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer: "0083a661637469766590a9636f6d706c6574656490a870726f706f73656490",
      left: ["d|active", "d|active/2", "b|active/2/root|81a46d65746181a6617574686f72a3616263"]),
    Vector(
      name: "list a document whose author is a number",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/2"),
        Entry("b", "active/2/root", "81a46d65746181a6617574686f7205"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696402a57469746c65a8556e7469746c6564a76372656174656400a665646974656400a6617574686f72a23035a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: ["d|active", "d|active/2", "b|active/2/root|81a46d65746181a6617574686f7205"]),
    Vector(
      name: "list a document whose author is a list of numbers",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/2"),
        Entry("b", "active/2/root", "81a46d65746181a6617574686f729201cd012c"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696402a57469746c65a8556e7469746c6564a76372656174656400a665646974656400a6617574686f72a53031313263a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: ["d|active", "d|active/2", "b|active/2/root|81a46d65746181a6617574686f729201cd012c"]),
    Vector(
      name: "list counts only the comment files",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/1",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/2",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/1/3"), Entry("f", "active/1/notes", "x"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747302a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/1|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/2|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/1/3", "b|active/1/notes|78",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list orders by the moment of creation",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"),
        Entry(
          "b", "active/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564cd012ca66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/3"),
        Entry(
          "b", "active/3/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564ccc8a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659387a2696402a57469746c65a55469746c65a763726561746564cd012ca66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e74730087a2696403a57469746c65a55469746c65a763726561746564ccc8a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e74730087a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
        "b|active/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564cd012ca66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/3",
        "b|active/3/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564ccc8a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list keeps the order of two created together",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"),
        Entry(
          "b", "active/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659287a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e74730087a2696402a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
        "b|active/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list orders creation moments that are text",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564a162a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"),
        Entry(
          "b", "active/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564a161a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659287a2696401a57469746c65a55469746c65a763726561746564a162a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e74730087a2696402a57469746c65a55469746c65a763726561746564a161a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564a162a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
        "b|active/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564a161a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list where two creation moments cannot be compared",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564a162a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"),
        Entry(
          "b", "active/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656405a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a763726561746564a162a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
        "b|active/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656405a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list skips a document that denies reading it",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"),
        Entry(
          "b", "active/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "2.allowed", "r:nobody\n"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "b|2.allowed|723a6e6f626f64790a", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
        "b|active/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list a document numbered with leading zeroes",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/007"),
        Entry(
          "b", "active/007/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696407a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/007",
        "b|active/007/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view without a document id",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("view"))]),
      answer: "024e6f20646f63756d656e7420494420737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a document id that is nothing",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .nil),
      ]),
      answer: "024e6f20646f63756d656e7420494420737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a document id that is text",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .string(" 1 ")),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e747390a46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a document id that is text naming no number",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .string("one")),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a document id that is a fraction",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .double(1.9)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e747390a46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a scope that is not one",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)), (.string("scope"), .string("elsewhere")),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a document that is not there",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(9)),
      ]),
      answer: "034e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a document with no root",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/2"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(2)),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
      ]),
    Vector(
      name: "view a root that does not decode",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"), Entry("f", "active/2/root", "not msgpack"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(2)),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2", "b|active/2/root|6e6f74206d73677061636b",
      ]),
    Vector(
      name: "view a document in the proposed scope",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "proposed"), Entry("d", "proposed/4"),
        Entry(
          "b", "proposed/4/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(4)),
      ]),
      answer:
        "0085a2696404a573636f7065a870726f706f736564a7636f6e74656e74a4426f6479a8636f6d6d656e747390a46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "d|proposed", "d|proposed/4",
        "b|proposed/4/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a document recording everything",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4020102a86964656e74697479c4020304"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e747390a46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c4020304a97369676e6174757265c4020102a6666f726d6174a86d61726b646f776e",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4020102a86964656e74697479c4020304",
      ]),
    Vector(
      name: "view a document recording nothing",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"), Entry("b", "active/1/root", "81a46d65746180"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a0a8636f6d6d656e747390a46d65746187a57469746c65a8556e7469746c6564a76372656174656400a665646974656400a6617574686f72a0a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: ["d|active", "d|active/1", "b|active/1/root|81a46d65746180"]),
    Vector(
      name: "view a document whose metadata is not a mapping",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry("b", "active/1/root", "81a46d657461a4666c6174"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: ["d|active", "d|active/1", "b|active/1/root|81a46d657461a4666c6174"]),
    Vector(
      name: "view the comments on a document",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/2",
          "82a7636f6e74656e74a65365636f6e64a46d65746184a6666f726d6174a86d61726b646f776ea76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/1",
          "82a7636f6e74656e74a54669727374a46d65746184a6666f726d6174a86d61726b646f776ea76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e74739286a2696401a7636f6e74656e74a54669727374a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776e86a2696402a7636f6e74656e74a65365636f6e64a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "d|active", "d|active/1",
        "b|active/1/1|82a7636f6e74656e74a54669727374a46d65746184a6666f726d6174a86d61726b646f776ea76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/2|82a7636f6e74656e74a65365636f6e64a46d65746184a6666f726d6174a86d61726b646f776ea76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view skips a comment that does not decode",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/1",
          "82a7636f6e74656e74a54669727374a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "active/1/2", "not msgpack"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e74739186a2696401a7636f6e74656e74a54669727374a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "d|active", "d|active/1",
        "b|active/1/1|82a7636f6e74656e74a54669727374a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/2|6e6f74206d73677061636b",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view skips a comment whose author is text",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("b", "active/1/1", "81a46d65746181a6617574686f72a3616263"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e747390a46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "d|active", "d|active/1", "b|active/1/1|81a46d65746181a6617574686f72a3616263",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view skips a comment that is a directory",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/1/1"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e747390a46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "d|active", "d|active/1", "d|active/1/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view skips a file not named for a number",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "active/1/notes", "x"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e747390a46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "d|active", "d|active/1", "b|active/1/notes|78",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view comments numbered the same",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/07",
          "82a7636f6e74656e74a6506164646564a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/7",
          "82a7636f6e74656e74a5506c61696ea46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a4426f6479a8636f6d6d656e74739286a2696407a7636f6e74656e74a5506c61696ea76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776e86a2696407a7636f6e74656e74a6506164646564a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea46d65746187a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: [
        "d|active", "d|active/1",
        "b|active/1/07|82a7636f6e74656e74a6506164646564a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/7|82a7636f6e74656e74a5506c61696ea46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "create with no signature",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
      ]),
      answer: "024e6f207369676e61747572652070726f7669646564",
      left: []),
    Vector(
      name: "create with a signature of the wrong length",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(pythonHex: "0000000000000000000000000000000000000000000000000000000000000000")
              ?? Data())
        ),
      ]),
      answer: "02496e76616c6964207369676e6174757265206c656e677468",
      left: []),
    Vector(
      name: "create with a signature over other content",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "566005fe5603ab52338af05563fac3c6d8513fe362e4aacc1b9de52410d389b60cfb8c4b4284574d67ed59ab9af6d4289357867e0dcae0c07e5aaa93a47f3608"
            ) ?? Data())
        ),
      ]),
      answer: "02496e76616c6964207369676e6174757265",
      left: []),
    Vector(
      name: "create with a signature that is text",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .string("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
        ),
      ]),
      answer: "02496e76616c6964207369676e6174757265",
      left: []),
    Vector(
      name: "create beyond the content limit",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("Title")),
        (.string("content"), .string(String(repeating: "m", count: 262143))),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "7c90653152e4be77261159cc16b6ff1ab9e53012cb58241137df9f84580255ce397ad930df7dba5126caa1fd1b43170cc342b00161ae0f403c9e998eb13a820f"
            ) ?? Data())
        ),
      ]),
      answer: "02436f6e74656e74206c696d6974206578636565646564",
      left: []),
    Vector(
      name: "create with no title",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("   ")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "025469746c65206973207265717569726564",
      left: []),
    Vector(
      name: "create with no content",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("  ")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "02436f6e74656e74206973207265717569726564",
      left: []),
    Vector(
      name: "create with a title that is not text",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .int(5)), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: []),
    Vector(
      name: "create with a format that is not text",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (.string("format"), .int(5)),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: []),
    Vector(
      name: "create a document",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("  Spaced  ")), (.string("content"), .string("  Body  ")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "0082a2696401a573636f7065a6616374697665",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a6537061636564a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4406aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0aa86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
      ]),
    Vector(
      name: "create written in micron",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (.string("format"), .string("micron")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "0082a2696401a573636f7065a6616374697665",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a66d6963726f6ea57469746c65a154a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4406aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0aa86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
      ]),
    Vector(
      name: "create written in a markup the node does not know",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (.string("format"), .string("html")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "0082a2696401a573636f7065a6616374697665",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a154a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4406aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0aa86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
      ]),
    Vector(
      name: "create numbers past the highest of every scope",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/4"),
        Entry(
          "b", "active/4/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "completed"), Entry("d", "completed/9"),
        Entry(
          "b", "completed/9/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "proposed"), Entry("d", "proposed/2"),
        Entry(
          "b", "proposed/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "0082a269640aa573636f7065a6616374697665",
      left: [
        "d|active", "d|active/10",
        "b|active/10/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a154a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4406aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0aa86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
        "d|active/4",
        "b|active/4/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|completed", "d|completed/9",
        "b|completed/9/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|proposed", "d|proposed/2",
        "b|proposed/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "create where a scope is a file",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [Entry("f", "active", "not a directory")],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "ff4572726f7220736176696e6720646f63756d656e74",
      left: ["b|active|6e6f742061206469726563746f7279"]),
    Vector(
      name: "propose a document",
      groupGrants: permissions(read: ["everyone"], propose: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("propose")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "0082a2696401a573636f7065a870726f706f736564",
      left: [
        "b|1.allowed|693a61636133316166303434316438316462656337316538326461306234623566350a773a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|proposed", "d|proposed/1",
        "b|proposed/1/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a154a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4406aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0aa86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
      ]),
    Vector(
      name: "propose with no signature",
      groupGrants: permissions(read: ["everyone"], propose: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("propose")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
      ]),
      answer: "024e6f207369676e61747572652070726f7669646564",
      left: []),
    Vector(
      name: "propose beside documents already numbered",
      groupGrants: permissions(read: ["everyone"], propose: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/3"),
        Entry(
          "b", "active/3/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("propose")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "0082a2696404a573636f7065a870726f706f736564",
      left: [
        "b|4.allowed|693a61636133316166303434316438316462656337316538326461306234623566350a773a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|active", "d|active/3",
        "b|active/3/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|proposed", "d|proposed/4",
        "b|proposed/4/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a154a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4406aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0aa86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
      ]),
    Vector(
      name: "edit a scope that is not one",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)), (.string("scope"), .string("elsewhere")),
        (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit with no signature",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)), (.string("title"), .string("T")),
      ]),
      answer: "024e6f207369676e61747572652070726f7669646564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit with a signature of the wrong length",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)), (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(pythonHex: "0000000000000000000000000000000000000000000000000000000000000000")
              ?? Data())
        ),
      ]),
      answer: "02496e76616c6964207369676e6174757265206c656e677468",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit with a signature over other content",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)), (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "02496e76616c6964207369676e6174757265",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit beyond the content limit",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)),
        (.string("content"), .string(String(repeating: "m", count: 262143))),
        (.string("title"), .string("Title")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "7c90653152e4be77261159cc16b6ff1ab9e53012cb58241137df9f84580255ce397ad930df7dba5126caa1fd1b43170cc342b00161ae0f403c9e998eb13a820f"
            ) ?? Data())
        ),
      ]),
      answer: "02436f6e74656e74206c696d6974206578636565646564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit changing nothing",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "024e6f206368616e67657320737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit where the document id is falsy",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(0)), (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "024e6f20646f63756d656e7420494420737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit a document that is not there",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(9)), (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "034e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "edit a document with no root",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/2"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(2)), (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
      ]),
    Vector(
      name: "edit a root that does not decode",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/2"), Entry("f", "active/2/root", "not msgpack"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(2)), (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: ["d|active", "d|active/2", "b|active/2/root|6e6f74206d73677061636b"]),
    Vector(
      name: "edit a document written by another",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)), (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "014e6f206163636573732c206e6f7420617574686f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840",
      ]),
    Vector(
      name: "edit the title",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)), (.string("title"), .string("  Renamed  ")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "00",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a752656e616d6564a76372656174656464a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4400351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09a86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
      ]),
    Vector(
      name: "edit the content",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)), (.string("content"), .string("  Fresh  ")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6118da201f5e73fd4192aed446bd8e6fbd7dc056d3e5f1b75cd655c6f93e5abc16ad3b1f3f30ef048a1eb39f4cdb1a440fcd7f1686324581f7462233b32dc908"
            ) ?? Data())
        ),
      ]),
      answer: "00",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a54672657368a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4406118da201f5e73fd4192aed446bd8e6fbd7dc056d3e5f1b75cd655c6f93e5abc16ad3b1f3f30ef048a1eb39f4cdb1a440fcd7f1686324581f7462233b32dc908a86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
      ]),
    Vector(
      name: "edit a document in the proposed scope",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "proposed"), Entry("d", "proposed/3"),
        Entry(
          "b", "proposed/3/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(3)), (.string("title"), .string("Renamed")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "00",
      left: [
        "d|proposed", "d|proposed/3",
        "b|proposed/3/root|82a7636f6e74656e74a4426f6479a46d65746187a6666f726d6174a86d61726b646f776ea57469746c65a752656e616d6564a76372656174656464a6656469746564cb41d954fc40200000a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5a97369676e6174757265c4400351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09a86964656e74697479c4408f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7",
      ]),
    Vector(
      name: "edit a document whose metadata is not a mapping",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry("b", "active/1/root", "81a46d657461a4666c6174"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(1)), (.string("title"), .string("T")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "0351c073555469596be3801a566392d99ea11ea111f62d33ee06417cfcd7b9f1a1cc8759c901732535cef29078b9ec89350f701703a2f28f8e96b68407265d09"
            ) ?? Data())
        ),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: ["d|active", "d|active/1", "b|active/1/root|81a46d657461a4666c6174"]),
    Vector(
      name: "delete a scope that is not one",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(1)), (.string("scope"), .string("elsewhere")),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "delete without a document id",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("delete"))]),
      answer: "024e6f20646f63756d656e7420494420737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "delete where the document id is falsy",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(0)),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "delete a document that is not there",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(9)),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "delete a document with no root",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/2"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(2)),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
      ]),
    Vector(
      name: "delete a root that does not decode",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/2"), Entry("f", "active/2/root", "not msgpack"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(2)),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: ["d|active", "d|active/2", "b|active/2/root|6e6f74206d73677061636b"]),
    Vector(
      name: "delete a document written by another",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840"
        ), Entry("f", "1.allowed", "r:everyone\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "014e6f206163636573732c206e6f7420617574686f72",
      left: [
        "b|1.allowed|723a65766572796f6e650a", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840",
      ]),
    Vector(
      name: "delete a document with no permissions file",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "delete a document",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "1.allowed", "r:everyone\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "00",
      left: ["d|active"]),
    Vector(
      name: "delete a document and the comments under it",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/1",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "1.allowed", "r:everyone\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "00",
      left: ["d|active"]),
    Vector(
      name: "delete a document another wrote, as an administrator",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840"
        ), Entry("f", "1.allowed", "r:everyone\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "00",
      left: ["d|active"]),
    Vector(
      name: "comment a scope that is not one",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(1)), (.string("scope"), .string("elsewhere")),
        (.string("content"), .string("Hi")),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment beyond the content limit",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(1)),
        (.string("content"), .string(String(repeating: "m", count: 262145))),
      ]),
      answer: "02436f6e74656e74206c696d6974206578636565646564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment without a document id",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("content"), .string("Hi")),
      ]),
      answer: "024e6f20646f63756d656e7420494420737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment where the document id is falsy",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(0)), (.string("content"), .string("Hi")),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment with no content",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(1)), (.string("content"), .string("  ")),
      ]),
      answer: "02436f6e74656e74206973207265717569726564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment a document that is not there",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(9)), (.string("content"), .string("Hi")),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment a document with no root",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/2"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(2)), (.string("content"), .string("Hi")),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
      ]),
    Vector(
      name: "comment a document",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(1)), (.string("content"), .string("  Hi  ")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a"
            ) ?? Data())
        ),
      ]),
      answer: "0081a2696401",
      left: [
        "d|active", "d|active/1",
        "b|active/1/1|82a7636f6e74656e74a24869a46d65746186a6666f726d6174a86d61726b646f776ea57469746c65c0a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a97369676e6174757265c4406aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0aa6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment written in micron",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(1)), (.string("content"), .string("Hi")),
        (.string("format"), .string("micron")),
      ]),
      answer: "0081a2696401",
      left: [
        "d|active", "d|active/1",
        "b|active/1/1|82a7636f6e74656e74a24869a46d65746186a6666f726d6174a66d6963726f6ea57469746c65c0a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a97369676e6174757265c0a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment numbers past the comments already there",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/1",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/4",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(1)), (.string("content"), .string("Hi")),
      ]),
      answer: "0081a2696405",
      left: [
        "d|active", "d|active/1",
        "b|active/1/1|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/4|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/5|82a7636f6e74656e74a24869a46d65746186a6666f726d6174a86d61726b646f776ea57469746c65c0a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a97369676e6174757265c0a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment where a name reads as a number but is not one",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/1",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/\u{B2}",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(1)), (.string("content"), .string("Hi")),
      ]),
      answer: "0081a2696401",
      left: [
        "d|active", "d|active/1",
        "b|active/1/1|82a7636f6e74656e74a24869a46d65746186a6666f726d6174a86d61726b646f776ea57469746c65c0a763726561746564cb41d954fc40200000a6656469746564cb41d954fc40200000a97369676e6174757265c0a6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/\u{B2}|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "complete without a document id",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("complete"))]
      ),
      answer: "024e6f20646f63756d656e7420494420737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "complete a document id that is text naming no number",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .string("one")),
      ]),
      answer: "02496e76616c696420646f63756d656e74204944",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "complete a document id that is text naming a number",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .string(" 1 ")),
      ]),
      answer: "0082a2696401a573636f7065a9636f6d706c65746564",
      left: [
        "d|active", "d|completed", "d|completed/1",
        "b|completed/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "complete a document that is not there",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .int(9)),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "complete a document with no root",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/2"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .int(2)),
      ]),
      answer: "ff4572726f72206c6f6164696e6720646f63756d656e74",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
      ]),
    Vector(
      name: "complete a document written by another",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840",
      ]),
    Vector(
      name: "complete a document another wrote, as an administrator",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "0082a2696401a573636f7065a9636f6d706c65746564",
      left: [
        "d|active", "d|completed", "d|completed/1",
        "b|completed/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840",
      ]),
    Vector(
      name: "complete a document",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
        Entry(
          "b", "active/1/1",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "0082a2696401a573636f7065a9636f6d706c65746564",
      left: [
        "d|active", "d|completed", "d|completed/1",
        "b|completed/1/1|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|completed/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "complete where the destination is already there",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "completed"), Entry("d", "completed/1"),
        Entry(
          "b", "completed/1/root",
          "82a7636f6e74656e74a54f6c646572a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "0082a2696401a573636f7065a9636f6d706c65746564",
      left: [
        "d|active", "d|completed", "d|completed/1", "d|completed/1/1",
        "b|completed/1/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|completed/1/root|82a7636f6e74656e74a54f6c646572a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "complete where the destination already holds the name",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "completed"), Entry("d", "completed/1"),
        Entry(
          "b", "completed/1/root",
          "82a7636f6e74656e74a54f6c646572a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "completed/1/1"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|completed", "d|completed/1", "d|completed/1/1",
        "b|completed/1/root|82a7636f6e74656e74a54f6c646572a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "complete a document in the proposed scope",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "proposed"), Entry("d", "proposed/1"),
        Entry(
          "b", "proposed/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("complete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|proposed", "d|proposed/1",
        "b|proposed/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "activate without a document id",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("activate"))]
      ),
      answer: "024e6f20646f63756d656e7420494420737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "activate a document id that is text naming no number",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("activate")),
        (.string("doc_id"), .string("one")),
      ]),
      answer: "02496e76616c696420646f63756d656e74204944",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "activate a document that is not there",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("activate")),
        (.string("doc_id"), .int(9)),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "activate a document that is already active",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("activate")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "activate a completed document",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "completed"), Entry("d", "completed/1"),
        Entry(
          "b", "completed/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("activate")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "0082a2696401a573636f7065a6616374697665",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|completed",
      ]),
    Vector(
      name: "activate a proposed document",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "proposed"), Entry("d", "proposed/2"),
        Entry(
          "b", "proposed/2/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("activate")),
        (.string("doc_id"), .int(2)),
      ]),
      answer: "0082a2696402a573636f7065a6616374697665",
      left: [
        "d|active", "d|active/2",
        "b|active/2/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|proposed",
      ]),
    Vector(
      name: "activate prefers the completed scope",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "completed"), Entry("d", "completed/1"),
        Entry(
          "b", "completed/1/root",
          "82a7636f6e74656e74a4446f6e65a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "proposed"), Entry("d", "proposed/1"),
        Entry(
          "b", "proposed/1/root",
          "82a7636f6e74656e74a74f666665726564a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("activate")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "0082a2696401a573636f7065a6616374697665",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4446f6e65a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|completed", "d|proposed", "d|proposed/1",
        "b|proposed/1/root|82a7636f6e74656e74a74f666665726564a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "activate a document with no root",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [Entry("d", "completed"), Entry("d", "completed/2")],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("activate")),
        (.string("doc_id"), .int(2)),
      ]),
      answer: "ff4572726f72206c6f6164696e6720646f63756d656e74",
      left: ["d|completed", "d|completed/2"]),
    Vector(
      name: "activate a document written by another",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "completed"), Entry("d", "completed/1"),
        Entry(
          "b", "completed/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("activate")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: [
        "d|completed", "d|completed/1",
        "b|completed/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410069092a03c194639207219dd05f9c840",
      ]),
    Vector(
      name: "activate where the destination is already there",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a743757272656e74a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "completed"), Entry("d", "completed/1"),
        Entry(
          "b", "completed/1/root",
          "82a7636f6e74656e74a4446f6e65a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("activate")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "0082a2696401a573636f7065a6616374697665",
      left: [
        "d|active", "d|active/1", "d|active/1/1",
        "b|active/1/1/root|82a7636f6e74656e74a4446f6e65a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "b|active/1/root|82a7636f6e74656e74a743757272656e74a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|completed",
      ]),
    Vector(
      name: "perms without a step",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("perms"))]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms with a step the node does not know",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("purge")),
      ]),
      answer: "02496e76616c69642073746570",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms get without a document id",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("get")),
      ]),
      answer: "024e6f20646f63756d656e7420494420737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms get a document id that is text naming no number",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("get")), (.string("doc_id"), .string("one")),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms get a document that is not there",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("get")), (.string("doc_id"), .int(9)),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms get a document with no root",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active/2"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("get")), (.string("doc_id"), .int(2)),
      ]),
      answer: "ff4572726f72206c6f6164696e6720646f63756d656e74",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2",
      ]),
    Vector(
      name: "perms get where the document refuses administering",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "1.allowed", "adm:nobody\nr:everyone\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("get")), (.string("doc_id"), .int(1)),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: [
        "b|1.allowed|61646d3a6e6f626f64790a723a65766572796f6e650a", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms get a document with no permissions file",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("get")), (.string("doc_id"), .int(1)),
      ]),
      answer: "0081a7636f6e74656e74a0",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms get a document",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "1.allowed", "r:everyone\ni:aca31af0441d81dbec71e82da0b4b5f5\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("get")), (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0081a7636f6e74656e74d92e723a65766572796f6e650a693a61636133316166303434316438316462656337316538326461306234623566350a",
      left: [
        "b|1.allowed|723a65766572796f6e650a693a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms set without a document id",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("set")), (.string("content"), .string("r:everyone\n")),
      ]),
      answer: "024e6f20646f63756d656e7420494420737065636966696564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms set a document that is not there",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("set")), (.string("doc_id"), .int(9)),
        (.string("content"), .string("r:everyone\n")),
      ]),
      answer: "03446f63756d656e74206e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms set a line the node cannot read",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("set")), (.string("doc_id"), .int(1)),
        (.string("content"), .string("r:everyone\nnonsense\n")),
      ]),
      answer: "02496e76616c6964207065726d697373696f6e20226e6f6e73656e736522206f6e206c696e652032",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms set a permission the node does not know",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("set")), (.string("doc_id"), .int(1)),
        (.string("content"), .string("frobnicate:everyone\n")),
      ]),
      answer:
        "02496e76616c6964207065726d697373696f6e202266726f626e69636174653a65766572796f6e6522206f6e206c696e652031",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms set past comments and blank lines",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("set")), (.string("doc_id"), .int(1)),
        (.string("content"), .string("# a note\n\nr:everyone\n")),
      ]),
      answer: "00",
      left: [
        "b|1.allowed|232061206e6f74650a0a723a65766572796f6e650a", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms set nothing",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "1.allowed", "r:everyone\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("set")), (.string("doc_id"), .int(1)),
      ]),
      answer: "00",
      left: [
        "b|1.allowed|", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms set a document",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("set")), (.string("doc_id"), .int(1)),
        (.string("content"), .string("r:everyone\nw:aca31af0441d81dbec71e82da0b4b5f5\n")),
      ]),
      answer: "00",
      left: [
        "b|1.allowed|723a65766572796f6e650a773a61636133316166303434316438316462656337316538326461306234623566350a",
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment where the document id is falsy and a document grants interacting",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("f", "0.allowed", "i:everyone\n"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(0)), (.string("content"), .string("Hi")),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: [
        "b|0.allowed|693a65766572796f6e650a", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "create with a signature that is too long",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("T")), (.string("content"), .string("Body")),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "6aacbbb35a3f4fec469702c35e5708b047ba6f64cfba70138b91bf6cecd8d7e7106a3d74ba1801402cc4188aa651066dde876f1df05686e21641c3b37f71ce0a00"
            ) ?? Data())
        ),
      ]),
      answer: "02496e76616c6964207369676e6174757265206c656e677468",
      left: []),
    Vector(
      name: "create at the content limit",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [Entry("f", "active", "not a directory")],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("create")),
        (.string("title"), .string("Title")),
        (.string("content"), .string(String(repeating: "m", count: 262131))),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "d10c229a96fe45fe51e57561824ce6b0812e262608dbad42401cd0444b7accb6a6de2307b7d59d6723150b388809eb13247fe4db575edd6f9b86ab1e754a090c"
            ) ?? Data())
        ),
      ]),
      answer: "ff4572726f7220736176696e6720646f63756d656e74",
      left: ["b|active|6e6f742061206469726563746f7279"]),
    Vector(
      name: "edit at the content limit",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("edit")),
        (.string("doc_id"), .int(9)), (.string("title"), .string("Title")),
        (.string("content"), .string(String(repeating: "m", count: 262139))),
        (
          .string("signature"),
          .bytes(
            Data(
              pythonHex:
                "76eb8db0f1fcbaf2928686150cda6f8859d6da8939559ebb838df157194b1b4dc86e3672f21c6d050556435e81854467835cfbda87e4f5bf432666354bc69005"
            ) ?? Data())
        ),
      ]),
      answer: "034e6f7420666f756e64",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "comment at the content limit",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("comment")),
        (.string("doc_id"), .int(9)),
        (.string("content"), .string(String(repeating: "m", count: 262144))),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms where the repository grants no writing",
      groupGrants: permissions(read: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("get")), (.string("doc_id"), .int(1)),
      ]),
      answer: "014e6f7420616c6c6f776564",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "perms with a step that is empty",
      groupGrants: permissions(
        read: ["everyone"], write: ["everyone"], interact: ["everyone"], admin: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("perms")),
        (.string("step"), .string("")),
      ]),
      answer: "02496e76616c69642072657175657374",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a root holding a key twice",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"), Entry("b", "active/1/root", "82a16101a16102"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "ff4572726f72206c6f6164696e6720646f63756d656e74",
      left: ["d|active", "d|active/1", "b|active/1/root|82a16101a16102"]),
    Vector(
      name: "view a root keyed by a list",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"), Entry("b", "active/1/root", "8191a16101"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a0a8636f6d6d656e747390a46d65746187a57469746c65a8556e7469746c6564a76372656174656400a665646974656400a6617574686f72a0a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: ["d|active", "d|active/1", "b|active/1/root|8191a16101"]),
    Vector(
      name: "list skips a root holding a key twice",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "active"), Entry("d", "active/2"),
        Entry("b", "active/2/root", "82a16101a16102"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer:
        "0083a66163746976659187a2696401a57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72d9206163613331616630343431643831646265633731653832646130623462356635a6666f726d6174a86d61726b646f776ea8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
        "d|active/2", "b|active/2/root|82a16101a16102",
      ]),
    Vector(
      name: "delete a document whose permissions are a directory",
      groupGrants: permissions(read: ["everyone"], write: ["everyone"], interact: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("d", "1.allowed"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("delete")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|1.allowed", "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "list where a scope cannot be read",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("m", "active", "100"),
      ],
      request: .map([(.int(0), .string("group/repo")), (.string("operation"), .string("list"))]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view where the comments cannot be listed",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry(
          "b", "active/1/root",
          "82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5"
        ), Entry("m", "active/1", "100"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "ff52656d6f7465206572726f72",
      left: [
        "d|active", "d|active/1",
        "b|active/1/root|82a7636f6e74656e74a4426f6479a46d65746185a6666f726d6174a86d61726b646f776ea57469746c65a55469746c65a76372656174656464a66564697465646ea6617574686f72c410aca31af0441d81dbec71e82da0b4b5f5",
      ]),
    Vector(
      name: "view a root keyed by a list twice",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry("b", "active/1/root", "8291a1610191a16102"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer:
        "0085a2696401a573636f7065a6616374697665a7636f6e74656e74a0a8636f6d6d656e747390a46d65746187a57469746c65a8556e7469746c6564a76372656174656400a665646974656400a6617574686f72a0a86964656e74697479c0a97369676e6174757265c0a6666f726d6174a86d61726b646f776e",
      left: ["d|active", "d|active/1", "b|active/1/root|8291a1610191a16102"]),
    Vector(
      name: "view a root keyed by a list holding a mapping",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"), Entry("b", "active/1/root", "819181a1610101"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "ff4572726f72206c6f6164696e6720646f63756d656e74",
      left: ["d|active", "d|active/1", "b|active/1/root|819181a1610101"]),
    Vector(
      name: "view a root keyed by a mapping",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"), Entry("b", "active/1/root", "8181a1610101"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "ff4572726f72206c6f6164696e6720646f63756d656e74",
      left: ["d|active", "d|active/1", "b|active/1/root|8181a1610101"]),
    Vector(
      name: "view a root keyed by one number written two ways",
      groupGrants: permissions(read: ["everyone"]),
      repositoryGrants: permissions(),
      registered: true,
      identity:
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f",
      tree: [
        Entry("d", "active"), Entry("d", "active/1"),
        Entry("b", "active/1/root", "8201a161cb3ff0000000000000a162"),
      ],
      request: .map([
        (.int(0), .string("group/repo")), (.string("operation"), .string("view")),
        (.string("doc_id"), .int(1)),
      ]),
      answer: "ff4572726f72206c6f6164696e6720646f63756d656e74",
      left: ["d|active", "d|active/1", "b|active/1/root|8201a161cb3ff0000000000000a162"]),
  ]

  /// Every request is answered as the reference answered it, having left what it left.
  func testAnswersMatchTheReference() throws {
    for vector in Self.vectors {
      let root = NSTemporaryDirectory() + "rngit-work-" + UUID().uuidString
      let groupPath = root + "/group"
      let repositoryPath = groupPath + "/repo"
      let workPath = RNGitWorkStore.directory(forRepository: repositoryPath)
      try FileManager.default.createDirectory(
        atPath: repositoryPath, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(atPath: root) }

      if let tree = vector.tree { try Self.seed(workPath, tree) }

      var group = RNGitGroup(name: "group", path: groupPath)
      group.permissions = vector.groupGrants
      if vector.registered {
        var repository = RNGitRepository(name: "repo", path: repositoryPath)
        repository.permissions = vector.repositoryGrants
        group.repositories["repo"] = repository
      }

      let handler = RNGitWorkHandler(
        access: RNGitAccessControl(groups: ["group": group]), clock: { 1_700_000_000.5 })

      let identity = vector.identity.flatMap { key in
        Data(pythonHex: key).flatMap { Identity.fromBytes($0) }
      }
      XCTAssertEqual(identity == nil, vector.identity == nil, vector.name)

      let answer = handler.handle(vector.request, from: identity)
      Self.relax(workPath, vector.tree)
      XCTAssertEqual(
        answer.map { $0.encoded.hexString } ?? "RAISED", vector.answer, vector.name)
      XCTAssertEqual(Self.snapshot(workPath), vector.left, vector.name)
    }
  }

  /// Builds `tree` under `root`, which the entries are named against.
  private static func seed(_ root: String, _ tree: [Entry]) throws {
    try FileManager.default.createDirectory(
      atPath: root, withIntermediateDirectories: true)
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
  private static func relax(_ root: String, _ tree: [Entry]?) {
    for entry in tree ?? [] where entry.kind == "m" {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: root + "/" + entry.path)
    }
  }

  /// Every directory and file under `root`, or `nil` where there is no directory at all.
  private static func snapshot(_ root: String) -> [String]? {
    guard RNGitWorkStore.isDirectory(root) else { return nil }
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
          found.append((path, "b", "b|" + path + "|" + bytes.hexString))
        }
      }
    }
    return
      found
      .sorted { $0.path == $1.path ? $0.kind < $1.kind : $0.path < $1.path }
      .map(\.line)
  }
}
