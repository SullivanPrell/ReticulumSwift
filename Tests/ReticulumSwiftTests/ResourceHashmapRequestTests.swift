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

/// A resource sender answers a hashmap request that carries no part hashes.
///
/// `Resource.request_next` sends `hmu_part + self.hash + requested_hashes` with
/// `requested_hashes` empty when every part of the known hashmap has arrived, and
/// `Link.py:1085-1088` and `Resource.request` take it: the sender replies with the next
/// hashmap segment.
final class ResourceHashmapRequestTests: XCTestCase {

  private var transports: [Transport] = []

  /// Delivers to its peer only while `delivers` is set, and records every packet it sends.
  final class GatedInterface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var delivers = true
    var sent: [Packet] = []
    weak var paired: GatedInterface?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
      let copy = try Packet.unpack(packet.pack())
      sent.append(copy)
      if delivers, let paired { paired.inboundHandler?(copy, paired) }
    }
  }

  func testAnEmptyHashmapRequestGetsTheNextHashmapSegment() throws {
    let aT = Transport()
    let bT = Transport()
    transports = [aT, bT]
    let bId = Identity()
    let bDest = try Destination(
      identity: bId, direction: .in, kind: .single, appName: "test", aspects: ["hmu"])
    bT.ownerIdentity = bId
    bT.register(destination: bDest)
    let aI = GatedInterface(name: "A")
    let bI = GatedInterface(name: "B")
    aI.paired = bI
    bI.paired = aI
    aT.register(interface: aI)
    bT.register(interface: bI)
    let aE = expectation(description: "a")
    let bE = expectation(description: "b")
    aT.onLinkEstablished = { _ in aE.fulfill() }
    bT.onLinkEstablished = { _ in bE.fulfill() }
    let aLink = try Link.initiate(destination: bDest, transport: aT)
    wait(for: [aE, bE], timeout: 1.0)
    let bLink = try XCTUnwrap(bT.links[aLink.linkID!])

    // 80-byte parts: 13,000 bytes spans three hashmap segments.
    aLink.establishedMtu = 80 + Constants.headerMaxSize + Constants.ifacMinSize
    bLink.establishedMtu = aLink.establishedMtu
    aI.delivers = false
    let sender = ResourceTransfer(link: aLink)
    let data = Data((0..<13_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
    try sender.send(payload: data, autoCompress: false)
    XCTAssertGreaterThan(sender.partCount, 2 * ResourceAdvertisement.hashmapMaxLength)

    let advPacket = try XCTUnwrap(aI.sent.last { $0.context == .resourceAdvertisement })
    let adv = try ResourceAdvertisement.unpack(bLink.decrypt(advPacket.data))
    XCTAssertEqual(
      adv.hashmap.count, ResourceAdvertisement.hashmapMaxLength * ResourceTransfer.mapHashLength)
    let lastMapHash = adv.hashmap.suffix(ResourceTransfer.mapHashLength)

    aI.sent.removeAll()
    let request = Data([ResourceTransfer.hashmapIsExhausted]) + lastMapHash + sender.resourceHash
    _ = try bLink.send(request, context: .resourceRequest)

    let hmu = try XCTUnwrap(aI.sent.first { $0.context == .resourceHashmapUpdate })
    let plaintext = try bLink.decrypt(hmu.data)
    XCTAssertEqual(plaintext.prefix(32), sender.resourceHash)
    guard case .array(let fields) = try MsgPack.decode(Data(plaintext.dropFirst(32))),
      fields.count == 2
    else { return XCTFail("HMU payload isn't [segment, hashmap]") }
    XCTAssertTrue(fields[0] == .uint(1) || fields[0] == .int(1), "segment \(fields[0])")
  }
}
