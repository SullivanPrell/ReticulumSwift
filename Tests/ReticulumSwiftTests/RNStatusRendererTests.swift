import XCTest
@testable import ReticulumSwift

/// Golden-output tests for the `rnstatus` renderer.
///
/// Python reference: `RNS/Utilities/rnstatus.py:361-675`.
///
/// Every expected string in this file was produced by running the **real** Python
/// `rnstatus.program_setup()` against the same synthetic stats dict, with `sys.stdout`
/// redirected and `time.time` pinned to `Self.now`. Trailing whitespace is significant and
/// intentional — Python pads the frequency/traffic columns and then appends possibly-empty
/// suffixes.
final class RNStatusRendererTests: XCTestCase {

    /// The value `time.time()` was pinned to when the goldens were generated.
    static let now: TimeInterval = 1_700_000_000

    // MARK: - Fixtures

    /// The same dict Python's generator calls `base_iface()`, in the same key order.
    /// `overrides` follows `dict.update` semantics: existing keys are replaced in place,
    /// new keys are appended.
    static func baseInterface(_ overrides: [(String, MsgPack.Value)] = []) -> MsgPack.Value {
        var pairs: [(String, MsgPack.Value)] = [
            ("clients", .nil),
            ("bitrate", .int(10_000_000)),
            ("rxs", .double(0)),
            ("txs", .double(0)),
            ("ifac_signature", .nil),
            ("ifac_size", .nil),
            ("ifac_netname", .nil),
            ("autoconnect_source", .nil),
            ("name", .string("TCPInterface[Server on 0.0.0.0:4242]")),
            ("short_name", .string("srv")),
            ("hash", .bytes(Data(repeating: 0x01, count: 32))),
            ("type", .string("TCPServerInterface")),
            ("rxb", .int(3_400_000)),
            ("txb", .int(1_200_000)),
            ("incoming_announce_frequency", .int(0)),
            ("outgoing_announce_frequency", .int(0)),
            ("incoming_pr_frequency", .int(0)),
            ("outgoing_pr_frequency", .int(0)),
            ("announce_rate_target", .nil),
            ("announce_rate_penalty", .nil),
            ("announce_rate_grace", .nil),
            ("held_announces", .int(0)),
            ("burst_active", .bool(false)),
            ("burst_activated", .int(0)),
            ("pr_burst_active", .bool(false)),
            ("pr_burst_activated", .int(0)),
            ("status", .bool(true)),
            ("mode", .int(1)),
        ]
        for (key, value) in overrides {
            if let index = pairs.firstIndex(where: { $0.0 == key }) { pairs[index].1 = value }
            else { pairs.append((key, value)) }
        }
        return .map(pairs.map { (.string($0.0), $0.1) })
    }

    static func top(_ interfaces: [MsgPack.Value],
                    _ overrides: [(String, MsgPack.Value)] = []) -> RNStatusStats {
        var pairs: [(String, MsgPack.Value)] = [
            ("interfaces", .array(interfaces)),
            ("rxb", .int(12_340_000)),
            ("txb", .int(9_990_000)),
            ("rxs", .double(48000)),
            ("txs", .double(24000)),
        ]
        for (key, value) in overrides {
            if let index = pairs.firstIndex(where: { $0.0 == key }) { pairs[index].1 = value }
            else { pairs.append((key, value)) }
        }
        pairs.append(("rss", .nil))
        return RNStatusStats(.map(pairs.map { (.string($0.0), $0.1) }))!
    }

    static func renderer(_ configure: (inout RNStatusRenderer.Options) -> Void = { _ in })
        -> RNStatusRenderer {
        var options = RNStatusRenderer.Options()
        configure(&options)
        return RNStatusRenderer(options: options, now: now)
    }

    // MARK: - Whole-block goldens

    func testMinimalTCPServerInterface() {
        let stats = Self.top([Self.baseInterface([("rxs", .double(24000)), ("txs", .double(9600))])])
        XCTAssertEqual(Self.renderer().render(stats: stats, linkCount: nil),
            "\n TCPInterface[Server on 0.0.0.0:4242]\n"
          + "    Status    : Up\n"
          + "    Mode      : Full\n"
          + "    Rate      : 10.00 Mbps\n"
          + "    Traffic   : ↑1.20 MB    9.60 Kbps\n"
          + "                ↓3.40 MB    24.00 Kbps\n\n")
    }

    func testAnnounceAndPathRequestBlocks() {
        let stats = Self.top([Self.baseInterface([
            ("clients", .int(4)),
            ("incoming_announce_frequency", .double(1.0)),
            ("outgoing_announce_frequency", .double(3.0)),
            ("incoming_pr_frequency", .double(0.4)),
            ("outgoing_pr_frequency", .double(1.2)),
        ])])
        let rendered = Self.renderer { $0.announceStats = true; $0.prStats = true }
            .render(stats: stats, linkCount: nil)
        XCTAssertEqual(rendered,
            "\n TCPInterface[Server on 0.0.0.0:4242]\n"
          + "    Status    : Up\n"
          + "    Clients   : 4\n"
          + "    Mode      : Full\n"
          + "    Rate      : 10.00 Mbps\n"
          + "    Path Rqs. : ↑1.2 Hz     0.3 Hz/c\n"
          + "                ↓0.4 Hz     \n"
          + "    Announces : 3.0 Hz↑     0.8 Hz/c\n"
          + "                1.0 Hz↓    \n"
          + "    Traffic   : ↑1.20 MB    0 bps\n"
          + "                ↓3.40 MB    0 bps\n\n")
    }

