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

/// `Packet.unpack` stores whatever context byte arrives (`Packet.py:264`, `:271`, RNS 1.5.5),
/// so a context a newer peer adds crosses an older node instead of being dropped there.
final class UnknownPacketContextTests: XCTestCase {

  /// No `Packet.Context` case has this value.
  private let unknown: UInt8 = 0x42
  private let destinationHash = Data(repeating: 0xD5, count: Constants.truncatedHashLength)

  /// `packet` packed, with its context byte replaced by ``unknown``.
  private func withUnknownContext(_ packet: Packet) throws -> Data {
    var raw = try packet.pack()
    let index = 2 + Constants.truncatedHashLength * (packet.headerType == .type2 ? 2 : 1)
    raw[index] = unknown
    return raw
  }

  private func dataPacket() -> Packet {
    Packet(
      destinationType: .single, packetType: .data, destinationHash: destinationHash,
      data: Data(repeating: 0x11, count: 64))
  }

  func testAnUnknownContextSurvivesUnpackAndPack() throws {
    let raw = try withUnknownContext(dataPacket())
    XCTAssertEqual(try Packet.unpack(raw).pack(), raw)
  }

  /// `get_hashable_part` hashes the raw frame from byte 2 (`Packet.py:363-366`).
  func testAnUnknownContextIsPartOfThePacketHash() throws {
    let raw = try withUnknownContext(dataPacket())
    XCTAssertEqual(
      try Packet.unpack(raw).hashablePart(), Data([raw[0] & 0b0000_1111]) + raw.dropFirst(2))
  }

  func testATransportNodeRelaysAnUnknownContextUnchanged() throws {
    let t = Transport()
    t.transportEnabled = true
    let from = InTransportRelayTests.MeshIface(name: "meshA")
    let toward = InTransportRelayTests.MeshIface(name: "meshB")
    t.register(interface: from)
    t.register(interface: toward)
    t.injectPath(
      destinationHash, nextHop: Data(repeating: 0xBB, count: 16), receivedOn: toward, hops: 1,
      announcePacketHash: nil)
    var packet = dataPacket()
    packet.headerType = .type2
    packet.transportType = .transport
    packet.transportID = t.transportInstanceID

    from.inboundHandler?(try Packet.unpack(withUnknownContext(packet)), from)

    let relayed = try XCTUnwrap(toward.sent.first { $0.destinationHash == destinationHash })
    XCTAssertEqual(try relayed.pack()[2 + 2 * 16], unknown)
  }

  /// Python's `Link.__receive` has no branch for the context, so nothing reaches the app.
  func testALinkDoesNotDeliverAnUnknownContextAsData() throws {
    let (aT, bT, aLink, bLink, bIface) = try establishLink()
    var delivered: [Data] = []
    bLink.setPacketCallback { data, _ in delivered.append(data) }
    func linkPacket(_ text: String) throws -> Packet {
      Packet(
        destinationType: .link, packetType: .data, destinationHash: try XCTUnwrap(aLink.linkID),
        data: try aLink.encrypt(Data(text.utf8)))
    }

    bIface.inboundHandler?(try Packet.unpack(withUnknownContext(linkPacket("unknown"))), bIface)
    bIface.inboundHandler?(try linkPacket("none"), bIface)

    XCTAssertEqual(delivered, [Data("none".utf8)])
    _ = (aT, bT)
  }

  private func establishLink() throws -> (
    Transport, Transport, Link, Link, LinkCallbackAPITests.LoopbackInterface
  ) {
    let aT = Transport()
    let bT = Transport()
    let bId = Identity()
    let bDest = try Destination(
      identity: bId, direction: .in, kind: .single, appName: "test", aspects: ["context"])
    bT.ownerIdentity = bId
    bT.register(destination: bDest)
    let aI = LinkCallbackAPITests.LoopbackInterface(name: "A")
    let bI = LinkCallbackAPITests.LoopbackInterface(name: "B")
    aI.paired = bI
    bI.paired = aI
    aT.register(interface: aI)
    bT.register(interface: bI)
    let established = expectation(description: "established")
    established.expectedFulfillmentCount = 2
    aT.onLinkEstablished = { _ in established.fulfill() }
    bT.onLinkEstablished = { _ in established.fulfill() }
    let aLink = try Link.initiate(destination: bDest, transport: aT)
    wait(for: [established], timeout: 1.0)
    return (aT, bT, aLink, try XCTUnwrap(bT.links[XCTUnwrap(aLink.linkID)]), bI)
  }
}
