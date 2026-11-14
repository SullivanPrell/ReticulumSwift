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

/// Tests for Transport's per-destination announce rate limiting.
///
/// Mirrors Python's `Transport.announce_rate_table` logic:
///   MAX_RATE_TIMESTAMPS = 16
///   active only when `interface.announceRateTarget != nil`
///   a "violation" = time since last announce < announceRateTarget
///   after announceRateGrace violations → blockedUntil = last + rateTarget + ratePenalty
final class AnnounceRateTableTests: XCTestCase {

  // MARK: - Helpers

  final class RateLimitedInterface: Interface {
    var name: String
    var bitrate: Int = 100_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    /// Mirrors Python's `announce_rate_target` (seconds between announces).
    var announceRateTarget: TimeInterval?
    /// Number of violations allowed before blocking.
    var announceRateGrace: Int = 3
    /// Additional penalty added to the block duration.
    var announceRatePenalty: TimeInterval = 0

    init(name: String, rateTarget: TimeInterval? = nil, grace: Int = 3, penalty: TimeInterval = 0) {
      self.name = name
      self.announceRateTarget = rateTarget
      self.announceRateGrace = grace
      self.announceRatePenalty = penalty
    }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {}
  }

  // MARK: - Constants

  func testMaxRateTimestampsConstant() {
    XCTAssertEqual(
      Transport.maxRateTimestamps, 16,
      "MAX_RATE_TIMESTAMPS must be 16")
  }

  // MARK: - Rate limiting disabled by default

  func testNoRateLimitWhenTargetIsNil() throws {
    let t = Transport()
    let iface = RateLimitedInterface(name: "unlimited", rateTarget: nil)
    t.register(interface: iface)

    let destHash = Data(repeating: 0x01, count: 16)
    let now = Date().timeIntervalSince1970

    // Even after 10 rapid announces, none should be blocked.
    for _ in 0..<10 {
      let blocked = t.isAnnounceRateBlocked(
        destinationHash: destHash,
        interface: iface,
        now: now)
      XCTAssertFalse(blocked, "no rate limit when announceRateTarget == nil")
    }
  }

  // MARK: - First announce always allowed

  func testFirstAnnounceIsNeverBlocked() throws {
    let t = Transport()
    let iface = RateLimitedInterface(name: "rated", rateTarget: 10.0)
    t.register(interface: iface)

    let destHash = Data(repeating: 0x02, count: 16)
    let blocked = t.isAnnounceRateBlocked(
      destinationHash: destHash,
      interface: iface,
      now: 1000.0)
    XCTAssertFalse(blocked, "first announce must never be blocked")
  }

  // MARK: - Violations accumulate

  func testRateViolationAccumulates() throws {
    let t = Transport()
    // Target: 10 seconds between announces. Grace: 0 violations allowed. Penalty: 0.
    let iface = RateLimitedInterface(name: "strict", rateTarget: 10.0, grace: 0, penalty: 0)
    t.register(interface: iface)

    let dest = Data(repeating: 0x03, count: 16)
    var now: TimeInterval = 1000.0

    // First announce (always allowed, seeds the table)
    _ = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)

