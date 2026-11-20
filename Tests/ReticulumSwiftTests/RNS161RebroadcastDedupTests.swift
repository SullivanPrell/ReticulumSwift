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

/// A rebroadcast skips the non-shared-medium interfaces that already delivered the same
/// announce (`Transport.py:985`, `:1748-1749`, `:2692-2696`).
final class RNS161RebroadcastDedupTests: XCTestCase {

  final class Port: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var sharedMedium: Bool
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private(set) var sent: [Packet] = []
    init(name: String, sharedMedium: Bool = false) {
      self.name = name
      self.sharedMedium = sharedMedium
    }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  func testTheRetransmissionSkipsInterfacesThatDeliveredTheSameAnnounce() throws {
    let t = Transport.unstamped()
    t.transportEnabled = true
    let first = Port(name: "first")
    let echo = Port(name: "echo")
    let radio = Port(name: "radio", sharedMedium: true)
    let quiet = Port(name: "quiet")
    for port in [first, echo, radio, quiet] { t.register(interface: port) }
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "dedup161",
      aspects: ["retry"])
    let announce = try Announce.make(for: destination)

    first.inboundHandler?(announce, first)
    echo.inboundHandler?(announce, echo)
    radio.inboundHandler?(announce, radio)
    let before = [echo, radio, quiet].map(\.sent.count)
    t.processAnnounceRetries(now: Date().timeIntervalSince1970 + 60)

    XCTAssertEqual(echo.sent.count - before[0], 0, "echo delivered it, so it's skipped")
    XCTAssertEqual(radio.sent.count - before[1], 1, "a shared medium is never skipped")
    XCTAssertEqual(quiet.sent.count - before[2], 1)
  }

  /// An announce that replaces an unresponsive path updates the table without a rebroadcast
  /// (`table_insertion_only`, `Transport.py:2686-2689`, `:2734`).
  func testReplacingAnUnresponsivePathDoesntRebroadcast() throws {
    let t = Transport.unstamped()
    t.transportEnabled = true
    let near = Port(name: "near")
    let far = Port(name: "far")
    let other = Port(name: "other")
    for port in [near, far, other] { t.register(interface: port) }
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "dedup161",
      aspects: ["revive"])
    let announce = try Announce.make(for: destination)
    near.inboundHandler?(announce, near)
    XCTAssertTrue(t.markPathUnresponsive(for: destination.hash))
    let before = (near.sent.count, other.sent.count)

    var longer = announce
    longer.hops = 2
    far.inboundHandler?(longer, far)

    XCTAssertTrue(t.paths[destination.hash]?.nextHopInterface === far)
    XCTAssertEqual(near.sent.count, before.0)
    XCTAssertEqual(other.sent.count, before.1)
  }
}
