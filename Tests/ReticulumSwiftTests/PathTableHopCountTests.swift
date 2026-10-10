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

/// The hop count every path-table surface reports, as Python RNS 1.5.5 counts it.
///
/// Python adds a hop when a packet arrives (`Transport.py:1800`) and takes it back on a local
/// client's interface or the interface to a shared instance (`:1937-1940`). The path table
/// stores that value as `IDX_PT_HOPS` (`announce_hops`, `:2333`, `:2458`), and these read it:
/// `hops_to` (`:3141`), `get_path_table` and its `max_hops` filter (`Reticulum.py:1735-1740`),
/// the destination table (`Transport.py:3838`), path re-balancing (`:2634`, `:2707`) and
/// interface discovery (`Discovery.py:373`). A direct mesh neighbour is 1 hop away.
final class PathTableHopCountTests: XCTestCase {

  // MARK: - Fixtures

  final class MeshIface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  /// Stands in for `LocalServerClientInterface`.
  final class ServingIface: Interface, LocalClientServingInterface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var clientCount: Int = 1
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  /// Hands what it sends to a paired interface, so a link completes its handshake.
  final class LoopIface: Interface {
    let name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    weak var paired: LoopIface?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {
      let raw = try packet.pack()
      guard let paired else { return }
      paired.inboundHandler?(try Packet.unpack(raw), paired)
    }
  }

  /// Accepts every stamp, so a discovery announce needs no proof of work.
  final class PassthroughStamps: DiscoveryStampValidator {
    let stampSize = 32
    func stampWorkblock(material: Data, expandRounds: Int) -> Data { Data(count: 256) }
    func stampValue(workblock: Data, stamp: Data) -> Int { 99 }
    func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { true }
  }

  /// Transports hold interfaces weakly and links hold transports weakly.
  private var retained: [AnyObject] = []
  private var tmpDir: URL!

  override func setUp() {
    super.setUp()
    tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns-path-hops-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    retained = []
    try? FileManager.default.removeItem(at: tmpDir)
    super.tearDown()
  }

  private func makeTransport() -> (Transport, MeshIface, ServingIface) {
    let t = Transport()
    t.cacheDirectory = tmpDir.appendingPathComponent("cache-\(UUID().uuidString)")
    let mesh = MeshIface(name: "mesh")
    let serving = ServingIface(name: "LocalInterface[50001]")
    t.register(interface: mesh)
    t.register(interface: serving)
    retained += [t, mesh, serving]
    return (t, mesh, serving)
  }

  private func destination(_ aspect: String, identity: Identity = Identity()) throws -> Destination
  {
    try Destination(
      identity: identity, direction: .in, kind: .single, appName: "pathhops", aspects: [aspect])
  }

  /// Delivers an announce for `destination` on `iface`, carrying `hops` on the wire.
  @discardableResult
  private func announce(
    _ destination: Destination, on iface: any Interface, hops: UInt8 = 0, appData: Data? = nil
  ) throws -> Packet {
    var packet = try Announce.make(for: destination, appData: appData)
    packet.hops = hops
    iface.inboundHandler?(try Packet.unpack(packet.pack()), iface)
    return packet
  }

  private func tableHops(_ t: Transport, maxHops: UInt8? = nil) -> [Data: UInt8] {
    Dictionary(
      t.getPathTable(maxHops: maxHops).map { ($0.destinationHash, $0.hops) },
      uniquingKeysWith: { first, _ in first })
  }

  // MARK: - hops_to

  func testAMeshNeighbourIsOneHopAway() throws {
    let (t, mesh, _) = makeTransport()
    let dest = try destination("neighbour")
    try announce(dest, on: mesh)

    XCTAssertEqual(
      t.hopsTo(dest.hash), 1,
      """
      `hops_to` returns `IDX_PT_HOPS` (Transport.py:3141), which is `announce_hops`, the \
      wire count plus the hop `inbound` adds on arrival (:1800, :2333)
      """)
  }

  func testALocalClientsDestinationIsZeroHopsAway() throws {
    let (t, _, serving) = makeTransport()
    let dest = try destination("client")
    try announce(dest, on: serving)

    XCTAssertEqual(
      t.hopsTo(dest.hash), 0,
      "a local client's interface takes back the hop `inbound` adds (Transport.py:1937-1938)")
  }

  func testADestinationBehindTheSharedInstanceKeepsItsWireCount() throws {
    let t = Transport()
    let toInstance = LocalInterface(name: "to-instance")
    t.register(interface: toInstance)
    retained += [t, toInstance]
    let dest = try destination("behind")
    try announce(dest, on: toInstance, hops: 1)

    XCTAssertEqual(
      t.hopsTo(dest.hash), 1,
      "the interface to a shared instance takes back the hop `inbound` adds (Transport.py:1940)")
  }

  // MARK: - get_path_table

