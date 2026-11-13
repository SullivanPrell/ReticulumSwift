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

/// RNS 1.6.0's stamp configuration: the `[stamps]` section, per-interface costs and the
/// `enable_stamping` / `enforce_stamps` constructor flags (`Reticulum.py:353-362`, `505-555`,
/// `963-971`).
final class StampConfigTests: XCTestCase {

  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns-stamps-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

  /// Costs clamp to `STAMP_COST_CAP`, `lr_cost` to `LINK_COST_CAP`, timeouts to 20 ms, and
  /// the switches only turn on (`Reticulum.py:505-555`).
  func testTheStampsSectionConfiguresTransport() {
    let cfg = ReticulumConfig.parse(
      """
      [stamps]
        enforce_stamps = yes
        stamp_destinations = no
        stamp_prs = yes
        always_stamp_lrs = yes
        destination_cost = 150
        destination_value = 30.5
        pr_cost = -4
        pr_value = 12.25
        lr_cost = 55
        lr_stamp_timeout = 0.001
        pr_stamp_timeout = 9
      """)
    XCTAssertEqual(cfg.unrecognisedKeys, [])

    var stamps = StampSettings()
    cfg.stamps.apply(to: &stamps)

    XCTAssertTrue(stamps.enforced)
    XCTAssertTrue(stamps.lrEnforced)
    XCTAssertFalse(stamps.stampDestinations, "`no` leaves the default")
    XCTAssertTrue(stamps.stampPRs)
    XCTAssertTrue(stamps.alwaysStampLRs)
    XCTAssertEqual(stamps.destinationCost, 100)
    XCTAssertEqual(stamps.destinationValue, 30.5)
    XCTAssertEqual(stamps.prCost, 0)
    XCTAssertEqual(stamps.prValue, 12.25)
    XCTAssertEqual(stamps.lrCost, 40)
    XCTAssertEqual(stamps.linkStampTimeout, 0.020)
    XCTAssertEqual(stamps.prStampTimeout, 9)
  }

  /// An absent section leaves every default in place.
  func testNoStampsSectionLeavesTheDefaults() {
    var stamps = StampSettings()
    ReticulumConfig.parse("[reticulum]").stamps.apply(to: &stamps)
    XCTAssertEqual(stamps.destinationCost, StampSettings().destinationCost)
    XCTAssertFalse(stamps.enforced)
  }

  /// `destination_cost` and `pr_cost` on an interface clamp to `STAMP_COST_CAP`
  /// (`Reticulum.py:963-971`, `1157-1158`).
  func testInterfaceCostsAreClamped() throws {
    let stack = Reticulum(configuration: .init(storagePath: dir, shareInstance: false))
    try stack.synthesizeInterfaces(
      from: ReticulumConfig.parse(
        """
        [interfaces]
          [[Costly]]
            type = TCPClientInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4965
            destination_cost = 150
            pr_cost = 7.5
        """))
    let iface = try XCTUnwrap(stack.transport.interfaces.first { $0.name == "Costly" })
    XCTAssertEqual(iface.destinationCost, 100)
    XCTAssertEqual(iface.prCost, 7.5)
    stack.stop()
  }

  /// `Reticulum(enable_stamping=True, enforce_stamps=True)` (`Reticulum.py:353-362`).
  func testConfigurationFlagsEnableStampingAndEnforcement() throws {
    var configuration = Reticulum.Configuration(storagePath: dir, shareInstance: false)
    configuration.configPath = dir.appendingPathComponent("config")
    try "[reticulum]\nenable_transport = no\n".write(
      to: configuration.configPath!, atomically: true, encoding: .utf8)
    configuration.enableStamping = true
    configuration.enforceStamps = true
    let stack = Reticulum(configuration: configuration)
    try stack.start()
    defer { stack.stop() }

    let stamps = stack.transport.stamps
    XCTAssertTrue(stamps.stampDestinations)
    XCTAssertTrue(stamps.stampPRs)
    XCTAssertTrue(stamps.stampLRs)
    XCTAssertTrue(stamps.enforced)
    XCTAssertTrue(stamps.lrEnforced)
  }

  /// `required_discovery_value` is read `as_float` (`Reticulum.py:674-677`).
  func testTheRequiredDiscoveryValueIsFractional() {
    let cfg = ReticulumConfig.parse("[reticulum]\nrequired_discovery_value = 14.5\n")
    XCTAssertEqual(cfg.reticulum.requiredDiscoveryValue, 14.5)
    XCTAssertNil(
      ReticulumConfig.parse("[reticulum]\nrequired_discovery_value = 0\n")
        .reticulum.requiredDiscoveryValue)
  }
}