    /// Python computes the announce block first but PRINTS Path Rqs. first (rnstatus.py:626).
    func testPathRequestBlockPrintsBeforeAnnounceBlock() {
        let stats = Self.top([Self.baseInterface([
            ("incoming_announce_frequency", .double(1.0)),
            ("outgoing_announce_frequency", .double(3.0)),
            ("incoming_pr_frequency", .double(0.4)),
            ("outgoing_pr_frequency", .double(1.2)),
        ])])
        let rendered = Self.renderer { $0.announceStats = true; $0.prStats = true }
            .render(stats: stats, linkCount: nil)
        let pathIndex = rendered.range(of: "Path Rqs.")!.lowerBound
        let announceIndex = rendered.range(of: "Announces")!.lowerBound
        XCTAssertLessThan(pathIndex, announceIndex)
    }

    /// `-P` without `-A`: iaf/oaf are empty strings that still receive a trailing arrow, so
    /// they are one character long and cannot raise mlen above the floor of 10.
    func testPathRequestsOnlyStillArrowsTheEmptyAnnounceStrings() {
        let stats = Self.top([Self.baseInterface([
            ("incoming_pr_frequency", .double(0.4)),
            ("outgoing_pr_frequency", .double(1.2)),
        ])])
        XCTAssertEqual(Self.renderer { $0.prStats = true }.render(stats: stats, linkCount: nil),
            "\n TCPInterface[Server on 0.0.0.0:4242]\n"
          + "    Status    : Up\n"
          + "    Mode      : Full\n"
          + "    Rate      : 10.00 Mbps\n"
          + "    Path Rqs. : 1.2 Hz↑     \n"
          + "                0.4 Hz↓     \n"
          + "    Traffic   : ↑1.20 MB    0 bps\n"
          + "                ↓3.40 MB    0 bps\n\n")
    }

    // MARK: - Column padding

    func testColumnsArePaddedInCharactersNotBytes() {
        let stats = Self.top([Self.baseInterface([
            ("clients", .int(4)),
            ("incoming_announce_frequency", .double(1.0)),
            ("outgoing_announce_frequency", .double(3.0)),
            ("incoming_pr_frequency", .double(0.4)),
            ("outgoing_pr_frequency", .double(1.2)),
        ])])
        let lines = Self.renderer { $0.announceStats = true; $0.prStats = true }
            .render(stats: stats, linkCount: nil)
            .components(separatedBy: "\n")

        // "↑1.20 MB" is 8 characters but 10 UTF-8 bytes; measuring in bytes would
        // over-pad every arrow-prefixed column by two.
        XCTAssertEqual("↑1.20 MB".count, 8)
        XCTAssertEqual("↑1.20 MB".utf8.count, 10)

        // Every one of the six padded strings must come out at exactly mlen = 10 here.
        func column(_ prefix: String) -> String {
            let line = lines.first { $0.hasPrefix(prefix) }!
            return String(line.dropFirst(prefix.count).prefix(10))
        }
        for (prefix, expected) in [("    Path Rqs. : ", "↑1.2 Hz   "),
                                   ("    Announces : ", "3.0 Hz↑   "),
                                   ("    Traffic   : ", "↑1.20 MB  ")] {
            XCTAssertEqual(column(prefix), expected)
            XCTAssertEqual(column(prefix).count, RNStatusApp.minimumColumnWidth)
        }
    }

    // MARK: - Shared Instance

    func testSharedInstanceServingPluralisation() {
        func serving(_ clients: Int64) -> String {
            let stats = Self.top([Self.baseInterface([
                ("name", .string("Shared Instance[37428]")),
                ("clients", .int(clients)),
                ("type", .string("LocalServerInterface")),
            ])])
            return Self.renderer().render(stats: stats, linkCount: nil)
        }
        // Python: cnum = max(clients-1, 0) — rnstatus subtracts its own attachment.
        XCTAssertTrue(serving(4).contains("    Serving   : 3 programs\n"))
        XCTAssertTrue(serving(2).contains("    Serving   : 1 program\n"))
        XCTAssertTrue(serving(0).contains("    Serving   : 0 programs\n"))
    }

