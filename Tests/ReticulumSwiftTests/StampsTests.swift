//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import CryptoKit
import XCTest

@testable import ReticulumSwift

/// The fixed-point stamp math RNS 1.6.0 added in `RNS/Stamps.py`.
///
/// Every expected value comes from `scripts/capture-stamp-vectors.py` run against RNS 1.6.0.
final class StampsTests: XCTestCase {

  func testTableMatchesUpstreamDigests() {
    XCTAssertEqual(Stamps.tab.count, Stamps.costFP)
    XCTAssertEqual(Stamps.tab[0], 1 << 33)
    let joined = Stamps.tab.map(String.init).joined(separator: ",")
    XCTAssertEqual(
      Data(SHA256.hash(data: Data(joined.utf8))).hexString,
      "55ba3ce1df224895b0dfdc102eb4359fc2f5a7efefee68df0cc90c8a8ac24f48")
  }

  func testCostToFixedPoint() {
    let cases: [(Double, Int, String, Double)] = [
      (0, 0, "0000", 0), (0.001, 0, "0000", 0), (1, 256, "0100", 1), (12.5, 3200, "0c80", 12.5),
      (15.8, 4045, "0fcd", 15.80078125), (23.5, 6016, "1780", 23.5), (25, 6400, "1900", 25),
      (99.999, 25600, "6400", 100), (100, 25600, "6400", 100), (150, 25600, "6400", 100),
      (-3, 0, "0000", 0),
    ]
    for (cost, fp, bytes, quantized) in cases {
      XCTAssertEqual(Stamps.costToFP(cost), fp, "\(cost)")
      XCTAssertEqual(Stamps.costToBytes(cost).hexString, bytes, "\(cost)")
      XCTAssertEqual(Stamps.costFromBytes(Data(hex: bytes)!), Double(fp) / 256, "\(cost)")
      XCTAssertEqual(Stamps.quantizeCost(cost), quantized, "\(cost)")
    }
  }

  func testTargetFromFixedPoint() {
    let cases: [(Int, String)] = [
      (0, "010000000000000000000000000000000000000000000000000000000000000000"),
      (1, "00ff4ecb5940000000000000000000000000000000000000000000000000000000"),
      (255, "008058d7d2c0000000000000000000000000000000000000000000000000000000"),
      (256, "008000000000000000000000000000000000000000000000000000000000000000"),
      (3200, "00000b504f333c0000000000000000000000000000000000000000000000000000"),
      (4045, "00000125e857118000000000000000000000000000000000000000000000000000"),
      (6016, "000000016a09e66780000000000000000000000000000000000000000000000000"),
      (25600, "000000000000000000000000001000000000000000000000000000000000000000"),
    ]
    for (fp, target) in cases {
      XCTAssertEqual(Data(Stamps.targetFromFP(fp)).hexString, target, "fp \(fp)")
    }
  }

  func testStampValueAndValidity() {
    let workblock = Data(SHA256.hash(data: Data("rs-160-stamps".utf8)))
    // stamp, value, then (cost, valid) at the value, one grid step above it, and its floor.
    let cases: [(String, Double, [(Double, Bool)])] = [
      (
        "6a41a1484e89d2dc18856a0d2446", 2.359375,
        [(2.359375, true), (2.36328125, false), (2, true)]
      ),
      (
        "0887373724e2a70860325d82c58b", 5.68359375,
        [(5.68359375, true), (5.6875, false), (5, true)]
      ),
      (
        "2deaf6d10874126f87ea46f38b8b", 7.921875,
        [(7.921875, true), (7.92578125, false), (7, true)]
      ),
      (
        "e136c624d3484f7a83f155fe246e", 12.015625,
        [(12.015625, true), (12.01953125, false), (12, true)]
      ),
      (
        "44809fb4416e6e928ae0b77ab272", 14.4765625,
        [(14.4765625, true), (14.48046875, false), (14, true)]
      ),
      ("6899afa82fac159f936c0c5df4a3", 0, [(0, true), (0.00390625, false), (1, false)]),
      (
        "98908628e46ff42cddb8ea720e28", 1.2890625,
        [(1.2890625, true), (1.29296875, false), (1, true)]
      ),
      (
        "6bc394536ef66c716fcbbe7f74eb", 14.859375,
        [(14.859375, true), (14.86328125, false), (14, true)]
      ),
    ]
    for (hex, value, checks) in cases {
      let stamp = Data(hex: hex)!
      XCTAssertEqual(Stamps.stampValue(workblock: workblock, stamp: stamp), value, hex)
      for (cost, valid) in checks {
        XCTAssertEqual(
          Stamps.stampValid(stamp: stamp, targetCost: cost, workblock: workblock), valid,
          "\(hex) at \(cost)")
      }
    }
  }

  func testWorkblockExpansion() {
    let material = Data("material".utf8)
    XCTAssertEqual(
      Data(SHA256.hash(data: Stamps.stampWorkblock(material, expandRounds: 3))).hexString,
      "43215790c523593fbb13120d7fc76a5f3552df23da09afac11f9e74da961dd16")
    XCTAssertEqual(Stamps.stampWorkblock(material, expandRounds: 0), material)
  }

  func testGeneratedStampMeetsItsCost() throws {
    let material = Data("generate".utf8)
    let found = try XCTUnwrap(
      Stamps.generateStamp(material, stampCost: 6.5, expandRounds: 0, size: 14))
    XCTAssertEqual(found.stamp.count, 14)
    XCTAssertTrue(Stamps.stampValid(stamp: found.stamp, targetCost: 6.5, workblock: material))
    XCTAssertEqual(found.value, Stamps.stampValue(workblock: material, stamp: found.stamp))
    XCTAssertNil(Stamps.generateStamp(material, stampCost: 101, expandRounds: 0))
    XCTAssertNil(
      Stamps.generateStamp(material, stampCost: 40, expandRounds: 0, isCancelled: { true }))
  }

  func testGeneratedKeyCarriesItsStamp() throws {
    let material = Data("link".utf8)
    let found = try XCTUnwrap(Stamps.generateStampedKey(material: material, stampCost: 4))
    let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: found.privateKey)
    XCTAssertEqual(key.publicKey.rawRepresentation, found.publicKey)
    XCTAssertTrue(Stamps.stampValid(stamp: found.publicKey, targetCost: 4, workblock: material))
    XCTAssertEqual(found.value, Stamps.stampValue(workblock: material, stamp: found.publicKey))
  }

  func testDestinationStampPersistence() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let hash = Data(repeating: 0xAB, count: 16)
    let material = Data("dst".utf8)
    let found = try XCTUnwrap(
      Stamps.generateStamp(material, stampCost: 5, expandRounds: 0, size: 14))
    XCTAssertNil(Stamps.loadDestinationStamp(hash, material: material, requiredValue: 5, in: dir))

    XCTAssertTrue(
      Stamps.storeDestinationStamp(hash, stamp: found.stamp, value: found.value, in: dir))
    let file = dir.appendingPathComponent("\(hash.hexString).dstamp")
    let entry = try XCTUnwrap(MsgPack.decode(Data(contentsOf: file)).asDictionary)
    XCTAssertEqual(entry["v"]?.asInt, 1)
    XCTAssertEqual(entry["stamp"]?.asData, found.stamp)

    let loaded = try XCTUnwrap(
      Stamps.loadDestinationStamp(hash, material: material, requiredValue: 5, in: dir))
    XCTAssertEqual(loaded.stamp, found.stamp)
    XCTAssertNil(
      Stamps.loadDestinationStamp(
        hash, material: material, requiredValue: found.value + 1, in: dir))
  }
}
