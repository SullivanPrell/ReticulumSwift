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

/// The hop count a shared instance relays, and how often it relays a local client's announce.
///
/// Python adds one hop on arrival (`Transport.py:1800`) and takes it back on a local client's
/// interface or the interface to a shared instance (`:1937-1940`). Every relay then sends
/// `packet.hops` as that leaves it. A local client's announce goes out once (`:2356-2360`).
final class LocalClientHopCountTests: XCTestCase {

  // MARK: - Fixtures

  final class MeshIface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var mode: InterfaceMode = .full
    var recursivePrs: Bool = false
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var sent: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  /// Stands in for `LocalServerClientInterface`.
  final class ServingIface: Interface, LocalClientServingInterface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var clientCount: Int = 1
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var sent: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  /// Interfaces hold their transport weakly, so the test keeps each one alive.
  private var instances: [Transport] = []

  private func makeInstance(transportEnabled: Bool) -> (Transport, ServingIface, MeshIface) {
    let t = Transport()
    instances.append(t)
    t.transportEnabled = transportEnabled
    let serving = ServingIface(name: "LocalInterface[50001]")
    let mesh = MeshIface(name: "mesh")
    t.register(interface: serving)
    t.register(interface: mesh)
    return (t, serving, mesh)
  }

  private func destination(_ aspect: String) throws -> Destination {
    try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "hops", aspects: [aspect])
  }

  private func announces(_ sent: [Packet], for hash: Data) -> [Packet] {
    sent.filter { $0.packetType == .announce && $0.destinationHash == hash }
  }

  private func pathResponses(_ sent: [Packet], for hash: Data) -> [Packet] {
    announces(sent, for: hash).filter { $0.context == .pathResponse }
  }

  private func pathRequest(for target: Data) -> Packet {
    Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Transport.pathRequestDestinationHash,
      data: target + Data(repeating: 0x5A, count: 16))
  }

  private func dataPacket(
    to dest: Data, hops: UInt8, headerType: Packet.HeaderType = .type1, transportID: Data? = nil
  ) -> Packet {
    var p = Packet(
      destinationType: .single, packetType: .data,
      destinationHash: dest, data: Data(repeating: 0x11, count: 32))
    p.hops = hops
    p.headerType = headerType
    p.transportID = transportID
    return p
  }

  // MARK: - A local client's announce

  func testALocalClientsAnnounceIsRelayedOnce() throws {
    for transportEnabled in [true, false] {
      let (t, serving, mesh) = makeInstance(transportEnabled: transportEnabled)
      let dest = try destination("once")

      serving.inboundHandler?(try Announce.make(for: dest), serving)
      let now = Date().timeIntervalSince1970
      t.processAnnounceRetries(now: now + 60)
      t.processAnnounceRetries(now: now + 120)

      XCTAssertEqual(
        announces(mesh.sent, for: dest.hash).count, 1,
        """
        transport \(transportEnabled): `retries = Transport.PATHFINDER_R` for a local client \
        (Transport.py:2356-2360), so the one jobs-loop send takes retries to \
        LOCAL_REBROADCASTS_MAX and completes the entry (:778-781)
        """)
    }
  }

  func testALocalClientsAnnounceKeepsItsWireHopCount() throws {
    for transportEnabled in [true, false] {
      let (_, serving, mesh) = makeInstance(transportEnabled: transportEnabled)
      let dest = try destination("wire")

      serving.inboundHandler?(try Announce.make(for: dest), serving)

      XCTAssertEqual(
        announces(mesh.sent, for: dest.hash).map(\.hops), [0],
        """
        transport \(transportEnabled): `announce_hops = packet.hops` (Transport.py:2333), \
        which a local client's interface leaves at the wire value (:1937-1940)
        """)
    }
  }

  func testAMeshAnnounceIsRelayedOneHopFurtherBothTimes() throws {
    let (t, _, inbound) = makeInstance(transportEnabled: true)
    let outbound = MeshIface(name: "mesh-out")
    t.register(interface: outbound)
    let dest = try destination("mesh")

    var announce = try Announce.make(for: dest)
    announce.hops = 2
    inbound.inboundHandler?(announce, inbound)
    t.processAnnounceRetries(now: Date().timeIntervalSince1970 + 60)

    XCTAssertEqual(
      announces(outbound.sent, for: dest.hash).map(\.hops), [3, 3],
      "`new_packet.hops = announce_entry[4]` (Transport.py:808), stored after :1800")
  }

  // MARK: - The copy for local clients

  func testTheLocalClientCopyOfAMeshAnnounceCountsTheArrivalHop() throws {
    let (_, serving, mesh) = makeInstance(transportEnabled: false)
    let dest = try destination("copy")

    var announce = try Announce.make(for: dest)
    announce.hops = 2
    mesh.inboundHandler?(announce, mesh)

    XCTAssertEqual(
      announces(serving.sent, for: dest.hash).map(\.hops), [3],
      "`new_announce.hops = packet.hops` (Transport.py:2428), incremented on arrival (:1800)")
  }

  func testTheCopyOfASiblingClientsAnnounceKeepsItsWireHopCount() throws {
    let (t, serving, _) = makeInstance(transportEnabled: false)
    let sibling = ServingIface(name: "LocalInterface[50002]")
    t.register(interface: sibling)
    let dest = try destination("sibling")

    serving.inboundHandler?(try Announce.make(for: dest), serving)

    let hops = announces(sibling.sent, for: dest.hash).map(\.hops)
    XCTAssertFalse(hops.isEmpty)
    XCTAssertEqual(
      Set(hops), [0],
      "a local client's arrival keeps the wire value (Transport.py:1937-1940)")
  }

  // MARK: - Path responses

  func testTheKnownPathAnswerForALocalClientsDestinationKeepsItsHopCount() throws {
    let (_, serving, mesh) = makeInstance(transportEnabled: true)
    let dest = try destination("known")
    serving.inboundHandler?(try Announce.make(for: dest), serving)
    mesh.sent.removeAll()

    mesh.inboundHandler?(pathRequest(for: dest.hash), mesh)

    XCTAssertEqual(
      pathResponses(mesh.sent, for: dest.hash).map(\.hops), [0],
      """
      `packet.hops = Transport.path_table[destination_hash][IDX_PT_HOPS]` \
      (Transport.py:3473), which is 0 for a local client's destination (:2333, :1937-1940)
      """)
  }

  func testTheDiscoveryReplayOfALocalClientsAnnounceKeepsItsWireHopCount() throws {
    let (t, serving, mesh) = makeInstance(transportEnabled: true)
    mesh.recursivePrs = true
    let dest = try destination("replay")
    mesh.inboundHandler?(pathRequest(for: dest.hash), mesh)
    XCTAssertNotNil(t.discoveryPathRequest(for: dest.hash), "fixture: the request must wait")
    mesh.sent.removeAll()

    serving.inboundHandler?(try Announce.make(for: dest), serving)

    XCTAssertEqual(
      pathResponses(mesh.sent, for: dest.hash).map(\.hops), [0],
      "`new_announce.hops = packet.hops` (Transport.py:2454), the wire value (:1937-1940)")
  }

  // MARK: - Data, links and proofs

  func testRelayHopsTakesBackTheArrivalHopOnLocalInterfaces() {
    let t = Transport()
    let packet = dataPacket(to: Data(repeating: 0x01, count: 16), hops: 2)
    XCTAssertEqual(
      t.relayHops(packet, from: ServingIface(name: "serving"), staysLocal: false), 2,
      "`is_local_client_interface` takes the hop back (Transport.py:1937-1938)")
    XCTAssertEqual(
      t.relayHops(packet, from: LocalInterface(name: "to-instance"), staysLocal: false), 2,
      "`interface_to_shared_instance` takes the hop back (Transport.py:1940)")
    XCTAssertEqual(
      t.relayHops(packet, from: MeshIface(name: "mesh"), staysLocal: false), 3,
      "any other interface keeps the arrival hop (Transport.py:1800)")
  }

  func testDataFromALocalClientKeepsItsWireHopCount() throws {
    let (t, serving, mesh) = makeInstance(transportEnabled: false)
    let dest = try destination("outbound")
    t.injectPath(
      dest.hash, nextHop: Data(repeating: 0xBB, count: 16),
      receivedOn: mesh, hops: 2, announcePacketHash: nil)

    serving.inboundHandler?(dataPacket(to: dest.hash, hops: 0), serving)

    XCTAssertEqual(
      mesh.sent.filter { $0.destinationHash == dest.hash }.map(\.hops), [0],
      "`new_raw += struct.pack(\"!B\", packet.hops)` (Transport.py:2029)")
  }

  func testDataFromTheMeshToALocalClientCountsTheArrivalHop() throws {
    let (t, serving, mesh) = makeInstance(transportEnabled: false)
    let dest = try destination("inbound")
    serving.inboundHandler?(try Announce.make(for: dest), serving)
    serving.sent.removeAll()

    mesh.inboundHandler?(
      dataPacket(to: dest.hash, hops: 1, headerType: .type2, transportID: t.transportInstanceID),
      mesh)

    XCTAssertEqual(
      serving.sent.filter { $0.destinationHash == dest.hash }.map(\.hops), [2],
      "incremented on arrival (Transport.py:1800), relayed at :2054")
  }

  // MARK: - local_hops_delta

  func testARelayedLocalClientAnnounceTakesTheHopsDelta() throws {
    let (t, serving, mesh) = makeInstance(transportEnabled: false)
    t.localHopsDelta = 5
    let sibling = ServingIface(name: "LocalInterface[50002]")
    t.register(interface: sibling)
    let dest = try destination("delta")

    serving.inboundHandler?(try Announce.make(for: dest), serving)

    XCTAssertEqual(
      announces(mesh.sent, for: dest.hash).map(\.hops), [5],
      "`should_apply_delta` holds for hops 0 on a mesh interface (Transport.py:1594-1611)")
    XCTAssertEqual(
      Set(announces(sibling.sent, for: dest.hash).map(\.hops)), [0],
      "`not interface in Transport.local_client_interfaces` (Transport.py:1611)")
  }

  func testTheKnownPathAnswerForALocalClientsDestinationTakesTheHopsDelta() throws {
    let (t, serving, mesh) = makeInstance(transportEnabled: true)
    t.localHopsDelta = 5
    let dest = try destination("known-delta")
    serving.inboundHandler?(try Announce.make(for: dest), serving)
    mesh.sent.removeAll()

    mesh.inboundHandler?(pathRequest(for: dest.hash), mesh)

    XCTAssertEqual(
      pathResponses(mesh.sent, for: dest.hash).map(\.hops), [5],
      "the answer leaves through `Transport.outbound` (Transport.py:808-813, :1594-1597)")
  }

  func testTheDiscoveryReplayOfALocalClientsAnnounceTakesTheHopsDelta() throws {
    let (t, serving, mesh) = makeInstance(transportEnabled: true)
    t.localHopsDelta = 5
    mesh.recursivePrs = true
    let dest = try destination("replay-delta")
    mesh.inboundHandler?(pathRequest(for: dest.hash), mesh)
    mesh.sent.removeAll()

    serving.inboundHandler?(try Announce.make(for: dest), serving)

    XCTAssertEqual(
      pathResponses(mesh.sent, for: dest.hash).map(\.hops), [5],
      "`new_announce.send()` goes through `Transport.outbound` (Transport.py:2455, :1594-1597)")
  }

  func testDataFromALocalClientToAMeshNeighbourTakesTheHopsDelta() throws {
    let (t, serving, mesh) = makeInstance(transportEnabled: false)
    t.localHopsDelta = 5
    let dest = try destination("neighbour")
    t.injectPath(dest.hash, nextHop: dest.hash, receivedOn: mesh, hops: 0, announcePacketHash: nil)

    serving.inboundHandler?(dataPacket(to: dest.hash, hops: 0), serving)

    XCTAssertEqual(
      mesh.sent.filter { $0.destinationHash == dest.hash }.map(\.hops), [5],
      """
      `for_local_client` needs path hops 0 (Transport.py:1968); a mesh neighbour is 1 hop away, \
      so `from_local_client and not to_local_client` mangles (:2111)
      """)
  }
}
