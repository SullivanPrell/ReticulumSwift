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

/// The `rnstatus` surface added or changed in RNS 1.5.5.
///
/// Every expected string here comes from running the real 1.5.5 `rnstatus.program_setup()`
/// (`git show 1.5.5:RNS/Utilities/rnstatus.py`) against `RNStatusRendererTests.discoveredFixtures`,
/// with `InterfaceDiscovery` stubbed to return those entries and `sys.stdout` redirected.
///
/// 1.5.5 adds a Running column and a Stack line naming the announcing implementation, hides
/// stale entries and entries without implementation info unless `--show-stale` or
/// `--show-unknown` is given (`rnstatus.py:254-255`, `329-331`), and adds `--attach`,
/// `--detach` and `--reload` (`rnstatus.py:179-207`, `879-881`).
final class RNStatus155SurfaceTests: XCTestCase {

  private typealias Fixtures = RNStatusRendererTests

  private func renderer(
    _ configure: (inout RNStatusRenderer.Options) -> Void = { _ in }
  ) -> RNStatusRenderer {
    var options = RNStatusRenderer.Options()
    configure(&options)
    return RNStatusRenderer(options: options, now: Fixtures.now)
  }

  private static let tableHeader =
    "\n"
    + "Name                      Type         Status     Last Heard   Value   Running          Location       \n"
    + String(repeating: "-", count: 110) + "\n"
  private static let backboneRow =
    "my-backbone               Backbone   ✓ Available  4m ago       21      RNS 1.5.5        55.6761, 12.5683\n"
  private static let unknownRow =
    "a-very-long-discovered-i… RNode      ? Unknown    2h ago       18      Unknown          N/A            \n"
  private static let staleRow =
    "stale-one                 TCPServer  × Stale      3d ago       14      RNSwift 1.22.1-… -35.2717, 138.5542\n"

  // MARK: - The table

  func testTheTableHidesStaleAndUnknownEntriesByDefault() {
    XCTAssertEqual(
      renderer().renderDiscoveredTable(Fixtures.discoveredFixtures()),
      Self.tableHeader + Self.backboneRow)
  }

  func testShowStaleAndShowUnknownEachAddTheirRows() {
    let fixtures = Fixtures.discoveredFixtures()
    XCTAssertEqual(
      renderer { $0.showUnknown = true }.renderDiscoveredTable(fixtures),
      Self.tableHeader + Self.backboneRow + Self.unknownRow)
    XCTAssertEqual(
      renderer { $0.showStale = true }.renderDiscoveredTable(fixtures),
      Self.tableHeader + Self.backboneRow + Self.staleRow)
    XCTAssertEqual(
      renderer {
        $0.showStale = true
        $0.showUnknown = true
      }.renderDiscoveredTable(fixtures),
      Self.tableHeader + Self.backboneRow + Self.unknownRow + Self.staleRow)
  }

  /// `if len(impl_str) > 16: impl_str = impl_str[:15]+"…"` (`rnstatus.py:320`).
  func testTheRunningColumnClipsPastSixteenCharacters() throws {
    var info = Fixtures.discoveredFixtures()[0]
    info.version = "1.5.5-abcdef"
    let exact = renderer().renderDiscoveredTable([info]).components(separatedBy: "\n")[3]
    XCTAssertTrue(exact.contains(" RNS 1.5.5-abcdef 55.6761"), exact)

    info.version = "1.5.5-abcdefg"
    let clipped = renderer().renderDiscoveredTable([info]).components(separatedBy: "\n")[3]
    XCTAssertTrue(clipped.contains(" RNS 1.5.5-abcde… 55.6761"), clipped)
  }

  /// `has_impl_info` needs both values present and truthy (`rnstatus.py:246`).
  func testImplementationInfoNeedsBothValues() {
    for (implName, version) in [("RNS", ""), ("", "1.5.5"), ("RNS", nil), (nil, "1.5.5")] {
      var info = Fixtures.discoveredFixtures()[0]
      info.implName = implName
      info.version = version
      XCTAssertEqual(
        renderer().renderDiscoveredTable([info]), Self.tableHeader,
        "\(String(describing: implName)) \(String(describing: version))")
      let shown = renderer { $0.showUnknown = true }.renderDiscoveredTable([info])
      XCTAssertTrue(shown.contains(" 21      Unknown          55.6761"), shown)
    }
  }

