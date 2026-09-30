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

/// The auto-connect rules RNS 1.5.5 added (`Discovery.py:483-490`, `772-876`).
///
/// Only a discovered `BackboneInterface` is dialled, and only when its announce names the
/// `RNS` implementation at 1.5.2 or later, unless `autoconnect_unverified_implementations` is
/// set. A name already in use gets a sequence number. Where Backbone isn't supported, which
/// includes Darwin, the endpoint is dialled as a `TCPClientInterface`. The monitor drops an
/// interface someone detached by hand.
final class DiscoveryAutoconnectCriteriaTests: XCTestCase {

  final class Peer: Interface {
    var name: String
    var bitrate: Int = 5_000_000
    var isOnline: Bool
    var stopped = false
    var inboundHandler: ((Packet, any Interface) -> Void)?
    let interfaceState = InterfaceState()
    init(name: String, online: Bool = false) {
      self.name = name
      self.isOnline = online
    }
    func start() throws {}
    func stop() { stopped = true }
    func send(_ packet: Packet) throws {}
  }

  private var transport: Transport!
  private var discovery: InterfaceDiscovery!
  private var storage: URL!

  override func setUp() {
    super.setUp()
    storage = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("autoconnect-criteria-\(UUID().uuidString)")
    transport = Transport()
    transport.transportIdentity = Identity()
    discovery = InterfaceDiscovery(storagePath: storage.path)
    discovery.transport = transport
    Reticulum.storedMaxAutoconnectedInterfaces = 4
  }

  override func tearDown() {
    discovery.stopMonitoring()
    Reticulum.storedMaxAutoconnectedInterfaces = 0
    Reticulum.storedAutoconnectUnverifiedImplementations = false
    try? FileManager.default.removeItem(at: storage)
    super.tearDown()
  }

  private func discovered(
    type: String = "BackboneInterface", reachableOn: String = "hub.example.net",
    port: Int = 4965, name: String = "Example hub",
    implName: String? = "RNS", version: String? = "1.5.5"
  ) -> DiscoveredInterfaceInfo {
    let now = Date().timeIntervalSince1970
    var info = DiscoveredInterfaceInfo(
      type: type, transport: true, name: name, received: now,
      stamp: Data(repeating: 0xAB, count: 32), value: 16,
      transportID: String(repeating: "a", count: 32),
      networkID: String(repeating: "b", count: 32), hops: 1,
      latitude: nil, longitude: nil, height: nil,
      ifacNetname: nil, ifacNetkey: nil,
      reachableOn: reachableOn, port: port,
      frequency: nil, bandwidth: nil, sf: nil, cr: nil,
      modulation: nil, channel: nil, configEntry: nil,
      discoveryHash: Data(repeating: 0xCD, count: 32),
      discovered: now, lastHeard: now, heardCount: 1)
    info.implName = implName
    info.version = version
    return info
  }

  private var dialled: [any Interface] { transport.interfaces.filter { $0.autoconnectHash != nil } }

  // MARK: - Types

  func testOnlyADiscoveredBackboneIsDialled() {
    discovery.autoconnect(discovered(type: "TCPServerInterface"))
    XCTAssertTrue(dialled.isEmpty, "AUTOCONNECT_TYPES is [\"BackboneInterface\"]")
    discovery.autoconnect(discovered())
    XCTAssertEqual(dialled.count, 1)
  }

  #if canImport(Darwin)
  func testOnDarwinADiscoveredBackboneIsDialledAsATCPClient() throws {
    discovery.autoconnect(discovered())
    let client = try XCTUnwrap(dialled.first as? TCPClientInterface)
    XCTAssertEqual(client.host, "hub.example.net")
    XCTAssertEqual(client.port, 4965)
  }
  #endif

  // MARK: - Implementation criteria

  func testAnotherImplementationIsNotDialled() {
    discovery.autoconnect(discovered(implName: "RNSwift", version: "1.22.1"))
    XCTAssertTrue(dialled.isEmpty)
  }

