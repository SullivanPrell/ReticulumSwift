import XCTest
@testable import ReticulumSwift

/// Decoding, presence-vs-nil semantics, sorting and the visibility filters `rnstatus`
/// applies to `get_interface_stats()`.
///
/// Python reference: `RNS/Utilities/rnstatus.py:361-413` and `RNS/Reticulum.py:1314-1468`.
final class RNStatusStatsTests: XCTestCase {

    // MARK: - Fixtures

    /// One interface map. Only the keys a test cares about are supplied, which is exactly
    /// how Python's builder behaves — most fields are `hasattr`-gated.
    static func interface(_ pairs: [(String, MsgPack.Value)]) -> MsgPack.Value {
        .map(pairs.map { (.string($0.0), $0.1) })
    }

    static func stats(_ interfaces: [MsgPack.Value],
                      extra: [(String, MsgPack.Value)] = []) -> MsgPack.Value {
        var pairs: [(MsgPack.Value, MsgPack.Value)] = [
            (.string("interfaces"), .array(interfaces)),
            (.string("rxb"), .int(0)),
            (.string("txb"), .int(0)),
            (.string("rxs"), .double(0)),
            (.string("txs"), .double(0)),
        ]
        for (key, value) in extra { pairs.append((.string(key), value)) }
        pairs.append((.string("rss"), .nil))
        return .map(pairs)
    }

    static func named(_ name: String, _ extra: [(String, MsgPack.Value)] = []) -> RNStatusInterfaceStats {
        RNStatusInterfaceStats(interface([("name", .string(name))] + extra))!
    }

    // MARK: - Decode

    func testDecodeRejectsNonMapAndMissingInterfaces() {
        XCTAssertNil(RNStatusStats(.array([])))
        XCTAssertNil(RNStatusStats(.map([(.string("rxb"), .int(1))])))
        XCTAssertNotNil(RNStatusStats(Self.stats([])))
    }

    func testTopLevelFields() {
        let value = Self.stats([], extra: [
            ("transport_id",     .bytes(Data(repeating: 0xAB, count: 16))),
            ("network_id",       .nil),
            ("transport_uptime", .double(3600)),
            ("probe_responder",  .bytes(Data(repeating: 0xCD, count: 16))),
        ])
        let stats = RNStatusStats(value)!
        XCTAssertTrue(stats.hasTransportID)
        XCTAssertEqual(stats.transportID, Data(repeating: 0xAB, count: 16))
        XCTAssertNil(stats.networkID)                       // present but nil
        XCTAssertEqual(stats.transportUptime, 3600)
        XCTAssertEqual(stats.probeResponder, Data(repeating: 0xCD, count: 16))
        // Python: `"transport_id" in stats and stats["transport_id"] != None` — an absent
        // key and a nil value must both read as "no transport".
        XCTAssertFalse(RNStatusStats(Self.stats([]))!.hasTransportID)
    }

    /// The single most load-bearing decode property: `if "key" in ifstat` must be
    /// distinguishable from `ifstat["key"] != None`, because they select different output.
    func testPresenceIsDistinguishableFromNil() {
        let keys = ["noise_floor", "cpu_load", "cpu_temp", "mem_load", "interference",
                    "switch_id", "endpoint_id", "via_switch_id", "announce_queue", "blocked_ips"]
        for key in keys {
            let present = Self.named("X", [(key, .nil)])
            XCTAssertTrue(present.has(key), "\(key) present-but-nil should read as present")
            XCTAssertNil(present.raw(key)?.asInt)
            XCTAssertTrue(present.raw(key)!.isNil)

            let absent = Self.named("X")
            XCTAssertFalse(absent.has(key), "\(key) should read as absent")
            XCTAssertNil(absent.raw(key))
        }
    }

    func testModeDescription() {
        // Python: rnstatus.py:421-427. Anything unrecognised — including MODE_FULL — is "Full".
        let cases: [(Int64, String)] = [
            (0x01, "Full"), (0x02, "Point-to-Point"), (0x03, "Access Point"),
            (0x04, "Roaming"), (0x05, "Boundary"), (0x06, "Gateway"),
            (0x07, "Internal"), (0x42, "Full"),
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(Self.named("X", [("mode", .int(raw))]).modeDescription, expected)
        }
    }

