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

/// Link hop counts as Python RNS 1.5.5 keeps them.
///
/// Python counts a hop when a packet arrives (`Transport.py:1800`), except on a local client's
/// interface or the interface to a shared instance (`:1937-1940`), and every link, destination
/// and receipt gets that count. A relay's link-table entry holds the path's remaining hops
/// (`IDX_LT_REM_HOPS`) and the request's taken hops (`IDX_LT_HOPS`, `:2090-2098`). It carries a
/// proof only over the remaining hops (`:2641`, `:2672`) and link traffic only over the count
/// its direction expects (`:2134-2150`). A proof over another count re-balances the relay's
/// path first (`:2614-2634`). A responder reads the request's count (`Link.py:204`) and the RTT
/// packet's (`Link.py:525`).
final class LinkHopCountTests: XCTestCase {

  // MARK: - Fixtures

  /// Records what a transport transmits on it.
  class RecordingHop: Interface {
    let name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private(set) var sent: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  /// Stands in for `LocalServerClientInterface`.
  final class ServingHop: RecordingHop, LocalClientServingInterface {
    var clientCount: Int = 1
  }

  /// Hands what it sends to a paired interface, so a link completes its handshake.
  class LoopHop: Interface {
    let name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    weak var paired: LoopHop?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {
      let raw = try packet.pack()
      guard let paired else { return }
      paired.inboundHandler?(try Packet.unpack(raw), paired)
    }
  }

  /// A responder's connection to a local client it serves.
  final class ServingLoop: LoopHop, LocalClientServingInterface {
    var clientCount: Int = 1
  }

  /// A `LoopHop` that also records what it sends.
  final class TapLoop: LoopHop {
    private(set) var sent: [Packet] = []
    override func send(_ packet: Packet) throws {
      sent.append(packet)
      try super.send(packet)
    }
  }

  /// Transports hold interfaces weakly and links hold transports weakly.
  private var retained: [AnyObject] = []
  private var savedRebalance = Transport.allowLinkPathRebalance

  override func setUp() {
    super.setUp()
    savedRebalance = Transport.allowLinkPathRebalance
  }

  override func tearDown() {
    Transport.allowLinkPathRebalance = savedRebalance
    retained = []
    super.tearDown()
  }

  // MARK: - Relay harness

  /// A transport node relaying one link, with the responder's identity recalled.
  private struct Relay {
    let transport: Transport
    let towardInitiator: RecordingHop
    let towardResponder: RecordingHop
    let responder: Identity
    let linkID: Data
    let destinationHash: Data
  }

  /// `pathHops` is the wire count stored for the responder's destination. `remainingHops` and
  /// `takenHops` are the link-table entry's counts, as Python keeps them.
  private func makeRelay(
    pathHops: UInt8, remainingHops: Int, takenHops: Int = 1, validated: Bool = false,
    towardResponder: RecordingHop = RecordingHop(name: "R→B"),
    hairpin: Bool = false
  ) -> Relay {
    let t = Transport()
    t.transportEnabled = true
    let responder = Identity()
    let destinationHash = Data(repeating: 0x4D, count: Constants.truncatedHashLength)
    let linkID = Data(repeating: 0x71, count: Constants.truncatedHashLength)
    let towardInitiator = hairpin ? towardResponder : RecordingHop(name: "R←A")
    t.register(interface: towardInitiator)
    if !hairpin { t.register(interface: towardResponder) }

    t.restore(identity: responder, forDestination: destinationHash)
    t.injectPath(
      destinationHash, nextHop: SecureRandom.bytes(Constants.truncatedHashLength),
      receivedOn: towardResponder, hops: pathHops, announcePacketHash: nil)
    var route = Transport.LinkRoute(
      linkID: linkID,
      initiatorSideInterface: towardInitiator,
      responderSideInterface: towardResponder,
      initiatorSideInterfaceName: towardInitiator.name,
      responderSideInterfaceName: towardResponder.name,
      destinationHash: destinationHash,
      lastHeard: Date(),
      remainingHops: remainingHops,
      takenHops: takenHops)
    route.validated = validated
    t.restore(linkRoute: route)

    retained += [t, towardInitiator, towardResponder]
    return Relay(
      transport: t, towardInitiator: towardInitiator, towardResponder: towardResponder,
      responder: responder, linkID: linkID, destinationHash: destinationHash)
  }

