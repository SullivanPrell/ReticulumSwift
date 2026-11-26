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

/// Records what Transport sends on it and delivers nothing.
private final class SpyInterface: Interface {
  var name: String
  var bitrate: Int = 0
  var isOnline: Bool = true
  var inboundHandler: ((Packet, any Interface) -> Void)?
  var sent: [Packet] = []

  init(name: String) { self.name = name }
  func start() throws {}
  func stop() {}
  func send(_ packet: Packet) throws { sent.append(packet) }
}

/// A link lives on the interface its request or proof arrived on: its packets go out only
/// there (`Transport.py:1757`) and are accepted only from there (`Transport.py:2974`,
/// `Link.py:1027`).
final class LinkAttachedInterfaceTests: XCTestCase {

  private struct Fixture {
    let initiator: Link
    let responderLink: Link
    let initiatorSpy: SpyInterface
    let responderSpy: SpyInterface
    let responderPaired: LoopbackInterface
    let transports: [Transport]  // a Link holds its Transport weakly
  }

  /// One loopback pair carries the link; each side also has a second, unpaired interface.
  private func makeFixture() throws -> Fixture {
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "attached", aspects: ["iface"])
    let responder = Transport()
    responder.ownerIdentity = identity
    responder.register(destination: destination)
    let initiatorTransport = Transport()

    let a = LoopbackInterface(name: "A")
    let b = LoopbackInterface(name: "B")
    a.paired = b
    b.paired = a
    let initiatorSpy = SpyInterface(name: "initiator-spy")
    let responderSpy = SpyInterface(name: "responder-spy")
    initiatorTransport.register(interface: a)
    initiatorTransport.register(interface: initiatorSpy)
    responder.register(interface: b)
    responder.register(interface: responderSpy)

    let link = try Link.initiate(destination: destination, transport: initiatorTransport)
    let responderLink = try XCTUnwrap(responder.links[link.linkID!])
    XCTAssertEqual(link.status, .active)
    XCTAssertEqual(responderLink.status, .active)
    XCTAssertTrue(link.attachedInterface === a)
    XCTAssertTrue(responderLink.attachedInterface === b)
    return Fixture(
      initiator: link, responderLink: responderLink, initiatorSpy: initiatorSpy,
      responderSpy: responderSpy, responderPaired: b, transports: [initiatorTransport, responder])
  }

  func testLinkPacketsLeaveOnlyOnTheAttachedInterface() throws {
    let f = try makeFixture()
    var got: Data?
    f.responderLink.onDataReceived = { data, _ in got = data }
    try f.initiator.send(Data("hello".utf8))
    XCTAssertEqual(got, Data("hello".utf8))

    // The unpaired interfaces saw the link request broadcast, but no link traffic.
    XCTAssertTrue(f.initiatorSpy.sent.contains { $0.packetType == .linkRequest })
    XCTAssertEqual(f.initiatorSpy.sent.filter { $0.destinationType == .link }.count, 0)
    XCTAssertEqual(f.responderSpy.sent.filter { $0.destinationType == .link }.count, 0)
  }

  func testLinkDataFromAnotherInterfaceIsDropped() throws {
    let f = try makeFixture()
    var received: [Data] = []
    f.responderLink.onDataReceived = { data, _ in received.append(data) }

    // A genuine link packet, captured on its way out of the initiator.
    let ciphertext = try f.initiator.encrypt(Data("injected".utf8))
    let packet = Packet(
      destinationType: .link, packetType: .data, destinationHash: f.initiator.linkID!,
      context: .none, data: ciphertext)
    let wire = try Packet.unpack(packet.pack())

    f.responderSpy.inboundHandler?(wire, f.responderSpy)
    XCTAssertEqual(received, [], "accepted a link packet from a foreign interface")

    // The same packet on the attached interface still lands: the foreign copy left no hash.
    f.responderPaired.inboundHandler?(wire, f.responderPaired)
    XCTAssertEqual(received, [Data("injected".utf8)])
  }
}
