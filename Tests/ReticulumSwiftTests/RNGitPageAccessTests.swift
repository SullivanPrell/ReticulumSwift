//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest

@testable import ReticulumSwift

/// What a reader of the pages may see, as Python RNS 1.5.4 resolves it.
final class RNGitPageAccessTests: XCTestCase {

  /// An identity recovered from a fixed key, so its hash is the reference's own.
  private static let alice = Data(pythonHex: "ef330a1940c70349459fc4401d273cb9")!

  /// A second such identity, which the node blocks.
  private static let bob = Data(pythonHex: "138b31508ad4e73d8c850d8029c8823e")!

  /// The grants the reference resolved against.
  private static func access() -> RNGitPageAccess {
    func granting(
      _ permission: WritableKeyPath<RNGitPermissionSet, [RNGitPermissionTarget]>,
      _ targets: [RNGitPermissionTarget]
    ) -> RNGitPermissionSet {
      var set = RNGitPermissionSet()
      set[keyPath: permission] = targets
      return set
    }

    let openToAll = RNGitGroup(
      name: "public", path: "/g/public",
      repositories: [
        "open": RNGitRepository(name: "open", path: "/g/public/open"),
        "closed": RNGitRepository(
          name: "closed", path: "/g/public/closed",
          permissions: granting(\.read, [.nobody])),
        "alices": RNGitRepository(
          name: "alices", path: "/g/public/alices",
          permissions: granting(\.read, [.identity(alice)])),
      ],
      permissions: granting(\.read, [.everyone]))

    let openToAlice = RNGitGroup(
      name: "private", path: "/g/private",
      repositories: [
        "one": RNGitRepository(name: "one", path: "/g/private/one"),
        "two": RNGitRepository(
          name: "two", path: "/g/private/two",
          permissions: granting(\.admin, [.identity(bob)])),
      ],
      permissions: granting(\.read, [.identity(alice)]))

    let openToNobody = RNGitGroup(
      name: "shut", path: "/g/shut",
      repositories: ["only": RNGitRepository(name: "only", path: "/g/shut/only")])

    return RNGitPageAccess(
      control: RNGitAccessControl(
        groups: ["public": openToAll, "private": openToAlice, "shut": openToNobody],
        blockedIdentities: [bob]))
  }

  /// The standing identity is the one the reference recovered from a key of nothing but zeroes.
  func testTheStandingIdentityMatchesTheReference() {
    XCTAssertEqual(
      Self.access().nullIdentityHash.map { String(format: "%02x", $0) }.joined(),
      "d7db22f63b453c23bb0688dde565b7c1")
  }

