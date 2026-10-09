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

/// A node relays a packet along its path table only when the packet is in transport to it.
///
/// Python relays a non-announce packet whose `transport_id` is this node's identity hash
/// (`Transport.py:2018-2019`), and stamps that hash itself on a packet for a local client,
/// whose path is 0 hops (`:1968`, `:2006-2007`). A HEADER_1 packet for anyone else carries no
/// `transport_id`, so no node relays it: not a transport node, and not a shared instance it
/// reaches from a local client. A sender inserts the transport header itself when it knows a
/// path (`:1396`, `:1416`).
///
/// The cache-request branch (`:2012-2013`) precedes the check, and link-table traffic
/// (`:2121-2160`) doesn't consult it.
final class InTransportRelayTests: XCTestCase {

  final class MeshIface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var mode: InterfaceMode = .full
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var sent: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  final class ServingIface: Interface, LocalClientServingInterface {
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

  private let destinationHash = Data(repeating: 0xD5, count: Constants.truncatedHashLength)
  private let nextHop = Data(repeating: 0xBB, count: Constants.truncatedHashLength)
  private var cacheDirectory: URL?

  override func tearDown() {
    if let cacheDirectory { try? FileManager.default.removeItem(at: cacheDirectory) }
    super.tearDown()
  }

  /// A transport node with a path to ``destinationHash`` on `toward`, 2 hops as Python counts.
  private func transportNode() -> (Transport, from: MeshIface, toward: MeshIface) {
    let t = Transport()
    t.transportEnabled = true
    let from = MeshIface(name: "meshA")
    let toward = MeshIface(name: "meshB")
    t.register(interface: from)
    t.register(interface: toward)
    t.injectPath(
      destinationHash, nextHop: nextHop, receivedOn: toward, hops: 1, announcePacketHash: nil)
    return (t, from, toward)
  }

  /// A shared instance with transport off, a local client and a mesh interface.
  private func sharedInstance() -> (Transport, client: ServingIface, mesh: MeshIface) {
    let t = Transport()
    t.transportEnabled = false
    let client = ServingIface(name: "Shared Instance[37428]")
    let mesh = MeshIface(name: "mesh")
    t.register(interface: client)
    t.register(interface: mesh)
    return (t, client, mesh)
  }

  private func packet(
    _ type: Packet.PacketType, to destination: Data, inTransportTo transportID: Data? = nil,
    context: Packet.Context = .none, data: Data = Data(repeating: 0x11, count: 64)
  ) -> Packet {
    var p = Packet(
      destinationType: .single, packetType: type, destinationHash: destination,
      context: context, data: data)
    if let transportID {
      p.headerType = .type2
      p.transportType = .transport
      p.transportID = transportID
    }
    return p
  }

  private func sent(_ iface: MeshIface, _ type: Packet.PacketType) -> [Packet] {
    iface.sent.filter { $0.packetType == type && $0.destinationHash == destinationHash }
  }

  // MARK: - Data

  func testATransportNodeDoesNotRelayHeader1Data() {
    let (t, from, toward) = transportNode()

    from.inboundHandler?(packet(.data, to: destinationHash), from)

    XCTAssertEqual(sent(toward, .data).count, 0, "no transport_id, so not in transport (:2018)")
    _ = t
  }

  func testATransportNodeRelaysDataInTransportToIt() {
    let (t, from, toward) = transportNode()

    from.inboundHandler?(
      packet(.data, to: destinationHash, inTransportTo: t.transportInstanceID), from)

    let relayed = sent(toward, .data)
    XCTAssertEqual(relayed.count, 1)
    XCTAssertEqual(relayed.first?.transportID, nextHop, "remaining_hops > 1 (:2026-2030)")
  }

  func testASharedInstanceDoesNotRelayHeader1DataFromALocalClient() {
    let (t, client, mesh) = sharedInstance()
    t.injectPath(
      destinationHash, nextHop: nextHop, receivedOn: mesh, hops: 1, announcePacketHash: nil)

    client.inboundHandler?(packet(.data, to: destinationHash), client)

    XCTAssertEqual(sent(mesh, .data).count, 0, "from_local_client opens the gate, not :2018")
  }

  func testASharedInstanceRelaysHeader1DataForALocalClient() {
    let (t, client, mesh) = sharedInstance()
    t.injectPath(
      destinationHash, nextHop: nextHop, receivedOn: client, hops: 0, announcePacketHash: nil)

    mesh.inboundHandler?(packet(.data, to: destinationHash), mesh)

    let relayed = client.sent.filter { $0.packetType == .data }
    XCTAssertEqual(relayed.count, 1, "for_local_client stamps this node's id (:2006-2007)")
    XCTAssertEqual(relayed.first?.headerType, .type1, "remaining_hops == 0 keeps the header")
  }

  // MARK: - Link requests

  func testATransportNodeDoesNotRelayAHeader1LinkRequest() {
    let (t, from, toward) = transportNode()

    from.inboundHandler?(packet(.linkRequest, to: destinationHash), from)

    XCTAssertEqual(sent(toward, .linkRequest).count, 0)
    XCTAssertTrue(t.linkRoutes.isEmpty, "a link_entry is recorded only by the relay (:2100)")
  }

  func testATransportNodeRelaysALinkRequestInTransportToIt() {
    let (t, from, toward) = transportNode()

    from.inboundHandler?(
      packet(.linkRequest, to: destinationHash, inTransportTo: t.transportInstanceID), from)

    XCTAssertEqual(sent(toward, .linkRequest).first?.transportID, nextHop)
    XCTAssertEqual(t.linkRoutes.count, 1)
  }

  func testASharedInstanceDoesNotRelayAHeader1LinkRequestFromALocalClient() {
    let (t, client, mesh) = sharedInstance()
    t.injectPath(
      destinationHash, nextHop: nextHop, receivedOn: mesh, hops: 1, announcePacketHash: nil)

    client.inboundHandler?(packet(.linkRequest, to: destinationHash), client)

    XCTAssertEqual(sent(mesh, .linkRequest).count, 0)
    XCTAssertTrue(t.linkRoutes.isEmpty)
  }

  func testASharedInstanceRelaysAHeader1LinkRequestForALocalClient() {
    let (t, client, mesh) = sharedInstance()
    t.injectPath(
      destinationHash, nextHop: nextHop, receivedOn: client, hops: 0, announcePacketHash: nil)

    mesh.inboundHandler?(packet(.linkRequest, to: destinationHash), mesh)

    XCTAssertEqual(client.sent.filter { $0.packetType == .linkRequest }.count, 1)
    XCTAssertEqual(t.linkRoutes.count, 1)
  }

  // MARK: - Cache requests

  /// A transport node whose cache holds nothing for the requested hash.
  private func cachingTransportNode() throws -> (Transport, from: MeshIface, toward: MeshIface) {
    let node = transportNode()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns-in-transport-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    cacheDirectory = directory
    node.0.cacheDirectory = directory
    return node
  }

  func testAServedHeader1CacheRequestIsAnswered() throws {
    let (t, from, toward) = try cachingTransportNode()
    let cached = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "intransport")
    let announce = try Announce.make(for: cached)
    try t.cacheAnnounce(announce)
    let request = packet(
      .data, to: destinationHash, context: .cacheRequest,
      data: Hashes.fullHash(try announce.hashablePart()))

    from.inboundHandler?(request, from)

    XCTAssertTrue(t.hasPath(to: cached.hash), "the cache answers before :2018")
    XCTAssertEqual(sent(toward, .data).count, 0)
  }

