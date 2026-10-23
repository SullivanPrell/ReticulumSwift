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

/// The jobs loop announces every destination in `mgmt_destinations` once
/// `mgmt_announce_interval` (2 h) has passed since the last round (`Transport.py:1178-1184`), and
/// `start` dates the last round so the first one goes 15 s in (`:397`), RNS 1.5.5.
final class ManagementAnnounceTests: XCTestCase {

  private var savedProbes = false
  private var savedManagement = false
  private let sink = PathRequestResponderTests.CapturingInterface(name: "eth0")
  private let networkIdentity = Identity()
  private let transport = Transport()

  override func setUp() {
    super.setUp()
    savedProbes = Reticulum.allowProbes
    savedManagement = Reticulum.storedRemoteManagementEnabled
    Reticulum.allowProbes = true
    Reticulum.storedRemoteManagementEnabled = true
    transport.transportIdentity = Identity()
    transport.transportEnabled = true
    transport.setNetworkIdentity(networkIdentity)
    transport.register(interface: sink)
  }

  override func tearDown() {
    transport.stop()
    Reticulum.allowProbes = savedProbes
    Reticulum.storedRemoteManagementEnabled = savedManagement
    super.tearDown()
  }

  private var announced: Set<Data> {
    Set(sink.sent.filter { $0.packetType == .announce }.map(\.destinationHash))
  }

  private func managementHashes() throws -> Set<Data> {
    let network = try Destination(
      identity: networkIdentity, direction: .in, kind: .single, appName: "rnstransport",
      aspects: ["network"])
    let instance = try Destination(
      identity: networkIdentity, direction: .in, kind: .single, appName: "rnstransport",
      aspects: ["network", "instance", RNSUtilities.hexrep(networkIdentity.hash, delimit: false)])
    return [
      try XCTUnwrap(transport.probeDestination).hash,
      try XCTUnwrap(transport.remoteManagementDestination).hash, network.hash, instance.hash,
    ]
  }

  func testTheFirstRoundGoesFifteenSecondsAfterStart() throws {
    let before = Date().timeIntervalSince1970
    try transport.start()
    let after = Date().timeIntervalSince1970

    transport.announceManagementDestinations(now: before + 14)
    XCTAssertEqual(announced, [])
    transport.announceManagementDestinations(now: after + 16)
    XCTAssertEqual(announced, try managementHashes())
  }

  func testLaterRoundsGoEveryTwoHours() throws {
    try transport.start()
    let first = Date().timeIntervalSince1970 + 16
    transport.announceManagementDestinations(now: first)
    let afterFirst = sink.sent.count

    transport.announceManagementDestinations(now: first + Transport.managementAnnounceInterval)
    XCTAssertEqual(sink.sent.count, afterFirst, "`>` at Transport.py:1179")
    transport.announceManagementDestinations(
      now: first + Transport.managementAnnounceInterval + 1)
    XCTAssertGreaterThan(sink.sent.count, afterFirst)
  }

  func testTheJobsLoopSendsTheRound() throws {
    try transport.start()
    transport.lastManagementAnnounce = 0
    transport.runJobs()
    XCTAssertEqual(announced, try managementHashes())
  }
}