  func testAnAnnounceWithoutImplementationInfoIsNotDialled() {
    discovery.autoconnect(discovered(implName: nil, version: nil))
    discovery.autoconnect(discovered(implName: "RNS", version: nil))
    discovery.autoconnect(discovered(implName: "RNS", version: ""))
    XCTAssertTrue(dialled.isEmpty)
  }

  func testAVersionBelowTheMinimumIsNotDialled() {
    discovery.autoconnect(discovered(version: "1.5.1"))
    discovery.autoconnect(discovered(version: "1.4.9"))
    discovery.autoconnect(discovered(version: "1.5"))
    XCTAssertTrue(dialled.isEmpty)
  }

  func testTheMinimumVersionAndLaterAreDialled() {
    for (i, v) in ["1.5.2", "1.10.0", "2.0", "1.5.2rc1"].enumerated() {
      var info = discovered(reachableOn: "hub\(i).example.net", name: "hub\(i)", version: v)
      info.discoveryHash = Data(repeating: UInt8(i), count: 32)
      discovery.autoconnect(info)
    }
    XCTAssertEqual(dialled.count, 4)
  }

  func testUnverifiedImplementationsAreDialledWhenAllowed() {
    Reticulum.storedAutoconnectUnverifiedImplementations = true
    discovery.autoconnect(discovered(implName: nil, version: nil))
    XCTAssertEqual(dialled.count, 1)
  }

  func testVersionTupleMatchesPython() {
    XCTAssertEqual(InterfaceDiscoveryHelpers.versionTuple("1.5.2"), [1, 5, 2])
    XCTAssertEqual(InterfaceDiscoveryHelpers.versionTuple(" 1.5 "), [1, 5])
    XCTAssertEqual(InterfaceDiscoveryHelpers.versionTuple("1.x.3"), [1])
    XCTAssertEqual(InterfaceDiscoveryHelpers.versionTuple("2rc1.4"), [2, 4])
    XCTAssertNil(InterfaceDiscoveryHelpers.versionTuple("x.1"))
    XCTAssertNil(InterfaceDiscoveryHelpers.versionTuple(""))
  }

  func testTheOptionIsReadFromConfig() {
    let cfg = ReticulumConfig.parse(
      """
      [reticulum]
        autoconnect_unverified_implementations = yes
      """)
    XCTAssertTrue(cfg.reticulum.autoconnectUnverifiedImplementations)
    XCTAssertFalse(
      cfg.unrecognisedKeys.contains("reticulum.autoconnect_unverified_implementations"))
  }

  // MARK: - Naming and IFAC

  func testANameInUseGetsASequenceNumber() {
    transport.register(interface: Peer(name: "Example hub"))
    transport.register(interface: Peer(name: "Example hub (2)"))
    discovery.autoconnect(discovered())
    XCTAssertEqual(dialled.first?.name, "Example hub (3)")
  }

  func testTheStringNoneIsNotAnIfacValue() throws {
    var info = discovered()
    info.ifacNetname = "None"
    info.ifacNetkey = "None"
    discovery.autoconnect(info)
    let iface = try XCTUnwrap(dialled.first)
    XCTAssertNil(iface.ifacNetname)
    XCTAssertNil(iface.ifacNetkey)
    XCTAssertNil(iface.ifacKey)
  }

  // MARK: - Monitoring

  func testAnInterfaceDetachedByHandLeavesMonitoring() {
    var reenabled = false
    discovery.reenableBootstrapInterfaces = { reenabled = true }
    let peer = Peer(name: "peer", online: true)
    peer.autoconnectHash = Data(repeating: 0xEE, count: 32)
    transport.register(interface: peer)
    discovery.monitorInterface(peer)
    transport.deregister(interface: peer)

    discovery.monitorTick()
    XCTAssertTrue(reenabled, "a detached interface doesn't count as a connected peer")
    XCTAssertFalse(peer.stopped, "teardown skips an interface that's no longer attached")
    XCTAssertEqual(discovery.monitoredInterfaceCount, 0)
  }
}