    func testSharedInstanceSubtractsItsOwnAnnounceShare() {
        let stats = Self.top([Self.baseInterface([
            ("name", .string("Shared Instance[37428]")),
            ("clients", .int(4)),
            ("type", .string("LocalServerInterface")),
            ("incoming_announce_frequency", .double(0.0)),
            ("outgoing_announce_frequency", .double(4.0)),
        ])])
        // oan = 4.0 - 4.0/4 = 3.0, but pc_str divides the RAW 4.0 by 4 → 1.0 Hz/c.
        XCTAssertEqual(Self.renderer { $0.announceStats = true }.render(stats: stats, linkCount: nil),
            "\n Shared Instance[37428]\n"
          + "    Status    : Up\n"
          + "    Serving   : 3 programs\n"
          + "    Rate      : 10.00 Mbps\n"
          + "    Announces : 3.0 Hz↑     1.0 Hz/c\n"
          + "                0 Hz  ↓    \n"
          + "    Traffic   : ↑1.20 MB    0 bps\n"
          + "                ↓3.40 MB    0 bps\n\n")
    }

    /// Python mutates the loop-local `clients` in the announce block; the path-request
    /// block then reuses the peers-derived count but resets `cspec` to "c".
    func testPeersFallbackLeaksIntoThePathRequestBlock() {
        let stats = Self.top([Self.baseInterface([
            ("name", .string("WeaveInterface[w]")),
            ("clients", .nil),
            ("incoming_announce_frequency", .double(1.0)),
            ("outgoing_announce_frequency", .double(2.5)),
            ("incoming_pr_frequency", .double(0.5)),
            ("outgoing_pr_frequency", .double(1.0)),
            ("peers", .int(5)),
        ])])
        XCTAssertEqual(Self.renderer { $0.announceStats = true; $0.prStats = true }
                        .render(stats: stats, linkCount: nil),
            "\n WeaveInterface[w]\n"
          + "    Status    : Up\n"
          + "    Mode      : Full\n"
          + "    Rate      : 10.00 Mbps\n"
          + "    Peers     : 5 reachable\n"
          + "    Path Rqs. : ↑1.0 Hz     0.2 Hz/c\n"   // count 5 reused, cspec back to "c"
          + "                ↓0.5 Hz     \n"
          + "    Announces : 2.5 Hz↑     0.5 Hz/p\n"   // cspec "p" here
          + "                1.0 Hz↓    \n"
          + "    Traffic   : ↑1.20 MB    0 bps\n"
          + "                ↓3.40 MB    0 bps\n\n")
    }

    // MARK: - Mirrored Python bugs

    func testCpuTempNilPrintsTheCpuLoadLabel() {
        // PYTHON BUG mirrored: rnstatus.py:501 prints "CPU load" in the cpu_temp nil branch.
        let stats = Self.top([Self.baseInterface([("cpu_temp", .nil)])])
        XCTAssertTrue(Self.renderer().render(stats: stats, linkCount: nil)
                        .contains("    CPU load  : Unknown\n"))
        XCTAssertFalse(Self.renderer().render(stats: stats, linkCount: nil).contains("CPU temp"))
    }

    func testHostTelemetryLines() {
        let stats = Self.top([Self.baseInterface([
            ("cpu_temp", .int(41)), ("cpu_load", .int(12)), ("mem_load", .int(38)),
        ])])
        let rendered = Self.renderer().render(stats: stats, linkCount: nil)
        XCTAssertTrue(rendered.contains("    CPU load  : 12 %\n"))
        XCTAssertTrue(rendered.contains("    CPU temp  : 41°C\n"))
        XCTAssertTrue(rendered.contains("    Mem usage : 38 %\n"))
    }

    func testMemLoadIsGatedOnCpuLoad() {
        // PYTHON BUG mirrored: rnstatus.py:504 tests ifstat["cpu_load"], not ["mem_load"].
        let stats = Self.top([Self.baseInterface([("mem_load", .int(38)), ("cpu_load", .nil)])])
        let rendered = Self.renderer().render(stats: stats, linkCount: nil)
        XCTAssertTrue(rendered.contains("    CPU load  : Unknown\n"))
        XCTAssertTrue(rendered.contains("    Mem usage : Unknown\n"))
    }

    func testMemLoadWithoutCpuLoadDegradesInsteadOfCrashing() {
        // DELIBERATE DIVERGENCE: Python raises an uncaught KeyError here and aborts the
        // whole run; Swift treats the absent key as nil and prints "Unknown".
        let stats = Self.top([Self.baseInterface([("mem_load", .int(38))])])
        XCTAssertTrue(Self.renderer().render(stats: stats, linkCount: nil)
                        .contains("    Mem usage : Unknown\n"))
    }

    // MARK: - Noise floor / interference

    func testNoiseFloorVariants() {
        func render(_ overrides: [(String, MsgPack.Value)]) -> String {
            Self.renderer().render(stats: Self.top([Self.baseInterface(overrides)]), linkCount: nil)
        }
        // (a) noise_floor present, interference absent
        XCTAssertTrue(render([("noise_floor", .int(-110))]).contains("    Noise Fl. : -110 dBm\n"))
        // (b) interference present-and-nil, no last_ts/last_dbm
        XCTAssertTrue(render([("noise_floor", .int(-110)), ("interference", .nil)])
                        .contains("    Noise Fl. : -110 dBm, no interference\n"))
        // (c) interference reading present
        XCTAssertTrue(render([("noise_floor", .int(-110)), ("interference", .int(-95))])
                        .contains("    Noise Fl. : -110 dBm\n    Intrfrnc. : -95 dBm\n"))
        // (e) noise_floor present-and-nil suppresses the interference line entirely
        let unknown = render([("noise_floor", .nil), ("interference", .int(-95))])
        XCTAssertTrue(unknown.contains("    Noise Fl. : Unknown\n"))
        XCTAssertFalse(unknown.contains("Intrfrnc."))
    }

