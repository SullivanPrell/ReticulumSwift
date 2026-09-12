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

/// Covers the two inbound size checks RNS 1.5.0 added to `preprocess_inbound`.
///
/// RNS 1.5.0 added two inbound size checks to `Transport.preprocess_inbound`:
///
///   `if interface and len(raw) > interface.HW_MTU + (interface.ifac_size or 0):`
///       `return interface.protocol_violation(f"Frame size exceeded MTU of …")`   (`:1789`)
///   `if len(raw) > RNS.Reticulum.MTU:`
///       `return … protocol_violation(f"Excessive announce packet frame size …")` (`:1804`)
///
/// Both sit at the transport seam, so they cover *every* interface. This port had only the
/// first one, only inside the HDLC deframer—which means UDP, RNode/KISS, AutoInterface,
/// Weave and the KISS-framed I2P path had no inbound frame bound at all, and no interface at
/// all bounded announces. A 1.5.x peer now drops these frames, so admitting them means
/// accepting packets the rest of the network has discarded and, on a transport-mode node,
/// forwarding them.
final class InboundFrameSizeGuardTests: XCTestCase {

  /// Delivers raw bytes rather than pre-parsed packets, so the transport seam under test
  /// actually runs.
  ///
  /// A double that calls `inboundHandler` instead would bypass every guard
  /// here and the suite would read as coverage while proving nothing.
  private final class RawLoopbackInterface: Interface {
    let interfaceState = InterfaceState()
    var name: String
    var bitrate: Int = 10_000_000
    var isOnline: Bool = true
    weak var paired: RawLoopbackInterface?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var rawInboundHandler: ((Data, any Interface) -> Void)?
    var ifacIdentity: Identity?
    var ifacKey: Data?
    var ifacSize: Int = 0
    var hwMtu: Int?

