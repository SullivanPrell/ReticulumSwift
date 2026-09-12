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

/// The `rnstatus` surface added or changed in RNS 1.5.2.
///
/// Every expected string here comes from running the **real** Python utility:
/// `rnstatus.program_setup()` from the tri-test virtualenv (RNS 1.5.2), driven by a stub
/// instance returning the same synthetic stats dictionary these tests build, with
/// `sys.stdout` redirected and `time.time` pinned to `RNStatusRendererTests.now`.
/// Trailing whitespace is significant—Python pads the frequency columns and then appends
/// possibly empty suffixes.
final class RNStatus152SurfaceTests: XCTestCase {

  // MARK: - Fixtures

  /// `RNStatusRendererTests.baseInterface` plus every key RNS 1.5.2 reads without a
  /// presence guard.
  ///
  /// The 1.5.2 utility subscripts 23 per-interface keys bare, so a
  /// payload missing any of them makes the real tool raise a `KeyError`.
  static func iface(_ overrides: [(String, MsgPack.Value)] = []) -> MsgPack.Value {
    var base: [(String, MsgPack.Value)] = [
      ("mtu", .int(500)),
      ("arxs", .double(0)), ("atxs", .double(0)),
      ("arxc", .int(0)), ("atxc", .int(0)),
      ("prxc", .int(0)), ("ptxc", .int(0)),
      ("txbuffered", .int(0)), ("txstalled", .bool(false)),
      ("txdrp", .int(0)), ("txdrb", .int(0)),
      ("battery_state", .nil), ("gravity", .int(0)),
      ("protocol_violations", .int(0)), ("ifac_violations", .int(0)),
      ("packet_filter_hits", .int(0)),
    ]
    base.append(contentsOf: overrides)
    return RNStatusRendererTests.baseInterface(base)
  }

  /// The top-level map with all 31 aggregate keys RNS 1.5.2 emits, zeroed.
  static func top(
    _ interfaces: [MsgPack.Value],
    _ overrides: [(String, MsgPack.Value)] = []
  ) -> RNStatusStats {
    var base: [(String, MsgPack.Value)] = [
      ("arxb", .int(0)), ("atxb", .int(0)),
      ("arxs", .double(0)), ("atxs", .double(0)),
      ("arxf", .double(0)), ("atxf", .double(0)),
      ("prxb", .int(0)), ("ptxb", .int(0)),
      ("prxs", .double(0)), ("ptxs", .double(0)),
      ("prxf", .double(0)), ("ptxf", .double(0)),
      ("rxpps", .int(0)), ("txpps", .int(0)),
      ("rxqt", .int(0)), ("rxqd", .int(0)), ("rxqa", .int(0)),
      ("rxqp", .int(0)), ("rxqil", .int(0)),
      ("rxqtd", .int(0)), ("rxqdd", .int(0)), ("rxqad", .int(0)),
      ("rxqpd", .int(0)), ("rxqild", .int(0)),
      ("tqpressure", .double(0)), ("dqpressure", .double(0)),
      ("aqpressure", .double(0)), ("pqpressure", .double(0)),
      ("ilqpressure", .double(0)), ("txq", .nil),
    ]
    base.append(contentsOf: overrides)
    return RNStatusRendererTests.top(interfaces, base)
  }

  static func renderer(_ configure: (inout RNStatusRenderer.Options) -> Void = { _ in })
    -> RNStatusRenderer
  {
    RNStatusRendererTests.renderer(configure)
  }

  /// The interface block the goldens below all start with, before any other key applies.
  static let plainInterface =
    "\n TCPInterface[Server on 0.0.0.0:4242]\n"
    + "    Status    : Up\n"
    + "    Mode      : Full\n"
    + "    Rate      : 10.00 Mbps, MTU 500\n"
    + "    Traffic   : ↑1.20 MB    0 bps\n"
    + "                ↓3.40 MB    0 bps\n"

  // MARK: - Option table

  func testTheFourNewFlagsParse() throws {
    let parser = RNStatusApp.makeParser()
    for (short, long) in [
      ("-b", "--blocked-ips"), ("-p", "--pps"),
      ("-q", "--queues"), ("-z", "--profiling"),
    ] {
      XCTAssertTrue(try parser.parse([short]).flag(long), "short \(short)")
      XCTAssertTrue(try parser.parse([long]).flag(long), "long \(long)")
      XCTAssertFalse(try parser.parse([]).flag(long), "default \(long)")
    }
  }