    /// (d) `interference == 0` is FALSY in Python, so a zero reading takes the "last seen"
    /// branch rather than printing "0 dBm".
    func testZeroInterferenceTakesTheLastSeenBranch() {
        let stats = Self.top([Self.baseInterface([
            ("noise_floor", .int(-110)),
            ("interference", .int(0)),
            ("interference_last_ts", .double(Self.now - 180)),
            ("interference_last_dbm", .int(-95)),
        ])])
        let rendered = Self.renderer().render(stats: stats, linkCount: nil)
        XCTAssertTrue(rendered.contains("    Noise Fl. : -110 dBm\n    Intrfrnc. : -95 dBm 3m ago\n"))
        XCTAssertFalse(rendered.contains("Intrfrnc. : 0 dBm"))

        // …and with no last_ts/last_dbm it falls back to ", no interference".
        let bare = Self.top([Self.baseInterface([("noise_floor", .int(-110)), ("interference", .int(0))])])
        XCTAssertTrue(Self.renderer().render(stats: bare, linkCount: nil)
                        .contains("    Noise Fl. : -110 dBm, no interference\n"))
    }

    // MARK: - Radio / IFAC / I2P

    func testIfacAndRadioLines() {
        let stats = Self.top([Self.baseInterface([
            ("name", .string("RNodeInterface[/dev/tty]")),
            ("type", .string("RNodeInterface")),
            ("ifac_signature", .bytes(Data((0..<64).map { UInt8($0) }))),
            ("ifac_size", .int(16)),
            ("ifac_netname", .string("testnet")),
            ("autoconnect_source", .string("0196e8bac082854147ba0bec49cb5926")),
            ("airtime_short", .double(0.35)), ("airtime_long", .double(0.12)),
            ("channel_load_short", .double(1.2)), ("channel_load_long", .double(0.8)),
            ("battery_percent", .int(87)), ("battery_state", .string("Discharging")),
            ("bitrate", .int(9600)), ("mode", .int(4)),
        ])])
        XCTAssertEqual(Self.renderer().render(stats: stats, linkCount: nil),
            "\n RNodeInterface[/dev/tty]\n"
          + "    Source    : Auto-connect via <0196e8bac082854147ba0bec49cb5926>\n"
          + "    Network   : testnet\n"
          + "    Status    : Up\n"
          + "    Mode      : Roaming\n"
          + "    Rate      : 9.60 kbps\n"          // lowercase k — speed_str, not prettyspeed
          + "    Battery   : 87% (Discharging)\n"
          + "    Airtime   : 0.35% (15s), 0.12% (1h)\n"
          + "    Ch. Load  : 1.2% (15s), 0.8% (1h)\n"
          + "    Access    : 128-bit IFAC by <…3b3c3d3e3f>\n"
          + "    Traffic   : ↑1.20 MB    0 bps\n"
          + "                ↓3.40 MB    0 bps\n\n")
    }

    func testWeaveAndI2PLines() {
        let stats = Self.top([Self.baseInterface([
            ("name", .string("I2PInterface[i2p]")),
            ("type", .string("I2PInterface")),
            ("clients", .int(1)),
            ("i2p_connectable", .bool(true)),
            ("i2p_b32", .string("abcdef.b32.i2p")),
            ("tunnelstate", .string("Tunnel Active")),
            ("switch_id", .string("aa:bb:cc")),
            ("endpoint_id", .nil),
            ("via_switch_id", .string("dd:ee")),
            ("peers", .int(3)),
        ])])
        XCTAssertEqual(Self.renderer().render(stats: stats, linkCount: nil),
            "\n I2PInterface[i2p]\n"
          + "    Status    : Up\n"
          + "    Peers     : 1 connected I2P endpoint\n"
          + "    Mode      : Full\n"
          + "    Rate      : 10.00 Mbps\n"
          + "    Switch ID : aa:bb:cc\n"
          + "    Endpoint  : Unknown\n"          // present-but-nil → "Unknown"
          + "    Via       : dd:ee\n"
          + "    Peers     : 3 reachable\n"      // yes, a second "Peers" line — Python too
          + "    I2P       : Tunnel Active\n"
          + "    I2P B32   : abcdef.b32.i2p\n"
          + "    Traffic   : ↑1.20 MB    0 bps\n"
          + "                ↓3.40 MB    0 bps\n\n")
    }

    func testBlockedIPsRideOnTheClientsLine() {
        let stats = Self.top([Self.baseInterface([("clients", .int(7)), ("blocked_ips", .int(3))])])
        let rendered = Self.renderer().render(stats: stats, linkCount: nil)
        // Python always pluralises: `" IP"+"s"`.
        XCTAssertTrue(rendered.contains("    Clients   : 7\n    Blocked   : 3 IPs\n"))

        // blocked_ips == 0 suppresses the line entirely.
        let none = Self.top([Self.baseInterface([("clients", .int(7)), ("blocked_ips", .int(0))])])
        XCTAssertFalse(Self.renderer().render(stats: none, linkCount: nil).contains("Blocked"))
    }

