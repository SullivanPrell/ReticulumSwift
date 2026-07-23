import XCTest
@testable import ReticulumSwift

/// `rnstatus -j` — order-preserving `json.dumps` output and the two bytes→hex passes.
///
/// Python reference: `RNS/Utilities/rnstatus.py:343-359` (stats) and `rnstatus.py:187-193`
/// (discovered interfaces).
final class RNStatusJSONTests: XCTestCase {

    // MARK: - Encoder

    func testSeparatorsAndScalars() {
        // json.dumps defaults: ", " between items, ": " between key and value.
        let value = MsgPack.Value.map([
            (.string("a"), .int(1)),
            (.string("b"), .nil),
            (.string("c"), .bool(true)),
            (.string("d"), .bool(false)),
            (.string("e"), .double(1.5)),
            (.string("f"), .array([.int(1), .int(2)])),
        ])
        XCTAssertEqual(RNStatusJSON.encode(value),
                       "{\"a\": 1, \"b\": null, \"c\": true, \"d\": false, \"e\": 1.5, \"f\": [1, 2]}")
    }

    func testFloatsUsePythonRepr() {
        XCTAssertEqual(RNStatusJSON.encode(.double(0.0)), "0.0")
        XCTAssertEqual(RNStatusJSON.encode(.double(12.0)), "12.0")
        XCTAssertEqual(RNStatusJSON.encode(.double(1699999760.0)), "1699999760.0")
        XCTAssertEqual(RNStatusJSON.encode(.double(0.0009311438115864411)), "0.0009311438115864411")
    }

    func testStringEscaping() {
        // json.dumps with ensure_ascii=True escapes everything above U+007F.
        XCTAssertEqual(RNStatusJSON.encode(.string("a\"b\\c")), "\"a\\\"b\\\\c\"")
        XCTAssertEqual(RNStatusJSON.encode(.string("line\nnext\ttab")), "\"line\\nnext\\ttab\"")
        XCTAssertEqual(RNStatusJSON.encode(.string("µ")), "\"\\u00b5\"")
        XCTAssertEqual(RNStatusJSON.encode(.string("↑")), "\"\\u2191\"")
        XCTAssertEqual(RNStatusJSON.encode(.string("Shared Instance[37428]")),
                       "\"Shared Instance[37428]\"")
    }

    func testKeyOrderIsPreservedWithRssLast() {
        // Python emits `rss` LAST, after the optional transport block (Reticulum.py:1467),
        // and json.dumps preserves dict insertion order — so the position is contractual.
        let value = MsgPack.Value.map([
            (.string("interfaces"), .array([])),
            (.string("rxb"), .int(1)),
            (.string("txb"), .int(2)),
            (.string("rxs"), .double(0)),
            (.string("txs"), .double(0)),
            (.string("transport_id"), .bytes(Data([0xDE, 0xAD]))),
            (.string("network_id"), .nil),
            (.string("transport_uptime"), .double(5)),
            (.string("probe_responder"), .nil),
            (.string("rss"), .nil),
        ])
        let encoded = RNStatusJSON.encode(RNStatusJSON.normaliseStats(value))
        XCTAssertEqual(encoded,
            "{\"interfaces\": [], \"rxb\": 1, \"txb\": 2, \"rxs\": 0.0, \"txs\": 0.0, "
          + "\"transport_id\": \"dead\", \"network_id\": null, \"transport_uptime\": 5.0, "
          + "\"probe_responder\": null, \"rss\": null}")
        XCTAssertTrue(encoded.hasSuffix("\"rss\": null}"))
    }

    func testEncodedOutputParsesAsJSON() throws {
        let value = MsgPack.Value.map([
            (.string("interfaces"), .array([.map([
                (.string("name"), .string("TCPInterface[Server on 0.0.0.0:4242]")),
                (.string("hash"), .bytes(Data(repeating: 0x01, count: 32))),
                (.string("rxb"), .int(3_400_000)),
            ])])),
            (.string("rss"), .nil),
        ])
        let encoded = RNStatusJSON.encode(RNStatusJSON.normaliseStats(value))
        let object = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
        XCTAssertNotNil(object)
        let interfaces = object?["interfaces"] as? [[String: Any]]
        XCTAssertEqual(interfaces?.first?["hash"] as? String, String(repeating: "01", count: 32))
    }

    // MARK: - bytes → hex normalisation