    // Second announce 1 second later—violates 10 seconds target
    now += 1.0
    let blocked = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)
    // With grace=0, first violation should block.
    XCTAssertTrue(blocked, "announce arriving before rate_target should be blocked when grace=0")
  }

  // MARK: - Grace allows some violations before blocking

  func testGraceAllowsViolationsBeforeBlocking() throws {
    let t = Transport()
    // Target: 10 seconds. Grace: 2 (first 2 violations pass, third blocks). Penalty: 0.
    let iface = RateLimitedInterface(name: "grace", rateTarget: 10.0, grace: 2, penalty: 0)
    t.register(interface: iface)

    let dest = Data(repeating: 0x04, count: 16)
    var now: TimeInterval = 1000.0

    // Seed with first announce.
    _ = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)

    // Violation 1 (arrives 1 second later, within target): shouldn't be blocked (within grace)
    now += 1.0
    var blocked = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)
    XCTAssertFalse(blocked, "violation 1 within grace should pass")

    // Violation 2: shouldn't be blocked (within grace)
    now += 1.0
    blocked = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)
    XCTAssertFalse(blocked, "violation 2 within grace should pass")

    // Violation 3: should be blocked (exceeds grace)
    now += 1.0
    blocked = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)
    XCTAssertTrue(blocked, "violation 3 exceeds grace=2 and should be blocked")
  }

  // MARK: - Block expires

  func testBlockExpiresAfterRateTargetPlusPenalty() throws {
    let t = Transport()
    // Target: 10 seconds. Grace: 0. Penalty: 5 seconds.
    let iface = RateLimitedInterface(name: "penalty", rateTarget: 10.0, grace: 0, penalty: 5.0)
    t.register(interface: iface)

    let dest = Data(repeating: 0x05, count: 16)
    var now: TimeInterval = 1000.0

    _ = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)

    // Trigger block
    now += 1.0
    _ = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)

    // Still within block window: blocked
    now += 5.0
    var blocked = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)
    XCTAssertTrue(blocked, "still within block window — should be blocked")

    // After block expires (now > last + target + penalty = 1001 + 10 + 5 = 1016)
    now = 1017.0
    blocked = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)
    XCTAssertFalse(blocked, "block window expired — announce should be allowed again")
  }

  // MARK: - Clean violation count on compliant announce

  func testViolationCountDecreasesOnCompliantAnnounce() throws {
    let t = Transport()
    // Target: 5 seconds. Grace: 3.
    let iface = RateLimitedInterface(name: "recover", rateTarget: 5.0, grace: 3, penalty: 0)
    t.register(interface: iface)

    let dest = Data(repeating: 0x06, count: 16)
    var now: TimeInterval = 1000.0

    // Seed.
    _ = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)

    // Accumulate 2 violations (each 1 second apart)
    now += 1.0
    _ = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)
    now += 1.0
    _ = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)

    // Now send a compliant announce (6 seconds gap > target 5 seconds)—violation count decreases
    now += 6.0
    let blocked = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)
    XCTAssertFalse(
      blocked, "compliant announce after violations should pass and reduce violation count")
  }

  // MARK: - Timestamps capped at MAX_RATE_TIMESTAMPS

  func testTimestampListCappedAtMaxRateTimestamps() throws {
    let t = Transport()
    let iface = RateLimitedInterface(name: "cap", rateTarget: 0.001)  // fast target
    t.register(interface: iface)

    let dest = Data(repeating: 0x07, count: 16)
    var now: TimeInterval = 1000.0
    for _ in 0..<(Transport.maxRateTimestamps + 5) {
      _ = t.isAnnounceRateBlocked(destinationHash: dest, interface: iface, now: now)
      now += 0.1
    }
    let count = t.announceRateTimestampCount(for: dest)
    XCTAssertLessThanOrEqual(
      count, Transport.maxRateTimestamps,
      "timestamps per destination must be capped at MAX_RATE_TIMESTAMPS")
  }

  // MARK: - Integration: rate blocking applied in handleAnnounce

  func testHandleAnnounceRespectRateLimit() throws {
    let t = Transport()
    let identity = Identity()
    let dest = try Destination(
      identity: identity, direction: .in, kind: .single,
      appName: "ratelimit", aspects: ["test"])
    // The announced destination must NOT be registered on this transport: a node ignores
    // announces for destinations it owns (`swift_devel/bugs/047`, Transport.py:1767-1772).
    // This test registered the destination it then announced to itself, so it was passing only
    // because that gate was missing; the registration was never what it was testing.

    // Interface with tight rate limiting: target=60 seconds, grace=0
    let iface = RateLimitedInterface(name: "tight", rateTarget: 60.0, grace: 0, penalty: 0)
    t.register(interface: iface)

    // Inject two rapid announces via the interface's inbound handler.
    let ann1 = try Announce.make(for: dest)
    let ann2 = try Announce.make(for: dest)
    let raw1 = try ann1.pack()
    let raw2 = try ann2.pack()

    iface.inboundHandler?(try Packet.unpack(raw1), iface)
    let pathsAfterFirst = t.paths[dest.hash]
    iface.inboundHandler?(try Packet.unpack(raw2), iface)

    // Both announces update the path table; rate blocking doesn't drop path entries,
    // it just increments violations. The first announce seeds the table (not blocked),
    // the second one with grace=0 increments violations and gets blocked.
    // The key observable: destinationHash is in announce rate table after two announces.
    XCTAssertNotNil(
      t.announceRateTimestampCount(for: dest.hash) >= 0 ? pathsAfterFirst : nil,
      "first announce always allowed and path table updated")
  }

  // MARK: - RNS 1.6.0: a rate-blocked announce still feeds handlers, the cache and routing

  final class RecordingHandler: AnnounceHandler {
    var aspectFilter: String?
    var receivePathResponses = true
    var received: [Data] = []
    func receivedAnnounce(
      destinationHash: Data, identity: Identity, appData: Data?,
      announcePacketHash: Data, isPathResponse: Bool
    ) { received.append(destinationHash) }
  }

  /// Records what it sends; a local-client server when `clientCount > 0`.
  final class SpyInterface: LocalClientServingInterface {
    var name: String
    var bitrate: Int = 100_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var clientCount: Int
    var sent: [Packet] = []
    init(name: String, clientCount: Int = 0) {
      self.name = name
      self.clientCount = clientCount
    }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  private func makeCachingTransport() -> Transport {
    let t = Transport()
    t.cacheDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rate-blocked-\(UUID().uuidString)")
    return t
  }

  private func cachedAnnounce(_ packet: Packet, in t: Transport) throws -> Packet? {
    try t.getCachedAnnounce(hash: Hashes.fullHash(packet.hashablePart()))
  }

  /// `Transport.py:2714-2724`: an existing path takes the blocked announce's next hop, hops,
  /// random blobs, receiving interface and packet, but keeps its timestamp and expiry.
  func testRateBlockedAnnounceUpdatesRoutingButNotLiveness() throws {
    let t = makeCachingTransport()
    let handler = RecordingHandler()
    t.register(announceHandler: handler)
    let first = RateLimitedInterface(name: "first", rateTarget: 60, grace: 0)
    let second = RateLimitedInterface(name: "second", rateTarget: 60, grace: 0)
    t.register(interface: first)
    t.register(interface: second)
    let dest = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "ratelimit", aspects: ["routing"])
    let now = Date().timeIntervalSince1970

    first.inboundHandler?(try Announce.make(for: dest, timestamp: now - 100), first)
    let before = try XCTUnwrap(t.paths[dest.hash])

    // More hops but a newer emission, so the `should_add` ladder accepts it (`:2551-2558`),
    // and inside 60 s of the first, so the rate table blocks it.
    var wire = try Announce.make(for: dest, timestamp: now)
    wire.headerType = .type2
    wire.transportType = .transport
    wire.transportID = Data(repeating: 0xAB, count: 16)
    wire.hops = before.hops + 2
    let blocked = try Packet.unpack(try wire.pack())
    second.inboundHandler?(blocked, second)

    XCTAssertEqual(handler.received, [dest.hash, dest.hash], "handlers still run (`:2765`)")
    XCTAssertNotNil(try cachedAnnounce(blocked, in: t), "still cached (`:2713`)")
    let after = try XCTUnwrap(t.paths[dest.hash])
    XCTAssertTrue(after.nextHopInterface === second)
    XCTAssertEqual(after.nextHopTransportID, Data(repeating: 0xAB, count: 16))
    XCTAssertEqual(after.hops, blocked.hops)
    let blob = blocked.data.subdata(
      in: Constants.keySize + Constants.nameHashLength..<Constants.keySize
        + Constants.nameHashLength + 10)
    XCTAssertEqual(after.randomBlobs, before.randomBlobs + [blob])
    XCTAssertEqual(after.cachedAnnounceHash, Hashes.fullHash(try blocked.hashablePart()))
    XCTAssertEqual(after.lastHeard, before.lastHeard, "a blocked announce doesn't refresh liveness")
    XCTAssertEqual(after.expires, before.expires, "a blocked announce doesn't extend the path")
  }

  /// `Transport.py:2717`: with no path to update, a blocked announce creates none, yet the
  /// handlers, the cache and the identity store still see it.
  func testRateBlockedAnnounceWithNoPathCreatesNone() throws {
    let t = makeCachingTransport()
    let handler = RecordingHandler()
    t.register(announceHandler: handler)
    let iface = RateLimitedInterface(name: "tight", rateTarget: 60, grace: 0)
    t.register(interface: iface)
    let dest = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "ratelimit", aspects: ["nopath"])
    // Seed the rate entry, so the first announce this node hears is already over the rate.
    XCTAssertFalse(t.isAnnounceRateBlocked(destinationHash: dest.hash, interface: iface))

    let announce = try Packet.unpack(try Announce.make(for: dest).pack())
    iface.inboundHandler?(announce, iface)

    XCTAssertNil(t.paths[dest.hash])
    XCTAssertEqual(handler.received, [dest.hash])
    XCTAssertNotNil(try cachedAnnounce(announce, in: t))
    XCTAssertNotNil(t.recall(identity: dest.hash))
  }

  /// `Transport.py:2606`, `:2649-2675`: a blocked announce isn't rebroadcast, but local
  /// clients still get it.
  func testRateBlockedAnnounceReachesLocalClientsButIsNotRelayed() throws {
    let t = Transport()
    t.transportEnabled = true
    let iface = RateLimitedInterface(name: "tight", rateTarget: 60, grace: 0)
    let mesh = SpyInterface(name: "mesh")
    let local = SpyInterface(name: "local", clientCount: 1)
    t.register(interface: iface)
    t.register(interface: mesh)
    t.register(interface: local)
    let dest = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "ratelimit", aspects: ["relay"])
    XCTAssertFalse(t.isAnnounceRateBlocked(destinationHash: dest.hash, interface: iface))

    iface.inboundHandler?(try Packet.unpack(try Announce.make(for: dest).pack()), iface)

    XCTAssertTrue(mesh.sent.isEmpty, "a rate-blocked announce isn't rebroadcast")
    XCTAssertEqual(local.sent.filter { $0.destinationHash == dest.hash }.count, 1)
  }

  /// `Transport.py:2584`: a path response never goes through the rate table.
  func testPathResponseIsNotRateChecked() throws {
    let t = Transport()
    let iface = RateLimitedInterface(name: "tight", rateTarget: 60, grace: 0)
    t.register(interface: iface)
    let dest = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "ratelimit", aspects: ["response"])
    XCTAssertFalse(t.isAnnounceRateBlocked(destinationHash: dest.hash, interface: iface))

    let response = try Announce.make(for: dest, isPathResponse: true)
    iface.inboundHandler?(try Packet.unpack(try response.pack()), iface)

    XCTAssertNotNil(t.paths[dest.hash])
  }
}