    // MARK: - Announce rate suffix, queue and bursts

    func testAnnounceRateSuffixVariants() {
        func render(_ target: MsgPack.Value, _ penalty: MsgPack.Value, _ grace: MsgPack.Value,
                    announceStats: Bool = true) -> String {
            let stats = Self.top([Self.baseInterface([
                ("announce_rate_target", target),
                ("announce_rate_penalty", penalty),
                ("announce_rate_grace", grace),
                ("incoming_announce_frequency", .double(1.0)),
                ("outgoing_announce_frequency", .double(1.0)),
            ])])
            return Self.renderer { $0.announceStats = announceStats }.render(stats: stats, linkCount: nil)
        }
        XCTAssertTrue(render(.int(60), .int(30), .int(5)).contains("(t:1m/p:30s/g:5)"))
        // grace 0 is falsy → drops the /g: component
        XCTAssertTrue(render(.int(60), .int(30), .int(0)).contains("(t:1m/p:30s)"))
        // penalty 0 is compared against None, so it stays
        XCTAssertTrue(render(.int(60), .int(0), .int(0)).contains("(t:1m/p:0s)"))
        // penalty nil → target only
        XCTAssertTrue(render(.int(60), .nil, .int(5)).contains("(t:1m)"))
        // target 0 / nil → no suffix at all
        XCTAssertFalse(render(.int(0), .int(30), .int(5)).contains("(t:"))
        XCTAssertFalse(render(.nil, .int(30), .int(5)).contains("(t:"))
        // and the keys are not even read without -A
        XCTAssertFalse(render(.int(60), .int(30), .int(5), announceStats: false).contains("(t:"))
    }

    func testQueuedAndHeldAnnounces() {
        let stats = Self.top([Self.baseInterface([
            ("announce_queue", .int(3)), ("held_announces", .int(1)),
            ("announce_rate_target", .int(60)), ("announce_rate_penalty", .int(30)),
            ("announce_rate_grace", .int(5)),
            ("incoming_announce_frequency", .double(1.0)),
            ("outgoing_announce_frequency", .double(1.0)),
        ])])
        XCTAssertEqual(Self.renderer { $0.announceStats = true }.render(stats: stats, linkCount: nil),
            "\n TCPInterface[Server on 0.0.0.0:4242]\n"
          + "    Status    : Up\n"
          + "    Mode      : Full\n"
          + "    Rate      : 10.00 Mbps\n"
          + "    Queued    : 3 announces\n"
          + "    Held      : 1 announce\n"
          + "    Announces : 1.0 Hz↑     \n"
          + "                1.0 Hz↓    (t:1m/p:30s/g:5)\n"
          + "    Traffic   : ↑1.20 MB    0 bps\n"
          + "                ↓3.40 MB    0 bps\n\n")

        // Zero counts suppress both lines, and -A off suppresses them regardless.
        let zero = Self.top([Self.baseInterface([("announce_queue", .int(0)), ("held_announces", .int(0))])])
        XCTAssertFalse(Self.renderer { $0.announceStats = true }
                        .render(stats: zero, linkCount: nil).contains("Queued"))
    }

    func testBurstStrings() {
        let stats = Self.top([Self.baseInterface([
            ("burst_active", .bool(true)), ("burst_activated", .double(Self.now - 8)),
            ("pr_burst_active", .bool(true)), ("pr_burst_activated", .double(Self.now - 12)),
            ("incoming_announce_frequency", .double(1.0)),
            ("outgoing_announce_frequency", .double(1.0)),
            ("incoming_pr_frequency", .double(1.0)),
            ("outgoing_pr_frequency", .double(1.0)),
        ])])
        // `time.time() - burst_activated` is a float in Python, so the seconds render as
        // "8.0s" rather than "8s". burst_str has a LEADING space; pburst_str does not.
        XCTAssertEqual(Self.renderer { $0.announceStats = true; $0.prStats = true }
                        .render(stats: stats, linkCount: nil),
            "\n TCPInterface[Server on 0.0.0.0:4242]\n"
          + "    Status    : Up\n"
          + "    Mode      : Full\n"
          + "    Rate      : 10.00 Mbps\n"
          + "    Path Rqs. : ↑1.0 Hz     \n"
          + "                ↓1.0 Hz     burst for 12.0s\n"
          + "    Announces : 1.0 Hz↑     \n"
          + "                1.0 Hz↓     burst for 8.0s\n"
          + "    Traffic   : ↑1.20 MB    0 bps\n"
          + "                ↓3.40 MB    0 bps\n\n")
    }

    // MARK: - Footer