  func testAnUnservedHeader1CacheRequestIsNotRelayed() throws {
    let (t, from, toward) = try cachingTransportNode()
    let request = packet(
      .data, to: destinationHash, context: .cacheRequest,
      data: Data(repeating: 0x2C, count: Constants.fullHashLength))

    from.inboundHandler?(request, from)

    XCTAssertEqual(sent(toward, .data).count, 0, "an unserved request reaches :2018")
    _ = t
  }

  func testAnUnservedCacheRequestInTransportIsRelayed() throws {
    let (t, from, toward) = try cachingTransportNode()
    let request = packet(
      .data, to: destinationHash, inTransportTo: t.transportInstanceID, context: .cacheRequest,
      data: Data(repeating: 0x2C, count: Constants.fullHashLength))

    from.inboundHandler?(request, from)

    XCTAssertEqual(sent(toward, .data).count, 1)
  }

  // MARK: - Link table

  func testHeader1LinkTrafficFollowsTheLinkTable() {
    let (t, from, toward) = transportNode()
    let linkID = Data(repeating: 0x71, count: Constants.truncatedHashLength)
    var route = Transport.LinkRoute(
      linkID: linkID, initiatorSideInterface: from, responderSideInterface: toward,
      initiatorSideInterfaceName: from.name, responderSideInterfaceName: toward.name,
      destinationHash: destinationHash, lastHeard: Date(), remainingHops: 2, takenHops: 1)
    route.validated = true
    t.restore(linkRoute: route)
    let linkData = Packet(
      destinationType: .link, packetType: .data, destinationHash: linkID,
      data: Data(repeating: 0x33, count: 48))

    from.inboundHandler?(linkData, from)

    let relayed = toward.sent.filter { $0.destinationHash == linkID }
    XCTAssertEqual(relayed.count, 1, "link packets carry no transport_id (:2121-2160)")
    XCTAssertEqual(relayed.first?.headerType, .type1)
  }
}
