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

/// Routing branches that compare a path's hop count, as Python RNS 1.5.5 counts it.
///
/// Python branches on `IDX_PT_HOPS`: the wire count plus the hop `inbound` adds
/// (`Transport.py:1800`), less the hop it takes back on a local client's interface or the
/// interface to a shared instance (`:1937-1940`). `PathEntry.hops` stores the wire count, so a
/// mesh neighbour is 0 on the wire and 1 to Python, while a local client's destination is 0 to
/// both. These cases put a path behind a local client at a wire count where the two disagree.
///
/// - `outbound` inserts a transport header when `IDX_PT_HOPS > 1`, or `== 1` behind a shared
///   instance (`:1396`, `:1416`).
/// - A relayed packet's header follows `remaining_hops` (`:2024-2054`), for data and link
///   requests alike.
/// - `for_local_client` is `IDX_PT_HOPS == 0` (`:1968`).
/// - The announce ladder compares `packet.hops` after `inbound` with `IDX_PT_HOPS` (`:2236`).
final class PathHopRoutingTests: XCTestCase {

  // MARK: - Fixtures

  final class MeshIface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
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

  /// Stands in for `LocalInterface`, a client's connection to its shared instance.
  final class SharedInstanceIface: SharedInstanceClientInterface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var sent: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  private let nextHop = Data(repeating: 0xAB, count: Constants.truncatedHashLength)
  private let baseTime: TimeInterval = 1_700_000_000

  /// Transports hold interfaces weakly.
  private var retained: [AnyObject] = []

  override func tearDown() {
    retained = []
    super.tearDown()
  }

  private func makeTransport(transportEnabled: Bool = false) -> (
    Transport, MeshIface, ServingIface
  ) {
    let t = Transport()
    t.transportEnabled = transportEnabled
    let mesh = MeshIface(name: "mesh")
    let serving = ServingIface(name: "LocalInterface[50001]")
    t.register(interface: mesh)
    t.register(interface: serving)
    retained += [t, mesh, serving]
    return (t, mesh, serving)
  }