  /// A link-request proof carrying `hops` on the wire. `forged` signs nothing.
  private func proof(for relay: Relay, hops: UInt8, forged: Bool = false) throws -> Packet {
    let ephemeral = Data((0..<Constants.halfKeySize).map { UInt8(($0 &* 7) &+ 3) })
    let signature =
      forged
      ? Data(repeating: 0xFF, count: Constants.signatureLength)
      : try relay.responder.sign(
        relay.linkID + ephemeral + relay.responder.signingPublicKey.rawRepresentation)
    return Packet(
      destinationType: .link, packetType: .proof, hops: hops,
      destinationHash: relay.linkID, context: .lrproof, data: signature + ephemeral)
  }

  /// A link data packet carrying `hops` on the wire, distinct per `tag`.
  private func linkData(for relay: Relay, hops: UInt8, tag: UInt8) -> Packet {
    Packet(
      destinationType: .link, packetType: .data, hops: hops,
      destinationHash: relay.linkID, context: .none, data: Data(repeating: tag, count: 32))
  }

  private func route(of relay: Relay) -> Transport.LinkRoute? {
    relay.transport.linkRoutes[relay.linkID]
  }

  // MARK: - Re-balancing at a relay

  func testAProofOverFewerHopsRebalancesTheRelaysPath() throws {
    let relay = makeRelay(pathHops: 2, remainingHops: 3)
    XCTAssertEqual(relay.transport.hopsTo(relay.destinationHash), 3, "test premise: a 3-hop path")

    relay.transport.handleIncoming(
      packet: try proof(for: relay, hops: 0), from: relay.towardResponder)

    XCTAssertEqual(
      relay.transport.hopsTo(relay.destinationHash), 1,
      "`path_entry[IDX_PT_HOPS] = packet.hops` (Transport.py:2634)")
    XCTAssertEqual(
      route(of: relay)?.remainingHops, 1,
      "`link_entry[IDX_LT_REM_HOPS] = packet.hops` (Transport.py:2632)")
    XCTAssertEqual(
      relay.towardInitiator.sent.map(\.hops), [1],
      "the re-balanced proof matches `IDX_LT_REM_HOPS` and goes out (Transport.py:2641-2662)")
  }

  func testAProofOverMoreHopsRebalancesTheRelaysPath() throws {
    let relay = makeRelay(pathHops: 0, remainingHops: 1)

    relay.transport.handleIncoming(
      packet: try proof(for: relay, hops: 2), from: relay.towardResponder)

    XCTAssertEqual(relay.transport.hopsTo(relay.destinationHash), 3)
    XCTAssertEqual(route(of: relay)?.remainingHops, 3)
    XCTAssertEqual(relay.towardInitiator.sent.map(\.hops), [3])
  }

  func testAForgedProofOverOtherHopsMovesNothing() throws {
    let relay = makeRelay(pathHops: 2, remainingHops: 3)
    let violations = relay.transport.interfaceCounts(for: relay.towardResponder).protocolViolations

    relay.transport.handleIncoming(
      packet: try proof(for: relay, hops: 0, forged: true), from: relay.towardResponder)

    XCTAssertEqual(relay.transport.hopsTo(relay.destinationHash), 3, "Transport.py:2636")
    XCTAssertEqual(route(of: relay)?.remainingHops, 3)
    XCTAssertTrue(relay.towardInitiator.sent.isEmpty, "Transport.py:2672")
    XCTAssertEqual(
      relay.transport.interfaceCounts(for: relay.towardResponder).protocolViolations, violations,
      """
      Python raises the violation only for a proof over the expected count (Transport.py:2668); \
      over another count it logs the mismatch and drops the proof (:2672)
      """)
  }

  func testAValidatedRouteIsNotRebalanced() throws {
    let relay = makeRelay(pathHops: 2, remainingHops: 3, validated: true)

    relay.transport.handleIncoming(
      packet: try proof(for: relay, hops: 0), from: relay.towardResponder)

    XCTAssertEqual(
      relay.transport.hopsTo(relay.destinationHash), 3,
      "`and not link_entry[IDX_LT_VALIDATED]` (Transport.py:2630)")
    XCTAssertTrue(relay.towardInitiator.sent.isEmpty, "Transport.py:2672")
  }

