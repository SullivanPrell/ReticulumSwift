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

/// Every top-level key `Reticulum.get_interface_stats()` publishes, in Python's own
/// insertion order (`Reticulum.py:1576-1616`).
///
/// `rnstatus` reads most of the per-interface fields behind `if "key" in ifstat`, but the
/// top-level ones it does **not**: `stats['rxpps']` under `-p` and `stats['rxqt']` under
/// `-q` are bare subscripts (`rnstatus.py:740`, `:785`). A Python operator pointing their
/// own `rnstatus` at this daemon gets a `KeyError` traceback and no output at all—the
/// failure mode a missing `txdrp` already produced once.
///
/// Order matters as well as presence: `rnstatus -j` dumps the dictionary in insertion
/// order, so the JSON a Swift daemon emits should be diffable against a Python one.
final class InterfaceStatsTopLevelKeysTests: XCTestCase {

  /// The keys Python emits before the optional transport block, in order.
  static let expectedOrder = [
    "interfaces", "rxb", "txb", "rxs", "txs",
    "arxb", "atxb", "arxs", "atxs", "arxf", "atxf",
    "prxb", "ptxb", "prxs", "ptxs", "prxf", "ptxf",
    "rxpps", "txpps",
    "rxqt", "rxqd", "rxqa", "rxqp", "rxqil",
    "rxqtd", "rxqdd", "rxqad", "rxqpd", "rxqild",
    "tqpressure", "dqpressure", "aqpressure", "pqpressure", "ilqpressure",
    "txq",
  ]

  private func keys(of value: MsgPack.Value) throws -> [String] {
    guard case .map(let pairs) = value else {
      XCTFail("the payload has to be a msgpack map")
      return []
    }
    return pairs.compactMap { $0.0.asString }
  }

  func testThePayloadCarriesPythonsKeysInPythonsOrder() throws {
    let t = Transport()
    let iface = UDPInterface(name: "Keys", listenPort: 4460, forwardPort: 4461)
    t.register(interface: iface)
    defer { t.deregister(interface: iface) }

    let produced = try keys(of: InterfaceStatsPayload.build(t))

    XCTAssertEqual(
      Array(produced.prefix(Self.expectedOrder.count)), Self.expectedOrder,
      "the leading keys must match Reticulum.py:1576-1613 exactly, in order")
    XCTAssertEqual(
      produced.last, "rss",
      "Python appends `rss` after the optional transport block "
        + "(Reticulum.py:1622), so it stays last")
  }

  func testTheEmptyPayloadCarriesTheSameKeys() throws {
    let produced = try keys(of: InterfaceStatsPayload.empty)

    XCTAssertEqual(
      Array(produced.prefix(Self.expectedOrder.count)), Self.expectedOrder,
      """
      `empty` is what a caller renders when no stats are available yet. A \
      reduced key set there means `rnstatus -p` works against a busy daemon \
      and raises KeyError against an idle one.
      """)
    XCTAssertEqual(produced.last, "rss")
  }

  func testQueueDepthsAndPressuresReadZero() throws {
    let t = Transport()
    let payload = try XCTUnwrap(InterfaceStatsPayload.build(t).asDictionary)

    for key in [
      "rxqt", "rxqd", "rxqa", "rxqp", "rxqil",
      "rxqtd", "rxqdd", "rxqad", "rxqpd", "rxqild",
    ] {
      XCTAssertEqual(
        payload[key]?.asInt, 0,
        "\(key): this port runs each inbound frame to completion on the "
          + "receiving thread, so no frame ever waits in a queue")
    }
    for key in ["tqpressure", "dqpressure", "aqpressure", "pqpressure", "ilqpressure"] {
      XCTAssertEqual(payload[key]?.asDouble, 0, "\(key)")
    }
  }

  func testTheTransmitQueueKeyIsNil() throws {
    let t = Transport()
    let payload = try XCTUnwrap(InterfaceStatsPayload.build(t).asDictionary)
    // Python assigns `stats["txq"] = None` outright (Reticulum.py:1613); the key has to
    // be present and nil, not absent.
    XCTAssertTrue(payload.keys.contains("txq"))
    XCTAssertEqual(payload["txq"], MsgPack.Value.nil)
  }

  func testTheAggregatesCarryTheTransportsValuesRatherThanConstants() throws {
    let t = Transport()
    let iface = UDPInterface(name: "Keys Live", listenPort: 4462, forwardPort: 4463)
    t.register(interface: iface)
    defer { t.deregister(interface: iface) }

    t.sampleInterfaceSpeeds(now: 20_000)
    t.notifyIncomingAnnounce(on: iface, size: 500)
    t.notifyOutgoingPathRequest(on: iface, size: 125)
    t.sampleInterfaceSpeeds(now: 20_010)

    let payload = try XCTUnwrap(InterfaceStatsPayload.build(t).asDictionary)
    XCTAssertEqual(payload["arxb"]?.asInt, 500)
    XCTAssertEqual(payload["ptxb"]?.asInt, 125)
    XCTAssertEqual(
      try XCTUnwrap(payload["arxs"]?.asDouble), 400, accuracy: 0.001,
      "500 bytes over 10 s = 400 bits/s, the same derivative rnstatus "
        + "prints beside the byte total")
    XCTAssertEqual(try XCTUnwrap(payload["ptxs"]?.asDouble), 100, accuracy: 0.001)
  }
}