  private func destination(_ aspect: String) throws -> Destination {
    try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "hoprouting",
      aspects: [aspect])
  }

  private func dataPacket(to destinationHash: Data, addressedTo transportID: Data? = nil)
    -> Packet
  {
    Packet(
      headerType: transportID == nil ? .type1 : .type2,
      transportType: transportID == nil ? .broadcast : .transport,
      destinationType: .single, packetType: .data, transportID: transportID,
      destinationHash: destinationHash, data: Data(repeating: 0x11, count: 32))
  }

  private func linkRequest(to destinationHash: Data, addressedTo transportID: Data) -> Packet {
    Packet(
      headerType: .type2, transportType: .transport,
      destinationType: .single, packetType: .linkRequest, transportID: transportID,
      destinationHash: destinationHash, data: Data(repeating: 0x22, count: Constants.keySize))
  }

  private func sent(_ iface: MeshIface, to destinationHash: Data) -> [Packet] {
    iface.sent.filter { $0.destinationHash == destinationHash && $0.packetType != .announce }
  }

  private func sent(_ iface: ServingIface, to destinationHash: Data) -> [Packet] {
    iface.sent.filter { $0.destinationHash == destinationHash && $0.packetType != .announce }
  }

  private func makeClient() -> (Transport, SharedInstanceIface) {
    let t = Transport()
    t.isConnectedToSharedInstance = true
    let toShared = SharedInstanceIface(name: "LocalInterface")
    t.register(interface: toShared)
    retained += [t, toShared]
    return (t, toShared)
  }

  // MARK: - outbound: Transport.py:1396-1436

  /// A shared instance sends to a path Python counts as 1 hop directly, whatever the
  /// interface; only a client behind a shared instance inserts a header at 1.
  func testOutboundSendsDirectToAOneHopPathBehindALocalClient() throws {
    let (t, _, serving) = makeTransport()
    let dest = Data(repeating: 0x01, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: serving, hops: 1, announcePacketHash: nil)

    try t.send(dataPacket(to: dest), generateReceipt: false)

    let out = try XCTUnwrap(sent(serving, to: dest).first)
    XCTAssertEqual(
      out.headerType, .type1,
      """
      wire 1 on a local client's interface is IDX_PT_HOPS 1, and a node not connected to a \
      shared instance inserts a transport header only above 1 (Transport.py:1396, :1416)
      """)
    XCTAssertNil(out.transportID)
  }

  func testOutboundInsertsAHeaderAboveOneHopBehindALocalClient() throws {
    let (t, _, serving) = makeTransport()
    let dest = Data(repeating: 0x02, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: serving, hops: 2, announcePacketHash: nil)

    try t.send(dataPacket(to: dest), generateReceipt: false)

    let out = try XCTUnwrap(sent(serving, to: dest).first)
    XCTAssertEqual(out.headerType, .type2, "IDX_PT_HOPS 2 > 1 (Transport.py:1396)")
    XCTAssertEqual(out.transportID, nextHop)
  }

  /// A sibling client's destination is 0 hops from a client and goes out unchanged.
  func testAClientSendsDirectToASiblingClient() throws {
    let (t, toShared) = makeClient()
    let dest = Data(repeating: 0x11, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: toShared, hops: 0, announcePacketHash: nil)

    try t.send(dataPacket(to: dest), generateReceipt: false)

    let out = try XCTUnwrap(toShared.sent.first { $0.destinationHash == dest })
    XCTAssertEqual(out.headerType, .type1, "IDX_PT_HOPS 0 (Transport.py:1937-1940, :1432-1437)")
  }

  func testAClientInsertsAHeaderTowardOneHop() throws {
    let (t, toShared) = makeClient()
    let dest = Data(repeating: 0x12, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: toShared, hops: 1, announcePacketHash: nil)

    try t.send(dataPacket(to: dest), generateReceipt: false)

    let out = try XCTUnwrap(toShared.sent.first { $0.destinationHash == dest })
    XCTAssertEqual(
      out.headerType, .type2,
      "IDX_PT_HOPS 1 behind a shared instance takes a header (Transport.py:1416)")
    XCTAssertEqual(out.transportID, nextHop)
  }

  func testOutboundSendsDirectToAMeshNeighbour() throws {
    let (t, mesh, _) = makeTransport()
    let dest = Data(repeating: 0x03, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: mesh, hops: 0, announcePacketHash: nil)

    try t.send(dataPacket(to: dest), generateReceipt: false)

    let out = try XCTUnwrap(sent(mesh, to: dest).first)
    XCTAssertEqual(out.headerType, .type1, "a mesh neighbour is IDX_PT_HOPS 1")
  }

  func testOutboundInsertsAHeaderTowardTwoMeshHops() throws {
    let (t, mesh, _) = makeTransport()
    let dest = Data(repeating: 0x04, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: mesh, hops: 1, announcePacketHash: nil)

    try t.send(dataPacket(to: dest), generateReceipt: false)

    let out = try XCTUnwrap(sent(mesh, to: dest).first)
    XCTAssertEqual(out.headerType, .type2, "wire 1 on the mesh is IDX_PT_HOPS 2")
    XCTAssertEqual(out.transportID, nextHop)
  }

  // MARK: - Relayed data: Transport.py:2024-2054

  /// `remaining_hops == 0` leaves the packet as it arrived when hop obfuscation is off.
  func testDataForALocalClientKeepsItsTransportHeader() throws {
    let (t, mesh, serving) = makeTransport()
    let dest = Data(repeating: 0x05, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: serving, hops: 0, announcePacketHash: nil)

    mesh.inboundHandler?(dataPacket(to: dest, addressedTo: t.transportInstanceID), mesh)

    let out = try XCTUnwrap(sent(serving, to: dest).first)
    XCTAssertEqual(
      out.headerType, .type2,
      """
      IDX_PT_HOPS 0 with local_hops_delta 0 rewrites only the hop byte \
      (Transport.py:2050-2054)
      """)
    XCTAssertEqual(out.transportID, t.transportInstanceID)
  }

  func testDataForALocalClientLosesItsTransportHeaderUnderHopObfuscation() throws {
    let (t, mesh, serving) = makeTransport()
    t.localHopsDelta = 5
    let dest = Data(repeating: 0x06, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: serving, hops: 0, announcePacketHash: nil)

    mesh.inboundHandler?(dataPacket(to: dest, addressedTo: t.transportInstanceID), mesh)

    let out = try XCTUnwrap(sent(serving, to: dest).first)
    XCTAssertEqual(out.headerType, .type1, "to_local_client with a delta strips (:2039-2044)")
    XCTAssertNil(out.transportID)
  }

  /// `remaining_hops == 1` strips the header, on any interface.
  func testDataOneHopBehindALocalClientLosesItsTransportHeader() throws {
    let (t, mesh, serving) = makeTransport(transportEnabled: true)
    let dest = Data(repeating: 0x07, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: serving, hops: 1, announcePacketHash: nil)

    mesh.inboundHandler?(dataPacket(to: dest, addressedTo: t.transportInstanceID), mesh)

    let out = try XCTUnwrap(sent(serving, to: dest).first)
    XCTAssertEqual(
      out.headerType, .type1,
      "wire 1 on a local client's interface is remaining_hops 1 (Transport.py:2032-2036)")
    XCTAssertNil(out.transportID)
  }

  func testDataForAMeshNeighbourLosesItsTransportHeader() throws {
    let (t, meshIn, _) = makeTransport(transportEnabled: true)
    let meshOut = MeshIface(name: "mesh-out")
    t.register(interface: meshOut)
    retained.append(meshOut)
    let dest = Data(repeating: 0x08, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: meshOut, hops: 0, announcePacketHash: nil)

    meshIn.inboundHandler?(dataPacket(to: dest, addressedTo: t.transportInstanceID), meshIn)

    let out = try XCTUnwrap(sent(meshOut, to: dest).first)
    XCTAssertEqual(out.headerType, .type1, "a mesh neighbour is remaining_hops 1")
  }

  func testDataTowardTwoMeshHopsIsReaddressed() throws {
    let (t, meshIn, _) = makeTransport(transportEnabled: true)
    let meshOut = MeshIface(name: "mesh-out")
    t.register(interface: meshOut)
    retained.append(meshOut)
    let dest = Data(repeating: 0x09, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: meshOut, hops: 1, announcePacketHash: nil)

    meshIn.inboundHandler?(dataPacket(to: dest, addressedTo: t.transportInstanceID), meshIn)

    let out = try XCTUnwrap(sent(meshOut, to: dest).first)
    XCTAssertEqual(out.headerType, .type2, "remaining_hops 2 > 1 (Transport.py:2026-2030)")
    XCTAssertEqual(out.transportID, nextHop)
  }

  // MARK: - Relayed link requests: the same branches

  func testLinkRequestForALocalClientKeepsItsTransportHeader() throws {
    let (t, mesh, serving) = makeTransport()
    let dest = Data(repeating: 0x0A, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: serving, hops: 0, announcePacketHash: nil)

    mesh.inboundHandler?(linkRequest(to: dest, addressedTo: t.transportInstanceID), mesh)

    let out = try XCTUnwrap(sent(serving, to: dest).first)
    XCTAssertEqual(
      out.headerType, .type2,
      "a link request takes the data branches: IDX_PT_HOPS 0 keeps the header (:2050-2054)")
    XCTAssertEqual(out.transportID, t.transportInstanceID)
  }

  func testLinkRequestForALocalClientLosesItsTransportHeaderUnderHopObfuscation() throws {
    let (t, mesh, serving) = makeTransport()
    t.localHopsDelta = 5
    let dest = Data(repeating: 0x0B, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: serving, hops: 0, announcePacketHash: nil)

    mesh.inboundHandler?(linkRequest(to: dest, addressedTo: t.transportInstanceID), mesh)

    let out = try XCTUnwrap(sent(serving, to: dest).first)
    XCTAssertEqual(out.headerType, .type1, "to_local_client with a delta strips (:2039-2044)")
  }

  func testLinkRequestOneHopBehindALocalClientLosesItsTransportHeader() throws {
    let (t, mesh, serving) = makeTransport(transportEnabled: true)
    let dest = Data(repeating: 0x0C, count: 16)
    t.injectPath(dest, nextHop: nextHop, receivedOn: serving, hops: 1, announcePacketHash: nil)

    mesh.inboundHandler?(linkRequest(to: dest, addressedTo: t.transportInstanceID), mesh)

    let out = try XCTUnwrap(sent(serving, to: dest).first)
    XCTAssertEqual(
      out.headerType, .type1,
      "wire 1 on a local client's interface is remaining_hops 1 (Transport.py:2032-2036)")
    XCTAssertNil(out.transportID)
  }

  // MARK: - for_local_client: Transport.py:1968

  /// The interface to a shared instance takes back the arrival hop too, so a sibling client's
  /// destination is 0 hops away from a client.
  func testASiblingClientsDestinationIsForALocalClient() throws {
    let (t, toShared) = makeClient()
    let sibling = Transport.PathEntry(
      destinationHash: Data(repeating: 0x0D, count: 16), nextHopInterface: toShared, hops: 0,
      lastHeard: Date(), identityHash: Data(count: 16))
    let behindShared = Transport.PathEntry(
      destinationHash: Data(repeating: 0x0E, count: 16), nextHopInterface: toShared, hops: 1,
      lastHeard: Date(), identityHash: Data(count: 16))

    XCTAssertTrue(t.forLocalClient(sibling), "IDX_PT_HOPS 0 (Transport.py:1937-1940, :1968)")
    XCTAssertFalse(t.forLocalClient(behindShared))
    XCTAssertFalse(t.forLocalClient(nil))
  }

  func testAMeshNeighbourIsNotForALocalClient() throws {
    let (t, mesh, serving) = makeTransport()
    let neighbour = Transport.PathEntry(
      destinationHash: Data(repeating: 0x0F, count: 16), nextHopInterface: mesh, hops: 0,
      lastHeard: Date(), identityHash: Data(count: 16))
    let client = Transport.PathEntry(
      destinationHash: Data(repeating: 0x10, count: 16), nextHopInterface: serving, hops: 0,
      lastHeard: Date(), identityHash: Data(count: 16))

    XCTAssertFalse(t.forLocalClient(neighbour), "a mesh neighbour is IDX_PT_HOPS 1")
    XCTAssertTrue(t.forLocalClient(client))
  }

  // MARK: - Announce path replacement: Transport.py:2236-2296

  /// Marks the stored path expired, keeping everything else the announce left there.
  private func expirePath(_ t: Transport, _ destinationHash: Data) throws {
    var path = try XCTUnwrap(t.paths[destinationHash])
    path.expires = Date().addingTimeInterval(-1)
    t.restore(path: path, forDestination: destinationHash)
  }

  /// A mesh announce at wire 0 is 1 hop, more than a local client's 0, so it takes the
  /// more-hops branch, where an expired path yields to any unheard announce (`:2267-2275`).
  func testAnExpiredLocalClientPathYieldsToAnOlderMeshAnnounce() throws {
    let (t, mesh, serving) = makeTransport()
    let dest = try destination("expired-local")
    serving.inboundHandler?(try Announce.make(for: dest, timestamp: baseTime), serving)
    try expirePath(t, dest.hash)

    mesh.inboundHandler?(try Announce.make(for: dest, timestamp: baseTime - 10), mesh)

    XCTAssertTrue(
      t.paths[dest.hash]?.nextHopInterface === mesh,
      """
      1 hop > IDX_PT_HOPS 0: an expired path takes an unheard announce whatever its emission \
      (Transport.py:2267-2275)
      """)
  }

  /// A local client's announce at wire 1 is 1 hop, equal to a mesh neighbour's, so it takes
  /// the fewer-or-equal branch, which wants a newer emission (`:2236-2239`).
  func testAnExpiredMeshPathKeepsAgainstAnOlderLocalAnnounceAtEqualHops() throws {
    let (t, mesh, serving) = makeTransport()
    let dest = try destination("expired-mesh")
    mesh.inboundHandler?(try Announce.make(for: dest, timestamp: baseTime), mesh)
    try expirePath(t, dest.hash)

    var older = try Announce.make(for: dest, timestamp: baseTime - 10)
    older.hops = 1
    serving.inboundHandler?(older, serving)

    XCTAssertTrue(
      t.paths[dest.hash]?.nextHopInterface === mesh,
      "1 hop <= IDX_PT_HOPS 1 needs a newer emission (Transport.py:2236-2239)")
  }

  /// The same announce arriving at more hops can revive an unresponsive path (`:2292-2295`).
  func testTheSameAnnounceFromTheMeshRevivesAnUnresponsiveLocalClientPath() throws {
    let (t, mesh, serving) = makeTransport()
    let dest = try destination("unresponsive-local")
    let announce = try Announce.make(for: dest, timestamp: baseTime)
    serving.inboundHandler?(try Packet.unpack(announce.pack()), serving)
    XCTAssertTrue(t.markPathUnresponsive(for: dest.hash))

    mesh.inboundHandler?(try Packet.unpack(announce.pack()), mesh)

    XCTAssertTrue(
      t.paths[dest.hash]?.nextHopInterface === mesh,
      """
      1 hop > IDX_PT_HOPS 0 with an equal emission revives an unresponsive path \
      (Transport.py:2292-2295)
      """)
  }

  /// Gravity applies only at fewer-or-equal hops (`:2240-2251`).
  func testTheSameAnnounceFromAHigherGravityMeshKeepsALocalClientPath() throws {
    let (t, mesh, serving) = makeTransport()
    mesh.gravity = 10
    let dest = try destination("gravity-local")
    let announce = try Announce.make(for: dest, timestamp: baseTime)
    serving.inboundHandler?(try Packet.unpack(announce.pack()), serving)

    mesh.inboundHandler?(try Packet.unpack(announce.pack()), mesh)

    XCTAssertTrue(
      t.paths[dest.hash]?.nextHopInterface === serving,
      "1 hop > IDX_PT_HOPS 0, so gravity never applies (Transport.py:2236, :2252-2296)")
  }

  // MARK: - The structural guard

  /// No routing branch in `Transport` compares the stored wire count.
  ///
  /// Every comparison of `.hops` in `Sources/ReticulumSwift/Transport/` is on a packet, an
  /// announce-table entry or two queued announces; a path's count is read through
  /// `pythonHops(of:)`, the one place that knows the interface takes part.
  func testNoTransportBranchComparesAPathsWireHops() throws {
    let transportDir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Sources/ReticulumSwift/Transport")
    // Separate patterns, so both sides of `a.hops <= b.hops` are seen.
    let comparisons = try [
      #"([\w$.\]?]+)\.hops\b\s*(?:==|!=|<=|>=|<|>)"#,
      #"(?:==|!=|<=|>=|<|>)\s*([\w$.\]?]+)\.hops\b"#,
    ].map { try NSRegularExpression(pattern: $0) }
    let pathSubscript = try NSRegularExpression(pattern: #"paths\[[^\]]*\]\??\.hops\b"#)
    let packetReceivers: Set<String> = ["packet", "held.packet", "$0", "$1", "lhs", "rhs"]

    var offences: [String] = []
    let files = try FileManager.default.contentsOfDirectory(
      at: transportDir, includingPropertiesForKeys: nil)
    for url in files where url.pathExtension == "swift" {
      let src = try String(contentsOf: url, encoding: .utf8)
      for (index, line) in src.components(separatedBy: .newlines).enumerated() {
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//") else { continue }
        // `IDX_AT_HOPS`, the announce table's own count (`Transport.py:2186`, `:2195`).
        if code.contains("incomingHops - 1 == entry.hops") { continue }
        let range = NSRange(code.startIndex..., in: code)
        let receivers = comparisons.flatMap { $0.matches(in: code, range: range) }.compactMap {
          Range($0.range(at: 1), in: code).map {
            String(code[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "?"))
          }
        }
        let flagged =
          receivers.contains { !packetReceivers.contains($0) }
          || pathSubscript.firstMatch(in: code, range: range) != nil
        if flagged { offences.append("  \(url.lastPathComponent):\(index + 1) — \(code)") }
      }
    }

    XCTAssertTrue(
      offences.isEmpty,
      """
      \(offences.count) site(s) compare a stored path's wire hop count:
      \(offences.joined(separator: "\n"))
      Python branches on IDX_PT_HOPS (Transport.py:1800, :1937-1940); compare \
      `pythonHops(of:)`.
      """)
  }
}