  /// `-b` and `-B` are different options; a case-folding parser would silently make
  /// `--burst` and `--blocked-ips` the same switch.
  func testLowerAndUpperCaseBAreDistinct() throws {
    let parser = RNStatusApp.makeParser()
    let lower = try parser.parse(["-b"])
    XCTAssertTrue(lower.flag("--blocked-ips"))
    XCTAssertFalse(lower.flag("--burst"))
    let upper = try parser.parse(["-B"])
    XCTAssertTrue(upper.flag("--burst"))
    XCTAssertFalse(upper.flag("--blocked-ips"))
  }

  // MARK: - Help text

  /// The whole `--help` page, byte for byte.
  ///
  /// Captured from the tri-test virtualenv's `rnstatus --help` (RNS 1.5.2) and then
  /// rewritten into the CPython &lt;= 3.11 options layout the port pins: 3.12 renders
  /// `-s, --sort SORT` where 3.11 renders `-s SORT, --sort SORT`. That layout belongs to
  /// whichever interpreter runs the Python tool, not to the port, so tri-test's
  /// `normalize_help` reconciles the two rows it affects; applying that function to this
  /// string reproduces the captured page exactly.
  static let pythonHelp = """
    usage: rnstatus [-h] [--config CONFIG] [--version] [-a] [-A] [-P] [-l] [-B]
                    [-b] [-t] [-p] [-q] [-z] [-s SORT] [-r] [-j] [-R hash]
                    [-i path] [-w seconds] [-d] [-D] [-m] [-I seconds] [-v]
                    [filter]

    Reticulum Network Stack Status

    positional arguments:
      filter                only display interfaces with names including filter

    options:
      -h, --help            show this help message and exit
      --config CONFIG       path to alternative Reticulum config directory
      --version             show program's version number and exit
      -a, --all             show all interfaces
      -A, --announce-stats  show announce stats
      -P, --pr-stats        show path request stats
      -l, --link-stats      show link stats
      -B, --burst           only show interfaces with active bursts
      -b, --blocked-ips     show blocked IPs per interface
      -t, --totals          display traffic totals
      -p, --pps             display packets per second in totals
      -q, --queues          display queue stats
      -z, --profiling       display live profiling results
      -s SORT, --sort SORT  sort interfaces by [rate, traffic, rx, tx, rxs, txs,
                            anns, arx, atx, arxc, atxc, held, prx, ptx, prxc,
                            ptxc, pvs, ivs, flt, txdrp, txdrb, txbuf]
      -r, --reverse         reverse sorting
      -j, --json            output in JSON format
      -R hash               transport identity hash of remote instance to get
                            status from
      -i path               path to identity used for remote management
      -w seconds            timeout before giving up on remote queries
      -d, --discovered      list discovered interfaces
      -D                    show details and config entries for discovered
                            interfaces
      -m, --monitor         continuously monitor status
      -I seconds, --monitor-interval seconds
                            refresh interval for monitor mode (default: 1)
      -v, --verbose
    """

  func testHelpTextIsTheWholePythonPage() {
    XCTAssertEqual(RNStatusApp.helpText, Self.pythonHelp)
  }

  /// The usage block is what `parser.print_usage(sys.stderr)` writes before an error, so
  /// a new flag has to reach the wrapped usage line as well as the options table.
  func testUsageBlockCarriesTheNewFlags() {
    let usage = RNStatusApp.usageText
    XCTAssertEqual(usage.components(separatedBy: "\n").count, 4)
    for token in ["[-b]", "[-p]", "[-q]", "[-z]"] {
      XCTAssertTrue(usage.contains(token), "missing \(token) in:\n\(usage)")
    }
    XCTAssertTrue(
      RNStatusApp.errorText("unrecognized arguments: -Q").hasSuffix(
        "\nrnstatus: error: unrecognized arguments: -Q"))
  }

  // MARK: - Sort vocabulary