  /// What `alice` may see is what the reference resolved.
  func testWhatAliceMaySeeMatchesTheReference() {
    let access = Self.access()
    let reader: Data? = Self.alice
    let readable = access.groups(readableBy: reader)

    XCTAssertEqual(readable.keys.sorted(), ["private", "public"])
    XCTAssertEqual(readable["private"]?.path, "/g/private")
    XCTAssertEqual(
      readable["private"]?.repositories.mapValues(\.path),
      ["one": "/g/private/one", "two": "/g/private/two"])
    XCTAssertEqual(readable["public"]?.path, "/g/public")
    XCTAssertEqual(
      readable["public"]?.repositories.mapValues(\.path),
      ["alices": "/g/public/alices", "open": "/g/public/open"])

    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "private").mapValues(\.path),
      ["one": "/g/private/one", "two": "/g/private/two"])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "public").mapValues(\.path),
      ["alices": "/g/public/alices", "open": "/g/public/open"])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "shut").mapValues(\.path),
      [:])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "nosuch").mapValues(\.path), [:])

    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "open")?.path,
      "/g/public/open")
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "closed")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "alices")?.path,
      "/g/public/alices")
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "private", named: "one")?.path,
      "/g/private/one")
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "private", named: "two")?.path,
      "/g/private/two")
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "shut", named: "only")?.path,
      nil)
    XCTAssertNil(access.repository(readableBy: reader, in: "public", named: "nosuch"))
    XCTAssertNil(access.repository(readableBy: reader, in: "nosuch", named: "one"))

    XCTAssertEqual(
      access.allows(reader, group: "public", repository: "open", permission: .read),
      true)
    XCTAssertEqual(
      access.allows(reader, group: "public", repository: "closed", permission: .read),
      false)
  }

  /// What `bob` may see is what the reference resolved.
  func testWhatBobMaySeeMatchesTheReference() {
    let access = Self.access()
    let reader: Data? = Self.bob
    let readable = access.groups(readableBy: reader)

    XCTAssertEqual(readable.keys.sorted(), [])

    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "private").mapValues(\.path),
      [:])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "public").mapValues(\.path),
      [:])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "shut").mapValues(\.path),
      [:])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "nosuch").mapValues(\.path), [:])

    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "open")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "closed")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "alices")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "private", named: "one")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "private", named: "two")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "shut", named: "only")?.path,
      nil)
    XCTAssertNil(access.repository(readableBy: reader, in: "public", named: "nosuch"))
    XCTAssertNil(access.repository(readableBy: reader, in: "nosuch", named: "one"))

    XCTAssertEqual(
      access.allows(reader, group: "public", repository: "open", permission: .read),
      false)
    XCTAssertEqual(
      access.allows(reader, group: "public", repository: "closed", permission: .read),
      false)
  }

  /// What `null` may see is what the reference resolved.
  func testWhatNullMaySeeMatchesTheReference() {
    let access = Self.access()
    let reader: Data? = Self.access().nullIdentityHash
    let readable = access.groups(readableBy: reader)

    XCTAssertEqual(readable.keys.sorted(), ["public"])
    XCTAssertEqual(readable["public"]?.path, "/g/public")
    XCTAssertEqual(
      readable["public"]?.repositories.mapValues(\.path), ["open": "/g/public/open"])

    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "private").mapValues(\.path),
      [:])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "public").mapValues(\.path),
      ["open": "/g/public/open"])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "shut").mapValues(\.path),
      [:])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "nosuch").mapValues(\.path), [:])

    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "open")?.path,
      "/g/public/open")
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "closed")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "alices")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "private", named: "one")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "private", named: "two")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "shut", named: "only")?.path,
      nil)
    XCTAssertNil(access.repository(readableBy: reader, in: "public", named: "nosuch"))
    XCTAssertNil(access.repository(readableBy: reader, in: "nosuch", named: "one"))

    XCTAssertEqual(
      access.allows(reader, group: "public", repository: "open", permission: .read),
      true)
    XCTAssertEqual(
      access.allows(reader, group: "public", repository: "closed", permission: .read),
      false)
  }

  /// What `none` may see is what the reference resolved.
  func testWhatNoneMaySeeMatchesTheReference() {
    let access = Self.access()
    let reader: Data? = nil
    let readable = access.groups(readableBy: reader)

    XCTAssertEqual(readable.keys.sorted(), ["public"])
    XCTAssertEqual(readable["public"]?.path, "/g/public")
    XCTAssertEqual(
      readable["public"]?.repositories.mapValues(\.path), ["open": "/g/public/open"])

    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "private").mapValues(\.path),
      [:])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "public").mapValues(\.path),
      ["open": "/g/public/open"])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "shut").mapValues(\.path),
      [:])
    XCTAssertEqual(
      access.repositories(readableBy: reader, in: "nosuch").mapValues(\.path), [:])

    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "open")?.path,
      "/g/public/open")
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "closed")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "public", named: "alices")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "private", named: "one")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "private", named: "two")?.path,
      nil)
    XCTAssertEqual(
      access.repository(readableBy: reader, in: "shut", named: "only")?.path,
      nil)
    XCTAssertNil(access.repository(readableBy: reader, in: "public", named: "nosuch"))
    XCTAssertNil(access.repository(readableBy: reader, in: "nosuch", named: "one"))

    XCTAssertEqual(
      access.allows(reader, group: "public", repository: "open", permission: .read),
      true)
    XCTAssertEqual(
      access.allows(reader, group: "public", repository: "closed", permission: .read),
      false)
  }

  /// A work document's own grants are resolved against the standing identity too.
  func testWhatAReaderMayDoOnAWorkDocumentMatchesTheReference() {
    let access = Self.access()
    var toAlice = RNGitPermissionSet()
    toAlice.interact = [.identity(Self.alice)]
    var toEveryone = RNGitPermissionSet()
    toEveryone.interact = [.everyone]

    for reader in [Self.alice, access.nullIdentityHash, nil] as [Data?] {
      XCTAssertEqual(
        access.allowsDocument(
          reader, group: "public", repository: "open", permission: .interact,
          documentPermissions: toAlice),
        reader == Self.alice)
      XCTAssertTrue(
        access.allowsDocument(
          reader, group: "public", repository: "open", permission: .interact,
          documentPermissions: toEveryone))
    }
  }

  /// A work document's own grants are read from the `allowed` file its number names, beside
  /// the repository's work.
  func testAWorkDocumentsOwnFileIsReadForItsNumber() throws {
    let base = NSTemporaryDirectory() + "/rngit-document-grants-" + UUID().uuidString
    defer { try? FileManager.default.removeItem(atPath: base) }
    let work = base + "/open.work"
    try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
    try ("interact:" + Self.alice.hexString + "\n").write(
      toFile: work + "/7.allowed", atomically: true, encoding: .utf8)

    var readable = RNGitPermissionSet()
    readable.read = [.everyone]
    let access = RNGitPageAccess(
      control: RNGitAccessControl(groups: [
        "public": RNGitGroup(
          name: "public", path: base,
          repositories: ["open": RNGitRepository(name: "open", path: base + "/open")],
          permissions: readable)
      ]))

    for reader in [Self.alice, nil] as [Data?] {
      XCTAssertEqual(
        access.allowsDocument(
          reader, group: "public", repository: "open", number: 7, permission: .interact),
        reader == Self.alice)
      XCTAssertFalse(
        access.allowsDocument(
          reader, group: "public", repository: "open", number: 8, permission: .interact))
    }
    XCTAssertFalse(
      access.allowsDocument(
        Self.alice, group: "public", repository: "nosuch", number: 7, permission: .interact))
  }
}