  func testThePathTableReportsTheCountHopsToReports() throws {
    let (t, mesh, serving) = makeTransport()
    let neighbour = try destination("table-neighbour")
    let client = try destination("table-client")
    try announce(neighbour, on: mesh)
    try announce(client, on: serving)

    let hops = tableHops(t)
    XCTAssertEqual(
      hops[neighbour.hash], 1,
      "`get_path_table` reports `path_table[dst_hash][2]` (Reticulum.py:1737-1740)")
    XCTAssertEqual(hops[client.hash], 0)
  }

  func testMaxHopsFiltersOnTheReportedCount() throws {
    let (t, mesh, serving) = makeTransport()
    let neighbour = try destination("filter-neighbour")
    let client = try destination("filter-client")
    try announce(neighbour, on: mesh)
    try announce(client, on: serving)

    XCTAssertEqual(
      Set(tableHops(t, maxHops: 0).keys), [client.hash],
      "`if max_hops == None or path_hops <= max_hops` (Reticulum.py:1738)")
    XCTAssertEqual(Set(tableHops(t, maxHops: 1).keys), [client.hash, neighbour.hash])
  }

  func testThePathTableRPCReportsTheSameCount() throws {
    let (t, mesh, _) = makeTransport()
    let dest = try destination("rpc")
    try announce(dest, on: mesh)
    let server = RPCServer(port: 0, authkey: Data(repeating: 0, count: 32))
    server.transport = t

    func call(maxHops: MsgPack.Value) throws -> [[String: MsgPack.Value]] {
      let request = MsgPack.encode(
        .map([(.string("get"), .string("path_table")), (.string("max_hops"), maxHops)]))
      let entries = try XCTUnwrap(MsgPack.decode(server.respond(to: request)).asArray)
      return entries.compactMap(\.asDictionary)
    }

    let all = try call(maxHops: .nil)
    XCTAssertEqual(
      all.first { $0["hash"]?.asData == dest.hash }?["hops"]?.asInt, 1,
      "the `path_table` RPC returns `get_path_table(max_hops=mh)` (Reticulum.py:1376)")
    XCTAssertTrue(
      try call(maxHops: .uint(0)).allSatisfy { $0["hash"]?.asData != dest.hash },
      "a 1-hop path is outside `max_hops` 0")
  }

  func testTheRemotePathHandlerReportsTheSameCount() throws {
    Reticulum.storedRemoteManagementEnabled = true
    defer { Reticulum.storedRemoteManagementEnabled = false }
    let (t, mesh, _) = makeTransport()
    t.transportIdentity = Identity()
    // Inbound runs on this thread, so the path is in the table before the handler reads it.
    t.usesInboundQueue = false
    try t.start()
    let dest = try destination("remote")
    try announce(dest, on: mesh)

    let mgmt = try XCTUnwrap(t.remoteManagementDestination)
    let pathHash = Hashes.truncatedHash(Data("/path".utf8))
    let handler = try XCTUnwrap(mgmt.requestHandlers[pathHash])
    let linkTransport = Transport()
    let linkIface = MeshIface(name: "link")
    linkTransport.register(interface: linkIface)
    retained += [linkTransport, linkIface]
    let link = try Link.initiate(destination: try destination("link"), transport: linkTransport)
    let response = try XCTUnwrap(
      handler.handler(
        pathHash, MsgPack.encode(.array([.string("table"), .bytes(dest.hash)])), Data(), link, 0))
    let entry = try XCTUnwrap(MsgPack.decode(response).asArray?.first?.asDictionary)

    XCTAssertEqual(
      entry["hops"]?.asInt, 1,
      "`/path` answers `Transport.owner.get_path_table(max_hops=max_hops)` (Transport.py:3358)")
  }

  // MARK: - rnpath

  func testRnpathPrintsTheReportedCount() throws {
    let (t, mesh, _) = makeTransport()
    let dest = try destination("rnpath")
    try announce(dest, on: mesh)

    XCTAssertEqual(
      TransportPathResolver(transport: t).hopsTo(dest.hash), 1,
      "`rnpath <hash>` prints `RNS.Transport.hops_to(destination_hash)` (rnpath.py:463)")
    let entry = try XCTUnwrap(t.getPathTable().first { $0.destinationHash == dest.hash })
    let line = RNPathFormatter.pathTableLine(RNPathTableEntry(entry, resolvingNamesWith: t))
    XCTAssertTrue(line.contains(" is 1 hop  away via "), "rnpath.py:288-290: \(line)")
  }

  // MARK: - destination_table

  func testTheDestinationTableStoresTheReportedCount() throws {
    let (t, mesh, _) = makeTransport()
    let dest = try destination("persist")
    try announce(dest, on: mesh)

    let entry = try XCTUnwrap(
      PathStore.snapshot(of: t).entries.first { $0.destinationHash == dest.hash })
    XCTAssertEqual(
      entry.hops, 1,
      "`hops = de[IDX_PT_HOPS]` is serialised as field 3 (Transport.py:3838-3846)")
  }

