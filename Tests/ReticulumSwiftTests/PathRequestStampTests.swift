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

/// RNS 1.6.0's path-request format: `dst || transport id || tag`, optionally followed by a
/// 16-byte `0xC1` stamp extension (`Transport.py:3974-4013`).
///
/// The extension comes from `scripts/capture-stamp-vectors.py` against RNS 1.6.0:
/// `stamp_path_request` for target `0xA1 * 16` and tag `0xB2 * 16` at the shipped `PR_VALUE`.
final class PathRequestStampTests: XCTestCase {

  static let target = Data(repeating: 0xA1, count: 16)
  static let tag = Data(repeating: 0xB2, count: 16)
  static let requestor = Data(repeating: 0xC3, count: 16)
  static let ext = Data(hex: "c100a3e86c5a8d1a21f32a1635844b2a")!
  static let lenient = Data([0xC1, 0xFF]) + Data(count: 14)

  final class Hop: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var mode: InterfaceMode
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private let lock = NSLock()
    private var packets: [Packet] = []
    init(name: String, mode: InterfaceMode = .full) {
      self.name = name
      self.mode = mode
    }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { lock.withLock { packets.append(packet) } }
    var requests: [Data] {
      lock.withLock {
        packets.filter { $0.destinationHash == Transport.pathRequestDestinationHash }.map(\.data)
      }
    }
  }

  final class ServingHop: Interface, LocalClientServingInterface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var clientCount: Int = 1
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var sent: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  private func pathRequest(_ body: Data) -> Packet {
    Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Transport.pathRequestDestinationHash, data: body)
  }

  private func stat(_ t: Transport, _ hop: any Interface, _ key: String) throws -> Int {
    let rows = try XCTUnwrap(InterfaceStatsPayload.build(t).asDictionary?["interfaces"]?.asArray)
    let row = rows.compactMap(\.asDictionary).first { $0["name"]?.asString == hop.displayName }
    return try XCTUnwrap(row?[key]?.asInt)
  }

  // MARK: - Ingress

  /// `Transport.py:2072-2086`: past 64 bytes is "Excessive path request size", and any length
  /// other than 32, 48 or 64 is "Invalid path request size". Both count a violation and stop.
  func testOnlyLegacyPlainAndStampedLengthsAreAccepted() throws {
    for (length, accepted) in [
      (32, true), (48, true), (64, true), (17, false), (31, false), (33, false), (47, false),
      (49, false), (63, false), (65, false),
    ] {
      let t = Transport()
      let hop = Hop(name: "len-\(length)")
      t.register(interface: hop)
      t.handleIncoming(
        packet: pathRequest(Self.target + Data(repeating: 0xEE, count: length - 16)), from: hop)
      XCTAssertEqual(try stat(t, hop, "protocol_violations"), accepted ? 0 : 1, "\(length)")
      XCTAssertEqual(try stat(t, hop, "prxc"), accepted ? 1 : 0, "\(length)")
    }
  }

  /// `Transport.py:2097-2131`: the stamp is checked against the receiving interface's
  /// `pr_cost`, and under `STAMPS_ENFORCED` an unstamped, lenient-relayed or insufficient
  /// request drops silently.
  func testEnforcementChecksTheStampAgainstTheInterfaceCost() throws {
    let stamped = Self.target + Self.requestor + Self.tag + Self.ext
    let cases: [(Data, Double?, Bool)] = [
      (stamped, nil, true),
      (stamped, 17, false),
      (Self.target + Self.requestor + Self.tag, nil, false),
      (Self.target + Self.requestor + Self.tag + Self.lenient, nil, false),
      (Self.target + Self.tag, nil, false),
    ]
    for (index, (body, prCost, accepted)) in cases.enumerated() {
      let t = Transport()
      t.stamps.enforced = true
      let hop = Hop(name: "enforce-\(index)")
      hop.prCost = prCost
      t.register(interface: hop)
      t.handleIncoming(packet: pathRequest(body), from: hop)
      XCTAssertEqual(try stat(t, hop, "prxc"), accepted ? 1 : 0, "case \(index)")
      XCTAssertEqual(try stat(t, hop, "protocol_violations"), 0, "case \(index)")
    }
  }

  // MARK: - Emission

  /// From 1.6.0 every request carries the transport identity hash (`Transport.py:3700-3703`).
  func testANonTransportNodeStillSendsItsTransportID() throws {
    let t = Transport()
    t.transportEnabled = false
    let hop = Hop(name: "emit")
    t.register(interface: hop)
    try t.requestPath(for: Self.target, onInterface: hop, tag: Self.tag)
    XCTAssertEqual(hop.requests, [Self.target + t.transportInstanceID + Self.tag])
  }

  /// `STAMP_PRS` grinds a stamp over `dst+tag` before sending, then reuses it from
  /// `pr_stamp_cache` (`Transport.py:3705-3719`, `4020-4049`).
  func testStampingOwnRequestsGrindsThenReusesTheStamp() throws {
    let t = Transport()
    t.stamps.stampPRs = true
    t.stamps.prValue = 6
    let hop = Hop(name: "grind")
    t.register(interface: hop)

    try t.requestPath(for: Self.target, onInterface: hop, tag: Self.tag)
    let deadline = Date().addingTimeInterval(10)
    while hop.requests.isEmpty && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    let body = try XCTUnwrap(hop.requests.first)
    XCTAssertEqual(body.count, 64)
    XCTAssertEqual(Data(body.prefix(48)), Self.target + t.transportInstanceID + Self.tag)
    XCTAssertEqual(Data(body[48..<50]), Data([0xC1, 0x00]))
    XCTAssertTrue(
      Stamps.stampValid(stamp: Data(body[50...]), targetCost: 6, workblock: Self.target + Self.tag))

    try t.requestPath(for: Self.target, onInterface: hop, tag: Self.tag)
    XCTAssertEqual(hop.requests.count, 2, "a cached stamp sends at once")
    XCTAssertEqual(hop.requests.last, body)
  }

  // MARK: - Forwarding

  /// Recursive discovery forwards the request's own tag and extension
  /// (`Transport.py:3935-3948`).
  func testRecursiveDiscoveryKeepsTheTagAndExtension() throws {
    for (ext, stampPRs, forwarded) in [
      (Self.ext, false, Self.ext), (nil, false, nil), (nil, true, Self.lenient),
    ] as [(Data?, Bool, Data?)] {
      let t = Transport()
      t.transportEnabled = true
      t.stamps.stampPRs = stampPRs
      let inbound = Hop(name: "gw", mode: .gateway)
      let outbound = Hop(name: "out")
      t.register(interface: inbound)
      t.register(interface: outbound)
      t.handleIncoming(
        packet: pathRequest(Self.target + Self.requestor + Self.tag + (ext ?? Data())),
        from: inbound)
      XCTAssertEqual(
        outbound.requests, [Self.target + t.transportInstanceID + Self.tag + (forwarded ?? Data())])
    }
  }

  /// A local client's request goes to the network under its own tag and extension
  /// (`Transport.py:3871-3878`), and a network request goes down to local clients the same way
  /// (`Transport.py:3950-3963`).
  func testLocalClientForwardsKeepTheTagAndExtension() throws {
    let t = Transport()
    t.transportEnabled = false
    let serving = ServingHop(name: "Shared Instance[37428]")
    let mesh = Hop(name: "mesh")
    t.register(interface: serving)
    t.register(interface: mesh)

    t.handleIncoming(
      packet: pathRequest(Self.target + Self.requestor + Self.tag + Self.ext), from: serving)
    XCTAssertEqual(mesh.requests, [Self.target + t.transportInstanceID + Self.tag + Self.ext])

    let other = Data(repeating: 0xD4, count: 16)
    t.handleIncoming(packet: pathRequest(other + Self.requestor + Self.tag), from: mesh)
    let down = serving.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
    XCTAssertEqual(down.map(\.data), [other + t.transportInstanceID + Self.tag])
  }

  /// A discovery request skipping one interface goes out under one tag on all the others
  /// (`Transport.py:4062-4075`).
  func testDiscoveryRequestsShareOneTag() throws {
    let t = Transport()
    t.discoveryPathRequestTxThrottle = 0.01
    let blocked = Hop(name: "blocked")
    let a = Hop(name: "a")
    let b = Hop(name: "b")
    for hop in [blocked, a, b] { t.register(interface: hop) }

    t.queueDiscoveryPathRequests([.init(destinationHash: Self.target, blockedInterface: blocked)])
    let deadline = Date().addingTimeInterval(5)
    while (a.requests.isEmpty || b.requests.isEmpty) && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.01)
    }
    XCTAssertTrue(blocked.requests.isEmpty)
    XCTAssertEqual(a.requests.count, 1)
    XCTAssertEqual(a.requests, b.requests)
  }
}