  func testWithRebalancingOffAProofOverOtherHopsIsDropped() throws {
    Transport.allowLinkPathRebalance = false
    let relay = makeRelay(pathHops: 2, remainingHops: 3)

    relay.transport.handleIncoming(
      packet: try proof(for: relay, hops: 0), from: relay.towardResponder)

    XCTAssertEqual(relay.transport.hopsTo(relay.destinationHash), 3, "Transport.py:2614")
    XCTAssertTrue(relay.towardInitiator.sent.isEmpty, "Transport.py:2672")
  }

  func testAProofFromTheInitiatorSideMovesNothing() throws {
    let relay = makeRelay(pathHops: 2, remainingHops: 3)

    relay.transport.handleIncoming(
      packet: try proof(for: relay, hops: 0), from: relay.towardInitiator)

    XCTAssertEqual(
      relay.transport.hopsTo(relay.destinationHash), 3,
      "`if packet.receiving_interface == link_entry[IDX_LT_NH_IF]` (Transport.py:2615)")
    XCTAssertTrue(relay.towardInitiator.sent.isEmpty)
    XCTAssertTrue(relay.towardResponder.sent.isEmpty)
  }

  func testAProofFromALocalClientResponderNeedsNoRebalancing() throws {
    let relay = makeRelay(
      pathHops: 0, remainingHops: 0, towardResponder: ServingHop(name: "LocalInterface[37428]"))

    relay.transport.handleIncoming(
      packet: try proof(for: relay, hops: 0), from: relay.towardResponder)

    XCTAssertEqual(
      route(of: relay)?.remainingHops, 0,
      "no hop is counted on a local client's interface (Transport.py:1937-1938)")
    XCTAssertEqual(relay.transport.hopsTo(relay.destinationHash), 0)
    XCTAssertEqual(relay.towardInitiator.sent.map(\.hops), [0])
  }

  // MARK: - Link traffic at a relay

  func testLinkTrafficFromTheResponderSideTravelsOverTheRemainingHops() {
    let relay = makeRelay(pathHops: 1, remainingHops: 2, takenHops: 1, validated: true)

    relay.transport.handleIncoming(
      packet: linkData(for: relay, hops: 0, tag: 1), from: relay.towardResponder)
    relay.transport.handleIncoming(
      packet: linkData(for: relay, hops: 1, tag: 2), from: relay.towardResponder)

    XCTAssertEqual(
      relay.towardInitiator.sent.map(\.hops), [2],
      "`if packet.hops == link_entry[IDX_LT_REM_HOPS]` (Transport.py:2145)")
  }

  func testLinkTrafficFromTheInitiatorSideTravelsOverTheTakenHops() {
    let relay = makeRelay(pathHops: 1, remainingHops: 2, takenHops: 1, validated: true)

    relay.transport.handleIncoming(
      packet: linkData(for: relay, hops: 0, tag: 1), from: relay.towardInitiator)
    relay.transport.handleIncoming(
      packet: linkData(for: relay, hops: 1, tag: 2), from: relay.towardInitiator)

    XCTAssertEqual(
      relay.towardResponder.sent.map(\.hops), [1],
      "`if packet.hops == link_entry[IDX_LT_HOPS]` (Transport.py:2149)")
  }

  func testHairpinnedLinkTrafficTravelsOverEitherCount() {
    let relay = makeRelay(
      pathHops: 2, remainingHops: 3, takenHops: 1, validated: true, hairpin: true)

    for (tag, hops) in [(1, 0), (2, 1), (3, 2)] as [(UInt8, UInt8)] {
      relay.transport.handleIncoming(
        packet: linkData(for: relay, hops: hops, tag: tag), from: relay.towardResponder)
    }

    XCTAssertEqual(
      relay.towardResponder.sent.map(\.hops), [1, 3],
      """
      `if packet.hops == link_entry[IDX_LT_REM_HOPS] or packet.hops == link_entry[IDX_LT_HOPS]` \
      (Transport.py:2137)
      """)
  }

  // MARK: - The hashlist at a relay