    func testTransportFooterWithLinkTable() {
        let stats = Self.top([Self.baseInterface()], [
            ("transport_id", .bytes(Data(repeating: 0xDE, count: 4) + Data())),
            ("network_id", .nil),
            ("transport_uptime", .double(90.0)),
            ("probe_responder", .nil),
        ])
        let rendered = Self.renderer { $0.linkStats = true }.render(stats: stats, linkCount: 1)
        // Python renders the float uptime with a float seconds component.
        XCTAssertTrue(rendered.hasSuffix("\n Transport Instance <dededede> running\n"
                                       + " Uptime is 1m and 30.0s, 1 entry in link table\n\n"))
    }

    func testFullTransportFooter() {
        let stats = Self.top([Self.baseInterface()], [
            ("transport_id", .bytes(Data(repeating: 0xDE, count: 16))),
            ("network_id", .bytes(Data(repeating: 0xCA, count: 16))),
            ("transport_uptime", .double(183852.0)),
            ("probe_responder", .bytes(Data(repeating: 0xBA, count: 16))),
        ])
        let rendered = Self.renderer { $0.linkStats = true }.render(stats: stats, linkCount: 12)
        XCTAssertTrue(rendered.hasSuffix(
            "\n Transport Instance <dededededededededededededededede> running\n"
          + " Network Identity   <cacacacacacacacacacacacacacacaca>\n"
          + " Probe responder at <babababababababababababababababa> active\n"
          + " Uptime is 2d, 3h, 4m and 12.0s, 12 entries in link table\n\n"))
    }

    func testTransportWithoutUptimeNeverShowsTheLinkTable() {
        // Python only ever attaches lstr to the "Uptime is …" line.
        let stats = Self.top([Self.baseInterface()], [
            ("transport_id", .bytes(Data(repeating: 0xDE, count: 16))),
        ])
        let rendered = Self.renderer { $0.linkStats = true }.render(stats: stats, linkCount: 12)
        XCTAssertFalse(rendered.contains("link table"))
        XCTAssertTrue(rendered.hasSuffix("running\n\n"))
    }

    func testLinkTableWithoutTransport() {
        let stats = Self.top([Self.baseInterface()])
        XCTAssertTrue(Self.renderer { $0.linkStats = true }.render(stats: stats, linkCount: 12)
                        .hasSuffix("\n 12 entries in link table\n\n"))
        // Without -l neither the count nor the line appears.
        XCTAssertTrue(Self.renderer().render(stats: stats, linkCount: 12)
                        .hasSuffix("                ↓3.40 MB    0 bps\n\n"))
    }

    func testTotalsBlock() {
        let stats = Self.top([Self.baseInterface()])
        // ↓12.34 MB is one character wider than ↑9.99 MB, so the TX line is padded to match.
        XCTAssertTrue(Self.renderer { $0.trafficTotals = true }.render(stats: stats, linkCount: nil)
                        .hasSuffix("\n Totals       : ↑9.99 MB   24.00 Kbps\n"
                                 + "                ↓12.34 MB  48.00 Kbps\n\n"))
    }

    // MARK: - Hide list end to end

    func testHiddenInterfacesAreOmittedUnlessShowAll() {
        let stats = Self.top([
            Self.baseInterface([("name", .string("Shared Instance[37428]")), ("clients", .int(2)),
                                ("type", .string("LocalServerInterface"))]),
            Self.baseInterface([("name", .string("LocalInterface[52000]")),
                                ("type", .string("LocalClientInterface"))]),
            Self.baseInterface([("name", .string("TCPInterface[Client on 1.2.3.4:4242]")),
                                ("type", .string("TCPClientInterface"))]),
        ])
        let defaultRender = Self.renderer().render(stats: stats, linkCount: nil)
        XCTAssertTrue(defaultRender.contains("Shared Instance[37428]"))
        XCTAssertFalse(defaultRender.contains("LocalInterface[52000]"))
        XCTAssertFalse(defaultRender.contains("TCPInterface[Client"))

        let allRender = Self.renderer { $0.showAll = true }.render(stats: stats, linkCount: nil)
        XCTAssertTrue(allRender.contains("LocalInterface[52000]"))
        XCTAssertTrue(allRender.contains("TCPInterface[Client on 1.2.3.4:4242]"))
        // Neither hidden interface gets a Mode line (rnstatus.py:473).
        XCTAssertEqual(allRender.components(separatedBy: "    Mode      : ").count - 1, 0)
    }

    // MARK: - Discovered interfaces

