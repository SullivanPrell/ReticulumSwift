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

/// Received integers outside the range of `Int`.
///
/// Python decodes any msgpack integer into an unbounded `int`, so a peer can send one where a
/// count, size or port is expected. `Int(_:)` traps on such a value.
final class WireIntegerRangeTests: XCTestCase {

  // MARK: - MsgPack.Value.asInt

  func testAsIntRefusesAnUnsignedValueAboveIntMax() {
    XCTAssertNil(MsgPack.Value.uint(UInt64.max).asInt)
    XCTAssertEqual(MsgPack.Value.uint(42).asInt, 42)
    XCTAssertEqual(MsgPack.Value.int(-42).asInt, -42)
  }

  // MARK: - Interface discovery (`Discovery.py:360-430`)

  private final class AcceptAnyStamp: DiscoveryStampValidator {
    let stampSize: Int = 32
    func stampWorkblock(material: Data, expandRounds: Int) -> Data {
      Data(repeating: 0, count: max(1, expandRounds) * 256)
    }
    func stampValue(workblock: Data, stamp: Data) -> Int { 99 }
    func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { true }
  }

  private func discover(_ fields: [(MsgPack.Value, MsgPack.Value)]) -> DiscoveredInterfaceInfo? {
    var result: DiscoveredInterfaceInfo?
    let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: AcceptAnyStamp()) {
      result = $0
    }
    handler.receivedAnnounce(
      destinationHash: Data(repeating: 0, count: 16),
      identity: Identity(),
      appData: Data([0x00]) + MsgPack.encode(.map(fields)) + Data(repeating: 0xAB, count: 32),
      announcePacketHash: Data(repeating: 0, count: 4),
      isPathResponse: false)
    return result
  }

  private func fields(type: String, _ extra: [(MsgPack.Value, MsgPack.Value)]) -> [(
    MsgPack.Value, MsgPack.Value
  )] {
    [
      (.uint(0x00), .string(type)),
      (.uint(0x01), .bool(true)),
      (.uint(0xFE), .bytes(Data(repeating: 0x11, count: 16))),
      (.uint(0xFF), .string("node")),
    ] + extra
  }

  func testABackbonePortAboveIntMaxDropsTheAnnounce() {
    let reachable: (MsgPack.Value, MsgPack.Value) = (.uint(0x02), .string("192.168.1.100"))
    XCTAssertNotNil(
      discover(fields(type: "BackboneInterface", [reachable, (.uint(0x06), .uint(4965))])))
    XCTAssertNil(
      discover(fields(type: "BackboneInterface", [reachable, (.uint(0x06), .uint(UInt64.max))])))
  }

  func testARadioSpreadingFactorAboveIntMaxReadsAsUnset() throws {
    let info = try XCTUnwrap(
      discover(fields(type: "RNodeInterface", [(.uint(0x0B), .uint(UInt64.max))])))
    XCTAssertNil(info.sf)
  }

  // MARK: - Resource advertisement (`Resource.py:1352-1376`)

  private func advertisement(_ overrides: [String: MsgPack.Value] = [:]) -> Data {
    var fields: [String: MsgPack.Value] = [
      "t": .uint(100), "d": .uint(100), "n": .uint(1),
      "h": .bytes(Data(repeating: 1, count: 32)), "r": .bytes(Data(repeating: 2, count: 4)),
      "o": .bytes(Data(repeating: 1, count: 32)), "i": .uint(1), "l": .uint(1), "q": .nil,
      "m": .bytes(Data(repeating: 3, count: 4)), "f": .uint(0x01),
    ]
    fields.merge(overrides) { $1 }
    return MsgPack.encode(.map(fields.map { (.string($0.key), $0.value) }))
  }

  func testAnAdvertisementCountAboveIntMaxIsRefused() throws {
    XCTAssertNoThrow(try ResourceAdvertisement.unpack(advertisement()))
    for key in ["d", "n", "i", "l"] {
      XCTAssertThrowsError(
        try ResourceAdvertisement.unpack(advertisement([key: .uint(1 << 63)])),
        "\(key) = 2^63 reaches Int(_:) on the receive path")
    }
  }
}
