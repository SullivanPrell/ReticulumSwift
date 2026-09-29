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

/// A link proves an inbound `DATA` packet with no context according to its destination's
/// proof strategy, as `Link.py:961-967` does.
final class LinkProofStrategyTests: XCTestCase {

  final class LoopbackInterface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    weak var paired: LoopbackInterface?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
      let copy = try Packet.unpack(try packet.pack())
      paired?.inboundHandler?(copy, paired!)
    }
  }

  private var initiatorTransport: Transport!
  private var responderTransport: Transport!

  private func establishLink(
    configure: (Destination) -> Void
  ) throws -> (initiator: Link, responder: Link) {
    initiatorTransport = Transport()
    responderTransport = Transport()
    let identity = Identity()
    let inbound = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "spec", aspects: ["proof"])
    configure(inbound)
    responderTransport.ownerIdentity = identity
    responderTransport.register(destination: inbound)
    let outbound = try Destination(
      identity: try Identity(publicKeyBytes: identity.publicKeyBytes), direction: .out,
      kind: .single, appName: "spec", aspects: ["proof"])
    let a = LoopbackInterface(name: "A")
    let b = LoopbackInterface(name: "B")
    a.paired = b
    b.paired = a
    initiatorTransport.register(interface: a)
    responderTransport.register(interface: b)
    let up = expectation(description: "both ends established")
    up.expectedFulfillmentCount = 2
    initiatorTransport.onLinkEstablished = { _ in up.fulfill() }
    responderTransport.onLinkEstablished = { _ in up.fulfill() }
    let initiator = try Link.initiate(destination: outbound, transport: initiatorTransport)
    wait(for: [up], timeout: 2.0)
    let responder = try XCTUnwrap(responderTransport.links[try XCTUnwrap(initiator.linkID)])
    return (initiator, responder)
  }

  private func sendAndAwaitDelivery(
    over link: Link, expectDelivery: Bool
  ) throws -> PacketReceipt {
    let receipt = try XCTUnwrap(try link.send(Data("proof me".utf8)))
    let delivered = expectation(description: "delivered")
    delivered.isInverted = !expectDelivery
    delivered.assertForOverFulfill = false
    receipt.setDeliveryCallback { _ in delivered.fulfill() }
    if receipt.status == .delivered { delivered.fulfill() }
    wait(for: [delivered], timeout: 1.0)
    return receipt
  }

  func testProveAllProvesEveryLinkPacket() throws {
    let (initiator, _) = try establishLink { $0.setProofStrategy(.proveAll) }

    let receipt = try sendAndAwaitDelivery(over: initiator, expectDelivery: true)

    XCTAssertEqual(receipt.status, .delivered)
  }

  func testProveNoneLeavesTheLinkPacketUnproven() throws {
    let (initiator, _) = try establishLink { $0.setProofStrategy(.proveNone) }

    let receipt = try sendAndAwaitDelivery(over: initiator, expectDelivery: false)

    XCTAssertEqual(receipt.status, .sent)
  }

  func testProveAppProvesWhenTheCallbackAsks() throws {
    let asked = expectation(description: "proof requested")
    let (initiator, _) = try establishLink { destination in
      destination.setProofStrategy(.proveApp)
      destination.setProofRequestedCallback { _ in
        asked.fulfill()
        return true
      }
    }

    let receipt = try sendAndAwaitDelivery(over: initiator, expectDelivery: true)

    wait(for: [asked], timeout: 1.0)
    XCTAssertEqual(receipt.status, .delivered)
  }

  func testProveAppLeavesThePacketUnprovenWhenTheCallbackDeclines() throws {
    let (initiator, _) = try establishLink { destination in
      destination.setProofStrategy(.proveApp)
      destination.setProofRequestedCallback { _ in false }
    }

    let receipt = try sendAndAwaitDelivery(over: initiator, expectDelivery: false)

    XCTAssertEqual(receipt.status, .sent)
  }
}