    static func discoveredFixtures() -> [DiscoveredInterfaceInfo] {
        [
            DiscoveredInterfaceInfo(
                type: "BackboneInterface", transport: true, name: "my-backbone",
                received: now - 240, stamp: Data(repeating: 0x11, count: 8), value: 21,
                transportID: String(repeating: "aa", count: 16),
                networkID: String(repeating: "bb", count: 16),
                hops: 2, latitude: 55.67610, longitude: 12.56830, height: 12.0,
                ifacNetname: nil, ifacNetkey: nil, reachableOn: "example.org", port: 4965,
                frequency: nil, bandwidth: nil, sf: nil, cr: nil, modulation: nil, channel: nil,
                configEntry: "[[my-backbone]]\n  type = BackboneInterface\n  enabled = yes",
                discoveryHash: Data(repeating: 0x22, count: 32),
                discovered: now - 300_000, lastHeard: now - 240, heardCount: 4,
                status: "available", statusCode: 1000),
            DiscoveredInterfaceInfo(
                type: "RNodeInterface", transport: false,
                name: "a-very-long-discovered-interface-name",
                received: now - 7200, stamp: Data(repeating: 0x33, count: 8), value: 18,
                transportID: String(repeating: "cc", count: 16),
                networkID: String(repeating: "cc", count: 16),
                hops: 1, latitude: nil, longitude: nil, height: nil,
                ifacNetname: nil, ifacNetkey: nil, reachableOn: nil, port: nil,
                frequency: 867_200_000, bandwidth: 125_000, sf: 8, cr: 5,
                modulation: nil, channel: nil,
                configEntry: "[[rnode]]\n  type = RNodeInterface",
                discoveryHash: Data(repeating: 0x44, count: 32),
                discovered: now - 90_000, lastHeard: now - 7200, heardCount: 2,
                status: "unknown", statusCode: 100),
            DiscoveredInterfaceInfo(
                type: "TCPServerInterface", transport: true, name: "stale-one",
                received: now - 300_000, stamp: Data(repeating: 0x55, count: 8), value: 14,
                transportID: String(repeating: "dd", count: 16),
                networkID: String(repeating: "dd", count: 16),
                hops: 3, latitude: -35.2717, longitude: 138.55425, height: nil,
                ifacNetname: nil, ifacNetkey: nil, reachableOn: "1.2.3.4", port: 4242,
                frequency: nil, bandwidth: nil, sf: nil, cr: nil, modulation: nil, channel: nil,
                configEntry: "[[stale]]\n  type = TCPClientInterface",
                discoveryHash: Data(repeating: 0x66, count: 32),
                discovered: now - 900_000, lastHeard: now - 300_000, heardCount: 1,
                status: "stale", statusCode: 0),
        ]
    }

    func testDiscoveredTable() {
        XCTAssertEqual(Self.renderer().renderDiscoveredTable(Self.discoveredFixtures()),
            "\n"
          + "Name                      Type         Status       Last Heard   Value    Location       \n"
          + "-----------------------------------------------------------------------------------------\n"
          + "my-backbone               Backbone     ✓ Available  4m ago       21       55.6761, 12.5683\n"
          + "a-very-long-discovered-i… RNode        ? Unknown    2h ago       18       N/A            \n"
          + "stale-one                 TCPServer    × Stale      3d ago       14       -35.2717, 138.5542\n")
    }

    func testDiscoveredTableFilterKeepsTheHeader() {
        // A filter that matches nothing still prints the header and the rule.
        let rendered = Self.renderer { $0.nameFilter = "RNODE" }
            .renderDiscoveredTable(Self.discoveredFixtures())
        XCTAssertEqual(rendered.components(separatedBy: "\n").count, 4)   // blank, header, rule, ""
        XCTAssertTrue(rendered.hasSuffix(String(repeating: "-", count: 89) + "\n"))

        // …and a matching filter keeps only that row, in the caller-supplied order.
        let matched = Self.renderer { $0.nameFilter = "STALE" }
            .renderDiscoveredTable(Self.discoveredFixtures())
        XCTAssertTrue(matched.contains("stale-one"))
        XCTAssertFalse(matched.contains("my-backbone"))
    }

    func testDiscoveredTableNeverTruncatesTypeAndCountsCharacters() {
        var info = Self.discoveredFixtures()[0]
        info.type = "SomethingVeryLongInterface"       // → "SomethingVeryLong", 17 chars
        info.name = "x"
        let row = Self.renderer().renderDiscoveredTable([info])
            .components(separatedBy: "\n")[3]
        // Python's `{:<12}` pads but never truncates, so the 17-character type pushes the
        // rest of the row right instead of being clipped.
        XCTAssertTrue(row.contains("SomethingVeryLong ✓ Available"), row)
        // The ✓/×/… markers are single characters, so the columns line up.
        XCTAssertEqual("✓ Available".count, 11)
        XCTAssertEqual("a-very-long-discovered-i…".count, 25)
    }

    func testDiscoveredOrderIsPreserved() {
        // listDiscoveredInterfaces has already sorted descending on
        // (statusCode, value, lastHeard); the renderer must not re-sort.
        let reversed = Array(Self.discoveredFixtures().reversed())
        let rows = Self.renderer().renderDiscoveredTable(reversed)
            .components(separatedBy: "\n").dropFirst(3)
        XCTAssertTrue(rows.first!.hasPrefix("stale-one"), rows.first!)
    }

