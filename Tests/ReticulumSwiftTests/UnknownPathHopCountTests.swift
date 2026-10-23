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

/// `Transport.hops_to` answers `PATHFINDER_M` (128) for a destination with no path
/// (`Transport.py:3141-3143`, RNS 1.5.7), and both timeouts built on it scale by that count.
final class UnknownPathHopCountTests: XCTestCase {

  private let perHop: TimeInterval = 6

  /// A sink with a bitrate, so a known path's first-hop term isn't the 6 s default.
  private func transport(pathHops: UInt8?) throws -> (Transport, Destination) {
    let transport = Transport()
    let sink = LinkParityTests.SinkInterface()
    sink.bitrate = 1200
    transport.register(interface: sink)
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "t")
    if let pathHops {
      transport.restore(identity: identity, forDestination: destination.hash)
      transport.restore(
        path: Transport.PathEntry(
          destinationHash: destination.hash, nextHopInterface: sink, hops: pathHops,
          lastHeard: Date(), identityHash: identity.hash),
        forDestination: destination.hash)
    }
    return (transport, destination)
  }

  private func receipt(to destination: Destination, on transport: Transport) throws
    -> PacketReceipt
  {
    let packet = Packet(
      destinationType: .single, packetType: .data, destinationHash: destination.hash,
      data: Data(repeating: 0xAB, count: 16))
    return try XCTUnwrap(transport.send(packet))
  }

  func testHopsToOrUnknownIsPythonsHopsTo() throws {
    let (unknown, nowhere) = try transport(pathHops: nil)
    XCTAssertEqual(unknown.hopsToOrUnknown(nowhere.hash), Transport.pathfinderM)
    let (known, there) = try transport(pathHops: 2)
    XCTAssertEqual(known.hopsToOrUnknown(there.hash), known.hopsTo(there.hash).map(Int.init))
  }

  /// `establishment_timeout = first_hop_timeout + ESTABLISHMENT_TIMEOUT_PER_HOP *
  /// max(1, hops_to)` and `expected_hops = hops_to` (`Link.py:280-282`).
  func testALinkWithNoPathWaitsForPythonsUnknownHopCount() throws {
    let (transport, destination) = try transport(pathHops: nil)
    let link = try Link.initiate(destination: destination, transport: transport)
    XCTAssertEqual(link.establishmentTimeout, 6 + perHop * 128, accuracy: 0.001)
    XCTAssertEqual(link.expectedHops, Transport.pathfinderM)
  }

  func testALinkOnAKnownPathWaitsForItsHopCount() throws {
    let (transport, destination) = try transport(pathHops: 2)
    let hops = try XCTUnwrap(transport.hopsTo(destination.hash).map(Int.init))
    let link = try Link.initiate(destination: destination, transport: transport)
    XCTAssertEqual(
      link.establishmentTimeout,
      transport.firstHopTimeout(for: destination.hash) + perHop * TimeInterval(max(1, hops)),
      accuracy: 0.001)
  }

  /// `timeout = get_first_hop_timeout + TIMEOUT_PER_HOP * hops_to` (`Packet.py:432-433`).
  func testAReceiptWithNoPathWaitsForPythonsUnknownHopCount() throws {
    let (transport, destination) = try transport(pathHops: nil)
    XCTAssertEqual(
      try receipt(to: destination, on: transport).timeout, 6 + perHop * 128, accuracy: 0.001)
  }

  func testAReceiptOnAKnownPathAddsTheFirstHopTimeout() throws {
    let (transport, destination) = try transport(pathHops: 2)
    let hops = try XCTUnwrap(transport.hopsTo(destination.hash).map(Int.init))
    let firstHop = transport.firstHopTimeout(for: destination.hash)
    XCTAssertGreaterThan(firstHop, 6, "test premise: the sink's bitrate adds to the first hop")
    XCTAssertEqual(
      try receipt(to: destination, on: transport).timeout,
      firstHop + perHop * TimeInterval(hops), accuracy: 0.001)
  }
}
