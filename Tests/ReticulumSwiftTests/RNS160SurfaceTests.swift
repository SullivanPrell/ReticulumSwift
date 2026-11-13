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

/// RNS 1.6.0's utility and RPC surface: `RNS.prettycost`, the path table's stamp and usage
/// columns, the transport's packet counters and path-pool counts, and the radio parameters
/// an RNode publishes (`RNS/__init__.py:183-186`; `Reticulum.py:1652-1661`, `1820-1850`,
/// `1881-1888`).
final class RNS160SurfaceTests: XCTestCase {

  final class Tap: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var sent: [Packet] = []
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(try Packet.unpack(packet.pack())) }
  }

  private var retained: [AnyObject] = []

  // MARK: - prettycost

  /// Vectors from Python 1.6.0's `RNS.prettycost`, which prints `quantize_cost(value)` to
  /// three places and `"n"` for None.
  func testPrettycostMatchesPython() {
    let vectors: [(Double?, String)] = [
      (nil, "n"), (21, "21.000"), (12.5, "12.500"), (23.4567, "23.457"), (9.1, "9.102"),
      (0.0625, "0.062"), (15.8, "15.801"),
    ]
    for (value, expected) in vectors {
      XCTAssertEqual(RNSUtilities.prettycost(value), expected, "\(String(describing: value))")
    }
  }

  // MARK: - Path table

  /// A receiver holding the path an unstamped `surface.path` announce installed.
  private func learnedPath() throws -> (Transport, Data) {
    let b = Transport()
    let tap = Tap(name: "tap")
    b.register(interface: tap)
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "surface", aspects: ["path"])
    b.register(destination: destination)
    _ = try b.announce(destination: destination)
    let packet = try XCTUnwrap(tap.sent.last { $0.packetType == .announce })

    let a = Transport()
    let inbound = Tap(name: "in")
    a.register(interface: inbound)
    retained += [b, tap, inbound]
    a.handleIncoming(packet: packet, from: inbound)
    XCTAssertTrue(a.hasPath(to: destination.hash))
    return (a, destination.hash)
  }

  private func rpcPathTable(_ t: Transport) throws -> [(MsgPack.Value, MsgPack.Value)] {
    let server = RPCServer(port: 47429, authkey: Data(repeating: 0, count: 32))
    server.transport = t
    let reply = try MsgPack.decode(
      server.respond(
        to: MsgPack.encode(
          .map([(.string("get"), .string("path_table")), (.string("max_hops"), .nil)]))))
    guard case .array(let rows) = reply, case .map(let pairs)? = rows.first else {
      XCTFail("no path_table row in \(reply)")
      return []
    }
    return pairs
  }

  /// `"value"`, `"used"` and `"lr_cost"` sit between `"expires"` and `"interface"`.
  ///
  /// A never-used path reports 0, and an unstamped announce a value of 0 with no link
  /// cost (`Reticulum.py:1881-1888`, `Identity.py:109-110`).
  func testTheRPCPathTableCarriesValueUsedAndLinkCost() throws {
    let (a, hash) = try learnedPath()

    let pairs = try rpcPathTable(a)

    XCTAssertEqual(
      pairs.compactMap { $0.0.asString },
      ["hash", "timestamp", "via", "hops", "expires", "value", "used", "lr_cost", "interface"])
    let row = Dictionary(
      uniqueKeysWithValues: pairs.compactMap { k, v in k.asString.map { ($0, v) } })
    XCTAssertEqual(row["hash"], .bytes(hash))
    XCTAssertEqual(row["value"]?.asDouble, 0)
    XCTAssertEqual(row["used"]?.asInt, 0)
    XCTAssertEqual(row["lr_cost"], .nil)
  }

  /// A used path reports its use time as a float (`path_table[dst_hash][7]`).
  func testAUsedPathReportsItsUseTime() throws {
    let (a, hash) = try learnedPath()
    var entry = try XCTUnwrap(a.paths[hash])
    let used = Date().addingTimeInterval(-60)
    entry.used = used
    a.restore(path: entry, forDestination: hash)

    let row = Dictionary(
      uniqueKeysWithValues: try rpcPathTable(a).compactMap { k, v in k.asString.map { ($0, v) } })

    XCTAssertEqual(row["used"], .double(used.timeIntervalSince1970))
  }

  // MARK: - Stats

  /// The announce and path-request counters move with each notification, and the pool
  /// counts split the path table into used and unused (`Transport.py:1827-1828`, `2054`,
  /// `2132`, `3565-3569`; `Reticulum.py:1823-1828`, `1845-1850`).
  func testTheCountersAndPoolCountsCarryLiveValues() throws {
    let (a, _) = try learnedPath()
    let other = Tap(name: "counted")
    a.register(interface: other)
    a.notifyOutgoingAnnounce(on: other)
    a.notifyIncomingPathRequest(on: other)
    a.notifyIncomingPathRequest(on: other)
    a.notifyOutgoingPathRequest(on: other)

    let stats = try XCTUnwrap(InterfaceStatsPayload.build(a).asDictionary)

    XCTAssertEqual(stats["rxpkts"]?.asInt, 1)
    XCTAssertEqual(stats["arxpkts"]?.asInt, 1, "the learned announce")
    XCTAssertEqual(stats["atxpkts"]?.asInt, 1)
    XCTAssertEqual(stats["prxpkts"]?.asInt, 2)
    XCTAssertEqual(stats["ptxpkts"]?.asInt, 1)
    XCTAssertEqual(stats["tlinks"]?.asInt, 0)
    XCTAssertEqual(stats["alinks"]?.asInt, 0)
    XCTAssertEqual(stats["plinks"]?.asInt, 0)
    XCTAssertEqual(stats["tpcount"]?.asInt, 1)
    XCTAssertEqual(stats["unupcount"]?.asInt, 1)
    XCTAssertEqual(stats["actpcount"]?.asInt, 0)
  }

  // MARK: - Radio parameters

  private func orderedRow(_ iface: any Interface) throws -> [(String, MsgPack.Value)] {
    let t = Transport()
    t.register(interface: iface)
    defer { t.deregister(interface: iface) }
    let interfaces = try XCTUnwrap(
      InterfaceStatsPayload.build(t).asDictionary?["interfaces"]?.asArray)
    guard case .map(let pairs)? = interfaces.first else {
      XCTFail("no interface row")
      return []
    }
    return pairs.compactMap { k, v in k.asString.map { ($0, v) } }
  }

  /// An RNode publishes its radio parameters ahead of its airtime, null until the radio
  /// reports them (`Reticulum.py:1652-1661`, `RNodeInterface.py:250-261`).
  func testAnRNodePublishesItsRadioParametersBeforeAirtime() throws {
    let rnode = RNodeInterface(name: "rnode-phy", transport: MockRNodeTransport())
    rnode.rStatRssi = -90
    rnode.rStatSnr = 7.25
    rnode.rFrequency = 867_200_000
    rnode.rSf = 8

    let pairs = try orderedRow(rnode)
    let keys = pairs.map(\.0)
    let start = try XCTUnwrap(keys.firstIndex(of: "rssi"))
    XCTAssertEqual(
      Array(keys[start...].prefix(9)),
      [
        "rssi", "snr", "signal_quality", "frequency", "bandwidth", "txpower", "sf", "cr",
        "airtime_short",
      ])
    let row = Dictionary(uniqueKeysWithValues: pairs)
    XCTAssertEqual(row["rssi"]?.asInt, -90)
    XCTAssertEqual(row["snr"]?.asDouble, 7.25)
    XCTAssertEqual(row["signal_quality"], .nil)
    XCTAssertEqual(row["frequency"]?.asInt, 867_200_000)
    XCTAssertEqual(row["bandwidth"], .nil)
    XCTAssertEqual(row["sf"]?.asInt, 8)
  }

  /// A sub-interface has no `r_stat_q` until its first quality report, and the multi-radio
  /// parent keeps only its never-updated statistics (`RNodeMultiInterface.py:270-272`, `734`,
  /// `985-995`).
  func testAMultiRadioPublishesPerRadioParametersAndItsParentOnlyStatistics() throws {
    let sub = RNodeSubInterface(
      name: "sub-phy", index: 0, interfaceType: "LoRa",
      frequency: 867_200_000, bandwidth: 125_000, txPower: 0, sf: 8, cr: 5)
    sub.rFrequency = 867_200_000

    var keys = try orderedRow(sub).map(\.0)
    XCTAssertEqual(
      keys.filter { ["rssi", "snr", "signal_quality", "frequency", "cr"].contains($0) },
      ["rssi", "snr", "frequency", "cr"])
    sub.rStatQ = 42.5
    keys = try orderedRow(sub).map(\.0)
    XCTAssertTrue(keys.contains("signal_quality"))

    let multi = try RNodeMultiInterface(
      name: "multi-phy", transport: MockRNodeTransport(), subInterfaces: [sub])
    let parent = Dictionary(uniqueKeysWithValues: try orderedRow(multi))
    XCTAssertEqual(parent["rssi"], .nil)
    XCTAssertEqual(parent["snr"], .nil)
    XCTAssertEqual(parent["signal_quality"], .nil)
    XCTAssertNil(parent["frequency"])
  }
}
