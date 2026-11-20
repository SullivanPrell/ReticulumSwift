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

/// RNS 1.6.1's traffic accounting and the stats it publishes: accepted and filtered inbound
/// bytes, link traffic, `link_distribution`, and the new `interface_stats` and `path_table`
/// keys (`Transport.py:1970-1995`, `:2509-2549`, `:3786-3815`, `Reticulum.py:1825-1966`,
/// `:2046-2051`, `:2076-2093`).
final class RNS161TrafficAccountingTests: XCTestCase {

  final class Port: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var rawInboundHandler: ((Data, any Interface) -> Void)?
    var sent: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  private func plainData() throws -> Data {
    try Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Hashes.randomHash(), data: Data(repeating: 0x42, count: 20)
    ).pack()
  }

  private func row(_ name: String, in t: Transport) throws -> [(String, MsgPack.Value)] {
    let rows = try XCTUnwrap(InterfaceStatsPayload.build(t).asDictionary?["interfaces"]?.asArray)
    for case .map(let pairs) in rows {
      let fields = pairs.compactMap { k, v in k.asString.map { ($0, v) } }
      if fields.contains(where: { $0.0 == "short_name" && $0.1 == .string(name) }) {
        return fields
      }
    }
    XCTFail("no row for \(name)")
    return []
  }

  private func value(_ key: String, _ fields: [(String, MsgPack.Value)]) -> MsgPack.Value? {
    fields.first { $0.0 == key }?.1
  }

  private func assertOrdered(
    _ keys: [String], in fields: [(String, MsgPack.Value)], file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let positions = keys.map { key in fields.firstIndex { $0.0 == key } }
    XCTAssertFalse(positions.contains(nil), "missing one of \(keys)", file: file, line: line)
    let found = positions.compactMap { $0 }
    XCTAssertEqual(found, found.sorted(), "out of order: \(keys)", file: file, line: line)
  }

  // MARK: - Inbound accounting

  /// `accepted_inbound` and `filtered_inbound` (`Transport.py:1973-1995`).
  func testAcceptedAndFilteredInboundAreCountedApart() throws {
    let t = Transport.unstamped()
    let port = Port(name: "rx")
    t.register(interface: port)
    let accepted = try plainData()
    let malformed = Data([0x00, 0x01, 0x02])

    port.rawInboundHandler?(accepted, port)
    port.rawInboundHandler?(malformed, port)

    let counts = t.interfaceCounts(for: port)
    XCTAssertEqual(counts.rxBytes, accepted.count)
    XCTAssertEqual(counts.filteredRxBytes, malformed.count)
    let fields = try row("rx", in: t)
    XCTAssertEqual(value("rxb", fields), .int(Int64(accepted.count)))
    XCTAssertEqual(value("frxb", fields), .int(Int64(malformed.count)))
    XCTAssertEqual(value("ftxb", fields), .int(0))
  }

  /// `if interface.parent_interface: interface.parent_interface.rxb += raw_len`
  /// (`Transport.py:1977`, `:1983`).
  func testASpawnedInterfaceCountsOnItsParentToo() throws {
    let t = Transport.unstamped()
    let server = TCPServerInterface(name: "srv", port: 4965)
    let client = TCPServerClientInterface(
      name: "Client on srv", parentServer: server, peerHost: "10.0.0.2", peerPort: 50000)
    t.register(interface: server)
    t.register(interface: client)
    let accepted = try plainData()

    client.rawInboundHandler?(accepted, client)
    client.rawInboundHandler?(Data([0x00]), client)

    XCTAssertEqual(t.interfaceCounts(for: client).rxBytes, accepted.count)
    XCTAssertEqual(t.interfaceCounts(for: server).rxBytes, accepted.count)
    XCTAssertEqual(t.interfaceCounts(for: server).filteredRxBytes, 1)
  }

  /// Filtered bytes feed a per-interface speed and the transport totals
  /// (`Transport.py:804-856`).
  func testFilteredBytesFeedTheSpeedsAndTotals() throws {
    let t = Transport.unstamped()
    let port = Port(name: "speed")
    t.register(interface: port)
    t.sampleInterfaceSpeeds(now: 1000)
    port.rawInboundHandler?(Data(repeating: 0, count: 3), port)

    t.sampleInterfaceSpeeds(now: 1001)

    XCTAssertEqual(t.filteredRxBytes, 3)
    XCTAssertEqual(t.filteredSpeedRx, 24, accuracy: 0.001)
    XCTAssertEqual(value("frxs", try row("speed", in: t)), .double(24))
  }

  // MARK: - Published keys

  func testInterfaceStatsCarryTheNewKeysInPythonsOrder() throws {
    let t = Transport.unstamped()
    let port = Port(name: "keys")
    t.register(interface: port)
    let fields = try row("keys", in: t)

    assertOrdered(["txs", "frxs", "ftxs", "arxs"], in: fields)
    assertOrdered(["txb", "frxb", "ftxb", "arxb"], in: fields)
    assertOrdered(["atxc", "afrxc", "prxb"], in: fields)
    assertOrdered(
      [
        "packet_filter_hits", "tunnel_id", "remote_transport_id", "rem_impl", "rem_vers",
        "rem_is_tn", "rem_dst_cost", "rem_pr_cost",
      ], in: fields)
    XCTAssertEqual(value("tunnel_id", fields), .nil)
  }

  /// `tunnel_id or local_tunnel_id`, the remote's hash, and `rem_*` except on a shared medium
  /// (`Reticulum.py:1927-1941`).
  func testTunnelKeysReportTheRemote() throws {
    let t = Transport.unstamped()
    let port = Port(name: "tunnel")
    t.register(interface: port)
    let udp = UDPInterface(name: "udp", listenPort: 0)
    t.register(interface: udp)
    defer { udp.stop() }
    for iface in [port as any Interface, udp] {
      iface.interfaceState.tunnelSynthesis.localTunnelID = Data(repeating: 0x0A, count: 32)
      iface.interfaceState.tunnelSynthesis.remoteTransportID = Data(repeating: 0x0B, count: 16)
      iface.interfaceState.tunnelSynthesis.remoteImpl = "RNS"
      iface.interfaceState.tunnelSynthesis.remoteVers = [1, 6, 1]
      iface.interfaceState.tunnelSynthesis.remoteIsTN = true
      iface.interfaceState.tunnelSynthesis.remoteDstCost = 17.8
      iface.interfaceState.tunnelSynthesis.remotePrCost = 12
    }

    let fields = try row("tunnel", in: t)
    XCTAssertEqual(value("tunnel_id", fields), .bytes(Data(repeating: 0x0A, count: 32)))
    XCTAssertEqual(value("remote_transport_id", fields), .bytes(Data(repeating: 0x0B, count: 16)))
    XCTAssertEqual(value("rem_impl", fields), .string("RNS"))
    XCTAssertEqual(value("rem_vers", fields), .array([.int(1), .int(6), .int(1)]))
    XCTAssertEqual(value("rem_is_tn", fields), .bool(true))
    XCTAssertEqual(value("rem_dst_cost", fields), .double(17.8))
    XCTAssertEqual(value("rem_pr_cost", fields), .double(12))

    let shared = try row("udp", in: t)
    XCTAssertEqual(value("remote_transport_id", shared), .bytes(Data(repeating: 0x0B, count: 16)))
    for key in ["rem_impl", "rem_vers", "rem_is_tn", "rem_dst_cost", "rem_pr_cost"] {
      XCTAssertEqual(value(key, shared), .nil, key)
    }
  }

  func testTransportStatsCarryLinkAndFilteredTotals() throws {
    let t = Transport.unstamped()
    guard case .map(let pairs) = InterfaceStatsPayload.build(t) else { return XCTFail() }
    let fields = pairs.compactMap { k, v in k.asString.map { ($0, v) } }
    assertOrdered(
      ["txs", "lrxb", "ltxb", "lrxs", "ltxs", "frxb", "ftxb", "frxs", "ftxs", "arxb"],
      in: fields)
  }

  // MARK: - Links

  private func relay() -> (Transport, from: Port, toward: Port, linkID: Data, dest: Data) {
    let t = Transport.unstamped()
    t.transportEnabled = true
    let from = Port(name: "meshA")
    let toward = Port(name: "meshB")
    t.register(interface: from)
    t.register(interface: toward)
    let linkID = Data(repeating: 0x71, count: Constants.truncatedHashLength)
    let dest = Data(repeating: 0xD5, count: Constants.truncatedHashLength)
    var route = Transport.LinkRoute(
      linkID: linkID, initiatorSideInterface: from, responderSideInterface: toward,
      initiatorSideInterfaceName: from.name, responderSideInterfaceName: toward.name,
      destinationHash: dest, lastHeard: Date(), remainingHops: 2, takenHops: 1)
    route.validated = true
    t.restore(linkRoute: route)
    return (t, from, toward, linkID, dest)
  }

  /// `Transport.link_rxb += len(packet.raw)`, `link_txb += raw_len` and the link table's
  /// traffic counter (`Transport.py:2509-2510`, `:2545-2549`).
  func testRelayedLinkTrafficIsCounted() throws {
    let (t, from, toward, linkID, _) = relay()
    let linkData = Packet(
      destinationType: .link, packetType: .data, destinationHash: linkID,
      data: Data(repeating: 0x33, count: 48))
    let size = try linkData.pack().count

    from.inboundHandler?(linkData, from)

    XCTAssertEqual(toward.sent.count, 1)
    XCTAssertEqual(t.linkRxBytes, size)
    XCTAssertEqual(t.linkTxBytes, size)
    XCTAssertEqual(t.linkRoute(for: linkID)?.traffic, size)
  }

  /// `link_distribution` (`Transport.py:3786-3815`).
  func testLinkDistributionGroupsLinksByDestination() throws {
    let (t, from, _, linkID, dest) = relay()
    let linkData = Packet(
      destinationType: .link, packetType: .data, destinationHash: linkID,
      data: Data(repeating: 0x33, count: 48))
    from.inboundHandler?(linkData, from)

    let distribution = t.linkDistribution()

    let entry = try XCTUnwrap(distribution[dest])
    XCTAssertEqual(entry.active, 1)
    XCTAssertEqual(entry.pending, 0)
    XCTAssertEqual(entry.traffic, try linkData.pack().count)
    XCTAssertEqual(entry.fromInterfaces, [Hashes.fullHash(Data(from.displayName.utf8))])
  }

  // MARK: - Path table

  /// `interface_hash` and `state` (`Reticulum.py:2050-2051`).
  func testPathTableRowsCarryTheInterfaceHashAndState() throws {
    let t = Transport.unstamped()
    let port = Port(name: "paths")
    t.register(interface: port)
    let dest = Data(repeating: 0xD7, count: 16)
    t.injectPath(
      dest, nextHop: Data(repeating: 1, count: 16), receivedOn: port, hops: 1,
      announcePacketHash: nil)
    _ = t.markPathUnresponsive(for: dest)

    let row = try XCTUnwrap(t.getPathTable().first { $0.destinationHash == dest })
    let encoded = RNPathTableEntry(row, resolvingNamesWith: t).msgpackValue()
    guard case .map(let pairs) = encoded else { return XCTFail() }
    let keys = pairs.compactMap { $0.0.asString }
    XCTAssertEqual(Array(keys.suffix(3)), ["interface", "interface_hash", "state"])
    XCTAssertEqual(
      pairs.first { $0.0 == .string("interface_hash") }?.1,
      .bytes(Hashes.fullHash(Data(port.displayName.utf8))))
    XCTAssertEqual(
      pairs.first { $0.0 == .string("state") }?.1, .uint(UInt64(Transport.stateUnresponsive)))
  }

  // MARK: - RPC

  /// `rawByteCount` is `len(packet.raw)`, context byte included.
  func testRawByteCountIsThePackedLength() throws {
    let packet = Packet(
      destinationType: .plain, packetType: .data, destinationHash: Hashes.randomHash(),
      data: Data(repeating: 0x42, count: 20))
    XCTAssertEqual(packet.rawByteCount, try packet.packedBytes().count)
  }

  /// `if path == "known_destinations"` (`Reticulum.py:1594`, `:2076-2093`).
  func testTheKnownDestinationsVerbReturnsTheEntries() throws {
    let t = Transport.unstamped()
    let identity = Identity()
    let dest = Data(repeating: 0xD8, count: 16)
    let row = KnownDestinationsStore.Row(
      lastHeard: 1_700_000_000.5, packetHash: Data(repeating: 0x0F, count: 32),
      publicKey: identity.publicKeyBytes, appData: Data("app".utf8), used: 0, stamp: nil,
      stampValue: 0, lrCost: nil)
    t.restore(knownDestinations: [dest: row])

    let server = RPCServer(port: 37433, authkey: Data(repeating: 0, count: 32))
    server.transport = t
    let call = try MsgPack.encode(.map([(.string("get"), .string("known_destinations"))]))
    guard case .map(let pairs) = try MsgPack.decode(server.respond(to: call)) else {
      return XCTFail()
    }
    XCTAssertEqual(pairs.count, 1)
    XCTAssertEqual(pairs.first?.0, .bytes(dest))
    let fields = try XCTUnwrap(pairs.first?.1.asArray)
    XCTAssertEqual(fields.count, 8)
    XCTAssertEqual(KnownDestinationsStore.Row(entry: fields), row)
  }

  /// `if path == "link_distribution"` (`Reticulum.py:1601`).
  func testTheLinkDistributionVerbReturnsTheTable() throws {
    let (t, _, _, _, dest) = relay()
    let server = RPCServer(port: 37434, authkey: Data(repeating: 0, count: 32))
    server.transport = t
    let call = try MsgPack.encode(.map([(.string("get"), .string("link_distribution"))]))
    guard case .map(let pairs) = try MsgPack.decode(server.respond(to: call)) else {
      return XCTFail()
    }
    let entry = try XCTUnwrap(pairs.first { $0.0 == .bytes(dest) }?.1.asDictionary)
    XCTAssertEqual(entry["active"]?.asInt, 1)
    XCTAssertEqual(entry["pending"]?.asInt, 0)
    XCTAssertEqual(entry["traffic"]?.asInt, 0)
    XCTAssertEqual(entry["from_ifs"]?.asArray?.count, 1)
  }
}
