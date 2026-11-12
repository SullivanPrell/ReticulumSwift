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

/// RNS 1.6.0's resource changes: the application flag (flag bit 6), and an advertisement too
/// large for the link carrying no hashmap, which the receiver then asks for with
/// `HASHMAP_IS_EMPTY` (`Resource.py:142`, `958-989`, `1018-1081`, `1375-1380`).
final class ResourceAdvertisement160Tests: XCTestCase {

  private func advertisement(parts: Int, appFlag: Bool = false) -> ResourceAdvertisement {
    ResourceAdvertisement(
      transferSize: UInt64(parts * 300), dataSize: UInt64(parts * 300), partCount: UInt64(parts),
      resourceHash: Data(repeating: 0x11, count: 32), randomHash: Data(repeating: 0x22, count: 4),
      originalHash: Data(repeating: 0x11, count: 32), segmentIndex: 1, totalSegments: 1,
      hashmap: Data(repeating: 0x33, count: parts * 4), encrypted: true, appFlag: appFlag)
  }

  // MARK: - Advertisement

  /// `self.f = 0x00 | self.a << 6 | ...` (`Resource.py:1343`).
  func testTheAppFlagIsBitSix() throws {
    let flagged = advertisement(parts: 1, appFlag: true)
    XCTAssertEqual(flagged.flags, 0x41)
    XCTAssertTrue(try ResourceAdvertisement.unpack(flagged.pack()).appFlag)
    XCTAssertFalse(try ResourceAdvertisement.unpack(advertisement(parts: 1).pack()).appFlag)
  }

  /// "Resource advertisement exceeds link MDU, deferring initial HMU" (`Resource.py:1375-1380`).
  func testAnAdvertisementOverTheLinkMduCarriesNoHashmap() throws {
    let adv = advertisement(parts: 74)
    XCTAssertEqual(try ResourceAdvertisement.unpack(adv.pack(mdu: 431)).hashmap.count, 296)
    let deferred = try ResourceAdvertisement.unpack(adv.pack(mdu: 367))
    XCTAssertEqual(deferred.hashmap, Data())
    XCTAssertEqual(deferred.partCount, 74)
  }

  // MARK: - Over a link

  final class Loopback: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    weak var paired: Loopback?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private let lock = NSLock()
    private var packets: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {
      let copy = try Packet.unpack(packet.pack())
      lock.withLock { packets.append(copy) }
      paired?.inboundHandler?(copy, paired!)
    }
    func sent(_ context: Packet.Context) -> [Packet] {
      lock.withLock { packets.filter { $0.context == context } }
    }
  }

  private var transports: [Transport] = []

  private func linkPair() throws -> (Link, Link, Loopback, Loopback) {
    let a = Transport()
    let b = Transport()
    transports = [a, b]
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "test", aspects: ["rs160"])
    b.ownerIdentity = identity
    b.register(destination: destination)
    let aI = Loopback(name: "A")
    let bI = Loopback(name: "B")
    aI.paired = bI
    bI.paired = aI
    a.register(interface: aI)
    b.register(interface: bI)
    let established = expectation(description: "established")
    established.expectedFulfillmentCount = 2
    a.onLinkEstablished = { _ in established.fulfill() }
    b.onLinkEstablished = { _ in established.fulfill() }
    let aLink = try Link.initiate(destination: destination, transport: a)
    wait(for: [established], timeout: 2)
    return (aLink, try XCTUnwrap(b.links[aLink.linkID!]), aI, bI)
  }

  private func transfer(
    _ payload: Data, from aLink: Link, to bLink: Link, appFlag: Bool = false,
    configure: (ResourceTransfer) -> Void = { _ in }
  ) throws -> (Data?, ResourceTransfer) {
    let done = expectation(description: "received")
    var received: Data?
    let receiver = ResourceTransfer(link: bLink)
    receiver.bindAsReceiver()
    receiver.onPayloadReceived = { data, _ in
      received = data
      done.fulfill()
    }
    let sender = ResourceTransfer(link: aLink)
    configure(sender)
    try sender.send(payload: payload, appFlag: appFlag)
    wait(for: [done], timeout: 20)
    return (received, receiver)
  }

  /// The flag rides every segment of a split resource (`Resource.py:796`).
  func testTheAppFlagReachesTheReceiver() throws {
    let (aLink, bLink, _, _) = try linkPair()
    let payload = Data((0..<250).map { UInt8($0 & 0xFF) })
    let (received, receiver) = try transfer(payload, from: aLink, to: bLink, appFlag: true) {
      $0.testSegmentSizeOverride = 100
    }
    XCTAssertEqual(received, payload)
    XCTAssertTrue(receiver.appFlag)
  }

  /// On a 450-byte link (MDU 367) a full first hashmap doesn't fit. The advertisement goes out
  /// without one, the receiver asks with `0xFE`, and the transfer completes on the HMU.
  func testADeferredHashmapIsRequestedAndServed() throws {
    let (aLink, bLink, aI, bI) = try linkPair()
    aLink.establishedMtu = 450
    bLink.establishedMtu = 450
    let payload = Data((0..<40_000).map { _ in UInt8.random(in: 0...255) })

    let (received, _) = try transfer(payload, from: aLink, to: bLink, configure: { _ in })
    XCTAssertEqual(received, payload)

    let ad = try XCTUnwrap(aI.sent(.resourceAdvertisement).first)
    XCTAssertEqual(try ResourceAdvertisement.unpack(bLink.decrypt(ad.data)).hashmap, Data())
    let request = try XCTUnwrap(bI.sent(.resourceRequest).first)
    XCTAssertEqual(try bLink.decrypt(request.data).first, 0xFE)
  }
}
