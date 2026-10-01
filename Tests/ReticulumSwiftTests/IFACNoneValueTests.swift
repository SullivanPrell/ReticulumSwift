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

/// How RNS 1.5.5 handles an IFAC value that isn't one.
///
/// A config value of `None` for `networkname`, `network_name`, `passphrase` or `pass_phrase` is
/// ignored with a warning (`Reticulum.py:889-902`). A discoverable interface with
/// `publish_ifac` set and neither value configured gets a warning, and IFAC publishing is turned
/// off (`Reticulum.py:1095-1098`). The announcer writes `IFAC_NETNAME` and `IFAC_NETKEY` only when
/// the interface has that value (`Discovery.py:236-238`), where it wrote a nil before.
final class IFACNoneValueTests: XCTestCase {

  private var warnings: [String] = []
  private var savedHandler: ((String, Reticulum.LogLevel) -> Void)?
  private var savedLevel: Reticulum.LogLevel = .notice

  override func setUp() {
    super.setUp()
    savedHandler = Reticulum.logHandler
    savedLevel = Reticulum.globalLogLevel
    Reticulum.globalLogLevel = .notice
    Reticulum.logHandler = { [weak self] message, level in
      if level == .warning { self?.warnings.append(message) }
    }
  }

  override func tearDown() {
    Reticulum.logHandler = savedHandler
    Reticulum.globalLogLevel = savedLevel
    super.tearDown()
  }

  private func apply(_ parameters: [String: String], to interface: any Interface) {
    Reticulum.applyInterfaceConfiguration(
      to: interface,
      from: ReticulumConfig.InterfaceConfig(
        name: interface.name, type: "TCPServerInterface", enabled: true,
        parameters: parameters))
  }

  // MARK: - "None" in the config

  func testNoneIsNotANetworkNameOrPassphrase() {
    for (nameKey, keyKey) in [("networkname", "passphrase"), ("network_name", "pass_phrase")] {
      warnings = []
      let iface = TCPServerInterface(name: "hub", port: 4965)
      apply([nameKey: "None", keyKey: "None"], to: iface)
      XCTAssertNil(iface.ifacNetname, nameKey)
      XCTAssertNil(iface.ifacNetkey, keyKey)
      XCTAssertNil(iface.ifacKey, "no IFAC key from \(nameKey)/\(keyKey) of None")
      XCTAssertEqual(
        warnings,
        [
          "Ambiguous IFAC network name \"None\", this value is ignored and an IFAC network name "
            + "has NOT been set",
          "Ambiguous IFAC passphrase \"None\", this value is ignored and an IFAC passphrase has "
            + "NOT been set",
        ])
    }
  }

  func testNoneInTheLaterSpellingLeavesTheEarlierValue() {
    let iface = TCPServerInterface(name: "hub", port: 4965)
    apply(
      ["networkname": "segment", "network_name": "None", "passphrase": "k", "pass_phrase": "None"],
      to: iface)
    XCTAssertEqual(iface.ifacNetname, "segment")
    XCTAssertEqual(iface.ifacNetkey, "k")
    XCTAssertNotNil(iface.ifacKey)
  }

  // MARK: - publish_ifac without IFAC

  func testPublishIfacWithoutIfacIsTurnedOff() {
    let iface = TCPServerInterface(name: "hub", port: 4965)
    apply(["discoverable": "yes", "publish_ifac": "yes"], to: iface)
    XCTAssertTrue(iface.discoverable)
    XCTAssertFalse(iface.discoveryPublishIfac)
    XCTAssertEqual(
      warnings,
      [
        "IFAC publishing was enabled for discoverable interface \(iface.displayName), but "
          + "neither IFAC netname nor passphrase is configured",
        "Disabling IFAC publishing for \(iface.displayName)",
      ])
  }

  func testPublishIfacWithANoneNetworkNameIsTurnedOff() {
    let iface = TCPServerInterface(name: "hub", port: 4965)
    apply(["discoverable": "yes", "publish_ifac": "yes", "network_name": "None"], to: iface)
    XCTAssertFalse(iface.discoveryPublishIfac)
  }

  func testPublishIfacWithANetworkNameStaysOn() {
    let iface = TCPServerInterface(name: "hub", port: 4965)
    apply(["discoverable": "yes", "publish_ifac": "yes", "network_name": "segment"], to: iface)
    XCTAssertTrue(iface.discoveryPublishIfac)
    XCTAssertTrue(warnings.isEmpty, warnings.joined(separator: "\n"))
  }

  // MARK: - The announce

  private final class FixedStamp: DiscoveryStampGenerator {
    func generateStamp(material: Data, targetCost: Int, expandRounds: Int) -> Data? {
      Data(repeating: 0xAB, count: 32)
    }
  }

  private func announcedKeys(_ iface: any Interface) throws -> Set<UInt64> {
    let transport = Transport()
    transport.transportIdentity = Identity()
    let announcer = try XCTUnwrap(
      InterfaceAnnouncer(transport: transport, stampGenerator: FixedStamp()))
    let appData = try XCTUnwrap(try announcer.announceData(for: iface))
    guard case .map(let entries) = try MsgPack.decode(Data(appData.dropFirst().dropLast(32)))
    else {
      XCTFail("announce payload is not a msgpack map")
      return []
    }
    return Set(
      entries.compactMap { k, _ in
        if case .uint(let n) = k { return n }
        return nil
      })
  }

  func testOnlyAConfiguredIfacValueIsAnnounced() throws {
    let iface = TCPServerInterface(name: "hub", port: 4965)
    apply(
      [
        "discoverable": "yes", "publish_ifac": "yes", "reachable_on": "hub.example.net",
        "network_name": "segment",
      ], to: iface)
    let keys = try announcedKeys(iface)
    XCTAssertTrue(keys.contains(0x07), "IFAC_NETNAME")
    XCTAssertFalse(keys.contains(0x08), "IFAC_NETKEY is left out, not written as nil")
  }

  func testAnEmptyIfacValueIsNotAnnounced() throws {
    let iface = TCPServerInterface(name: "hub", port: 4965)
    apply(
      [
        "discoverable": "yes", "publish_ifac": "yes", "reachable_on": "hub.example.net",
        "passphrase": "k",
      ], to: iface)
    iface.ifacNetname = ""
    let keys = try announcedKeys(iface)
    XCTAssertFalse(keys.contains(0x07), "an empty IFAC_NETNAME is falsy in Python")
    XCTAssertTrue(keys.contains(0x08), "IFAC_NETKEY")
  }
}
