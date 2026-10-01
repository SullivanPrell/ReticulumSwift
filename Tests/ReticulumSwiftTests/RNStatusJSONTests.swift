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

/// `rnstatus -j`—order-preserving `json.dumps` output and the two bytes→hex passes.
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
    XCTAssertEqual(
      RNStatusJSON.encode(value),
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
    XCTAssertEqual(
      RNStatusJSON.encode(.string("Shared Instance[37428]")),
      "\"Shared Instance[37428]\"")
  }

  func testKeyOrderIsPreservedWithRssLast() {
    // Python emits `rss` LAST, after the optional transport block (Reticulum.py:1467),
    // and json.dumps preserves dict insertion order—so the position is contractual.
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
    XCTAssertEqual(
      encoded,
      "{\"interfaces\": [], \"rxb\": 1, \"txb\": 2, \"rxs\": 0.0, \"txs\": 0.0, "
        + "\"transport_id\": \"dead\", \"network_id\": null, \"transport_uptime\": 5.0, "
        + "\"probe_responder\": null, \"rss\": null}")
    XCTAssertTrue(encoded.hasSuffix("\"rss\": null}"))
  }

  func testEncodedOutputParsesAsJSON() throws {
    let value = MsgPack.Value.map([
      (
        .string("interfaces"),
        .array([
          .map([
            (.string("name"), .string("TCPInterface[Server on 0.0.0.0:4242]")),
            (.string("hash"), .bytes(Data(repeating: 0x01, count: 32))),
            (.string("rxb"), .int(3_400_000)),
          ])
        ])
      ),
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
      (
        .string("interfaces"),
        .array([
          .map([
            (.string("hash"), .bytes(Data([0xAA, 0xBB]))),
            (.string("ifac_signature"), .bytes(Data([0x01, 0x02, 0x03]))),
            (.string("parent_interface_hash"), .bytes(Data([0xFF]))),
            (.string("name"), .string("x")),
            // Nested two levels deep: Python's loop doesn't reach this, and
            // json.dumps would raise a TypeError on it.
            (.string("blocked_ip_list"), .array([.bytes(Data([0x09]))])),
          ])
        ])
      ),
      (.string("transport_id"), .bytes(Data([0xDE, 0xAD, 0xBE, 0xEF]))),
      (.string("network_id"), .nil),
      (.string("probe_responder"), .bytes(Data([0xBA, 0xBE]))),
    ])
    guard case .map(let pairs) = RNStatusJSON.normaliseStats(value) else {
      return XCTFail("expected a map")
    }
    let top = Dictionary(
      uniqueKeysWithValues: pairs.compactMap { key, element in
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
    let value = MsgPack.Value.array([
      .map([
        (.string("stamp"), .bytes(Data(repeating: 0x11, count: 4))),
        (.string("discovery_hash"), .bytes(Data(repeating: 0x22, count: 4))),
        // Already hex STRINGS on disk (Discovery.py:323-324)—must stay strings.
        (.string("transport_id"), .string("aabb")),
        (.string("network_id"), .string("ccdd")),
      ])
    ])
    let entry = RNStatusJSON.normaliseDiscovered(value).asArray?.first?.asDictionary
    XCTAssertEqual(entry?["stamp"]?.asString, "11111111")
    XCTAssertEqual(entry?["discovery_hash"]?.asString, "22222222")
    XCTAssertEqual(entry?["transport_id"]?.asString, "aabb")
    XCTAssertEqual(entry?["network_id"]?.asString, "ccdd")
  }

  // MARK: - Discovered array

  // The end-to-end `-d -j` golden is `RNStatus155SurfaceTests.testDiscoveredJSONMatchesPython`.

  func testDiscoveredFrequencyStaysIntegral() {
    // DiscoveredInterfaceInfo.frequency is a Double? where the wire carries an int;
    // emitting 867200000.0 would diverge from Python.
    let entry = RNStatusJSON.msgpackValue(for: RNStatusRendererTests.discoveredFixtures()[1])
    XCTAssertEqual(entry.asDictionary?["frequency"], .int(867_200_000))
    XCTAssertEqual(entry.asDictionary?["bandwidth"], .int(125_000))
  }
}