  func testARelayedLinkPacketEntersTheHashlist() throws {
    let relay = makeRelay(pathHops: 1, remainingHops: 2, takenHops: 1, validated: true)
    let packet = linkData(for: relay, hops: 0, tag: 1)

    relay.transport.handleIncoming(packet: packet, from: relay.towardInitiator)
    relay.transport.handleIncoming(packet: packet, from: relay.towardInitiator)

    XCTAssertTrue(
      relay.transport.testContainsPacketHash(try packet.packetHash()),
      "`Transport.add_packet_hash(packet.packet_hash)` (Transport.py:2156)")
    XCTAssertEqual(
      relay.towardResponder.sent.map(\.hops), [1],
      "`packet_filter` drops the repeat (Transport.py:1795)")
  }

  func testALinkPacketOutOfTurnStaysOutOfTheHashlist() throws {
    let relay = makeRelay(pathHops: 1, remainingHops: 2, takenHops: 1, validated: true)
    let early = linkData(for: relay, hops: 1, tag: 1)
    let inTurn = linkData(for: relay, hops: 0, tag: 1)
    XCTAssertEqual(
      try early.packetHash(), try inTurn.packetHash(), "test premise: one packet, two counts")

    relay.transport.handleIncoming(packet: early, from: relay.towardInitiator)
    XCTAssertFalse(
      relay.transport.testContainsPacketHash(try early.packetHash()),
      "`remember_packet_hash = False` for a link-table packet (Transport.py:1953)")
    relay.transport.handleIncoming(packet: inTurn, from: relay.towardInitiator)

    XCTAssertEqual(
      relay.towardResponder.sent.map(\.hops), [1],
      "the copy that arrives at this node's turn still goes out (Transport.py:2149-2160)")
  }

  func testARelayedProofStaysOutOfTheHashlist() throws {
    let relay = makeRelay(pathHops: 1, remainingHops: 2)
    let lrproof = try proof(for: relay, hops: 1)

    relay.transport.handleIncoming(packet: lrproof, from: relay.towardResponder)
    relay.transport.handleIncoming(packet: lrproof, from: relay.towardResponder)

    XCTAssertFalse(
      relay.transport.testContainsPacketHash(try lrproof.packetHash()),
      "the proof relay records nothing (Transport.py:1958, :2641-2669)")
    XCTAssertEqual(
      relay.towardInitiator.sent.map(\.hops), [2, 2],
      "so a repeated proof goes out again")
  }

  /// Initiates a link from A to an adjacent B, returning B's proof and A's link.
  ///
  /// A's path to B's destination stores `pathHops` on the wire.
  private func initiateAdjacent(pathHops: UInt8) throws -> (Transport, Packet, Link) {
    let a = Transport()
    let b = Transport()
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "linkhops", aspects: ["tap"])
    b.ownerIdentity = identity
    b.register(destination: destination)
    let ai = LoopHop(name: "A")
    let bi = TapLoop(name: "B")
    ai.paired = bi
    bi.paired = ai
    a.register(interface: ai)
    b.register(interface: bi)
    a.injectPath(
      destination.hash, nextHop: b.transportInstanceID, receivedOn: ai, hops: pathHops,
      announcePacketHash: nil)
    retained += [a, b, ai, bi]

    let link = try Link.initiate(destination: destination, transport: a)
    let proof = try XCTUnwrap(bi.sent.first { $0.context == .lrproof })
    return (a, proof, link)
  }

  func testAnInitiatorRecordsAProofOverItsExpectedHops() throws {
    let (initiator, proof, link) = try initiateAdjacent(pathHops: 0)

    XCTAssertEqual(link.status, .active, "test premise: the proof validated")
    XCTAssertTrue(
      initiator.testContainsPacketHash(try proof.packetHash()),
      """
      `if packet.hops == link.expected_hops: Transport.add_packet_hash(...)` \
      (Transport.py:2713-2717)
      """)
  }

  func testAnInitiatorDoesNotRecordAProofOverOtherHops() throws {
    Transport.allowLinkPathRebalance = false
    let (initiator, proof, link) = try initiateAdjacent(pathHops: 2)

    XCTAssertEqual(link.status, .pending, "test premise: expected 3 hops, the proof took 1")
    XCTAssertFalse(initiator.testContainsPacketHash(try proof.packetHash()))
  }

