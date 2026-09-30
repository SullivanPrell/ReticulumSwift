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

/// What RNS 1.5.5 reads from an interface discovery announce, and what it persists.
///
/// `InterfaceAnnounceHandler.received_announce` records the announcing implementation and
/// version (`Discovery.py:348-349`, `364-365`), keeps IFAC values only when they're non-empty
/// strings (`378-379`), and writes `peers = <b32>.b32.i2p` into an I2P config entry (`408`).
/// `list_discovered_interfaces` drops the string `"None"` persisted as an IFAC value by nodes
/// that published an unset one (`540-547`). `rnstatus -d` reads the persisted files directly
/// (`rnstatus.py:221-223`), so the keys are Python's.
final class DiscoveryImplementationInfoTests: XCTestCase {

  private final class Passthrough: DiscoveryStampValidator {
    let stampSize = 32
    func stampWorkblock(material: Data, expandRounds: Int) -> Data { Data(count: 256) }
    func stampValue(workblock: Data, stamp: Data) -> Int { 99 }
    func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { true }
  }

  private var tempDir: URL!

  override func setUp() {
    super.setUp()
    tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("disc_impl_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
    super.tearDown()
  }

  private func receive(_ fields: [(MsgPack.Value, MsgPack.Value)]) -> DiscoveredInterfaceInfo? {
    var result: DiscoveredInterfaceInfo?
    let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: Passthrough()) {
      result = $0
    }
    let payload = Data([0x00]) + MsgPack.encode(.map(fields)) + Data(repeating: 0xAB, count: 32)
    handler.receivedAnnounce(
      destinationHash: Data(count: 16), identity: Identity(), appData: payload,
      announcePacketHash: Data(count: 4), isPathResponse: false)
    return result
  }

  private func backbone(_ extra: [(MsgPack.Value, MsgPack.Value)] = [])
    -> [(MsgPack.Value, MsgPack.Value)]
  {
    [
      (.uint(0x00), .string("BackboneInterface")),
      (.uint(0x01), .bool(true)),
      (.uint(0xFE), .bytes(Data(repeating: 0x11, count: 16))),
      (.uint(0xFF), .string("Hub")),
      (.uint(0x02), .string("10.0.0.5")),
      (.uint(0x06), .uint(4242)),
      (.uint(0x03), .nil), (.uint(0x04), .nil), (.uint(0x05), .nil),
    ] + extra
  }

  func testTheAnnouncingImplementationAndVersionAreRead() throws {
    let info = try XCTUnwrap(
      receive(backbone([(.uint(0xFD), .string("RNS")), (.uint(0xFC), .string("1.5.5"))])))
    XCTAssertEqual(info.implName, "RNS")
    XCTAssertEqual(info.version, "1.5.5")
  }

  func testAnAnnounceWithoutImplementationInfoHasNone() throws {
    let info = try XCTUnwrap(receive(backbone()))
    XCTAssertNil(info.implName)
    XCTAssertNil(info.version)
  }

  func testEmptyIfacValuesAreNotKept() throws {
    let info = try XCTUnwrap(
      receive(backbone([(.uint(0x07), .string("")), (.uint(0x08), .string(""))])))
    XCTAssertNil(info.ifacNetname)
    XCTAssertNil(info.ifacNetkey)
    XCTAssertFalse(info.configEntry?.contains("network_name") ?? true)
  }

  func testAnI2PConfigEntryNamesTheB32Address() throws {
    let info = try XCTUnwrap(
      receive([
        (.uint(0x00), .string("I2PInterface")),
        (.uint(0x01), .bool(true)),
        (.uint(0xFE), .bytes(Data(repeating: 0x11, count: 16))),
        (.uint(0xFF), .string("Tunnel")),
        (.uint(0x02), .string("abcdefghijklmnop")),
        (.uint(0x03), .nil), (.uint(0x04), .nil), (.uint(0x05), .nil),
      ]))
    XCTAssertTrue(
      info.configEntry?.contains("peers = abcdefghijklmnop.b32.i2p\n") ?? false,
      info.configEntry ?? "no config entry")
  }

  func testImplementationInfoIsPersistedUnderPythonsKeys() throws {
    let disc = InterfaceDiscovery(storagePath: tempDir.path)
    var info = try XCTUnwrap(
      receive(backbone([(.uint(0xFD), .string("RNS")), (.uint(0xFC), .string("1.5.5"))])))
    info.hops = 1
    disc.interfaceDiscovered(info)
    let file = tempDir.appendingPathComponent(
      RNSUtilities.hexrep(try XCTUnwrap(info.discoveryHash), delimit: false))
    guard case .map(let pairs) = try MsgPack.decode(Data(contentsOf: file)) else {
      return XCTFail("not a map")
    }
    let keys = Dictionary(
      pairs.compactMap { k, v -> (String, MsgPack.Value)? in
        if case .string(let s) = k { return (s, v) }
        return nil
      }, uniquingKeysWith: { a, _ in a })
    XCTAssertEqual(keys["impl_name"], .string("RNS"))
    XCTAssertEqual(keys["version"], .string("1.5.5"))

    let listed = try XCTUnwrap(disc.listDiscoveredInterfaces().first)
    XCTAssertEqual(listed.implName, "RNS")
    XCTAssertEqual(listed.version, "1.5.5")
  }

  func testAnAbsentImplementationIsPersistedAsNil() throws {
    let disc = InterfaceDiscovery(storagePath: tempDir.path)
    let info = try XCTUnwrap(receive(backbone()))
    disc.interfaceDiscovered(info)
    let file = tempDir.appendingPathComponent(
      RNSUtilities.hexrep(try XCTUnwrap(info.discoveryHash), delimit: false))
    guard case .map(let pairs) = try MsgPack.decode(Data(contentsOf: file)) else {
      return XCTFail("not a map")
    }
    let names = pairs.compactMap { k, v -> String? in
      if case .string(let s) = k, s == "impl_name" || s == "version", v == .nil { return s }
      return nil
    }
    XCTAssertEqual(Set(names), ["impl_name", "version"], "Python writes both keys as None")
  }

  func testListingDropsIfacValuesPersistedAsTheStringNone() throws {
    let disc = InterfaceDiscovery(storagePath: tempDir.path)
    var info = try XCTUnwrap(receive(backbone()))
    info.ifacNetname = "None"
    info.ifacNetkey = "None"
    disc.interfaceDiscovered(info)
    let listed = try XCTUnwrap(disc.listDiscoveredInterfaces().first)
    XCTAssertNil(listed.ifacNetname)
    XCTAssertNil(listed.ifacNetkey)
  }
}