    func testNormaliseStatsConvertsTopLevelAndOneLevelIn() {
        let value = MsgPack.Value.map([
            (.string("interfaces"), .array([.map([
                (.string("hash"), .bytes(Data([0xAA, 0xBB]))),
                (.string("ifac_signature"), .bytes(Data([0x01, 0x02, 0x03]))),
                (.string("parent_interface_hash"), .bytes(Data([0xFF]))),
                (.string("name"), .string("x")),
                // Nested two levels deep: Python's loop does NOT reach this, and
                // json.dumps would raise a TypeError on it.
                (.string("blocked_ip_list"), .array([.bytes(Data([0x09]))])),
            ])])),
            (.string("transport_id"), .bytes(Data([0xDE, 0xAD, 0xBE, 0xEF]))),
            (.string("network_id"), .nil),
            (.string("probe_responder"), .bytes(Data([0xBA, 0xBE]))),
        ])
        guard case .map(let pairs) = RNStatusJSON.normaliseStats(value) else {
            return XCTFail("expected a map")
        }
        let top = Dictionary(uniqueKeysWithValues: pairs.compactMap { key, element in
            key.asString.map { ($0, element) }
        })
        XCTAssertEqual(top["transport_id"]?.asString, "deadbeef")
        XCTAssertEqual(top["probe_responder"]?.asString, "babe")
        XCTAssertTrue(top["network_id"]!.isNil)

        let iface = top["interfaces"]?.asArray?.first?.asDictionary
        XCTAssertEqual(iface?["hash"]?.asString, "aabb")
        XCTAssertEqual(iface?["ifac_signature"]?.asString, "010203")
        XCTAssertEqual(iface?["parent_interface_hash"]?.asString, "ff")
        // Two levels deep is untouched.
        XCTAssertEqual(iface?["blocked_ip_list"]?.asArray?.first, .bytes(Data([0x09])))
    }

    func testNormaliseDiscoveredConvertsStampAndDiscoveryHash() {
        let value = MsgPack.Value.array([.map([
            (.string("stamp"), .bytes(Data(repeating: 0x11, count: 4))),
            (.string("discovery_hash"), .bytes(Data(repeating: 0x22, count: 4))),
            // Already hex STRINGS on disk (Discovery.py:323-324) — must stay strings.
            (.string("transport_id"), .string("aabb")),
            (.string("network_id"), .string("ccdd")),
        ])])
        let entry = RNStatusJSON.normaliseDiscovered(value).asArray?.first?.asDictionary
        XCTAssertEqual(entry?["stamp"]?.asString, "11111111")
        XCTAssertEqual(entry?["discovery_hash"]?.asString, "22222222")
        XCTAssertEqual(entry?["transport_id"]?.asString, "aabb")
        XCTAssertEqual(entry?["network_id"]?.asString, "ccdd")
    }

    // MARK: - Discovered array, end to end

    /// Golden captured from the real Python `rnstatus -d -j` with the same three entries
    /// and `time.time` pinned to `RNStatusRendererTests.now`.
    func testEncodeDiscoveredMatchesPython() {
        let encoded = RNStatusJSON.encodeDiscovered(RNStatusRendererTests.discoveredFixtures())
        XCTAssertEqual(encoded,
            "[{\"type\": \"BackboneInterface\", \"transport\": true, \"name\": \"my-backbone\", "
          + "\"received\": 1699999760.0, \"stamp\": \"1111111111111111\", \"value\": 21, "
          + "\"transport_id\": \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\", "
          + "\"network_id\": \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\", \"hops\": 2, "
          + "\"latitude\": 55.6761, \"longitude\": 12.5683, \"height\": 12.0, "
          + "\"reachable_on\": \"example.org\", \"port\": 4965, "
          + "\"config_entry\": \"[[my-backbone]]\\n  type = BackboneInterface\\n  enabled = yes\", "
          + "\"discovery_hash\": \"\(String(repeating: "22", count: 32))\", "
          + "\"discovered\": 1699700000.0, \"last_heard\": 1699999760.0, \"heard_count\": 4, "
          + "\"status\": \"available\", \"status_code\": 1000}, "
          + "{\"type\": \"RNodeInterface\", \"transport\": false, "
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
          + "{\"type\": \"TCPServerInterface\", \"transport\": true, \"name\": \"stale-one\", "
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

    func testDiscoveredFrequencyStaysIntegral() {
        // DiscoveredInterfaceInfo.frequency is a Double? where the wire carries an int;
        // emitting 867200000.0 would diverge from Python.
        let entry = RNStatusJSON.msgpackValue(for: RNStatusRendererTests.discoveredFixtures()[1])
        XCTAssertEqual(entry.asDictionary?["frequency"], .int(867_200_000))
        XCTAssertEqual(entry.asDictionary?["bandwidth"], .int(125_000))
    }
}
