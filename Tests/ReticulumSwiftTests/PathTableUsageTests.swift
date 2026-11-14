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

/// RNS 1.6.0's path-table usage: `IDX_PT_USED` records when a path last carried traffic, a
/// path never used is culled after `unused_path_linger`, the never-used pool is held to
/// `PATH_POOL_UNUSED_TARGET`, and `mark_path_responsive` refreshes a path
/// (`Transport.py:1120-1159`, `3632-3646`).
final class PathTableUsageTests: XCTestCase {

  final class Hop: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    weak var paired: Hop?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String, bitrate: Int = 0) {
      self.name = name
      self.bitrate = bitrate
    }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {
      let copy = try Packet.unpack(packet.pack())
      paired?.inboundHandler?(copy, paired!)
    }
  }

  private func dst(_ n: Int) -> Data {
    Data([UInt8(n & 0xFF), UInt8(n >> 8)]) + Data(repeating: 0xD0, count: 14)
  }

  private func path(
    _ n: Int, via hop: Hop, heard: Date, expires: Date? = nil, used: Date? = nil
  ) -> Transport.PathEntry {
    var entry = Transport.PathEntry(
      destinationHash: dst(n), nextHopInterface: hop, hops: 1, lastHeard: heard,
      identityHash: Data(repeating: 0x01, count: 16), expires: expires)
    entry.used = used
    return entry
  }

  // MARK: - Use

  /// `path_entry[IDX_PT_USED] = outbound_time` replaced 1.5.7's timestamp refresh
  /// (`Transport.py:1618`).
  func testSendingOverAPathMarksItUsedAndLeavesItsTimestamp() throws {
    let t = Transport()
    let hop = Hop(name: "send")
    t.register(interface: hop)
    let heard = Date().addingTimeInterval(-3600)
    t.restore(path: path(1, via: hop, heard: heard), forDestination: dst(1))

    _ = try t.send(
      Packet(destinationType: .single, packetType: .data, destinationHash: dst(1), data: Data([1])),
      generateReceipt: false)

    let entry = try XCTUnwrap(t.paths[dst(1)])
    XCTAssertEqual(entry.lastHeard, heard)
    XCTAssertEqual(try XCTUnwrap(entry.used).timeIntervalSinceNow, 0, accuracy: 5)
  }

  /// A replacing announce keeps the old entry's `path_used` (`Transport.py:2510`, `2726`).
  func testAReplacingAnnounceKeepsTheUseTime() throws {
    let t = Transport()
    t.stamps.destinationCost = 8
    let hop = Hop(name: "announce")
    t.register(interface: hop)
    let hash = Data(hex: "cb20bb86f3256654f6ca46b3139b1187")!
    let used = Date().addingTimeInterval(-60)
    var old = Transport.PathEntry(
      destinationHash: hash, nextHopInterface: hop, hops: 3,
      lastHeard: Date().addingTimeInterval(-7200), identityHash: Data(repeating: 1, count: 16))
    old.used = used
    t.restore(path: old, forDestination: hash)

    t.handleIncoming(packet: try Packet.unpack(AnnounceStampTests.withAppData), from: hop)

    let entry = try XCTUnwrap(t.paths[hash])
    XCTAssertEqual(entry.lastHeard.timeIntervalSinceNow, 0, accuracy: 5, "not replaced")
    XCTAssertEqual(entry.used, used)
  }

  // MARK: - Culling

  /// `elif path_used == 0 and now > path_timestamp + unused_path_linger * …` (`:1145`).
  func testANeverUsedPathGoesAfterTheLinger() {
    let t = Transport()
    let hop = Hop(name: "linger")
    t.register(interface: hop)
    let now = Date()
    let past = now.addingTimeInterval(-Transport.unusedPathLinger - 1)
    t.restore(path: path(1, via: hop, heard: past), forDestination: dst(1))
    t.restore(path: path(2, via: hop, heard: past, used: past), forDestination: dst(2))
    t.restore(
      path: path(3, via: hop, heard: now.addingTimeInterval(-Transport.unusedPathLinger + 60)),
      forDestination: dst(3))

    t.sweepExpiredPaths(now: now)

    XCTAssertFalse(t.hasPath(to: dst(1)))
    XCTAssertTrue(t.hasPath(to: dst(2)))
    XCTAssertTrue(t.hasPath(to: dst(3)))
  }

  /// `UNUSED_PATH_LINGER_LEAF` when transport is off (`Transport.py:451-454`).
  func testALeafNodeLingersTwelveMinutes() {
    let t = Transport()
    t.transportEnabled = false
    let hop = Hop(name: "leaf")
    t.register(interface: hop)
    let now = Date()
    t.restore(
      path: path(1, via: hop, heard: now.addingTimeInterval(-13 * 60)), forDestination: dst(1))
    t.restore(
      path: path(2, via: hop, heard: now.addingTimeInterval(-11 * 60)), forDestination: dst(2))

    t.sweepExpiredPaths(now: now)

    XCTAssertFalse(t.hasPath(to: dst(1)))
    XCTAssertTrue(t.hasPath(to: dst(2)))
  }

  /// `PATH_SLOW_LINGER_FACTOR` below `PATH_SLOW_BITRATE` (`Transport.py:1132`, `1145`).
  func testASlowInterfaceLingersTenTimesLonger() {
    let t = Transport()
    let slow = Hop(name: "slow", bitrate: 1200)
    t.register(interface: slow)
    let now = Date()
    let linger = Transport.unusedPathLinger
    t.restore(
      path: path(1, via: slow, heard: now.addingTimeInterval(-linger - 1)), forDestination: dst(1))
    t.restore(
      path: path(2, via: slow, heard: now.addingTimeInterval(-linger * 10 - 1)),
      forDestination: dst(2))

    t.sweepExpiredPaths(now: now)

    XCTAssertTrue(t.hasPath(to: dst(1)))
    XCTAssertFalse(t.hasPath(to: dst(2)))
  }

  /// Above `PATH_POOL_UNUSED_TARGET`, the never-used paths sorting first by
  /// `(slow, expiry)` go, checked every `pool_size_check_interval` (`Transport.py:1150-1159`).
  func testTheNeverUsedPoolIsCulledToItsTarget() {
    let t = Transport()
    let fast = Hop(name: "fast")
    let slow = Hop(name: "slow", bitrate: 1200)
    t.register(interface: fast)
    t.register(interface: slow)
    let now = Date()
    let target = Transport.pathPoolUnusedTarget
    for n in 0..<(target + 1) {
      let expires = now.addingTimeInterval(86_400 + Double(n))
      t.restore(path: path(n, via: fast, heard: now, expires: expires), forDestination: dst(n))
    }
    t.restore(
      path: path(target + 1, via: slow, heard: now, expires: now.addingTimeInterval(3600)),
      forDestination: dst(target + 1))
    t.restore(
      path: path(
        target + 2, via: fast, heard: now, expires: now.addingTimeInterval(3600), used: now),
      forDestination: dst(target + 2))

    t.sweepExpiredPaths(now: now)
    XCTAssertEqual(t.paths.count, target + 3, "culled before the check interval")

    t.sweepExpiredPaths(now: now.addingTimeInterval(Transport.poolSizeCheckInterval + 1))
    XCTAssertEqual(t.paths.count, target + 1)
    XCTAssertFalse(t.hasPath(to: dst(0)))
    XCTAssertFalse(t.hasPath(to: dst(1)))
    XCTAssertTrue(t.hasPath(to: dst(target + 1)), "a slow path sorts after every fast one")
    XCTAssertTrue(t.hasPath(to: dst(target + 2)), "a used path isn't in the pool")
  }

  // MARK: - Responsiveness

  /// `mark_path_responsive` refreshes timestamp, expiry and use (`Transport.py:3632-3646`).
  func testMarkingAPathResponsiveRefreshesIt() throws {
    let t = Transport()
    let hop = Hop(name: "responsive")
    t.register(interface: hop)
    let old = Date().addingTimeInterval(-3600)
    t.restore(
      path: path(1, via: hop, heard: old, expires: Date().addingTimeInterval(60)),
      forDestination: dst(1))

    XCTAssertTrue(t.markPathResponsive(for: dst(1)))

    let entry = try XCTUnwrap(t.paths[dst(1)])
    XCTAssertEqual(entry.lastHeard.timeIntervalSinceNow, 0, accuracy: 5)
    XCTAssertEqual(entry.expires.timeIntervalSinceNow, Transport.pathExpiry, accuracy: 5)
    XCTAssertEqual(try XCTUnwrap(entry.used).timeIntervalSinceNow, 0, accuracy: 5)
  }

  /// An established link proves its destination live (`Link.py:513`).
  func testAnEstablishedLinkMarksItsPathResponsive() throws {
    let a = Transport()
    let b = Transport()
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "test", aspects: ["used"])
    b.ownerIdentity = identity
    b.register(destination: destination)
    let aI = Hop(name: "A")
    let bI = Hop(name: "B")
    aI.paired = bI
    bI.paired = aI
    a.register(interface: aI)
    b.register(interface: bI)
    a.restore(identity: identity, forDestination: destination.hash)
    let old = Date().addingTimeInterval(-3600)
    a.restore(
      path: Transport.PathEntry(
        destinationHash: destination.hash, nextHopInterface: aI, hops: 1, lastHeard: old,
        identityHash: identity.hash),
      forDestination: destination.hash)
    let established = expectation(description: "established")
    a.onLinkEstablished = { _ in established.fulfill() }

    _ = try Link.initiate(destination: destination, transport: a)
    wait(for: [established], timeout: 2)

    let entry = try XCTUnwrap(a.paths[destination.hash])
    XCTAssertEqual(entry.lastHeard.timeIntervalSinceNow, 0, accuracy: 5)
    XCTAssertNotNil(entry.used)
  }

  // MARK: - Storage

  /// The ninth field is `IDX_PT_USED`; an eight-field entry loads as used now
  /// (`Transport.py:557`, `4342-4356`).
  func testTheUseTimeIsTheNinthStoredField() throws {
    let entry = PathStore.Entry(
      destinationHash: dst(1), timestamp: 100, receivedFrom: dst(1), hops: 1, expires: 200,
      randomBlobs: [], interfaceHash: Data(repeating: 2, count: 16),
      announceHash: Data(repeating: 3, count: 32), used: 150)
    guard case .array(let fields) = entry.msgpackValue else { return XCTFail() }
    XCTAssertEqual(fields.count, 9)
    XCTAssertEqual(fields[8].asDouble, 150)
    XCTAssertEqual(PathStore.Entry.decode(entry.msgpackValue)?.used, 150)

    let legacy = MsgPack.Value.array(Array(fields.prefix(8)))
    XCTAssertEqual(
      try XCTUnwrap(PathStore.Entry.decode(legacy)).used, Date().timeIntervalSince1970,
      accuracy: 5)
  }
}
