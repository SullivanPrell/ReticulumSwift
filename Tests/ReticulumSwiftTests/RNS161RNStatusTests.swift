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

/// The `rnstatus` surface RNS 1.6.1 adds: `-F`, `-T`, five sort keys, the filtered announce
/// count and the Links totals line.
///
/// Expected strings come from the 1.6.1 `rnstatus.py` f-strings run against the 1.6.1
/// `RNS.prettysize`, `prettyspeed`, `prettycost` and `hexrep`.
final class RNS161RNStatusTests: XCTestCase {

  private typealias Fixtures = RNStatus152SurfaceTests

  private static let tunnelFields: [(String, MsgPack.Value)] = [
    ("tunnel_id", .bytes(Data(0..<32))),
    ("remote_transport_id", .bytes(Data(repeating: 0x11, count: 16))),
    ("rem_impl", .string("RNS")),
    ("rem_vers", .array([.int(1), .int(6), .int(1)])),
    ("rem_is_tn", .bool(true)),
    ("rem_dst_cost", .double(12.5)),
    ("rem_pr_cost", .nil),
  ]

  func testTheTwoNewFlagsParse() throws {
    let parser = RNStatusApp.makeParser()
    for (short, long) in [("-F", "--filter-stats"), ("-T", "--tunnels")] {
      XCTAssertTrue(try parser.parse([short]).flag(long), "short \(short)")
      XCTAssertTrue(try parser.parse([long]).flag(long), "long \(long)")
      XCTAssertFalse(try parser.parse([]).flag(long), "default \(long)")
    }
  }

  /// `rnstatus.py:435-447`.
  func testTheFilteredSortKeys() {
    let quiet = Fixtures.iface([
      ("name", .string("quiet")), ("frxb", .int(1)), ("ftxb", .int(0)), ("frxs", .double(1)),
      ("ftxs", .double(0)), ("afrxc", .int(1)),
    ])
    let busy = Fixtures.iface([
      ("name", .string("busy")), ("frxb", .int(9)), ("ftxb", .int(0)), ("frxs", .double(9)),
      ("ftxs", .double(0)), ("afrxc", .int(9)),
    ])
    let stats = Fixtures.top([quiet, busy])
    for key in ["frx", "frxs", "afrxc"] {
      let sort = RNStatusApp.Sort(rawValue: key)
      XCTAssertNotNil(sort, key)
      XCTAssertEqual(
        stats.sortedInterfaces(by: sort, reverse: false).map(\.name), ["busy", "quiet"])
    }
    XCTAssertNotNil(RNStatusApp.Sort(rawValue: "ftx"))
    XCTAssertNotNil(RNStatusApp.Sort(rawValue: "ftxs"))
  }

  /// `rnstatus.py:559-572`.
  func testTunnelLinesFollowTheRate() {
    let stats = Fixtures.top([Fixtures.iface(Self.tunnelFields)])
    let rendered = Fixtures.renderer { $0.tunnelStats = true }.render(stats: stats, linkCount: nil)
    XCTAssertTrue(
      rendered.contains(
        "    Rate      : 10.00 Mbps, MTU 500\n"
          + "    Tunnel ID : 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f\n"
          + "    Rem.Tr.ID : <11111111111111111111111111111111>\n"
          + "    Rem.Vers. : RNS 1.6.1, transport enabled\n"
          + "    Rem.Csts. : Dst 12.500, PR ?\n"), rendered)
    XCTAssertFalse(
      Fixtures.renderer().render(stats: stats, linkCount: nil).contains("Tunnel ID"))
  }

  /// A server with clients skips the Tunnel ID line; one without a tunnel prints `None` and
  /// nothing more.
  func testTunnelLinesForClientsAndMissingTunnels() {
    let unknown: [(String, MsgPack.Value)] = [
      ("clients", .int(3)), ("tunnel_id", .bytes(Data(0..<32))), ("remote_transport_id", .nil),
      ("rem_impl", .nil), ("rem_vers", .nil), ("rem_is_tn", .nil), ("rem_dst_cost", .nil),
      ("rem_pr_cost", .nil),
    ]
    let serving = Fixtures.renderer { $0.tunnelStats = true }
      .render(stats: Fixtures.top([Fixtures.iface(unknown)]), linkCount: nil)
    XCTAssertFalse(serving.contains("Tunnel ID"), serving)
    XCTAssertTrue(
      serving.contains(
        "    Rem.Tr.ID : Unknown\n"
          + "    Rem.Vers. : Unknown implementation, unknown version\n"
          + "    Rem.Csts. : Dst ?, PR ?\n"), serving)

    let none = Fixtures.renderer { $0.tunnelStats = true }
      .render(stats: Fixtures.top([Fixtures.iface([("tunnel_id", .nil)])]), linkCount: nil)
    XCTAssertTrue(none.contains("    Tunnel ID : None\n    Traffic"), none)
  }

  /// `rnstatus.py:761-762`.
  func testTheAnnounceTotalCarriesTheFilteredCount() {
    let stats = Fixtures.top([
      Fixtures.iface([("arxc", .int(31)), ("atxc", .int(12)), ("afrxc", .int(4))])
    ])
    let rendered = Fixtures.renderer { $0.announceStats = true }.render(
      stats: stats, linkCount: nil)
    XCTAssertTrue(rendered.contains("    Announces : 31↓ 12↑ total, 4 filtered\n"), rendered)
  }

  /// `rnstatus.py:781-787`.
  func testTheInterfaceFilteredLine() {
    let stats = Fixtures.top([
      Fixtures.iface([
        ("frxb", .int(2048)), ("ftxb", .int(0)), ("frxs", .double(800)), ("ftxs", .double(0)),
      ])
    ])
    let rendered = Fixtures.renderer { $0.filterStats = true }.render(stats: stats, linkCount: nil)
    XCTAssertTrue(
      rendered.contains(
        "    Traffic   : ↑1.20 MB    0 bps\n                ↓3.40 MB    0 bps\n"
          + "    Filtered  : ↑0 B  0 bps\n                ↓2.05 KB  800 bps\n"), rendered)
  }

  /// `rnstatus.py:829-862`: Filtered, then Links, after Totals.
  func testTheFilteredAndLinksTotals() {
    let stats = Fixtures.top(
      [],
      [
        ("rxb", .int(12_340_000)), ("txb", .int(9_990_000)),
        ("rxs", .double(48000)), ("txs", .double(24000)),
        ("frxb", .int(1000)), ("ftxb", .int(0)), ("frxs", .double(80)), ("ftxs", .double(0)),
        ("lrxb", .int(500_000)), ("ltxb", .int(250_000)),
        ("lrxs", .double(12000)), ("ltxs", .double(6000)),
        ("arxs", .double(4800)),
      ])
    let rendered = Fixtures.renderer {
      $0.trafficTotals = true
      $0.filterStats = true
      $0.linkStats = true
    }.render(stats: stats, linkCount: nil)
    XCTAssertTrue(
      rendered.contains(
        "\n Filtered     : ↑0 B      0 bps\n                ↓1.00 KB  80 bps\n"
          + "\n Links        : ↑250.00 KB  6.00 Kbps, 25% of data flow\n"
          + "                ↓500.00 KB  12.00 Kbps, 27% of data flow\n"), rendered)
  }
}
