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

/// A shared-instance client builds none of the management destinations: its instance serves
/// them. `Transport.start` gates remote management and the network destinations on `not
/// Transport.owner.is_connected_to_shared_instance` (`Transport.py:367`, `:382`), and the probe
/// destination on `transport_enabled()` (`:404`, `:511`), which a client turns off
/// (`Reticulum.py:440`), RNS 1.5.7.
final class ClientManagementDestinationTests: XCTestCase {

  private var savedProbes = false
  private var savedManagement = false

  override func setUp() {
    super.setUp()
    savedProbes = Reticulum.allowProbes
    savedManagement = Reticulum.storedRemoteManagementEnabled
    Reticulum.allowProbes = true
    Reticulum.storedRemoteManagementEnabled = true
  }

  override func tearDown() {
    Reticulum.allowProbes = savedProbes
    Reticulum.storedRemoteManagementEnabled = savedManagement
    super.tearDown()
  }

  private struct Built {
    let probe: Bool
    let management: Bool
    let network: Bool
  }

  private func start(client: Bool = false, transport: Bool = true) throws -> Built {
    let t = Transport()
    t.transportIdentity = Identity()
    let networkIdentity = Identity()
    t.setNetworkIdentity(networkIdentity)
    t.transportEnabled = transport
    t.isConnectedToSharedInstance = client
    try t.start()
    defer { t.stop() }
    let network = try Destination(
      identity: networkIdentity, direction: .in, kind: .single, appName: "rnstransport",
      aspects: ["network"])
    return Built(
      probe: t.probeDestination != nil, management: t.remoteManagementDestination != nil,
      network: t.registeredDestinations[network.hash] != nil)
  }

  /// Twice in one method, so a leaked static would show on the second pass.
  func testAClientBuildsNoManagementDestinations() throws {
    for _ in 0..<2 {
      let built = try start(client: true)
      XCTAssertFalse(built.probe, "Transport.py:511, under transport_enabled() at :404")
      XCTAssertFalse(built.management, "Transport.py:367")
      XCTAssertFalse(built.network, "Transport.py:382")
    }
  }

  func testAnInstanceBuildsThemAll() throws {
    let built = try start()
    XCTAssertTrue(built.probe)
    XCTAssertTrue(built.management)
    XCTAssertTrue(built.network)
  }

  func testANodeWithTransportOffBuildsNoProbeDestination() throws {
    let built = try start(transport: false)
    XCTAssertFalse(built.probe, "Transport.py:511, under transport_enabled() at :404")
    XCTAssertTrue(built.management, "Transport.py:367 doesn't read transport_enabled()")
    XCTAssertTrue(built.network)
  }
}
