//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import CryptoKit
import XCTest

@testable import ReticulumSwift

/// RNS 1.6.0 link-request stamps: the initiator's X25519 key is a stamp over
/// `destination.hash + sig_pub` (`Link.py:192-200`, `310-387`).
///
/// The keys and value come from `scripts/capture-stamp-vectors.py` against RNS 1.6.0: the
/// `rs160.stamped` destination of identity `bytes(range(64))`, whose own key bytes the vector
/// reuses, valued at 4.6640625.
final class LinkStampTests: XCTestCase {

  static let pub = Data(hex: "8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f")!
  static let sig = Data(hex: "29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7")!
  static let value = 4.6640625

  final class Hop: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private let lock = NSLock()
    private var packets: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { lock.withLock { packets.append(packet) } }
    var linkRequests: [Packet] { lock.withLock { packets.filter { $0.packetType == .linkRequest } } }
  }

  private func inbound() throws -> (Identity, Destination) {
    let identity = try Identity(privateKeyBytes: Data(0..<64))
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "rs160", aspects: ["stamped"])
    return (identity, destination)
  }

  private func request(to destination: Destination) -> Packet {
    Packet(
      destinationType: .single, packetType: .linkRequest, destinationHash: destination.hash,
      data: Self.pub + Self.sig)
  }

  // MARK: - Responder

  func testTheResponderValuesTheInitiatorKey() throws {
    let (identity, destination) = try inbound()
    XCTAssertEqual(destination.hash.hexString, "cb20bb86f3256654f6ca46b3139b1187")
    let link = try Link.answer(
      request: request(to: destination), destination: destination, owner: identity,
      transport: Transport())
    XCTAssertEqual(link.stampCost, Self.value)
  }

  /// `if RNS.Transport.LR_STAMPS_ENFORCED and not stamp_valid(peer_pub_bytes,
  /// owner.get_link_cost(), stamp_material)` refuses the request (`Link.py:195`).
  func testEnforcementRefusesAKeyBelowTheLinkCost() throws {
    let (identity, destination) = try inbound()
    let t = Transport()
    t.stamps.lrEnforced = true
    destination.setLinkCost(Self.value + 1 / 256)
    XCTAssertThrowsError(
      try Link.answer(
        request: request(to: destination), destination: destination, owner: identity,
        transport: t)
    ) { XCTAssertEqual($0 as? Link.LinkError, .insufficientStamp) }

    destination.setLinkCost(Self.value)
    XCTAssertNoThrow(
      try Link.answer(
        request: request(to: destination), destination: destination, owner: identity,
        transport: t))
  }

  // MARK: - Initiator

  /// A destination that announced a link cost gets a key ground to it (`Link.py:310-313`).
  func testTheInitiatorGrindsAKeyForAnAnnouncedCost() throws {
    let t = Transport()
    t.stamps.destinationCost = 8
    let hop = Hop(name: "lr-announced")
    t.register(interface: hop)
    defer { t.deregister(interface: hop) }
    t.handleIncoming(packet: try Packet.unpack(AnnounceStampTests.withAppData), from: hop)
    let identity = try XCTUnwrap(t.recall(identity: Data(hex: "cb20bb86f3256654f6ca46b3139b1187")!))
    let destination = try Destination(
      identity: identity, direction: .out, kind: .single, appName: "rs160", aspects: ["stamped"])

    let link = try Link.initiate(destination: destination, transport: t)
    let packet = try waitForRequest(on: hop)
    XCTAssertEqual(link.stampCost, 7.25)
    XCTAssertTrue(
      Stamps.stampValid(
        stamp: Data(packet.data.prefix(32)), targetCost: 7.25,
        workblock: destination.hash + link.sigPubBytes))
    XCTAssertEqual(Data(packet.data.prefix(32)), link.pubBytes)
    XCTAssertNotNil(link.linkID)
  }

  /// `ALWAYS_STAMP_LRS` stamps toward a destination that announced no cost, at `LR_COST`.
  func testAlwaysStampingUsesTheDefaultLinkCost() throws {
    let t = Transport()
    t.stamps.alwaysStampLRs = true
    t.stamps.lrCost = 5
    let hop = Hop(name: "lr-always")
    t.register(interface: hop)
    defer { t.deregister(interface: hop) }
    let destination = try Destination(
      identity: Identity(), direction: .out, kind: .single, appName: "rs160", aspects: ["always"])

    let link = try Link.initiate(destination: destination, transport: t)
    let packet = try waitForRequest(on: hop)
    XCTAssertEqual(link.stampCost, 5)
    XCTAssertTrue(
      Stamps.stampValid(
        stamp: Data(packet.data.prefix(32)), targetCost: 5,
        workblock: destination.hash + link.sigPubBytes))
  }

  func testNoCostSendsTheRequestAtOnce() throws {
    let t = Transport()
    let hop = Hop(name: "lr-plain")
    t.register(interface: hop)
    defer { t.deregister(interface: hop) }
    let destination = try Destination(
      identity: Identity(), direction: .out, kind: .single, appName: "rs160", aspects: ["plain"])

    let link = try Link.initiate(destination: destination, transport: t)
    XCTAssertEqual(hop.linkRequests.count, 1)
    XCTAssertNil(link.stampCost)
  }

  /// A key that can't be ground in time closes the link with `STAMP_FAILURE`
  /// (`Link.py:337-342`), and no request goes out.
  func testAStampTimeoutClosesTheLink() throws {
    let t = Transport()
    t.stamps.alwaysStampLRs = true
    t.stamps.lrCost = 40
    t.stamps.linkStampTimeout = 0
    let hop = Hop(name: "lr-timeout")
    t.register(interface: hop)
    defer { t.deregister(interface: hop) }
    let destination = try Destination(
      identity: Identity(), direction: .out, kind: .single, appName: "rs160", aspects: ["slow"])

    let link = try Link.initiate(destination: destination, transport: t)
    let deadline = Date().addingTimeInterval(10)
    while link.status != .closed && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    XCTAssertEqual(link.teardownReason, .stampFailure)
    XCTAssertEqual(link.status, .closed)
    XCTAssertTrue(hop.linkRequests.isEmpty)
  }

  private func waitForRequest(on hop: Hop) throws -> Packet {
    let deadline = Date().addingTimeInterval(10)
    while hop.linkRequests.isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    return try XCTUnwrap(hop.linkRequests.first)
  }
}
