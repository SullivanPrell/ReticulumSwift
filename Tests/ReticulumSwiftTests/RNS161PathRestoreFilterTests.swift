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

/// RNS 1.6.1's path-table load: blackholed identities and filtered destination types stay out
/// (`Transport.py:582-599`), and `block_destination_type` takes a `<hex>` name hash
/// (`Transport.py:4878-4885`).
final class RNS161PathRestoreFilterTests: XCTestCase {

  final class Mesh: Interface {
    var name = "mesh"
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  private var tmpDir: URL!
  private var retained: [AnyObject] = []

  override func setUp() {
    super.setUp()
    tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns-restore-filter-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    retained = []
    try? FileManager.default.removeItem(at: tmpDir)
    super.tearDown()
  }

  /// A transport holding one cached announce for `aspect`, and its stored path entry.
  private func stored(_ aspect: String) throws -> (Transport, Destination, PathStore.Entry) {
    let t = Transport()
    t.cacheDirectory = tmpDir.appendingPathComponent("cache-\(UUID().uuidString)")
    let mesh = Mesh()
    t.register(interface: mesh)
    retained += [t, mesh]
    let identity = Identity()
    let dest = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "restorefilter",
      aspects: [aspect])
    let packet = try Announce.make(for: dest)
    try t.cacheAnnounce(packet, receivingInterfaceName: mesh.name)
    t.restore(identity: identity, forDestination: dest.hash)
    let entry = PathStore.Entry(
      destinationHash: dest.hash, timestamp: Date().timeIntervalSince1970,
      receivedFrom: dest.hash, hops: 1,
      expires: Date().addingTimeInterval(3600).timeIntervalSince1970,
      randomBlobs: [], interfaceHash: mesh.hash,
      announceHash: Hashes.fullHash(try packet.hashablePart()))
    return (t, dest, entry)
  }

  func testAnUnfilteredEntryIsRestored() throws {
    let (t, dest, entry) = try stored("plain")
    PathStore(entries: [entry]).install(into: t)
    XCTAssertTrue(t.hasPath(to: dest.hash))
  }

  /// `if path_identity and path_identity.hash in Transport.blackholed_identities`
  /// (`Transport.py:585`).
  func testABlackholedIdentitysPathIsNotRestored() throws {
    let (t, dest, entry) = try stored("blackholed")
    t.blackholeIdentity(try XCTUnwrap(t.recall(identity: dest.hash)?.hash))

    let installed = PathStore(entries: [entry]).install(into: t)

    XCTAssertFalse(t.hasPath(to: dest.hash))
    XCTAssertTrue(installed.contains(dest.hash), "dropped for good, not held pending")
  }

  /// `if name_hash in Transport.blocked_destination_types` (`Transport.py:596`).
  func testABlockedTypesPathIsNotRestored() throws {
    let (t, dest, entry) = try stored("blocked")
    t.blockDestinationType("restorefilter.blocked")

    PathStore(entries: [entry]).install(into: t)

    XCTAssertFalse(t.hasPath(to: dest.hash))
  }

  /// `or Transport.required_destinations_only and name_hash not in
  /// Transport.allowed_destination_types` (`Transport.py:596`): a client's want doesn't count.
  func testRequiredDestinationsOnlyRestoresOnlyAllowedTypes() throws {
    let (t, dest, entry) = try stored("wanted")
    t.requiredDestinationsOnly = true
    t.wantsDestinationType("restorefilter.wanted", requester: Data(repeating: 1, count: 16))
    PathStore(entries: [entry]).install(into: t)
    XCTAssertFalse(t.hasPath(to: dest.hash))

    let (allowed, allowedDest, allowedEntry) = try stored("allowed")
    allowed.requiredDestinationsOnly = true
    allowed.allowDestinationType("restorefilter.allowed")
    PathStore(entries: [allowedEntry]).install(into: allowed)
    XCTAssertTrue(allowed.hasPath(to: allowedDest.hash))
  }

  /// `full_name[1:1+NAME_HASH_LENGTH//8*2]` parsed with `bytes.fromhex`, falling back to
  /// `name_hash` of that text (`Transport.py:4880-4885`).
  func testABracketedHexNameBlocksThatHash() throws {
    let (t, dest, entry) = try stored("hex")
    let nameHash = Transport.destinationTypeHash("restorefilter.hex")
    XCTAssertTrue(t.blockDestinationType("<\(nameHash.hexString)>"))

    PathStore(entries: [entry]).install(into: t)

    XCTAssertFalse(t.hasPath(to: dest.hash))
    XCTAssertEqual(
      Transport.filterTypeHash("<0011>"), Transport.destinationTypeHash("0011>"),
      "a short bracketed name keeps its closing bracket and falls back to name_hash")
    XCTAssertFalse(t.blockDestinationType(""), "`if not full_name: return`")
  }
}
