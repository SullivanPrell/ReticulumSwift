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

/// The jobs loop's link-failure path rediscovery (`Transport.py:697-724`, `:885-955`,
/// `:1226-1280`).
///
/// A link this node initiated that closes before it activates expires the path on a
/// non-transport node, and asks the network for a new one. A relayed link request that
/// nobody proves within its proof timeout leaves the link table, and in four cases asks for
/// the destination's path again. The requests queue, at most 32, and go out one every half
/// second.
final class LinkPathRediscoveryTests: XCTestCase {

  // MARK: - Fixtures

  final class MeshIface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var mode: InterfaceMode = .full
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private let lock = NSLock()
    private var sentPackets: [(packet: Packet, at: Date)] = []
    var sent: [Packet] {
      lock.lock()
      defer { lock.unlock() }
      return sentPackets.map(\.packet)
    }
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {
      lock.lock()
      sentPackets.append((packet, Date()))
      lock.unlock()
    }

    /// The path requests sent here for `destinationHash`.
    func pathRequests(for destinationHash: Data) -> [Packet] {
      sent.filter { Self.isPathRequest($0, for: destinationHash) }
    }

    /// When this interface sent each path request for `destinationHash`.
    func pathRequestTimes(for destinationHash: Data) -> [Date] {
      lock.lock()
      defer { lock.unlock() }
      return sentPackets.filter { Self.isPathRequest($0.packet, for: destinationHash) }.map(\.at)
    }

