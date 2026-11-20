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

/// RNS 1.6.1's announce ingress: size violations, the announce prefilter, filtered-announce
/// counting, held-announce culling and the per-interface hop limiter (`Transport.py:2100-2160`,
/// `:4462-4480`, `Interface.py:296-341`, `Packet.py:240-243`).
final class RNS161AnnounceIngressTests: XCTestCase {

  final class Port: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  private func makeAnnounce(
    _ aspect: String, appData: Data? = nil
  ) throws -> (packet: Packet, destinationHash: Data) {
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "ingress161",
      aspects: [aspect])
    let packet = try Announce.make(for: destination, appData: appData)
    return (try Packet.unpack(packet.pack()), destination.hash)
  }

  /// A raw `HEADER_1` single-destination announce carrying `count` payload bytes.
  private func rawAnnounce(payload count: Int) throws -> Packet {
    let raw =
      Data([0x01, 0x00]) + Data(repeating: 0xA5, count: 16) + Data([0x00])
      + Data(repeating: 0x5A, count: count)
    return try Packet.unpack(raw)
  }

  private func blob(at timebase: TimeInterval) -> Data {
    var t = UInt64(timebase)
    var tail = [UInt8](repeating: 0, count: 5)
    for i in (0..<5).reversed() {
      tail[i] = UInt8(t & 0xFF)
      t >>= 8
    }
    return Data(repeating: 0x11, count: 5) + Data(tail)
  }

  // MARK: - Size violations

  /// `if packet.header_type == HEADER_1 and MTU-len(raw) < TRUNCATED_HASHLENGTH//8`
  /// (`Transport.py:2117`).
  func testAHeaderOneAnnounceWithoutRoomForATransportIDIsAViolation() throws {
    let t = Transport()
    let port = Port(name: "tight")
    t.register(interface: port)
    let packet = try rawAnnounce(payload: 470)

    t.inbound(packet, from: port)

    XCTAssertEqual(t.interfaceCounts(for: port).protocolViolations, 1)
    XCTAssertEqual(t.interfaceCounts(for: port).announceRxCount, 0)
  }

  /// `if len(packet.data) < KEYSIZE//8+NAME_HASH_LENGTH//8+10` (`Transport.py:2118`).
  func testAShortAnnouncePayloadIsAViolation() throws {
    let t = Transport()
    let port = Port(name: "short")
    t.register(interface: port)

    t.inbound(try rawAnnounce(payload: 83), from: port)

    XCTAssertEqual(t.interfaceCounts(for: port).protocolViolations, 1)
  }

  /// `Packet.pack` refuses a `HEADER_1` announce a transport node couldn't forward
  /// (`Packet.py:240-243`).
  func testPackingAnAnnounceWithoutRoomForATransportIDThrows() throws {
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "ingress161",
      aspects: ["pack"])
    let overhead = try Announce.make(for: destination).pack().count
    let fits = Constants.mtu - 16 - overhead
    XCTAssertNoThrow(try Announce.make(for: destination, appData: Data(count: fits)).pack())
    XCTAssertThrowsError(try Announce.make(for: destination, appData: Data(count: fits + 1)).pack())
  }

  // MARK: - Prefilter

  /// A known destination's announce emitted before its path's newest blob can't update the
  /// path, so it's counted with no size and filtered (`Transport.py:2131-2143`).
  func testAnAnnounceOlderThanItsPathIsFiltered() throws {
    let t = Transport()
    let port = Port(name: "prefilter")
    t.register(interface: port)
    let (packet, destinationHash) = try makeAnnounce("old")
    var entry = Transport.PathEntry(
      destinationHash: destinationHash, nextHopInterface: port, hops: 2, lastHeard: Date(),
      identityHash: Data(repeating: 0x01, count: 16),
      randomBlobs: [blob(at: Date().timeIntervalSince1970 + 1000)])
    entry.used = Date()
    t.restore(path: entry, forDestination: destinationHash)

    t.inbound(packet, from: port)

    let counts = t.interfaceCounts(for: port)
    XCTAssertEqual(counts.filteredAnnounceRxCount, 1)
    XCTAssertEqual(counts.announceRxCount, 1)
    XCTAssertEqual(counts.announceRxBytes, 0)
    XCTAssertEqual(t.paths[destinationHash]?.hops, 2)
  }

  /// `announce_prefilter` (`Transport.py:4462-4480`).
  func testTheAnnouncePrefilterComparesTimebasesThenGravityThenState() throws {
    let port = Port(name: "pf")
    let (packet, destinationHash) = try makeAnnounce("pf")
    let emitted = Transport.timebaseFromRandomBlob(
      packet.data.subdata(in: 64 + 10..<64 + 20))
    func entry(_ timebase: TimeInterval) -> Transport.PathEntry {
      Transport.PathEntry(
        destinationHash: destinationHash, nextHopInterface: port, hops: 1, lastHeard: Date(),
        identityHash: Data(repeating: 0x01, count: 16), randomBlobs: [blob(at: timebase)])
    }
    let t = Transport()
    t.register(interface: port)
    let incoming = Port(name: "incoming")
    t.register(interface: incoming)
    let arrived = try Packet.unpack(packet.pack())

    XCTAssertTrue(t.announcePrefilter(arrived, on: incoming, pathEntry: entry(emitted - 1)))
    XCTAssertFalse(t.announcePrefilter(arrived, on: incoming, pathEntry: entry(emitted + 1)))
    XCTAssertFalse(t.announcePrefilter(arrived, on: incoming, pathEntry: entry(emitted)))
    incoming.gravity = 1
    XCTAssertTrue(t.announcePrefilter(arrived, on: incoming, pathEntry: entry(emitted)))
    incoming.gravity = 0
    t.restore(path: entry(emitted), forDestination: destinationHash)
    XCTAssertTrue(t.markPathUnresponsive(for: destinationHash))
    XCTAssertTrue(t.announcePrefilter(arrived, on: incoming, pathEntry: entry(emitted)))
  }

  // MARK: - Holding

  /// A held announce that a newer path made useless is culled at release time
  /// (`Interface.py:316-336`).
  func testAHeldAnnounceAPathMadeUselessIsCulled() throws {
    let t = Transport()
    let port = Port(name: "held")
    t.register(interface: port)
    let (packet, destinationHash) = try makeAnnounce("held")
    t.holdAnnounce(packet, destinationHash: destinationHash, on: port)
    XCTAssertEqual(t.heldAnnounceCount(for: port), 1)
    t.restore(
      path: Transport.PathEntry(
        destinationHash: destinationHash, nextHopInterface: port, hops: 1, lastHeard: Date(),
        identityHash: Data(repeating: 0x01, count: 16),
        randomBlobs: [blob(at: Date().timeIntervalSince1970 + 1000)]),
      forDestination: destinationHash)

    XCTAssertNil(t.processHeldAnnounces(for: port, now: Date().timeIntervalSince1970 + 3600))
    XCTAssertEqual(t.heldAnnounceCount(for: port), 0)
  }

  /// A replaced or refused held announce counts as filtered (`Interface.py:298-306`).
  func testRefusedAndReplacedHeldAnnouncesCountAsFiltered() throws {
    let t = Transport()
    let port = Port(name: "full")
    t.register(interface: port)
    port.interfaceState.icMaxHeldAnnounces = 1
    let (first, firstHash) = try makeAnnounce("first")
    let (second, secondHash) = try makeAnnounce("second")
    t.holdAnnounce(first, destinationHash: firstHash, on: port)
    t.holdAnnounce(first, destinationHash: firstHash, on: port)
    t.holdAnnounce(second, destinationHash: secondHash, on: port)

    XCTAssertEqual(t.interfaceCounts(for: port).filteredAnnounceRxCount, 2)
    XCTAssertEqual(t.filteredAnnounceRxCount, 2)
  }

  // MARK: - Hop limiter

  /// `if interface.hop_limiter and not packet.hops < interface.hop_limiter` (`Transport.py:2108`).
  func testAnInterfaceHopLimiterDropsFarPackets() throws {
    let t = Transport()
    let port = Port(name: "limited")
    t.register(interface: port)
    port.interfaceState.hopLimiter = 2
    var (packet, destinationHash) = try makeAnnounce("far")
    packet.hops = 2

    t.inbound(packet, from: port)

    XCTAssertNil(t.paths[destinationHash])
    XCTAssertEqual(t.interfaceCounts(for: port).announceRxCount, 0)

    var (near, nearHash) = try makeAnnounce("near")
    near.hops = 1
    t.inbound(near, from: port)
    XCTAssertNotNil(t.paths[nearHash])
  }
}
