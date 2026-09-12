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

/// Tests for Transport.set_network_identity() and Transport.has_network_identity().
///
/// Mirrors Python's Transport.network_identity concept used for remote management
/// and interface discovery.
final class NetworkIdentityTests: XCTestCase {

  func testHasNetworkIdentityFalseByDefault() {
    let t = Transport()
    XCTAssertFalse(t.hasNetworkIdentity)
  }

  func testSetNetworkIdentity() {
    let t = Transport()
    let id = Identity()
    t.setNetworkIdentity(id)
    XCTAssertTrue(t.hasNetworkIdentity)
    XCTAssertEqual(t.networkIdentity, id)
  }

  func testSetNetworkIdentityOnlyOnce() {
    let t = Transport()
    let id1 = Identity()
    let id2 = Identity()
    t.setNetworkIdentity(id1)
    t.setNetworkIdentity(id2)  // should be ignored (already set)
    XCTAssertEqual(t.networkIdentity, id1, "network identity can only be set once")
  }

  func testNetworkIdentityIsDistinctFromOwnerIdentity() {
    let t = Transport()
    let ownerID = Identity()
    let networkID = Identity()
    t.ownerIdentity = ownerID
    t.setNetworkIdentity(networkID)
    XCTAssertEqual(t.ownerIdentity, ownerID)
    XCTAssertEqual(t.networkIdentity, networkID)
    XCTAssertNotEqual(t.ownerIdentity?.hash, t.networkIdentity?.hash)
  }
}