  // MARK: - A relayed link

  private struct Chain {
    let initiator: Transport
    let relay: Transport
    let responder: Transport
    let destination: Destination
  }

  /// A—R—B. R's path to B's destination stores `relayPathHops` on the wire although B is
  /// adjacent, and A's path runs through R.
  private func makeChain(relayPathHops: UInt8) throws -> Chain {
    let a = Transport()
    let r = Transport()
    let b = Transport()
    r.transportEnabled = true
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "linkhops", aspects: ["chain"])
    b.ownerIdentity = identity
    b.register(destination: destination)

    let ar = LoopHop(name: "A→R")
    let ra = LoopHop(name: "R→A")
    let rb = LoopHop(name: "R→B")
    let br = LoopHop(name: "B→R")
    ar.paired = ra
    ra.paired = ar
    rb.paired = br
    br.paired = rb
    a.register(interface: ar)
    r.register(interface: ra)
    r.register(interface: rb)
    b.register(interface: br)

    a.injectPath(
      destination.hash, nextHop: r.transportInstanceID, receivedOn: ar, hops: 1,
      announcePacketHash: nil)
    r.injectPath(
      destination.hash, nextHop: b.transportInstanceID, receivedOn: rb, hops: relayPathHops,
      announcePacketHash: nil)
    r.restore(identity: identity, forDestination: destination.hash)