    // MARK: - Hide list

    func testDefaultHiddenPrefixes() {
        let hidden = ["LocalInterface[37428]",
                      "TCPInterface[Client on 1.2.3.4:4242]",
                      "BackboneInterface[Client on x]",
                      "AutoInterfacePeer[x]",
                      "WeaveInterfacePeer[x]",
                      "I2PInterfacePeer[Connected peer x]"]
        for name in hidden {
            XCTAssertTrue(RNStatusStats.shouldHide(Self.named(name), showAll: false), name)
            XCTAssertFalse(RNStatusStats.shouldHide(Self.named(name), showAll: true), "\(name) under -a")
        }
    }

    func testAlwaysVisibleInterfaces() {
        for name in ["Shared Instance[37428]", "TCPInterface[Server on 0.0.0.0:4242]",
                     "BackboneInterface[Slivovica/1.2.3.4:4440]"] {
            XCTAssertFalse(RNStatusStats.shouldHide(Self.named(name), showAll: false), name)
        }
    }

    func testNonConnectableI2PIsHiddenEvenUnderShowAll() {
        // Python re-applies this gate outside the `dispall or …` guard (rnstatus.py:403).
        let off = Self.named("I2PInterface[x]", [("i2p_connectable", .bool(false))])
        XCTAssertTrue(RNStatusStats.shouldHide(off, showAll: false))
        XCTAssertTrue(RNStatusStats.shouldHide(off, showAll: true))

        let on = Self.named("I2PInterface[x]", [("i2p_connectable", .bool(true))])
        XCTAssertFalse(RNStatusStats.shouldHide(on, showAll: false))

        // The guard requires the key to be PRESENT; absent means visible.
        XCTAssertFalse(RNStatusStats.shouldHide(Self.named("I2PInterface[x]"), showAll: false))
    }

    // MARK: - Name / burst filters

    func testNameFilterIsCaseInsensitiveSubstring() {
        let iface = Self.named("BackboneInterface[Slivovica/1.2.3.4:4440]")
        XCTAssertTrue(RNStatusStats.passesFilters(iface, nameFilter: nil, burstFilter: false))
        XCTAssertTrue(RNStatusStats.passesFilters(iface, nameFilter: "sliv", burstFilter: false))
        XCTAssertTrue(RNStatusStats.passesFilters(iface, nameFilter: "SLIVOVICA", burstFilter: false))
        XCTAssertFalse(RNStatusStats.passesFilters(iface, nameFilter: "rnode", burstFilter: false))
        // Python: `not name_filter` is true for the empty string.
        XCTAssertTrue(RNStatusStats.passesFilters(iface, nameFilter: "", burstFilter: false))
    }

    func testBurstFilterRequiresBothKeys() {
        // Python: burst_act needs BOTH "burst_active" and "pr_burst_active" present before
        // either value is consulted (rnstatus.py:409).
        let bursting = Self.named("X", [("burst_active", .bool(true)), ("pr_burst_active", .bool(false))])
        XCTAssertTrue(RNStatusStats.passesFilters(bursting, nameFilter: nil, burstFilter: true))

        let prBursting = Self.named("X", [("burst_active", .bool(false)), ("pr_burst_active", .bool(true))])
        XCTAssertTrue(RNStatusStats.passesFilters(prBursting, nameFilter: nil, burstFilter: true))

        let quiet = Self.named("X", [("burst_active", .bool(false)), ("pr_burst_active", .bool(false))])
        XCTAssertFalse(RNStatusStats.passesFilters(quiet, nameFilter: nil, burstFilter: true))

        // Only one key present → burst_act is false regardless of its value.
        let partial = Self.named("X", [("burst_active", .bool(true))])
        XCTAssertFalse(RNStatusStats.passesFilters(partial, nameFilter: nil, burstFilter: true))
        // …but the name filter still rescues it (burst_act OR nfilt).
        XCTAssertTrue(RNStatusStats.passesFilters(partial, nameFilter: "x", burstFilter: true))
    }

    func testBurstFilterWithEmptyNameFilterDoesNotMatch() {
        // Python: `nfilt = … if name_filter else False` — the empty string is falsy here,
        // unlike in the plain name-filter branch.
        let quiet = Self.named("X", [("burst_active", .bool(false)), ("pr_burst_active", .bool(false))])
        XCTAssertFalse(RNStatusStats.passesFilters(quiet, nameFilter: "", burstFilter: true))
    }

