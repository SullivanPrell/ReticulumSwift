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

final class ProbeDestinationTests: XCTestCase {

  override func setUp() {
    super.setUp()
    // Reset static flags after each test.
    Reticulum.allowProbes = false
    Reticulum.storedRemoteManagementEnabled = false
  }

  override func tearDown() {
    Reticulum.allowProbes = false
    Reticulum.storedRemoteManagementEnabled = false
    super.tearDown()
  }

  func testProbeDestinationNotCreatedByDefault() {
    let transport = Transport()
    transport.transportIdentity = Identity()
    try? transport.start()
    XCTAssertNil(
      transport.probeDestination,
      "Probe destination should not be created when allowProbes is false")
  }

  func testProbeDestinationCreatedWhenEnabled() {
    Reticulum.allowProbes = true
    let transport = Transport()
    transport.transportIdentity = Identity()
    try? transport.start()
    XCTAssertNotNil(
      transport.probeDestination,
      "Probe destination should be created when allowProbes is true")
  }

  func testProbeDestinationHasProveAllStrategy() {
    Reticulum.allowProbes = true
    let transport = Transport()
    transport.transportIdentity = Identity()
    try? transport.start()
    XCTAssertEqual(transport.probeDestination?.proofStrategy, .proveAll)
  }

  func testProbeDestinationDoesNotAcceptLinks() {
    Reticulum.allowProbes = true
    let transport = Transport()
    transport.transportIdentity = Identity()
    try? transport.start()
    XCTAssertFalse(transport.probeDestination?.acceptsLinks ?? true)
  }

  func testProbeDestinationIsSingleType() {
    Reticulum.allowProbes = true
    let transport = Transport()
    transport.transportIdentity = Identity()
    try? transport.start()
    XCTAssertEqual(transport.probeDestination?.kind, .single)
  }

  func testProbeDestinationUsesTransportIdentity() {
    Reticulum.allowProbes = true
    let identity = Identity()
    let transport = Transport()
    transport.transportIdentity = identity
    try? transport.start()
    XCTAssertEqual(transport.probeDestination?.identity?.hash, identity.hash)
  }

  func testProbeDestinationHashMatchesExpected() throws {
    Reticulum.allowProbes = true
    let identity = Identity()
    let transport = Transport()
    transport.transportIdentity = identity
    try? transport.start()

    // Expected hash: same as constructing the destination directly.
    let expected = try Destination(
      identity: identity, direction: .in, kind: .single,
      appName: "rnstransport", aspects: ["probe"])
    XCTAssertEqual(transport.probeDestination?.hash, expected.hash)
  }

  func testProbeDestinationRegisteredInTransport() {
    Reticulum.allowProbes = true
    let transport = Transport()
    transport.transportIdentity = Identity()
    try? transport.start()

    guard let probe = transport.probeDestination else {
      XCTFail("Probe destination not created")
      return
    }
    XCTAssertNotNil(
      transport.registeredDestinations[probe.hash],
      "Probe destination should be registered in transport.registeredDestinations")
  }
}