  // MARK: - The details

  private static let backboneDetails =
    "Network   ID : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"
    + "Transport ID : aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
    + "Name         : my-backbone\n"
    + "Type         : BackboneInterface\n"
    + "Stack        : RNS 1.5.5\n"
    + "Status       : Available\n"
    + "Transport    : Enabled\n"
    + "Distance     : 2 hops\n"
    + "Discovered   : 3d and 11h ago\n"
    + "Last Heard   : 4m ago\n"
    + "Location     : 55.6761, 12.5683, 12.0m h\n"
    + "Address      : example.org\n"
    + "Port         : 4965\n"
    + "Stamp Value  : 21\n"
    + "\nConfiguration Entry:\n"
    + "  [[my-backbone]]\n"
    + "    type = BackboneInterface\n"
    + "    enabled = yes\n"
  private static let staleDetails =
    "Transport ID : dddddddddddddddddddddddddddddddd\n"
    + "Name         : stale-one\n"
    + "Type         : TCPServerInterface\n"
    + "Stack        : RNSwift 1.22.1-development\n"
    + "Status       : Stale\n"
    + "Transport    : Enabled\n"
    + "Distance     : 3 hops\n"
    + "Discovered   : 10d and 10h ago\n"
    + "Last Heard   : 3d and 11h ago\n"
    + "Location     : -35.2717, 138.5542\n"
    + "Address      : 1.2.3.4\n"
    + "Port         : 4242\n"
    + "Stamp Value  : 14\n"
    + "\nConfiguration Entry:\n"
    + "  [[stale]]\n"
    + "    type = TCPClientInterface\n"
  private static let separator = "\n" + String(repeating: "=", count: 47) + "\n\n"

  func testTheDetailsHideStaleAndUnknownEntriesByDefault() {
    XCTAssertEqual(
      renderer().renderDiscoveredDetails(Fixtures.discoveredFixtures()),
      "\n" + Self.backboneDetails)
  }

  /// The separator is printed when the entry's index in the name-filtered list is above zero,
  /// so an entry the stale and unknown checks skip still counts (`rnstatus.py:240`, `280`).
  func testTheSeparatorCountsEntriesTheFiltersSkip() {
    let reversed = Array(Fixtures.discoveredFixtures().reversed())
    XCTAssertEqual(
      renderer().renderDiscoveredDetails(reversed),
      "\n" + Self.separator + Self.backboneDetails)
    XCTAssertEqual(
      renderer { $0.showStale = true }.renderDiscoveredDetails(reversed),
      "\n" + Self.staleDetails + Self.separator + Self.backboneDetails)
  }

  func testTheWidthsAreThe155Ones() {
    XCTAssertEqual(RNStatusApp.discoveredTableRuleWidth, 110)  // rnstatus.py:313
    XCTAssertEqual(RNStatusApp.detailSeparatorWidth, 47)  // rnstatus.py:280
  }

  // MARK: - JSON