    func testDiscoveredDetails() {
        XCTAssertEqual(Self.renderer().renderDiscoveredDetails(Self.discoveredFixtures()),
            "\n"
          + "Network   ID : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n"
          + "Transport ID : aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"
          + "Name         : my-backbone\n"
          + "Type         : BackboneInterface\n"
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
          + "\n================================\n\n"
          + "Transport ID : cccccccccccccccccccccccccccccccc\n"
          + "Name         : a-very-long-discovered-interface-name\n"
          + "Type         : RNodeInterface\n"
          + "Status       : Unknown\n"
          + "Transport    : Disabled\n"
          + "Distance     : 1 hop\n"
          + "Discovered   : 1d and 1h ago\n"
          + "Last Heard   : 2h ago\n"
          + "Location     : Unknown\n"
          + "Frequency    : 867,200,000 Hz\n"
          + "Bandwidth    : 125,000 Hz\n"
          + "Sprd. Factor : 8\n"
          + "Coding Rate  : 5\n"
          + "Stamp Value  : 18\n"
          + "\nConfiguration Entry:\n"
          + "  [[rnode]]\n"
          + "    type = RNodeInterface\n"
          + "\n================================\n\n"
          + "Transport ID : dddddddddddddddddddddddddddddddd\n"
          + "Name         : stale-one\n"
          + "Type         : TCPServerInterface\n"
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
          + "    type = TCPClientInterface\n")
    }

    func testDiscoveredDetailsOmitsNetworkIDWhenItMatchesTheTransportID() {
        // Python: network is set only when transport_id != network_id (a string compare on
        // undelimited hex), and it prints raw hex with no <> wrapper.
        let rendered = Self.renderer().renderDiscoveredDetails([Self.discoveredFixtures()[1]])
        XCTAssertFalse(rendered.contains("Network   ID"))
        XCTAssertTrue(rendered.contains("Transport ID : cccccccccccccccccccccccccccccccc\n"))
        XCTAssertFalse(rendered.contains("<cc"))
    }

    func testDiscoveredDetailsWithoutConfigEntryStopsMidEntry() {
        // Python raises KeyError there and abandons the rest with everything already printed.
        var info = Self.discoveredFixtures()[0]
        info.configEntry = nil
        let rendered = Self.renderer().renderDiscoveredDetails([info])
        XCTAssertTrue(rendered.hasSuffix("Stamp Value  : 21\n"))
        XCTAssertFalse(rendered.contains("Configuration Entry"))
    }

    // MARK: - Formatting helpers

    func testPythonStrMatchesPythonsStr() {
        XCTAssertEqual(RNStatusRenderer.pythonStr(.int(41)), "41")
        XCTAssertEqual(RNStatusRenderer.pythonStr(.double(1.2)), "1.2")
        XCTAssertEqual(RNStatusRenderer.pythonStr(.double(12.0)), "12.0")
        XCTAssertEqual(RNStatusRenderer.pythonStr(.nil), "None")
        XCTAssertEqual(RNStatusRenderer.pythonStr(.bool(true)), "True")
        XCTAssertEqual(RNStatusRenderer.pythonStr(.string("x")), "x")
    }

    func testPrettytimeKeepsThePythonIntFloatDistinction() {
        // Python: round(time, 2) preserves the argument's type.
        XCTAssertEqual(RNStatusRenderer.prettytime(12, isFloat: false), "12s")
        XCTAssertEqual(RNStatusRenderer.prettytime(12, isFloat: true), "12.0s")
        XCTAssertEqual(RNStatusRenderer.prettytime(90, isFloat: true), "1m and 30.0s")
        XCTAssertEqual(RNStatusRenderer.prettytime(90, isFloat: false), "1m and 30s")
        XCTAssertEqual(RNStatusRenderer.prettytime(183852, isFloat: true), "2d, 3h, 4m and 12.0s")
        XCTAssertEqual(RNStatusRenderer.prettytime(0, isFloat: true), "0s")
        XCTAssertEqual(RNStatusRenderer.prettytime(-90, isFloat: false), "-1m and 30s")
        // compact truncates to int and shows at most two components.
        XCTAssertEqual(RNStatusRenderer.prettytime(300_000, isFloat: true, compact: true), "3d and 11h")
    }

    func testPythonRoundMatchesPythonsRound() {
        // Python: round(3.07455, 4) == 3.0745 — rounds the exact decimal, half to even.
        XCTAssertEqual(RNStatusRenderer.pythonRound(3.07455, 4), "3.0745")
        XCTAssertEqual(RNStatusRenderer.pythonRound(138.55425, 4), "138.5542")
        XCTAssertEqual(RNStatusRenderer.pythonRound(55.0, 4), "55.0")
        XCTAssertEqual(RNStatusRenderer.pythonRound(-35.2717, 4), "-35.2717")
        XCTAssertEqual(RNStatusRenderer.pythonRound(43.0, 4), "43.0")
    }

    func testThousandsSeparators() {
        // Python f"{867200000:,}" — and the integral form must not leak a ".0".
        XCTAssertEqual(RNStatusRenderer.thousands(867_200_000), "867,200,000")
        XCTAssertEqual(RNStatusRenderer.thousands(125_000), "125,000")
        XCTAssertEqual(RNStatusRenderer.thousands(999), "999")
        XCTAssertEqual(RNStatusRenderer.thousands(-1_234_567), "-1,234,567")
    }

    func testPadNeverTruncates() {
        XCTAssertEqual(RNStatusRenderer.pad("ab", 5), "ab   ")
        XCTAssertEqual(RNStatusRenderer.pad("abcdefgh", 5), "abcdefgh")
        XCTAssertEqual(RNStatusRenderer.pad("✓ Available", 12), "✓ Available ")
    }
}