  func testARestoredEntryReportsItsStoredCount() throws {
    let (t, mesh, _) = makeTransport()
    let identity = Identity()
    let dest = try destination("restore", identity: identity)
    let packet = try Announce.make(for: dest)
    try t.cacheAnnounce(packet, receivingInterfaceName: mesh.name)
    t.restore(identity: identity, forDestination: dest.hash)
    let stored = PathStore.Entry(
      destinationHash: dest.hash, timestamp: Date().timeIntervalSince1970,
      receivedFrom: dest.hash, hops: 1,
      expires: Date().addingTimeInterval(3600).timeIntervalSince1970,
      randomBlobs: [], interfaceHash: mesh.hash,
      announceHash: Hashes.fullHash(try packet.hashablePart()))

    PathStore(entries: [stored]).install(into: t)

    XCTAssertEqual(
      t.hopsTo(dest.hash), 1,
      "a restored entry takes field 3 as `IDX_PT_HOPS` unchanged (Transport.py:317-327, :346)")
  }

  // MARK: - Path re-balancing

  /// Two transports on a looped pair; `b` holds a destination `a` can link to.
  private func makeLinkPair() throws -> (Transport, Transport, Destination) {
    let a = Transport()
    let b = Transport()
    let identity = Identity()
    let dest = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "pathhops", aspects: ["link"])
    b.ownerIdentity = identity
    b.register(destination: dest)
    let ai = LoopIface(name: "A")
    let bi = LoopIface(name: "B")
    ai.paired = bi
    bi.paired = ai
    a.register(interface: ai)
    b.register(interface: bi)
    retained += [a, b, ai, bi]
    return (a, b, dest)
  }

  func testALinkToAKnownNeighbourIsNotRebalanced() throws {
    let (a, _, dest) = try makeLinkPair()
    let ai = try XCTUnwrap(a.interfaces.first)
    try announce(dest, on: ai)

    let link = try Link.initiate(destination: dest, transport: a)

    XCTAssertEqual(link.status, .active)
    XCTAssertNil(
      link.rebalanced,
      """
      `expected_hops = hops_to(...)` (Link.py:281) and the proof's `packet.hops` (:1800) are \
      both 1, so the proof needs no re-balancing (Transport.py:2696-2707)
      """)
    XCTAssertEqual(link.expectedHops, 1)
  }

  func testRebalancingMovesThePathToTheProofsCount() throws {
    let (a, _, dest) = try makeLinkPair()
    let ai = try XCTUnwrap(a.interfaces.first)
    try announce(dest, on: ai, hops: 2)
    XCTAssertEqual(a.hopsTo(dest.hash), 3, "test premise: a 3-hop path")

    let link = try Link.initiate(destination: dest, transport: a)

    XCTAssertEqual(link.status, .active)
    XCTAssertNotNil(link.rebalanced)
    XCTAssertEqual(link.expectedHops, 1, "`link.expected_hops = packet.hops` (Transport.py:2705)")
    XCTAssertEqual(
      a.hopsTo(dest.hash), 1, "`path_entry[IDX_PT_HOPS] = packet.hops` (Transport.py:2707)")
  }

  // MARK: - Interface discovery

  func testADiscoveredInterfaceReportsItsPathsCount() throws {
    let (t, mesh, _) = makeTransport()
    var discovered: DiscoveredInterfaceInfo?
    t.discoverInterfaces(
      storagePath: tmpDir.appendingPathComponent("discovery").path,
      stampValidator: PassthroughStamps(), callback: { discovered = $0 })
    let identity = Identity()
    let announcer = try Destination(
      identity: identity, direction: .in, kind: .single,
      appName: "rnstransport", aspects: ["discovery", "interface"])
    let info: [(MsgPack.Value, MsgPack.Value)] = [
      (.uint(0x00), .string("BackboneInterface")),
      (.uint(0x01), .bool(true)),
      (.uint(0xFE), .bytes(Data(repeating: 0x11, count: 16))),
      (.uint(0xFF), .string("Hub")),
      (.uint(0x02), .string("10.0.0.5")),
      (.uint(0x06), .uint(4242)),
      (.uint(0x03), .nil), (.uint(0x04), .nil), (.uint(0x05), .nil),
    ]
    let appData = Data([0x00]) + MsgPack.encode(.map(info)) + Data(repeating: 0xAB, count: 32)

    try announce(announcer, on: mesh, appData: appData)

    let received = try XCTUnwrap(discovered, "the discovery announce was not accepted")
    XCTAssertEqual(
      received.hops, 1, "`\"hops\": RNS.Transport.hops_to(destination_hash)` (Discovery.py:373)")
  }
}