  /// `-d -j` prints every entry, whatever `--show-stale` and `--show-unknown` say, with
  /// `impl_name` and `version` right after `type` and `None` when absent (`Discovery.py:363-365`).
  func testDiscoveredJSONMatchesPython() {
    XCTAssertEqual(
      RNStatusJSON.encodeDiscovered(Fixtures.discoveredFixtures()),
      "[{\"type\": \"BackboneInterface\", \"impl_name\": \"RNS\", \"version\": \"1.5.5\", "
        + "\"transport\": true, \"name\": \"my-backbone\", "
        + "\"received\": 1699999760.0, \"stamp\": \"1111111111111111\", \"value\": 21, "
        + "\"transport_id\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\", "
        + "\"network_id\": \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\", \"hops\": 2, "
        + "\"latitude\": 55.6761, \"longitude\": 12.5683, \"height\": 12.0, "
        + "\"reachable_on\": \"example.org\", \"port\": 4965, "
        + "\"config_entry\": \"[[my-backbone]]\\n  type = BackboneInterface\\n  enabled = yes\", "
        + "\"discovery_hash\": \"\(String(repeating: "22", count: 32))\", "
        + "\"discovered\": 1699700000.0, \"last_heard\": 1699999760.0, \"heard_count\": 4, "
        + "\"status\": \"available\", \"status_code\": 1000}, "
        + "{\"type\": \"RNodeInterface\", \"impl_name\": null, \"version\": null, "
        + "\"transport\": false, "
        + "\"name\": \"a-very-long-discovered-interface-name\", \"received\": 1699992800.0, "
        + "\"stamp\": \"3333333333333333\", \"value\": 18, "
        + "\"transport_id\": \"cccccccccccccccccccccccccccccccc\", "
        + "\"network_id\": \"cccccccccccccccccccccccccccccccc\", \"hops\": 1, "
        + "\"latitude\": null, \"longitude\": null, \"height\": null, "
        + "\"frequency\": 867200000, \"bandwidth\": 125000, \"sf\": 8, \"cr\": 5, "
        + "\"config_entry\": \"[[rnode]]\\n  type = RNodeInterface\", "
        + "\"discovery_hash\": \"\(String(repeating: "44", count: 32))\", "
        + "\"discovered\": 1699910000.0, \"last_heard\": 1699992800.0, \"heard_count\": 2, "
        + "\"status\": \"unknown\", \"status_code\": 100}, "
        + "{\"type\": \"TCPServerInterface\", \"impl_name\": \"RNSwift\", "
        + "\"version\": \"1.22.1-development\", \"transport\": true, \"name\": \"stale-one\", "
        + "\"received\": 1699700000.0, \"stamp\": \"5555555555555555\", \"value\": 14, "
        + "\"transport_id\": \"dddddddddddddddddddddddddddddddd\", "
        + "\"network_id\": \"dddddddddddddddddddddddddddddddd\", \"hops\": 3, "
        + "\"latitude\": -35.2717, \"longitude\": 138.55425, \"height\": null, "
        + "\"reachable_on\": \"1.2.3.4\", \"port\": 4242, "
        + "\"config_entry\": \"[[stale]]\\n  type = TCPClientInterface\", "
        + "\"discovery_hash\": \"\(String(repeating: "66", count: 32))\", "
        + "\"discovered\": 1699100000.0, \"last_heard\": 1699700000.0, \"heard_count\": 1, "
        + "\"status\": \"stale\", \"status_code\": 0}]")
  }

  /// The operator's LXMF address is set after the discovery hash (`Discovery.py:460-463`).
  func testTheOperatorAddressFollowsTheDiscoveryHash() throws {
    var info = Fixtures.discoveredFixtures()[0]
    info.operatorLxmfAddress = String(repeating: "ee", count: 16)
    guard case .map(let pairs) = RNStatusJSON.msgpackValue(for: info) else {
      return XCTFail("not a map")
    }
    let keys = pairs.compactMap { k, _ -> String? in
      if case .string(let s) = k { return s }
      return nil
    }
    let hash = try XCTUnwrap(keys.firstIndex(of: "discovery_hash"))
    XCTAssertEqual(keys[hash + 1], "operator_lxmf_address")
  }

  // MARK: - Persistence