    init(name: String, hwMtu: Int? = nil) {
      self.name = name
      self.hwMtu = hwMtu
    }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
      // `packedBytes()`, not `pack()`. `pack()` enforces the 500-byte packet MTU, so a
      // double built on it silently emits nothing for an oversized announce and every
      // receive-side assertion below would pass without the receiver ever being asked a
      // question. A Backbone peer (HW_MTU 1 MiB) really does put frames this size on the
      // wire, and that peer is what this double stands in for.
      let raw = try packet.packedBytes()
      paired?.rawInboundHandler?(raw, paired!)
    }
  }

  /// Feed `raw` at the seam and report whether it reached the transport core.
  private func reachesCore(_ raw: Data, hwMtu: Int?, ifacSize: Int = 0) throws -> Bool {
    let t = Transport()
    let iface = RawLoopbackInterface(name: "in", hwMtu: hwMtu)
    iface.ifacSize = ifacSize
    t.register(interface: iface)

    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in,
      kind: .single, appName: "sizeguard")
    t.register(destination: destination)

    var delivered = false
    t.onPacketDelivered = { _, _, _ in delivered = true }
    iface.rawInboundHandler?(raw, iface)
    return delivered
  }

  /// A DATA packet of exactly `total` bytes on the wire, addressed to `destinationHash`.
  private func frame(bytes total: Int, to destinationHash: Data) throws -> Data {
    let overhead = 2 + Constants.truncatedHashLength + 1
    let packet = Packet(
      destinationType: .single, packetType: .data,
      destinationHash: destinationHash,
      data: Data(repeating: 0x5A, count: total - overhead))
    // `packedBytes()`, not `pack()`: `pack()` enforces the 500-byte packet MTU, so it
    // can't produce the frames under test—which is the point. A peer on a
    // large-MTU medium (Backbone's HW_MTU is 1 MiB) legitimately puts frames this size
    // on the wire, and an attacker can put any size there at all.
    let raw = try packet.packedBytes()
    XCTAssertEqual(raw.count, total, "fixture must be exactly the size under test")
    return raw
  }

  // MARK: - Frame size vs HW_MTU

  func testAFrameLargerThanTheInterfaceMtuNeverReachesTheCore() throws {
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in,
      kind: .single, appName: "sizeguard")
    let hwMtu = 512
    let raw = try frame(bytes: hwMtu + 1, to: destination.hash)

    let t = Transport()
    let iface = RawLoopbackInterface(name: "in", hwMtu: hwMtu)
    t.register(interface: iface)
    t.register(destination: destination)
    var delivered = false
    t.onPacketDelivered = { _, _, _ in delivered = true }
    iface.rawInboundHandler?(raw, iface)

    XCTAssertFalse(
      delivered,
      """
      `len(raw) > interface.HW_MTU + (interface.ifac_size or 0)` \
      (Transport.py:1789). The bound is the interface's own hardware MTU, so \
      a frame past it could not have been legitimately produced by a peer on \
      that medium.
      """)
  }

  func testAFrameExactlyAtTheInterfaceMtuIsDelivered() throws {
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in,
      kind: .single, appName: "sizeguard")
    let hwMtu = 512
    let raw = try frame(bytes: hwMtu, to: destination.hash)

    let t = Transport()
    let iface = RawLoopbackInterface(name: "in", hwMtu: hwMtu)
    t.register(interface: iface)
    t.register(destination: destination)
    var delivered = false
    t.onPacketDelivered = { _, _, _ in delivered = true }
    iface.rawInboundHandler?(raw, iface)

    XCTAssertTrue(
      delivered,
      "the comparison is `>`, not `>=` — a frame filling the MTU exactly is "
        + "legal, and this is the case that separates the two")
  }

  func testTheIfacSizeIsAddedToTheAllowance() throws {
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in,
      kind: .single, appName: "sizeguard")
    let hwMtu = 512
    let ifacSize = 16
    let raw = try frame(bytes: hwMtu + ifacSize, to: destination.hash)

    let t = Transport()
    let iface = RawLoopbackInterface(name: "in", hwMtu: hwMtu)
    iface.ifacSize = ifacSize
    t.register(interface: iface)
    t.register(destination: destination)
    var delivered = false
    t.onPacketDelivered = { _, _, _ in delivered = true }
    iface.rawInboundHandler?(raw, iface)

    XCTAssertTrue(
      delivered,
      "Python's allowance is `HW_MTU + ifac_size` (Transport.py:1789) — "
        + "without the addend an IFAC interface would reject full-size frames")
  }

  func testAnInterfaceWithoutAHardwareMtuDoesNotGate() throws {
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in,
      kind: .single, appName: "sizeguard")
    let raw = try frame(bytes: 4096, to: destination.hash)

    let t = Transport()
    let iface = RawLoopbackInterface(name: "in", hwMtu: nil)
    t.register(interface: iface)
    t.register(destination: destination)
    var delivered = false
    t.onPacketDelivered = { _, _, _ in delivered = true }
    iface.rawInboundHandler?(raw, iface)

    XCTAssertTrue(
      delivered,
      """
      `HW_MTU` is `None` on the base class, and Python's unguarded `None + …` \
      would raise — which its blanket `except` turns into a silent drop of \
      every packet on such an interface. Every shipped interface sets HW_MTU, \
      so that branch is unreachable upstream; this port skips the check rather \
      than reproducing a latent crash as a behaviour.
      """)
  }

  // MARK: - Announce frame size vs Reticulum.MTU

  func testAnOversizedAnnounceIsDropped() throws {
    let (sender, receiver, senderIface, _) = makeRawPair()
    let handler = CountingAnnounceHandler()
    receiver.register(announceHandler: handler)

    let destination = try Destination(
      identity: Identity(), direction: .in,
      kind: .single, appName: "bloat")
    // Push the announce past `Reticulum.MTU` with oversized app data. Everything else
    // about the announce—signature, ratchet, name hash—stays valid, so the *only*
    // reason for a drop is the size.
    try sender.announce(
      destination: destination,
      appData: Data(repeating: 0x42, count: Constants.mtu))

    XCTAssertEqual(
      handler.count, 0,
      """
      `if len(raw) > RNS.Reticulum.MTU: return … protocol_violation\
      ("Excessive announce packet frame size")` (Transport.py:1804). An \
      announce is flooded onward by every transport node that accepts it, so \
      an unbounded one is an amplification vector, not just a large packet.
      """)
    _ = senderIface
  }

  func testAnAnnounceWithinTheMtuIsAccepted() throws {
    let (sender, receiver, senderIface, _) = makeRawPair()
    let handler = CountingAnnounceHandler()
    receiver.register(announceHandler: handler)

    let destination = try Destination(
      identity: Identity(), direction: .in,
      kind: .single, appName: "ok")
    try sender.announce(destination: destination, appData: Data("small".utf8))

    XCTAssertEqual(
      handler.count, 1,
      "an ordinary announce must still arrive — the guard is a ceiling, not "
        + "a new requirement")
    _ = senderIface
  }

  // MARK: - Harness

  private final class CountingAnnounceHandler: AnnounceHandler {
    var aspectFilter: String? = nil
    var receivePathResponses: Bool = false
    private(set) var count = 0
    func receivedAnnounce(
      destinationHash: Data, identity: Identity, appData: Data?,
      announcePacketHash: Data, isPathResponse: Bool
    ) { count += 1 }
  }

  private func makeRawPair() -> (Transport, Transport, RawLoopbackInterface, RawLoopbackInterface) {
    let a = Transport()
    let b = Transport()
    let aI = RawLoopbackInterface(name: "A")
    let bI = RawLoopbackInterface(name: "B")
    aI.paired = bI
    bI.paired = aI
    a.register(interface: aI)
    b.register(interface: bI)
    return (a, b, aI, bI)
  }
}
