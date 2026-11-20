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

/// RNS 1.6.1's `announce_rate_table` file (`Storage.py:167-345`, `Transport.py:466-473`,
/// `:4701-4706`).
final class RNS161AnnounceRateTableStoreTests: XCTestCase {

  final class Port: Interface {
    var name = "rate"
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  /// `AnnounceRateTable.persist` from the 1.6.1 reference, after `check_and_update` at 1000.0
  /// and 1003.5 with target 10, grace 2 and penalty 5 for the key `00 01 .. 0f`.
  private let pythonVector = Data(
    hex:
      "524e5341525401001010000001000000000102030405060708090a0b0c0d0e0f00000000005c8f40000000"
      + "00000000000100000002020000000000408f4000000000005c8f40"
      + String(repeating: "00", count: 14 * 8))!

  private let key = Data((0..<16).map { UInt8($0) })

  private func scratch() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("rnsart-\(UUID().uuidString)")
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func transport() -> Transport {
    let t = Transport.unstamped()
    t.transportEnabled = true
    return t
  }

  func testPersistingMatchesTheReferenceBytes() throws {
    let t = transport()
    let port = Port()
    port.announceRateTarget = 10
    port.announceRateGrace = 2
    port.announceRatePenalty = 5
    _ = t.isAnnounceRateBlocked(destinationHash: key, interface: port, now: 1000)
    _ = t.isAnnounceRateBlocked(destinationHash: key, interface: port, now: 1003.5)
    let url = scratch()

    try t.saveAnnounceRateTable(to: url)

    XCTAssertEqual(try Data(contentsOf: url).hexString, pythonVector.hexString)
  }

  func testLoadingTheReferenceBytesRestoresTheEntry() throws {
    let url = scratch()
    try pythonVector.write(to: url)
    let t = transport()

    XCTAssertTrue(t.loadAnnounceRateTable(from: url))

    let entry = try XCTUnwrap(t.getRateTable().first)
    XCTAssertEqual(entry.destinationHash, key)
    XCTAssertEqual(entry.last, 1003.5)
    XCTAssertEqual(entry.rateViolations, 1)
    XCTAssertEqual(entry.blockedUntil, 0)
    XCTAssertEqual(entry.timestamps, [1000, 1003.5])
  }

  /// A full ring is read oldest first from `ts_head` (`Storage.py:296-298`).
  func testAFullRingRoundTripsInOrder() throws {
    let t = transport()
    let port = Port()
    port.announceRateTarget = 1
    port.announceRateGrace = 100
    for n in 0..<20 {
      _ = t.isAnnounceRateBlocked(destinationHash: key, interface: port, now: 2000 + Double(n * 2))
    }
    let url = scratch()
    try t.saveAnnounceRateTable(to: url)
    let restored = transport()

    XCTAssertTrue(restored.loadAnnounceRateTable(from: url))

    XCTAssertEqual(restored.getRateTable().first?.timestamps, t.getRateTable().first?.timestamps)
    XCTAssertEqual(restored.getRateTable().first?.timestamps.count, Transport.maxRateTimestamps)
  }

  /// `load` refuses a bad magic, version, flags byte or size (`Storage.py:256-266`).
  func testMalformedFilesAreRefused() throws {
    let url = scratch()
    var badMagic = pythonVector
    badMagic[0] = 0x00
    var badVersion = pythonVector
    badVersion[6] = 0x02
    var badFlags = pythonVector
    badFlags[7] = 0x01
    for blob in [badMagic, badVersion, badFlags, pythonVector.dropLast(), Data(count: 15)] {
      try blob.write(to: url)
      XCTAssertFalse(transport().loadAnnounceRateTable(from: url))
    }
  }

  /// `save_announce_rate_table` runs only for a transport node not attached to a shared
  /// instance (`Transport.py:4702`).
  func testOnlyATransportNodeSavesTheTable() throws {
    let endpoint = transport()
    endpoint.transportEnabled = false
    let client = transport()
    client.isConnectedToSharedInstance = true
    let port = Port()
    port.announceRateTarget = 10
    for t in [endpoint, client] {
      _ = t.isAnnounceRateBlocked(destinationHash: key, interface: port, now: 1000)
      let url = scratch()

      try t.saveAnnounceRateTable(to: url)

      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
  }
}
