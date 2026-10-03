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

/// `Transport.path_requests` (`Transport.py:187`): when this node last asked the network for
/// each destination.
///
/// `request_path` records it (`Transport.py:3321`), the jobs loop culls it after
/// `PATH_REQUEST_GATE_TIMEOUT` (`Transport.py:981-1100`), and the ingress hold lets the
/// answer through (`Transport.py:1819`).
final class ClientPathRequestTests: XCTestCase {

  // MARK: - Fixtures

  private final class RequestInterface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var sent: [Packet] = []
    var mode: InterfaceMode = .full
    var ingressControl: Bool = true
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  private func makeNode() -> (Transport, RequestInterface) {
    let t = Transport()
    let iface = RequestInterface(name: "mesh")
    t.register(interface: iface)
    t.prioritizeInterfaces()
    return (t, iface)
  }

  private func remoteDestination() throws -> Destination {
    try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "test", aspects: ["requested"])
  }

  /// Fills the announce tracker inside the last half-second of real time, so the next look
  /// starts a burst.
  private func floodAnnounces(_ t: Transport, on iface: any Interface) {
    let start = Date().timeIntervalSince1970 - 0.5
    for i in 0..<60 {
      t.notifyIncomingAnnounce(on: iface, at: start + Double(i) * 0.008)
    }
  }

  // MARK: - Recording and expiry

  func testRequestPathRecordsWhenItAsked() throws {
    let (t, _) = makeNode()
    let target = Data(repeating: 0x5A, count: 16)
    let before = Date().timeIntervalSince1970

    try t.requestPath(for: target)

    let recorded = try XCTUnwrap(
      t.pathRequestTimestamp(for: target),
      "`Transport.path_requests[destination_hash] = time.time()` (Transport.py:3321)")
    XCTAssertGreaterThanOrEqual(recorded, before)
    XCTAssertLessThanOrEqual(recorded, Date().timeIntervalSince1970)
  }

  func testTheEntryExpiresAfterTheGateTimeout() throws {
    let (t, _) = makeNode()
    let target = Data(repeating: 0x5A, count: 16)
    try t.requestPath(for: target)
    let recorded = try XCTUnwrap(t.pathRequestTimestamp(for: target))

    t.sweepPathRequestTables(now: recorded + Transport.pathRequestGateTimeout)
    XCTAssertNotNil(
      t.pathRequestTimestamp(for: target),
      "`if time.time() > ts + PATH_REQUEST_GATE_TIMEOUT` (Transport.py:985) is strict")

    t.sweepPathRequestTables(now: recorded + Transport.pathRequestGateTimeout + 0.001)
    XCTAssertNil(t.pathRequestTimestamp(for: target))
  }

  // MARK: - The ingress-hold exemption

  func testAnAnnounceThisNodeRequestedIsNotHeld() throws {
    let (t, iface) = makeNode()
    let dest = try remoteDestination()
    try t.requestPath(for: dest.hash)
    XCTAssertNil(t.discoveryPathRequest(for: dest.hash), "only path_requests holds the target")

    floodAnnounces(t, on: iface)
    iface.inboundHandler?(try Announce.make(for: dest), iface)

    XCTAssertTrue(
      t.hasPath(to: dest.hash),
      "`if packet.destination_hash in Transport.path_requests ...: pass` (Transport.py:1819)")
    XCTAssertEqual(t.heldAnnounceCount(for: iface), 0)
  }

  func testAnUnrequestedAnnounceInABurstIsHeld() throws {
    let (t, iface) = makeNode()
    let dest = try remoteDestination()

    floodAnnounces(t, on: iface)
    iface.inboundHandler?(try Announce.make(for: dest), iface)

    XCTAssertFalse(t.hasPath(to: dest.hash))
    XCTAssertEqual(t.heldAnnounceCount(for: iface), 1)
  }

  func testTheExemptionLapsesWithItsEntry() throws {
    let (t, iface) = makeNode()
    let dest = try remoteDestination()
    try t.requestPath(for: dest.hash)
    let recorded = try XCTUnwrap(t.pathRequestTimestamp(for: dest.hash))
    t.sweepPathRequestTables(now: recorded + Transport.pathRequestGateTimeout + 1)

    floodAnnounces(t, on: iface)
    iface.inboundHandler?(try Announce.make(for: dest), iface)

    XCTAssertFalse(t.hasPath(to: dest.hash))
    XCTAssertEqual(t.heldAnnounceCount(for: iface), 1)
  }

  func testAWaitingDiscoveryEntryAloneExemptsItsAnnounce() throws {
    let (t, iface) = makeNode()
    let requestor = RequestInterface(name: "requestor")
    t.register(interface: requestor)
    let dest = try remoteDestination()
    t.batchDiscoveryPathRequest(dest.hash, on: requestor)
    XCTAssertNil(t.pathRequestTimestamp(for: dest.hash), "only discovery_path_requests holds it")

    floodAnnounces(t, on: iface)
    iface.inboundHandler?(try Announce.make(for: dest), iface)

    XCTAssertTrue(
      t.hasPath(to: dest.hash),
      "`... or packet.destination_hash in Transport.discovery_path_requests` (Transport.py:1819)")
  }
}