    retained += [a, r, b, ar, ra, rb, br]
    return Chain(initiator: a, relay: r, responder: b, destination: destination)
  }

  func testARelayRebalancesAStalePathFromTheProof() throws {
    let chain = try makeChain(relayPathHops: 2)
    XCTAssertEqual(chain.relay.hopsTo(chain.destination.hash), 3, "test premise: a 3-hop path")

    let link = try Link.initiate(destination: chain.destination, transport: chain.initiator)

    XCTAssertEqual(link.status, .active)
    XCTAssertEqual(
      chain.relay.hopsTo(chain.destination.hash), 1,
      "`path_entry[IDX_PT_HOPS] = packet.hops` (Transport.py:2634)")
  }

  func testWithRebalancingOffAStalePathKeepsTheLinkPending() throws {
    Transport.allowLinkPathRebalance = false
    let chain = try makeChain(relayPathHops: 2)

    let link = try Link.initiate(destination: chain.destination, transport: chain.initiator)

    XCTAssertEqual(
      link.status, .pending,
      "the relay drops a proof over other than `IDX_LT_REM_HOPS` (Transport.py:2672)")
    XCTAssertEqual(chain.relay.hopsTo(chain.destination.hash), 3)
  }

  func testAfterRebalancingTheResponderReachesTheInitiator() throws {
    let chain = try makeChain(relayPathHops: 2)
    let link = try Link.initiate(destination: chain.destination, transport: chain.initiator)
    let responderLink = try XCTUnwrap(chain.responder.links[try XCTUnwrap(link.linkID)])
    var received: Data?
    link.onDataReceived = { data, _ in received = data }

    _ = try responderLink.send(Data("pong".utf8))

    XCTAssertEqual(
      received, Data("pong".utf8),
      "responder-side traffic travels over the re-balanced `IDX_LT_REM_HOPS` (Transport.py:2145)")
  }

  // MARK: - The responder's count

  func testTheResponderCountsTheRTTPacketsHops() throws {
    let chain = try makeChain(relayPathHops: 0)
    let link = try Link.initiate(destination: chain.destination, transport: chain.initiator)
    let responderLink = try XCTUnwrap(chain.responder.links[try XCTUnwrap(link.linkID)])

    XCTAssertEqual(responderLink.status, .active)
    XCTAssertEqual(
      responderLink.expectedHops, 2,
      "`self.expected_hops = packet.hops` (Link.py:525), after R and B each counted a hop")
  }

  func testTheResponderTimesOutARelayedRequestByItsHops() throws {
    let chain = try makeChain(relayPathHops: 0)
    let link = try Link.initiate(destination: chain.destination, transport: chain.initiator)
    let responderLink = try XCTUnwrap(chain.responder.links[try XCTUnwrap(link.linkID)])

    XCTAssertEqual(
      responderLink.establishmentTimeout,
      Link.establishmentTimeoutPerHop * 2 + Link.keepaliveInterval, accuracy: 0.001,
      "`ESTABLISHMENT_TIMEOUT_PER_HOP * max(1, packet.hops) + KEEPALIVE` (Link.py:204)")
  }

  /// A and B on a looped pair; B's side serves A as a local client when `serving` is set.
  private func makePair(serving: Bool) throws -> (Transport, Transport, Destination) {
    let a = Transport()
    let b = Transport()
    let identity = Identity()
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "linkhops", aspects: ["pair"])
    b.ownerIdentity = identity
    b.register(destination: destination)
    let ai = LoopHop(name: "A")
    let bi: LoopHop = serving ? ServingLoop(name: "LocalInterface[37428]") : LoopHop(name: "B")
    ai.paired = bi
    bi.paired = ai
    a.register(interface: ai)
    b.register(interface: bi)
    retained += [a, b, ai, bi]
    return (a, b, destination)
  }

  func testAResponderServingALocalClientCountsNoArrivalHop() throws {
    let (a, b, destination) = try makePair(serving: true)

    let link = try Link.initiate(destination: destination, transport: a)
    let responderLink = try XCTUnwrap(b.links[try XCTUnwrap(link.linkID)])

    XCTAssertEqual(responderLink.status, .active)
    XCTAssertEqual(responderLink.expectedHops, 0, "Transport.py:1937-1938, Link.py:525")
    XCTAssertEqual(
      responderLink.establishmentTimeout,
      Link.establishmentTimeoutPerHop * 1 + Link.keepaliveInterval, accuracy: 0.001,
      "`max(1, packet.hops)` (Link.py:204)")
  }

  // MARK: - Packets handed above Transport

  func testADestinationReceivesThePacketWithItsArrivalHop() throws {
    let (a, _, destination) = try makePair(serving: false)
    destination.proofStrategy = .proveNone
    var received: Packet?
    destination.onPacketReceived = { _, packet in received = packet }

    try a.send(
      Packet(
        destinationType: .single, packetType: .data, destinationHash: destination.hash,
        data: try destination.encrypt(Data("hello".utf8))),
      generateReceipt: false)

    XCTAssertEqual(try XCTUnwrap(received).hops, 1, "`packet.hops += 1` (Transport.py:1800)")
  }

  func testADestinationServingALocalClientReceivesThePacketWithoutAnArrivalHop() throws {
    let (a, _, destination) = try makePair(serving: true)
    destination.proofStrategy = .proveNone
    var received: Packet?
    destination.onPacketReceived = { _, packet in received = packet }

    try a.send(
      Packet(
        destinationType: .single, packetType: .data, destinationHash: destination.hash,
        data: try destination.encrypt(Data("hello".utf8))),
      generateReceipt: false)

    XCTAssertEqual(try XCTUnwrap(received).hops, 0, "Transport.py:1937-1938")
  }

  func testAProofReachesItsReceiptWithItsArrivalHop() throws {
    let (a, _, destination) = try makePair(serving: false)
    destination.proofStrategy = .proveAll
    a.restore(identity: try XCTUnwrap(destination.identity), forDestination: destination.hash)

    let receipt = try XCTUnwrap(
      a.send(
        Packet(
          destinationType: .single, packetType: .data, destinationHash: destination.hash,
          data: try destination.encrypt(Data("hello".utf8)))))

    XCTAssertEqual(
      try XCTUnwrap(receipt.proofPacket).hops, 1,
      "`receipt.proof_packet` is the inbound packet (Packet.py:427-431, Transport.py:1800)")
  }

  func testALinkProofReachesItsReceiptWithItsArrivalHop() throws {
    let (a, b, destination) = try makePair(serving: false)
    let link = try Link.initiate(destination: destination, transport: a)
    let responderLink = try XCTUnwrap(b.links[try XCTUnwrap(link.linkID)])
    responderLink.onDataReceived = { _, inbound in inbound.proveInboundData() }

    let receipt = try XCTUnwrap(link.send(Data("ping".utf8)))

    XCTAssertEqual(try XCTUnwrap(receipt.proofPacket).hops, 1, "Transport.py:1800")
  }
}