    private static func isPathRequest(_ packet: Packet, for destinationHash: Data) -> Bool {
      packet.destinationHash == Transport.pathRequestDestinationHash
        && packet.data.prefix(Constants.truncatedHashLength) == destinationHash
    }
  }

  /// Stands in for the shared instance's interface to one local client.
  final class ClientIface: Interface, LocalClientServingInterface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var clientCount: Int = 1
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private let lock = NSLock()
    private var sentPackets: [Packet] = []
    var sent: [Packet] {
      lock.lock()
      defer { lock.unlock() }
      return sentPackets
    }
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {
      lock.lock()
      sentPackets.append(packet)
      lock.unlock()
    }
  }

  private func node(transportEnabled: Bool = false) -> (Transport, MeshIface) {
    let t = Transport()
    t.transportEnabled = transportEnabled
    let mesh = MeshIface(name: "mesh")
    t.register(interface: mesh)
    return (t, mesh)
  }

  private func remote(_ aspect: String = "far") throws -> (Identity, Destination) {
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .out, kind: .single, appName: "rediscovery",
      aspects: [aspect])
    return (identity, destination)
  }

  /// A path to `destination` through `iface`, stored at the wire hop count `hops`.
  private func installPath(
    _ t: Transport, to destination: Destination, identity: Identity, via iface: any Interface,
    hops: UInt8 = 0
  ) {
    t.restore(
      path: Transport.PathEntry(
        destinationHash: destination.hash, nextHopInterface: iface, hops: hops,
        lastHeard: Date(), identityHash: identity.hash),
      forDestination: destination.hash)
  }

  private func queued(_ t: Transport) -> [Data] {
    t.queuedDiscoveryPathRequests.map(\.destinationHash)
  }

  private func waitUntil(
    _ description: String, timeout: TimeInterval = 3, _ condition: () -> Bool
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { usleep(10_000) }
    XCTAssertTrue(condition(), description)
  }

  // MARK: - Closed pending links (Transport.py:697-724)

  func testAPendingLinkThatClosesExpiresThePathAndAsksAgain() throws {
    let (t, mesh) = node()
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: mesh)
    let link = try Link.initiate(destination: destination, transport: t)

    // The watchdog's establishment timeout ends a pending link with `close()`.
    link.close()
    t.runLinkJobs(now: Date())

    XCTAssertFalse(
      t.hasPath(to: destination.hash),
      "`Transport.expire_path(link.destination.hash)` (Transport.py:705)")
    XCTAssertEqual(queued(t), [destination.hash], "`path_requests[...] = None` (Transport.py:720)")
    XCTAssertNil(
      t.queuedDiscoveryPathRequests.first?.blockedInterface, "`blocked_if = None` (:719)")
    XCTAssertNil(t.links[try XCTUnwrap(link.linkID)], "`pending_links.remove` (Transport.py:723)")
  }

  func testAPendingLinkTornDownByItsOwnerAlsoRediscovers() throws {
    let (t, mesh) = node()
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: mesh)
    let link = try Link.initiate(destination: destination, transport: t)

    try link.teardown()
    t.runLinkJobs(now: Date())

    XCTAssertFalse(t.hasPath(to: destination.hash))
    XCTAssertEqual(queued(t), [destination.hash])
  }

  func testTheQueuedRequestGoesOutAfterTheThrottle() throws {
    let (t, mesh) = node()
    t.discoveryPathRequestTxThrottle = 0.05
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: mesh)
    let link = try Link.initiate(destination: destination, transport: t)
    link.close()

    t.runLinkJobs(now: Date())

    XCTAssertTrue(
      mesh.pathRequests(for: destination.hash).isEmpty,
      "`handle_disovery_path_requests` sleeps before each request (Transport.py:1251)")
    waitUntil("the rediscovery request went out") {
      mesh.pathRequests(for: destination.hash).count == 1
    }
    XCTAssertTrue(t.queuedDiscoveryPathRequests.isEmpty)
  }

  func testATransportNodeKeepsThePathOfAFailedLink() throws {
    let (t, mesh) = node(transportEnabled: true)
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: mesh)
    let link = try Link.initiate(destination: destination, transport: t)
    link.close()

    t.runLinkJobs(now: Date())

    XCTAssertTrue(t.hasPath(to: destination.hash), "`if not transport_enabled()` (:704)")
    XCTAssertTrue(queued(t).isEmpty)
    XCTAssertNil(t.links[try XCTUnwrap(link.linkID)], "the closed link still leaves the table")
  }

  func testASharedInstanceClientLeavesTheRequestToTheInstance() throws {
    let (t, mesh) = node()
    t.isConnectedToSharedInstance = true
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: mesh)
    let link = try Link.initiate(destination: destination, transport: t)
    link.close()

    t.runLinkJobs(now: Date())

    XCTAssertFalse(t.hasPath(to: destination.hash))
    XCTAssertTrue(
      queued(t).isEmpty, "`if not Transport.owner.is_connected_to_shared_instance` (:710)")
  }

  func testARecentRequestHoldsOffTheRediscovery() throws {
    let (t, mesh) = node()
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: mesh)
    try t.requestPath(for: destination.hash)
    let asked = try XCTUnwrap(t.pathRequestTimestamp(for: destination.hash))
    let link = try Link.initiate(destination: destination, transport: t)
    link.close()

    t.runLinkJobs(now: Date(timeIntervalSince1970: asked + Transport.pathRequestMinInterval))

    XCTAssertFalse(t.hasPath(to: destination.hash), "the path still expires")
    XCTAssertTrue(
      queued(t).isEmpty,
      "`if time.time() - last_path_request > Transport.PATH_REQUEST_MI` (:716) is strict")
  }

  func testAnActiveLinkThatClosesDoesNotRediscover() throws {
    let (t, mesh) = node()
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: mesh)
    let link = try Link.initiate(destination: destination, transport: t)
    // `Transport.activate_link` moves a link out of `pending_links` once it activates.
    link.establishedAt = Date()
    link.close()

    t.runLinkJobs(now: Date())

    XCTAssertTrue(t.hasPath(to: destination.hash))
    XCTAssertTrue(queued(t).isEmpty)
    XCTAssertNil(t.links[try XCTUnwrap(link.linkID)], "`active_links.remove` (Transport.py:743)")
  }

  func testALinkThatClosedIsCountedOnce() throws {
    let (t, mesh) = node()
    t.discoveryPathRequestTxThrottle = 60
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: mesh)
    let link = try Link.initiate(destination: destination, transport: t)
    link.close()
    t.runLinkJobs(now: Date())
    installPath(t, to: destination, identity: identity, via: mesh)

    t.runLinkJobs(now: Date().addingTimeInterval(Transport.pathRequestMinInterval + 1))

    XCTAssertTrue(t.hasPath(to: destination.hash), "the second pass found no closed link")
    XCTAssertEqual(queued(t), [destination.hash])
  }

  // MARK: - The discovery request queue (Transport.py:1226-1280)

  func testTheQueueHoldsEachDestinationOnce() throws {
    let (t, _) = node()
    t.discoveryPathRequestTxThrottle = 60
    let target = Data(repeating: 0x41, count: Constants.truncatedHashLength)

    t.queueDiscoveryPathRequests([.init(destinationHash: target, blockedInterface: nil)])
    t.queueDiscoveryPathRequests([.init(destinationHash: target, blockedInterface: nil)])

    XCTAssertEqual(queued(t), [target], "`if destination_hash not in queued_destinations` (:1230)")
  }

  func testTheQueueHoldsAtMost32() throws {
    let (t, _) = node()
    t.discoveryPathRequestTxThrottle = 60
    let batch = (0..<40).map {
      Transport.QueuedDiscoveryPathRequest(
        destinationHash: Data(repeating: UInt8($0), count: Constants.truncatedHashLength),
        blockedInterface: nil)
    }

    t.queueDiscoveryPathRequests(batch)

    XCTAssertEqual(Transport.maxQueuedDiscoveryPathRequests, 32, "`max_queued_discovery_prs`")
    XCTAssertEqual(t.queuedDiscoveryPathRequests.count, 32)
  }

  func testABlockedInterfaceIsSkipped() throws {
    let (t, mesh) = node()
    t.discoveryPathRequestTxThrottle = 0.01
    let other = MeshIface(name: "other")
    t.register(interface: other)
    let target = Data(repeating: 0x42, count: Constants.truncatedHashLength)

    t.queueDiscoveryPathRequests([.init(destinationHash: target, blockedInterface: mesh)])

    waitUntil("the request went out on the other interface") {
      other.pathRequests(for: target).count == 1
    }
    usleep(100_000)
    XCTAssertTrue(
      mesh.pathRequests(for: target).isEmpty,
      "`if interface != blocked_if: Transport.request_path(...)` (Transport.py:1263)")
  }

  func testRequestsGoOutOneThrottleApart() throws {
    let (t, mesh) = node()
    t.discoveryPathRequestTxThrottle = 0.2
    let first = Data(repeating: 0x43, count: Constants.truncatedHashLength)
    let second = Data(repeating: 0x44, count: Constants.truncatedHashLength)
    t.queueDiscoveryPathRequests([.init(destinationHash: first, blockedInterface: nil)])
    t.queueDiscoveryPathRequests([.init(destinationHash: second, blockedInterface: nil)])

    waitUntil("both requests went out") {
      mesh.pathRequests(for: first).count == 1 && mesh.pathRequests(for: second).count == 1
    }
    let sentAt = try XCTUnwrap(mesh.pathRequestTimes(for: first).first)
    let nextAt = try XCTUnwrap(mesh.pathRequestTimes(for: second).first)
    XCTAssertGreaterThanOrEqual(
      nextAt.timeIntervalSince(sentAt), 0.15, "the second waits a throttle (Transport.py:1251)")
  }

  // MARK: - Unproven link-table entries (Transport.py:885-955)

  /// A relayed link request's link-table entry, as `handleLinkRequest` records it.
  private func route(
    for destination: Destination, from initiatorSide: any Interface,
    to responderSide: any Interface, takenHops: Int, proofTimeout: Date,
    validated: Bool = false, lastHeard: Date = Date()
  ) -> Transport.LinkRoute {
    var route = Transport.LinkRoute(
      linkID: SecureRandom.bytes(Constants.truncatedHashLength),
      initiatorSideInterface: initiatorSide,
      responderSideInterface: responderSide,
      initiatorSideInterfaceName: initiatorSide.name,
      responderSideInterfaceName: responderSide.name,
      destinationHash: destination.hash,
      lastHeard: lastHeard,
      takenHops: takenHops,
      proofTimeout: proofTimeout)
    route.validated = validated
    return route
  }

  private func relay(transportEnabled: Bool = true) -> (Transport, MeshIface, MeshIface) {
    let t = Transport()
    t.transportEnabled = transportEnabled
    let a = MeshIface(name: "toward initiator")
    let b = MeshIface(name: "toward responder")
    t.register(interface: a)
    t.register(interface: b)
    return (t, a, b)
  }

  func testAnUnprovenEntryLeavesAtItsProofTimeoutNotTheLinkTimeout() throws {
    let (t, a, b) = relay()
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: b, hops: 2)
    let now = Date()
    let waiting = route(
      for: destination, from: a, to: b, takenHops: 3, proofTimeout: now.addingTimeInterval(1),
      lastHeard: now.addingTimeInterval(-Link.staleTime * 2))
    let expired = route(
      for: destination, from: a, to: b, takenHops: 3, proofTimeout: now.addingTimeInterval(-1))
    t.restore(linkRoute: waiting)
    t.restore(linkRoute: expired)

    t.runLinkJobs(now: now)

    XCTAssertNotNil(t.linkRoutes[waiting.linkID], "only `IDX_LT_PROOF_TMO` ages it (:884)")
    XCTAssertNil(t.linkRoutes[expired.linkID])
  }

  func testAValidatedEntryLeavesWhenItsInterfaceDoes() throws {
    let (t, a, b) = relay()
    let (_, destination) = try remote()
    let entry = route(
      for: destination, from: a, to: b, takenHops: 1,
      proofTimeout: Date().addingTimeInterval(-60), validated: true)
    t.restore(linkRoute: entry)

    t.runLinkJobs(now: Date())
    XCTAssertNotNil(t.linkRoutes[entry.linkID], "a validated entry ignores the proof timeout")

    t.deregister(interface: b)
    t.runLinkJobs(now: Date())
    XCTAssertNil(
      t.linkRoutes[entry.linkID],
      "`elif not link_entry[IDX_LT_NH_IF] in Transport.interfaces` (Transport.py:877)")
  }

  func testAMissingPathIsRequestedAgain() throws {
    let (t, a, b) = relay()
    let (_, destination) = try remote()
    t.restore(
      linkRoute: route(
        for: destination, from: a, to: b, takenHops: 3, proofTimeout: Date().addingTimeInterval(-1)
      ))

    t.runLinkJobs(now: Date())

    XCTAssertEqual(queued(t), [destination.hash], "`if not Transport.has_path(...)` (:899)")
  }

  func testALocalClientsLinkRequestIsRediscovered() throws {
    let (t, a, b) = relay(transportEnabled: false)
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: b, hops: 3)
    t.restore(
      linkRoute: route(
        for: destination, from: a, to: b, takenHops: 0, proofTimeout: Date().addingTimeInterval(-1)
      ))

    t.runLinkJobs(now: Date())

    XCTAssertEqual(queued(t), [destination.hash], "`lr_taken_hops == 0` (Transport.py:906)")
    XCTAssertFalse(
      t.hasPath(to: destination.hash), "a non-transport node drops the path (Transport.py:955)")
  }

  func testAOneHopDestinationIsMarkedUnresponsiveAndAskedForElsewhere() throws {
    let (t, a, b) = relay()
    let (identity, destination) = try remote()
    // Wire hops 0 is Python's hop count 1: Python adds one on receipt (Transport.py:1800).
    installPath(t, to: destination, identity: identity, via: b, hops: 0)
    t.restore(
      linkRoute: route(
        for: destination, from: a, to: b, takenHops: 3, proofTimeout: Date().addingTimeInterval(-1)
      ))

    t.runLinkJobs(now: Date())

    XCTAssertEqual(queued(t), [destination.hash], "`Transport.hops_to(...) == 1` (:915)")
    XCTAssertTrue(
      t.queuedDiscoveryPathRequests.first?.blockedInterface === a,
      "`blocked_if = link_entry[IDX_LT_RCVD_IF]` (Transport.py:918)")
    XCTAssertTrue(t.pathIsUnresponsive(to: destination.hash), "Transport.py:931")
    XCTAssertTrue(t.hasPath(to: destination.hash), "a transport node keeps the path")
  }

  func testAOneHopInitiatorIsMarkedUnresponsiveAndAskedForElsewhere() throws {
    let (t, a, b) = relay()
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: b, hops: 4)
    t.restore(
      linkRoute: route(
        for: destination, from: a, to: b, takenHops: 1, proofTimeout: Date().addingTimeInterval(-1)
      ))

    t.runLinkJobs(now: Date())

    XCTAssertEqual(queued(t), [destination.hash], "`lr_taken_hops == 1` (Transport.py:937)")
    XCTAssertTrue(t.queuedDiscoveryPathRequests.first?.blockedInterface === a, ":940")
    XCTAssertTrue(t.pathIsUnresponsive(to: destination.hash), "Transport.py:944")
  }

  func testABoundaryInterfaceDoesNotMarkThePathUnresponsive() throws {
    let (t, a, b) = relay()
    a.mode = .boundary
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: b, hops: 4)
    t.restore(
      linkRoute: route(
        for: destination, from: a, to: b, takenHops: 1, proofTimeout: Date().addingTimeInterval(-1)
      ))

    t.runLinkJobs(now: Date())

    XCTAssertEqual(queued(t), [destination.hash])
    XCTAssertFalse(
      t.pathIsUnresponsive(to: destination.hash),
      "`.mode != MODE_BOUNDARY` (Transport.py:943)")
  }

  func testAnUnremarkableTimeoutAsksForNothing() throws {
    let (t, a, b) = relay()
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: b, hops: 4)
    t.restore(
      linkRoute: route(
        for: destination, from: a, to: b, takenHops: 3, proofTimeout: Date().addingTimeInterval(-1)
      ))

    t.runLinkJobs(now: Date())

    XCTAssertTrue(queued(t).isEmpty)
    XCTAssertFalse(t.pathIsUnresponsive(to: destination.hash))
  }

  func testARecentRequestHoldsOffAllButAMissingPath() throws {
    let (t, a, b) = relay()
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: b, hops: 0)
    try t.requestPath(for: destination.hash)
    let asked = try XCTUnwrap(t.pathRequestTimestamp(for: destination.hash))
    t.restore(
      linkRoute: route(
        for: destination, from: a, to: b, takenHops: 1, proofTimeout: Date().addingTimeInterval(-1)
      ))

    t.runLinkJobs(
      now: Date(timeIntervalSince1970: asked + Transport.pathRequestMinInterval - 1))

    XCTAssertTrue(queued(t).isEmpty, "`path_request_throttle` (Transport.py:894)")
    XCTAssertFalse(t.pathIsUnresponsive(to: destination.hash))
  }

  func testARelayedLinkRequestRecordsItsHopsAndProofTimeout() throws {
    let (t, a, b) = relay()
    let (identity, destination) = try remote()
    installPath(t, to: destination, identity: identity, via: b, hops: 2)
    let initiator = Identity()
    let request = Packet(
      destinationType: .single, packetType: .linkRequest, destinationHash: destination.hash,
      data: initiator.publicKeyBytes)

    let before = Date()
    a.inboundHandler?(request, a)

    let recorded = try XCTUnwrap(t.linkRoutes.values.first)
    XCTAssertEqual(recorded.takenHops, 1, "`packet.hops` after the inbound +1 (Transport.py:2096)")
    // remaining_hops is the path's Python hop count, 3 (Transport.py:2062).
    let expected =
      Transport.extraLinkProofTimeout(for: b) + Link.establishmentTimeoutPerHop * 3
    XCTAssertEqual(
      recorded.proofTimeout.timeIntervalSince(before), expected, accuracy: 1,
      "Transport.py:2061-2062")
  }

  // MARK: - Path-request answers mark the destination used

  func testAnsweringFromThePathTableMarksTheDestinationUsed() throws {
    let (t, a, b) = relay()
    let local = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "rediscovery",
      aspects: ["answered"])
    b.inboundHandler?(try Announce.make(for: local), b)
    XCTAssertTrue(t.hasPath(to: local.hash))
    XCTAssertNil(t.knownDestinationLastUsed[local.hash])

    a.inboundHandler?(
      Packet(
        destinationType: .plain, packetType: .data,
        destinationHash: Transport.pathRequestDestinationHash,
        data: local.hash + SecureRandom.bytes(Constants.truncatedHashLength)),
      a)

    XCTAssertTrue(
      a.sent.contains { $0.context == .pathResponse && $0.destinationHash == local.hash })
    XCTAssertNotNil(
      t.knownDestinationLastUsed[local.hash],
      "`RNS.Identity._used_destination_data(packet.destination_hash)` (Transport.py:3521)")
  }

  // MARK: - Roaming-mode path requests (Transport.py:3468-3469)

  /// A roaming-mode interface gets no answer about a path that leads back over it.
  func testARoamingInterfaceIsntAnsweredWithAPathOverItself() throws {
    let (t, a, b) = relay()
    a.mode = .roaming
    let overA = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "rediscovery",
      aspects: ["over-a"])
    let overB = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "rediscovery",
      aspects: ["over-b"])
    a.inboundHandler?(try Announce.make(for: overA), a)
    b.inboundHandler?(try Announce.make(for: overB), b)
    XCTAssertTrue(t.hasPath(to: overA.hash))
    XCTAssertTrue(t.hasPath(to: overB.hash))

    a.inboundHandler?(pathRequest(for: overA.hash), a)
    a.inboundHandler?(pathRequest(for: overB.hash), a)

    XCTAssertEqual(
      a.sent.filter { $0.context == .pathResponse }.map(\.destinationHash), [overB.hash],
      "Transport.py:3468-3469")
  }

  // MARK: - Path requests for a local client's destination (Transport.py:3438-3448)

  private func sharedInstance() throws -> (
    Transport, MeshIface, MeshIface, ClientIface, Destination
  ) {
    let t = Transport()
    t.transportEnabled = false
    let asking = MeshIface(name: "asking")
    let elsewhere = MeshIface(name: "elsewhere")
    // No announce cap, so the answer isn't queued behind the relay of the client's announce.
    asking.bitrate = 0
    elsewhere.bitrate = 0
    let client = ClientIface(name: "LocalInterface[50001]")
    t.register(interface: asking)
    t.register(interface: elsewhere)
    t.register(interface: client)
    let onClient = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "rediscovery",
      aspects: ["client"])
    // A minute old, so the client's answer is more recently emitted, as Python requires of
    // an announce at the same hop count (`Transport.py:2237-2240`).
    let earlier = Date().timeIntervalSince1970 - 60
    client.inboundHandler?(try Announce.make(for: onClient, timestamp: earlier), client)
    XCTAssertTrue(t.hasPath(to: onClient.hash))
    return (t, asking, elsewhere, client, onClient)
  }

  private func pathRequest(for hash: Data) -> Packet {
    Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Transport.pathRequestDestinationHash,
      data: hash + SecureRandom.bytes(Constants.truncatedHashLength))
  }

  /// The client's answer goes out as an ordinary announce on every interface.
  ///
  /// The announce-table entry at `Transport.py:2384-2395` attaches the `attached_interface`
  /// that `:2336` cleared, not the interface that asked, and doesn't block rebroadcasts, so
  /// the jobs loop sends it everywhere with context `NONE` (`Transport.py:784-805`).
  func testTheClientsAnswerGoesOutAsAnAnnounce() throws {
    let (t, asking, elsewhere, client, onClient) = try sharedInstance()
    let sentBefore = (asking.sent.count, elsewhere.sent.count)

    asking.inboundHandler?(pathRequest(for: onClient.hash), asking)
    XCTAssertTrue(
      client.sent.contains { $0.destinationHash == Transport.pathRequestDestinationHash },
      "the request reaches the client (Transport.py:3585-3590)")
    XCTAssertTrue(t.pendingLocalPathRequest(for: onClient.hash) === asking, "Transport.py:3447")
    XCTAssertNotNil(t.knownDestinationLastUsed[onClient.hash], "Transport.py:3448")

    let answer = try Announce.make(for: onClient, isPathResponse: true)
    client.inboundHandler?(answer, client)

    for (iface, before) in [(asking, sentBefore.0), (elsewhere, sentBefore.1)] {
      let out = iface.sent.dropFirst(before).filter {
        $0.packetType == .announce && $0.destinationHash == onClient.hash
      }
      XCTAssertEqual(out.count, 1, "\(iface.name): Transport.py:2375-2395")
      XCTAssertEqual(out.first?.context, Packet.Context.none, "\(iface.name): Transport.py:785-786")
      XCTAssertEqual(
        out.first?.hops, answer.hops, "\(iface.name): `announce_hops = packet.hops` (:2332)")
      XCTAssertEqual(out.first?.headerType, .type2)
      XCTAssertEqual(out.first?.transportID, t.transportInstanceID)
    }
    XCTAssertNil(t.pendingLocalPathRequest(for: onClient.hash), "`.pop(...)` (:2381)")
  }

  func testASecondAnswerFindsNoRequestWaiting() throws {
    let (_, asking, _, client, onClient) = try sharedInstance()
    asking.inboundHandler?(pathRequest(for: onClient.hash), asking)
    let first = try Announce.make(
      for: onClient, timestamp: Date().timeIntervalSince1970 - 30, isPathResponse: true)
    client.inboundHandler?(first, client)
    let afterFirst = asking.sent.count
    XCTAssertGreaterThan(afterFirst, 0)

    // More recently emitted, so the path table takes it, and only the waiting request is
    // missing.
    let second = try Announce.make(for: onClient, isPathResponse: true)
    client.inboundHandler?(second, client)

    XCTAssertEqual(asking.sent.count, afterFirst)
  }

  func testAWaitingRequestLeavesWithItsInterface() throws {
    let (t, asking, _, _, onClient) = try sharedInstance()
    asking.inboundHandler?(pathRequest(for: onClient.hash), asking)
    XCTAssertNotNil(t.pendingLocalPathRequest(for: onClient.hash))

    t.deregister(interface: asking)
    t.sweepPendingLocalPathRequests()

    XCTAssertFalse(
      t.hasPendingLocalPathRequest(for: onClient.hash),
      "`if not pending_local_path_requests[...] in Transport.interfaces` (Transport.py:841)")
  }
}