  private func persistedKeys(_ info: DiscoveredInterfaceInfo) throws -> [(String, MsgPack.Value)] {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("disc-order-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let discovery = InterfaceDiscovery(storagePath: dir.path)
    discovery.interfaceDiscovered(info)
    let file = dir.appendingPathComponent(
      RNSUtilities.hexrep(try XCTUnwrap(info.discoveryHash), delimit: false))
    guard case .map(let pairs) = try MsgPack.decode(Data(contentsOf: file)) else {
      XCTFail("not a map")
      return []
    }
    return pairs.compactMap { k, v in
      if case .string(let s) = k { return (s, v) }
      return nil
    }
  }

  /// A discovery file holds the keys in the order Python's `info` dict gains them
  /// (`Discovery.py:363-463`, then `606-608`), since Python's own `rnstatus -d -j` prints a
  /// file straight from disk.
  func testAPersistedEntryKeepsPythonsKeyOrder() throws {
    var weave = Fixtures.discoveredFixtures()[1]
    weave.type = "WeaveInterface"
    weave.implName = "RNS"
    weave.version = "1.5.5"
    weave.ifacNetname = "segment"
    weave.ifacNetkey = "k"
    weave.sf = nil
    weave.cr = nil
    weave.channel = 11
    weave.modulation = "2FSK"
    weave.operatorLxmfAddress = String(repeating: "ee", count: 16)
    XCTAssertEqual(
      try persistedKeys(weave).map(\.0),
      [
        "type", "impl_name", "version", "transport", "name", "received", "stamp", "value",
        "transport_id", "network_id", "hops", "latitude", "longitude", "height",
        "ifac_netname", "ifac_netkey", "frequency", "bandwidth", "channel", "modulation",
        "config_entry", "discovery_hash", "operator_lxmf_address",
        "discovered", "last_heard", "heard_count",
      ])

    XCTAssertEqual(
      try persistedKeys(Fixtures.discoveredFixtures()[0]).map(\.0),
      [
        "type", "impl_name", "version", "transport", "name", "received", "stamp", "value",
        "transport_id", "network_id", "hops", "latitude", "longitude", "height",
        "reachable_on", "port", "config_entry", "discovery_hash",
        "discovered", "last_heard", "heard_count",
      ])
  }

  /// The announce carries an integer frequency and bandwidth, and Python persists what it
  /// decoded, so its `rnstatus -D` prints `867,200,000 Hz` from the file, not `867,200,000.0 Hz`.
  func testAnIntegralFrequencyIsPersistedAsAnInteger() throws {
    let keys = Dictionary(
      try persistedKeys(Fixtures.discoveredFixtures()[1]), uniquingKeysWith: { a, _ in a })
    for key in ["frequency", "bandwidth"] {
      switch keys[key] {
      case .int, .uint: break
      default: XCTFail("\(key) persisted as \(String(describing: keys[key]))")
      }
    }
  }

  // MARK: - The log line

  func testTheDiscoveredLogNamesTheImplementation() {
    var lines: [String] = []
    let savedHandler = Reticulum.logHandler
    let savedLevel = Reticulum.globalLogLevel
    Reticulum.globalLogLevel = .debug
    Reticulum.logHandler = { message, level in
      if level == .debug, message.hasPrefix("Discovered ") { lines.append(message) }
    }
    defer {
      Reticulum.logHandler = savedHandler
      Reticulum.globalLogLevel = savedLevel
    }
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("disc-log-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let discovery = InterfaceDiscovery(storagePath: dir.path)
    let fixtures = Fixtures.discoveredFixtures()
    discovery.interfaceDiscovered(fixtures[0])
    discovery.interfaceDiscovered(fixtures[1])

    // Python: `Discovery.py:594-600`.
    XCTAssertEqual(
      lines,
      [
        "Discovered BackboneInterface (RNS 1.5.5) 2 hops away with stamp value 21: my-backbone",
        "Discovered RNodeInterface (unknown implementation) 1 hop away with stamp value 18: "
          + "a-very-long-discovered-interface-name",
      ])
  }

  // MARK: - Attach, detach and reload

  func testManageReportsMatchPython() {
    let cases: [(RNStatusApp.ManageAction, RNStatusApp.ManageReply, String, Int32)] = [
      (.attach, .succeeded, "Interface Hub was attached", 0),
      (.attach, .failed, "Could not attach interface Hub", 1),
      (.attach, .missing, "The interface Hub does not exist", 1),
      (.attach, .unknown, "Unknown error while attaching interface Hub", 1),
      (.detach, .succeeded, "Interface Hub was detached", 0),
      (.detach, .failed, "Could not detach interface Hub", 1),
      (.detach, .missing, "The interface Hub does not exist", 1),
      (.detach, .unknown, "Unknown error while detaching interface Hub", 1),
      (.reload, .succeeded, "Interface Hub was reloaded", 0),
      (.reload, .failed, "Could not reload interface Hub", 1),
      (.reload, .missing, "The interface Hub does not exist", 1),
      (.reload, .unknown, "Unknown error while reloading interface Hub", 1),
    ]
    for (action, reply, message, code) in cases {
      let report = RNStatusApp.manageReport(action, name: "Hub", reply: reply)
      XCTAssertEqual(report.message, message)
      XCTAssertEqual(report.code, code, message)
    }
  }

  func testAReplyMapsFromTheTriState() {
    XCTAssertEqual(RNStatusApp.ManageReply(true), .succeeded)
    XCTAssertEqual(RNStatusApp.ManageReply(false), .failed)
    XCTAssertEqual(RNStatusApp.ManageReply(nil), .missing)
  }

  func testTheNewOptionsParse() throws {
    let parser = RNStatusApp.makeParser()
    let parsed = try parser.parse(
      ["--attach", "A", "--detach", "B", "--reload", "C", "--show-stale", "--show-unknown"])
    XCTAssertEqual(parsed.value("--attach"), "A")
    XCTAssertEqual(parsed.value("--detach"), "B")
    XCTAssertEqual(parsed.value("--reload"), "C")
    XCTAssertTrue(parsed.flag("--show-stale"))
    XCTAssertTrue(parsed.flag("--show-unknown"))
    XCTAssertEqual(
      RNStatusApp.manageRequest(parsed).map { [$0.action.rawValue, $0.name] }, ["attach", "A"],
      "Python checks attach, then detach, then reload, and exits after the first")
    XCTAssertEqual(
      RNStatusApp.manageRequest(try parser.parse(["--reload", "C"])).map(\.action), .reload)
    XCTAssertNil(RNStatusApp.manageRequest(try parser.parse(["-d"])))
    XCTAssertNil(
      RNStatusApp.manageRequest(try parser.parse(["--attach", ""])),
      "`if attach:` is false for an empty name")
  }

  // MARK: - Help text

  /// `rnstatus --help` from RNS 1.5.5, rendered by CPython 3.11's argparse at 80 columns.
  ///
  /// CPython 3.12 and later render `-s, --sort SORT` where 3.11 renders `-s SORT, --sort SORT`.
  /// That layout belongs to whichever interpreter runs the Python tool, not to the port, so
  /// reticulum-interop's `normalize_help` reconciles the two rows it affects.
  static let pythonHelp = """
    usage: rnstatus [-h] [--config CONFIG] [--version] [--attach name]
                    [--detach name] [--reload name] [-a] [-A] [-P] [-l] [-B] [-b]
                    [-t] [-p] [-q] [-z] [-s SORT] [-r] [-j] [-R hash] [-i path]
                    [-w seconds] [-d] [-D] [--show-stale] [--show-unknown] [-m]
                    [-I seconds] [-v]
                    [filter]

    Reticulum Network Stack Status

    positional arguments:
      filter                only display interfaces with names including filter

    options:
      -h, --help            show this help message and exit
      --config CONFIG       path to alternative Reticulum config directory
      --version             show program's version number and exit
      --attach name         Attach interface by name
      --detach name         Detach interface by name
      --reload name         Reload interface by name
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
      --show-stale          show stale discovery entries
      --show-unknown        show discovery entries without version info
      -m, --monitor         continuously monitor status
      -I seconds, --monitor-interval seconds
                            refresh interval for monitor mode (default: 1)
      -v, --verbose
    """

  func testHelpTextIsTheWholePythonPage() {
    XCTAssertEqual(RNStatusApp.helpText, Self.pythonHelp)
    XCTAssertEqual(RNStatusApp.usageText.components(separatedBy: "\n").count, 6)
  }
}