    // MARK: - Sorting

    private func fixture() -> RNStatusStats {
        RNStatusStats(Self.stats([
            Self.interface([("name", .string("A")), ("bitrate", .int(100)), ("rxb", .int(10)), ("txb", .int(1)),
                            ("rxs", .double(3)), ("txs", .double(9)), ("held_announces", .int(2)),
                            ("incoming_announce_frequency", .double(1)), ("outgoing_announce_frequency", .double(0)),
                            ("incoming_pr_frequency", .double(5)), ("outgoing_pr_frequency", .double(2))]),
            Self.interface([("name", .string("B")), ("bitrate", .int(300)), ("rxb", .int(1)), ("txb", .int(30)),
                            ("rxs", .double(9)), ("txs", .double(3)), ("held_announces", .int(0)),
                            ("incoming_announce_frequency", .double(0)), ("outgoing_announce_frequency", .double(4)),
                            ("incoming_pr_frequency", .double(1)), ("outgoing_pr_frequency", .double(7))]),
            Self.interface([("name", .string("C")), ("bitrate", .int(200)), ("rxb", .int(5)), ("txb", .int(5)),
                            ("rxs", .double(6)), ("txs", .double(6)), ("held_announces", .int(1)),
                            ("incoming_announce_frequency", .double(2)), ("outgoing_announce_frequency", .double(0)),
                            ("incoming_pr_frequency", .double(3)), ("outgoing_pr_frequency", .double(0))]),
        ]))!
    }

    private func names(_ sort: RNStatusApp.Sort?, reverse: Bool = false) -> [String] {
        fixture().sortedInterfaces(by: sort, reverse: reverse).map(\.name)
    }

    func testEverySortTokenOrdersDescendingByDefault() {
        // Python: `reverse = not sort_reverse` — descending unless -r is given.
        XCTAssertEqual(names(.rate),      ["B", "C", "A"])
        XCTAssertEqual(names(.bitrate),   ["B", "C", "A"])
        XCTAssertEqual(names(.rx),        ["A", "C", "B"])
        XCTAssertEqual(names(.tx),        ["B", "C", "A"])
        XCTAssertEqual(names(.rxs),       ["B", "C", "A"])
        XCTAssertEqual(names(.txs),       ["A", "C", "B"])
        XCTAssertEqual(names(.traffic),   ["B", "A", "C"])   // 31, 11, 10 → B, A, C
        XCTAssertEqual(names(.announces), ["B", "C", "A"])   // 4, 2, 1
        XCTAssertEqual(names(.announce),  ["B", "C", "A"])
        XCTAssertEqual(names(.arx),       ["C", "A", "B"])
        XCTAssertEqual(names(.atx),       ["B", "A", "C"])   // 4, 0, 0 → stable on the tie
        XCTAssertEqual(names(.prx),       ["A", "C", "B"])
        XCTAssertEqual(names(.ptx),       ["B", "A", "C"])
        XCTAssertEqual(names(.held),      ["A", "C", "B"])
    }

    func testReverseFlipsDirection() {
        XCTAssertEqual(names(.rate, reverse: true), ["A", "C", "B"])
        XCTAssertEqual(names(.held, reverse: true), ["B", "C", "A"])
    }

    func testUnknownSortLeavesOrderUntouched() {
        XCTAssertEqual(names(nil), ["A", "B", "C"])
    }

    func testSortIsStableInBothDirections() {
        // Python's list.sort is stable, and reverse=True preserves that stability. Swift's
        // sort gives no such guarantee, so the implementation decorates with the input index.
        let value = Self.stats((0..<4).map { index in
            Self.interface([("name", .string("if\(index)")), ("rxb", .int(7)), ("txb", .int(0))])
        })
        let stats = RNStatusStats(value)!
        XCTAssertEqual(stats.sortedInterfaces(by: .rx, reverse: false).map(\.name),
                       ["if0", "if1", "if2", "if3"])
        XCTAssertEqual(stats.sortedInterfaces(by: .rx, reverse: true).map(\.name),
                       ["if0", "if1", "if2", "if3"])
    }
}
