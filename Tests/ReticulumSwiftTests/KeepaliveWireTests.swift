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

/// Link keepalives travel unencrypted, as Python packs them (`Packet.py:209-212`) and
/// reads them (`Link.py:1130-1135`).
final class KeepaliveWireTests: XCTestCase {

  /// Python's keepalive probe and echo for link ID `0x00...0x0f`, captured from RNS 1.5.5
  /// by `scripts/capture-keepalive-vectors.py`.
  static let pythonProbe = "0c00000102030405060708090a0b0c0d0e0ffaff"
  static let pythonEcho = "0c00000102030405060708090a0b0c0d0e0ffafe"

  final class RecordingLoopback: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    weak var paired: RecordingLoopback?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private let lock = NSLock()
    private var packets: [Data] = []
    var sent: [Data] { lock.withLock { packets } }

    init(name: String) { self.name = name }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
      let raw = try packet.pack()
      lock.withLock { packets.append(raw) }
      paired?.inboundHandler?(try Packet.unpack(raw), paired!)
    }
  }

  private var aTransport: Transport!
  private var bTransport: Transport!

  /// Python's packet from `vector`, carrying `linkID`.
  private func pythonPacket(_ vector: String, linkID: Data) throws -> Data {
    var raw = try XCTUnwrap(Data(hex: vector))
    raw.replaceSubrange(2..<18, with: linkID)
    return raw
  }

  private func establishLink() throws -> (Link, Link, RecordingLoopback, RecordingLoopback) {
    aTransport = Transport()
    bTransport = Transport()
    let bIdentity = Identity()
    let bDest = try Destination(
      identity: bIdentity, direction: .in, kind: .single, appName: "x", aspects: ["keepalive"])
    bTransport.ownerIdentity = bIdentity
    bTransport.register(destination: bDest)
    let aI = RecordingLoopback(name: "A")
    let bI = RecordingLoopback(name: "B")
    aI.paired = bI
    bI.paired = aI
    aTransport.register(interface: aI)
    bTransport.register(interface: bI)

    let aE = expectation(description: "a")
    let bE = expectation(description: "b")
    aTransport.onLinkEstablished = { _ in aE.fulfill() }
    bTransport.onLinkEstablished = { _ in bE.fulfill() }
    let aLink = try Link.initiate(destination: bDest, transport: aTransport)
    wait(for: [aE, bE], timeout: 1.0)
    let bLink = try XCTUnwrap(bTransport.links[aLink.linkID!])
    return (aLink, bLink, aI, bI)
  }

  func testInitiatorSendsPythonsProbe() throws {
    let (aLink, _, aI, _) = try establishLink()
    try aLink.sendKeepalive()
    let probe = try XCTUnwrap(aI.sent.last)
    XCTAssertEqual(
      probe.hexString, try pythonPacket(Self.pythonProbe, linkID: aLink.linkID!).hexString)
  }

  /// A Python responder's echo counts as inbound traffic, the second one included.
  ///
  /// Every echo is the same raw `0xFE`, so a repeat must pass the duplicate filter
  /// (`Transport.py:1635`).
  func testInitiatorCountsPythonsEchoAsInbound() throws {
    let (aLink, _, aI, _) = try establishLink()
    let echo = try pythonPacket(Self.pythonEcho, linkID: aLink.linkID!)
    for attempt in 1...2 {
      let before = aLink.lastInbound ?? .distantPast
      Thread.sleep(forTimeInterval: 0.01)
      aI.inboundHandler?(try Packet.unpack(echo), aI)
      XCTAssertGreaterThan(
        aLink.lastInbound ?? .distantPast, before, "echo \(attempt) was not counted as inbound")
    }
  }

  /// An initiator drops a probe before counting it as inbound (`Link.py:938`).
  func testInitiatorIgnoresPythonsProbe() throws {
    let (aLink, _, aI, _) = try establishLink()
    let lastInbound = aLink.lastInbound
    let rx = aLink.rx
    Thread.sleep(forTimeInterval: 0.01)
    aI.inboundHandler?(
      try Packet.unpack(try pythonPacket(Self.pythonProbe, linkID: aLink.linkID!)), aI)
    XCTAssertEqual(aLink.lastInbound, lastInbound)
    XCTAssertEqual(aLink.rx, rx)
  }

  /// A link packet counts as inbound data before its decrypt, so one that fails to
  /// decrypt still refreshes the link (`Link.py:942-946`).
  func testUndecryptablePacketCountsAsInbound() throws {
    let (aLink, _, aI, _) = try establishLink()
    try assertCountsAsInboundData(
      aLink, on: aI, packetType: .data, context: .none, data: Data(repeating: 0xAB, count: 64))
  }

  /// A resource part and a resource proof count as inbound data, as every non-keepalive
  /// link packet does (`Link.py:942-945`).
  func testResourcePacketsCountAsInboundData() throws {
    let (aLink, _, aI, _) = try establishLink()
    try assertCountsAsInboundData(
      aLink, on: aI, packetType: .data, context: .resource, data: Data(repeating: 0x01, count: 40))
    try assertCountsAsInboundData(
      aLink, on: aI, packetType: .proof, context: .resourceProof,
      data: Data(repeating: 0x02, count: 96))
  }

  private func assertCountsAsInboundData(
    _ link: Link, on interface: RecordingLoopback, packetType: Packet.PacketType,
    context: Packet.Context, data: Data, line: UInt = #line
  ) throws {
    let packet = Packet(
      destinationType: .link, packetType: packetType, destinationHash: link.linkID!,
      context: context, data: data)
    let (rx, rxBytes) = (link.rx, link.rxBytes)
    let lastInbound = link.lastInbound ?? .distantPast
    let lastData = link.lastData ?? .distantPast
    Thread.sleep(forTimeInterval: 0.01)
    interface.inboundHandler?(try Packet.unpack(try packet.pack()), interface)
    XCTAssertGreaterThan(link.lastInbound ?? .distantPast, lastInbound, "lastInbound", line: line)
    XCTAssertGreaterThan(link.lastData ?? .distantPast, lastData, "lastData", line: line)
    XCTAssertEqual(link.rx, rx + 1, "rx", line: line)
    XCTAssertEqual(link.rxBytes, rxBytes + data.count, "rxBytes", line: line)
  }

  /// A responder that has sent nothing for a keepalive interval answers a Python probe
  /// with Python's echo (`Link.py:1131-1135`).
  func testIdleResponderAnswersPythonsProbe() throws {
    let (aLink, bLink, _, bI) = try establishLink()
    // Keeps the initiator's own watchdog from probing during the idle wait.
    aLink.testSetRtt(Link.keepaliveMaxRTT)
    bLink.testSetRtt(0.001)
    Thread.sleep(forTimeInterval: Link.keepaliveMin + 0.2)

    let before = bI.sent.count
    bI.inboundHandler?(
      try Packet.unpack(try pythonPacket(Self.pythonProbe, linkID: bLink.linkID!)), bI)
    let echo = try XCTUnwrap(bI.sent.dropFirst(before).last, "the responder sent no echo")
    XCTAssertEqual(
      echo.hexString, try pythonPacket(Self.pythonEcho, linkID: bLink.linkID!).hexString)
  }
}
