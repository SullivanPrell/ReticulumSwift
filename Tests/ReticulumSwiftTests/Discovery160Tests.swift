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

/// RNS 1.6.0's interface discovery: stamps come from `RNS.Stamps` with fractional values, an
/// announce carries the interface's quantized destination and path-request costs, and a
/// receiver ignores an announce from beyond `PATHFINDER_M - 1` hops (`Discovery.py:52`, `171-172`,
/// `294-296`, `345-346`).
final class Discovery160Tests: XCTestCase {

  private var transport: Transport!

  override func setUp() {
    super.setUp()
    transport = Transport()
    transport.transportIdentity = Identity()
  }

  /// A cheap discoverable listener, so the real stamper finds its stamp at once.
  private func server() -> TCPServerInterface {
    let server = TCPServerInterface(name: "hub", port: 4965)
    server.discoverable = true
    server.discoveryName = "Example hub"
    server.reachableOn = "hub.example.net"
    server.discoveryStampValue = 1
    return server
  }

  private func pairs(_ appData: Data) throws -> [(MsgPack.Value, MsgPack.Value)] {
    guard case .map(let entries) = try MsgPack.decode(Data(appData.dropFirst().dropLast(32)))
    else { throw XCTSkip("not a map") }
    return entries
  }

  // MARK: - Stamper

  /// `self.stamper = RNS.Stamps` (`Discovery.py:52`, `264`).
  func testTheBuiltInStamperIsRNSStamps() throws {
    let stamper = DiscoveryStamper()
    let material = Hashes.fullHash(Data("discovery".utf8))
    let stamp = try XCTUnwrap(
      stamper.generateStamp(material: material, targetCost: 2.5, expandRounds: 2))
    let workblock = stamper.stampWorkblock(material: material, expandRounds: 2)

    XCTAssertEqual(stamper.stampSize, 32)
    XCTAssertEqual(stamp.count, 32)
    XCTAssertEqual(workblock, Stamps.stampWorkblock(material, expandRounds: 2))
    XCTAssertTrue(stamper.stampValid(stamp: stamp, targetCost: 2.5, workblock: workblock))
    XCTAssertEqual(
      stamper.stampValue(workblock: workblock, stamp: stamp),
      Stamps.stampValue(workblock: workblock, stamp: stamp))
  }

  /// With no stamper injected, a stack uses the built-in one, as Python no longer needs LXMF.
  func testAConfigurationDefaultsToTheBuiltInStamper() {
    let configuration = Reticulum.Configuration(storagePath: URL(fileURLWithPath: "/tmp/unused"))
    XCTAssertTrue(configuration.discoveryStampValidator is DiscoveryStamper)
    XCTAssertTrue(configuration.discoveryStampGenerator is DiscoveryStamper)
  }

  // MARK: - Costs on the wire

  /// `DST_COST` and `PR_COST` follow `TRANSPORT_VERS`, quantized, falling back to the
  /// transport's costs (`Discovery.py:166-172`, `Interface.py:350-358`).
  func testAnAnnounceCarriesTheInterfaceCostsQuantized() throws {
    let iface = server()
    iface.destinationCost = 23.4567
    let announcer = try XCTUnwrap(
      InterfaceAnnouncer(transport: transport, stampGenerator: DiscoveryStamper()))

    let entries = try pairs(try XCTUnwrap(announcer.announceData(for: iface)))
    let keys = entries.compactMap { k, _ -> UInt64? in
      if case .uint(let n) = k { return n }
      return nil
    }
    let vers = try XCTUnwrap(keys.firstIndex(of: 0xFC))
    XCTAssertEqual(Array(keys[vers...].prefix(3)), [0xFC, 0xFB, 0xFA])
    let values = Dictionary(uniqueKeysWithValues: zip(keys, entries.map(\.1)))
    XCTAssertEqual(values[0xFB], .double(Stamps.quantizeCost(23.4567)))
    XCTAssertEqual(values[0xFA], .double(Stamps.quantizeCost(transport.stamps.prCost)))
  }

  /// The receiver records `dst_cost`, `pr_cost` and `hops`, and ignores an announce from
  /// `PATHFINDER_M` hops (`Discovery.py:292-296`, `345-346`, `369-371`).
  func testTheReceiverRecordsCostsAndIgnoresUnreachableHops() throws {
    let iface = server()
    iface.destinationCost = 30
    iface.prCost = 9.1
    let announcer = try XCTUnwrap(
      InterfaceAnnouncer(transport: transport, stampGenerator: DiscoveryStamper()))
    let appData = try XCTUnwrap(announcer.announceData(for: iface))
    func receive(hops: Int) -> DiscoveredInterfaceInfo? {
      var received: DiscoveredInterfaceInfo?
      InterfaceAnnounceHandler(
        requiredValue: 1, stampValidator: DiscoveryStamper(), hopsTo: { _ in hops },
        callback: { received = $0 }
      ).receivedAnnounce(
        destinationHash: Data(repeating: 1, count: 16), identity: Identity(), appData: appData,
        announcePacketHash: Data(repeating: 2, count: 32), isPathResponse: false)
      return received
    }

    let info = try XCTUnwrap(receive(hops: Transport.pathfinderM - 1))
    XCTAssertEqual(info.dstCost, 30)
    XCTAssertEqual(info.prCost, Stamps.quantizeCost(9.1))
    XCTAssertEqual(info.hops, Transport.pathfinderM - 1)
    XCTAssertGreaterThanOrEqual(info.value, 1)
    XCTAssertNil(receive(hops: Transport.pathfinderM))
  }

  // MARK: - Lifecycle

  /// With the built-in stamper every stack that has a discoverable interface runs an
  /// announcer, so a stopped one must give its thread back: 64 parked loops exhaust GCD's
  /// pool and deadlock anything else that waits on a global queue.
  func testStoppedAnnouncersHoldNoThread() throws {
    // Held, as a transport holds its announcer; a released one's loop never runs.
    var held: [InterfaceAnnouncer] = []
    for _ in 0..<80 {
      let announcer = try XCTUnwrap(
        InterfaceAnnouncer(transport: transport, stampGenerator: DiscoveryStamper()))
      announcer.start()
      announcer.stop()
      held.append(announcer)
    }
    defer { withExtendedLifetime(held) {} }
    let ran = expectation(description: "a background block still runs")
    DispatchQueue.global(qos: .background).async { ran.fulfill() }
    wait(for: [ran], timeout: 5)
  }

  /// A stopped transport releases its discovery jobs, so a restarted stack doesn't keep the
  /// old ones running.
  func testStoppingTheTransportReleasesItsDiscoveryJobs() {
    transport.enableDiscovery(stampGenerator: DiscoveryStamper())
    transport.enableBlackholeUpdater()
    XCTAssertNotNil(transport.interfaceAnnouncer)

    transport.stop()

    XCTAssertNil(transport.interfaceAnnouncer)
    XCTAssertNil(transport.blackholeUpdater)
  }

  // MARK: - Blackhole

  /// `BlackholeUpdater.start` wants `rnstransport.info.blackhole` (`Discovery.py:906-908`).
  func testTheBlackholeUpdaterWantsBlackholeAnnounces() {
    let updater = BlackholeUpdater(transport: transport)
    updater.start()
    defer { updater.stop() }

    XCTAssertTrue(
      transport.unwantsDestinationType(
        "rnstransport.info.blackhole", requester: transport.applicationIdentity.hash),
      "registered by start()")
  }
}