  /// The tokens the 1.5.2 if-chain tests, in the order it tests them (rnstatus.py:379-401).
  static let pythonSortTokens = [
    "rate", "bitrate", "rx", "tx", "rxs", "txs", "traffic",
    "anns", "announces", "arx", "atx", "arxc", "atxc",
    "prx", "ptx", "prxc", "ptxc", "held",
    "pvs", "ivs", "flt", "gravity", "g", "txdrp", "txdrb", "txbuf",
  ]

  func testSortVocabularyMatchesPython() {
    XCTAssertEqual(RNStatusApp.Sort.allCases.map(\.rawValue), Self.pythonSortTokens)
  }

  /// The port accepted `announce` singular, which Python's chain has never held, so
  /// `-s announce` sorted here and left the order untouched there.
  func testAnnounceSingularIsNotASortToken() {
    XCTAssertNil(RNStatusApp.Sort(rawValue: "announce"))
  }

  /// The `-s` help string appears twice—once for the option table, once wrapped
  /// inside ``RNStatusApp/helpText``.
  ///
  /// Re-join the wrapped rows and the two must agree,
  /// so adding a key to one and not the other fails here rather than shipping.
  func testWrappedSortHelpRejoinsToTheOptionTableSpelling() throws {
    let lines = RNStatusApp.helpText.components(separatedBy: "\n")
    let start = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("  -s SORT, --sort SORT") })
    var chunks = [String(lines[start].dropFirst(24))]
    var index = start + 1
    while index < lines.count, lines[index].hasPrefix(String(repeating: " ", count: 24)) {
      chunks.append(lines[index].trimmingCharacters(in: .whitespaces))
      index += 1
    }
    XCTAssertEqual(chunks.joined(separator: " "), RNStatusApp.sortHelp)
  }

  /// Every token in the help list has to be a case the enum accepts—otherwise `--help`
  /// advertises a sort the tool ignores.
  func testEveryAdvertisedSortTokenIsAccepted() throws {
    let inside = try XCTUnwrap(RNStatusApp.sortHelp.range(of: "["))
    let closing = try XCTUnwrap(RNStatusApp.sortHelp.range(of: "]"))
    let listed = RNStatusApp.sortHelp[inside.upperBound..<closing.lowerBound]
      .components(separatedBy: ", ")
    XCTAssertEqual(listed.count, 22)
    for token in listed {
      XCTAssertNotNil(RNStatusApp.Sort(rawValue: token), "advertised but unaccepted: \(token)")
    }
  }

  func testEverySortKeyReadsADistinctPayloadField() {
    let fields: [(RNStatusApp.Sort, String)] = [
      (.arxc, "arxc"), (.atxc, "atxc"), (.prxc, "prxc"), (.ptxc, "ptxc"),
      (.pvs, "protocol_violations"), (.ivs, "ifac_violations"),
      (.flt, "packet_filter_hits"), (.gravity, "gravity"), (.g, "gravity"),
      (.txdrp, "txdrp"), (.txdrb, "txdrb"), (.txbuf, "txbuffered"),
    ]
    for (sort, key) in fields {
      let stats = Self.top([
        Self.iface([("name", .string("low")), (key, .int(1))]),
        Self.iface([("name", .string("high")), (key, .int(9))]),
      ])
      XCTAssertEqual(
        stats.sortedInterfaces(by: sort, reverse: false).map(\.name),
        ["high", "low"], "descending on \(sort.rawValue)")
      XCTAssertEqual(
        stats.sortedInterfaces(by: sort, reverse: true).map(\.name),
        ["low", "high"], "-r on \(sort.rawValue)")
    }
  }

  // MARK: - Per-interface additions

  func testRateCarriesTheMTU() {
    XCTAssertEqual(
      Self.renderer().render(stats: Self.top([Self.iface()]), linkCount: nil),
      Self.plainInterface + "\n")
  }

  /// Python subscripts `ifstat['mtu']` bare inside the bitrate guard, so a payload with
  /// a bitrate and no MTU raises there.
  ///
  /// The port renders the rate alone.
  func testAMissingMTURendersTheRateAlone() {
    var pairs: [(String, MsgPack.Value)] = []
    for (key, value) in [
      ("arxs", MsgPack.Value.double(0)), ("atxs", .double(0)),
      ("arxc", .int(0)), ("atxc", .int(0)),
      ("prxc", .int(0)), ("ptxc", .int(0)),
      ("txdrp", .int(0)), ("gravity", .int(0)),
    ] {
      pairs.append((key, value))
    }
    let stats = Self.top([RNStatusRendererTests.baseInterface(pairs)])
    XCTAssertTrue(
      Self.renderer().render(stats: stats, linkCount: nil)
        .contains("    Rate      : 10.00 Mbps\n"))
  }

  func testGravitySuffixOnTheStatusLine() {
    let stats = Self.top([Self.iface([("gravity", .int(3))])])
    XCTAssertTrue(
      Self.renderer().render(stats: stats, linkCount: nil)
        .contains("    Status    : Up, gravity 3\n"))
  }

  /// Python's second test is truthiness, so a reported gravity of zero adds nothing.
  func testZeroGravityAddsNothing() {
    XCTAssertTrue(
      Self.renderer().render(stats: Self.top([Self.iface()]), linkCount: nil)
        .contains("    Status    : Up\n"))
  }

  func testTXDropsLine() {
    let stats = Self.top([Self.iface([("txdrp", .int(7)), ("txdrb", .int(8192))])])
    XCTAssertTrue(
      Self.renderer().render(stats: stats, linkCount: nil)
        .contains("    TX Drops  : 7 (8.19 KB)\n"))
  }

  /// The line prints both counters whenever either is non-zero, so IFAC violations alone
  /// still render a leading "0 protocol".
  func testViolationsLine() {
    let cases: [([(String, MsgPack.Value)], String?)] = [
      ([("protocol_violations", .int(4)), ("ifac_violations", .int(2))], "4 protocol, 2 IFAC"),
      ([("protocol_violations", .int(4))], "4 protocol"),
      ([("ifac_violations", .int(2))], "0 protocol, 2 IFAC"),
      ([], nil),
    ]
    for (overrides, expected) in cases {
      let rendered = Self.renderer().render(
        stats: Self.top([Self.iface(overrides)]), linkCount: nil)
      if let expected {
        XCTAssertTrue(
          rendered.contains("    Violatns. : \(expected)\n"),
          "expected \(expected) in:\n\(rendered)")
      } else {
        XCTAssertFalse(rendered.contains("Violatns."), rendered)
      }
    }
  }

  func testFilterHitsLine() {
    let stats = Self.top([Self.iface([("packet_filter_hits", .int(9))])])
    XCTAssertTrue(
      Self.renderer().render(stats: stats, linkCount: nil)
        .contains("    Flt. Hits : 9\n"))
    XCTAssertFalse(
      Self.renderer().render(stats: Self.top([Self.iface()]), linkCount: nil)
        .contains("Flt. Hits"))
  }

  /// Both lifetime counters must be non-zero for the extra header line; the frequency
  /// pair then moves down onto a continuation line.
  func testLifetimeCounterHeaderLines() {
    let stats = Self.top([
      Self.iface([
        ("arxc", .int(31)), ("atxc", .int(12)), ("prxc", .int(5)), ("ptxc", .int(3)),
        ("incoming_announce_frequency", .double(1.0)),
        ("outgoing_announce_frequency", .double(3.0)),
        ("incoming_pr_frequency", .double(0.4)),
        ("outgoing_pr_frequency", .double(1.2)),
      ])
    ])
    let rendered = Self.renderer {
      $0.announceStats = true
      $0.prStats = true
    }
    .render(stats: stats, linkCount: nil)
    XCTAssertEqual(
      rendered,
      "\n TCPInterface[Server on 0.0.0.0:4242]\n"
        + "    Status    : Up\n"
        + "    Mode      : Full\n"
        + "    Rate      : 10.00 Mbps, MTU 500\n"
        + "    Path Rqs. : 5↓ 3↑ total\n"
        + "                ↑1.2 Hz    \n"
        + "                ↓0.4 Hz     \n"
        + "    Announces : 31↓ 12↑ total\n"
        + "                3.0 Hz↑    \n"
        + "                1.0 Hz↓    \n"
        + "    Traffic   : ↑1.20 MB    0 bps\n"
        + "                ↓3.40 MB    0 bps\n\n")
  }

  /// One counter at zero keeps the two-line form.
  func testASingleZeroCounterKeepsTheTwoLineForm() {
    let stats = Self.top([
      Self.iface([
        ("arxc", .int(31)), ("atxc", .int(0)),
        ("incoming_announce_frequency", .double(1.0)),
        ("outgoing_announce_frequency", .double(3.0)),
      ])
    ])
    let rendered = Self.renderer { $0.announceStats = true }.render(stats: stats, linkCount: nil)
    XCTAssertFalse(rendered.contains("total"), rendered)
    XCTAssertTrue(rendered.contains("    Announces : 3.0 Hz↑"), rendered)
  }

  // MARK: - Blocked IPs (-b)

  static func blockedInterface() -> MsgPack.Value {
    iface([
      ("name", .string("BackboneInterface[Server on 0.0.0.0:4242]")),
      ("clients", .int(3)),
      ("blocked_ips", .int(2)),
      ("blocked_ip_list", .array([.string("10.0.0.7"), .string("10.0.0.9")])),
    ])
  }

  func testBlockedIPListOnlyUnderTheFlag() {
    let stats = Self.top([Self.blockedInterface()])
    let withFlag = Self.renderer { $0.blockedIPs = true }.render(stats: stats, linkCount: nil)
    XCTAssertEqual(
      withFlag,
      "\n BackboneInterface[Server on 0.0.0.0:4242]\n"
        + "    Status    : Up\n"
        + "    Clients   : 3\n"
        + "    Blocked   : 2 IPs\n"
        + "                10.0.0.7\n"
        + "                10.0.0.9\n"
        + "    Mode      : Full\n"
        + "    Rate      : 10.00 Mbps, MTU 500\n"
        + "    Traffic   : ↑1.20 MB    0 bps\n"
        + "                ↓3.40 MB    0 bps\n\n")

    let without = Self.renderer().render(stats: stats, linkCount: nil)
    XCTAssertTrue(without.contains("    Blocked   : 2 IPs\n    Mode"), without)
    XCTAssertFalse(without.contains("10.0.0.7"), without)
  }

  // MARK: - Totals (-t)

  func testPacketsPerSecondInTotals() {
    let stats = Self.top(
      [Self.iface([("rxs", .double(24000)), ("txs", .double(9600))])],
      [("rxpps", .int(42)), ("txpps", .int(17))])
    let rendered = Self.renderer {
      $0.trafficTotals = true
      $0.pps = true
    }
    .render(stats: stats, linkCount: nil)
    XCTAssertTrue(
      rendered.hasSuffix(
        "\n Totals       : ↑9.99 MB   24.00 Kbps, 17 pps\n"
          + "                ↓12.34 MB  48.00 Kbps, 42 pps\n\n"), rendered)
  }

  /// `-p` is a suffix on the totals lines, so it renders nothing without `-t`.
  func testPacketsPerSecondNeedsTotals() {
    let stats = Self.top([Self.iface()], [("rxpps", .int(42)), ("txpps", .int(17))])
    XCTAssertFalse(
      Self.renderer { $0.pps = true }.render(stats: stats, linkCount: nil)
        .contains("pps"))
  }

  func testTotalsWithAnnounceAndPathRequestAggregates() {
    let stats = Self.top(
      [Self.iface([("rxs", .double(24000)), ("txs", .double(9600))])],
      [
        ("arxb", .int(880_000)), ("atxb", .int(440_000)),
        ("arxs", .double(1200)), ("atxs", .double(600)),
        ("arxf", .double(1.5)), ("atxf", .double(0.75)),
        ("prxb", .int(220_000)), ("ptxb", .int(110_000)),
        ("prxs", .double(480)), ("ptxs", .double(240)),
        ("prxf", .double(0.4)), ("ptxf", .double(0.2)),
      ])
    let rendered = Self.renderer {
      $0.trafficTotals = true
      $0.announceStats = true
      $0.prStats = true
    }.render(stats: stats, linkCount: nil)
    XCTAssertTrue(
      rendered.hasSuffix(
        "\n Totals       : ↑9.99 MB   24.00 Kbps, 96% data (23.16 Kbps)\n"
          + "                ↓12.34 MB  48.00 Kbps, 96% data (46.32 Kbps)\n"
          + "\n Path Rqs.    : ↑110.00 KB  240 bps, 1% of flow, 200.00 mHz\n"
          + "                ↓220.00 KB  480 bps, 1% of flow, 400.00 mHz\n"
          + "\n Announces    : ↑440.00 KB  600 bps, 2% of flow, 750.00 mHz\n"
          + "                ↓880.00 KB  1.20 Kbps, 2% of flow, 1.50 Hz\n\n"), rendered)
  }

  // MARK: - Queue stats (-q)

  func testQueuePressureOnAnIdleInstance() {
    let rendered = Self.renderer { $0.queueStats = true }
      .render(
        stats: Self.top([Self.iface([("rxs", .double(24000)), ("txs", .double(9600))])]),
        linkCount: nil)
    XCTAssertTrue(
      rendered.hasSuffix(
        "\n Qu. Pressure : 0.0% total, 0 pkts\n"
          + "                0.0% data, 0 pkts\n"
          + "                0.0% announce, 0 pkts\n"
          + "                0.0% path request, 0 pkts\n"
          + "                0.0% ingress limiter, 0 pkts\n\n"), rendered)
  }

  func testQueuePressureWithDepthsAndDrops() {
    let stats = Self.top(
      [Self.iface([("rxs", .double(24000)), ("txs", .double(9600))])],
      [
        ("rxqt", .int(97)), ("rxqd", .int(61)), ("rxqa", .int(22)),
        ("rxqp", .int(11)), ("rxqil", .int(3)),
        ("rxqtd", .int(5)), ("rxqdd", .int(4)), ("rxqad", .int(3)),
        ("rxqpd", .int(2)), ("rxqild", .int(1)),
        ("tqpressure", .double(0.1234)), ("dqpressure", .double(0.061)),
        ("aqpressure", .double(0.022)), ("pqpressure", .double(0.011)),
        ("ilqpressure", .double(0.003)),
      ])
    XCTAssertTrue(
      Self.renderer { $0.queueStats = true }
        .render(stats: stats, linkCount: nil).hasSuffix(
          "\n Qu. Pressure : 12.3% total, 97 pkts, 5 dropped\n"
            + "                6.1% data, 61 pkts, 4 dropped\n"
            + "                2.2% announce, 22 pkts, 3 dropped\n"
            + "                1.1% path request, 11 pkts, 2 dropped\n"
            + "                0.3% ingress limiter, 3 pkts, 1 dropped\n\n"))
  }

  /// Python subscripts every queue key bare, so a peer that omits them makes its own
  /// tool raise.
  ///
  /// The port reads them with a zero default and still renders the block.
  func testQueueStatsAgainstAPeerWithoutTheKeys() {
    let bare = RNStatusStats(
      .map([
        (.string("interfaces"), .array([])),
        (.string("rxb"), .int(0)), (.string("txb"), .int(0)),
        (.string("rxs"), .double(0)), (.string("txs"), .double(0)),
      ]))!
    XCTAssertTrue(
      Self.renderer { $0.queueStats = true }.render(stats: bare, linkCount: nil)
        .contains("Qu. Pressure : 0.0% total, 0 pkts\n"))
  }

  // MARK: - Discovered details

  /// Python: rnstatus.py:246, added in RNS 1.5.0 and never rendered by the port.
  func testDiscoveredDetailsRenderTheOperatorLXMFAddress() throws {
    var info = DiscoveredInterfaceInfo(
      type: "TCPServerInterface", transport: true,
      name: "Test", received: 0, stamp: Data(), value: 3,
      transportID: "aabb", networkID: "aabb", hops: 1,
      discovered: RNStatusRendererTests.now,
      lastHeard: RNStatusRendererTests.now,
      heardCount: 1, status: "available", statusCode: 0)
    info.operatorLxmfAddress = "8dcd3f0a4e0c1a1b2c3d4e5f60718293"
    let rendered = Self.renderer().renderDiscoveredDetails([info])
    XCTAssertTrue(rendered.contains("LXMF address : 8dcd3f0a4e0c1a1b2c3d4e5f60718293\n"), rendered)
    let lxmfIndex = try XCTUnwrap(rendered.range(of: "LXMF address")).lowerBound
    let nameIndex = try XCTUnwrap(rendered.range(of: "Name         :")).lowerBound
    XCTAssertLessThan(lxmfIndex, nameIndex, rendered)
  }
}
