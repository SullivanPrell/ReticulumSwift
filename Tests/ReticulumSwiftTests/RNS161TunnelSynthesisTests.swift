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

/// RNS 1.6.1's tunnel synthesis: the signed extension, reverse synthesis, the duplicate and
/// size guards, teardown, and the reconnect window (`Transport.py:3170-3298`, `:636-637`,
/// `:1287`, `:1413`, `:4832-4840`).
final class RNS161TunnelSynthesisTests: XCTestCase {

  final class TunnelPort: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var allowsTunnels = true
    var tunnelsAllowed: Bool { allowsTunnels }
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var sent: [Packet] = []
    var stopped = false
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {
      stopped = true
      isOnline = false
    }
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  private typealias Key = DiscoveryFieldKey

  private func ext(_ pairs: [(Key, MsgPack.Value)]) -> Data {
    MsgPack.encode(.map(pairs.map { (.uint($0.0.rawValue), $0.1) }))
  }

  private var validExt: [(Key, MsgPack.Value)] {
    [
      (.transportImpl, .string("RNS")), (.transportVers, .string("1.6.1")),
      (.transport, .bool(true)), (.dstCost, .double(17.8)), (.prCost, .double(12.0)),
    ]
  }

  /// `data = tunnel_id_data+random_hash+signature+ext_payload`, signed over
  /// `tunnel_id_data+random_hash+ext_payload` (`Transport.py:3187-3190`).
  private func synthesis(
    from identity: Identity, ext: Data = Data(), signature: Data? = nil
  ) throws -> (packet: Packet, tunnelID: Data) {
    let idData = identity.publicKeyBytes + Hashes.fullHash(Data("remote-if".utf8))
    let random = Hashes.randomHash()
    let sig = try signature ?? identity.sign(idData + random + ext)
    let packet = Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Transport.tunnelSynthesizeHash, data: idData + random + sig + ext)
    return (packet, Hashes.fullHash(idData))
  }

  private func receiver() -> (Transport, TunnelPort) {
    let t = Transport()
    t.transportIdentity = Identity()
    let port = TunnelPort(name: "tcp")
    t.register(interface: port)
    port.sent.removeAll()
    return (t, port)
  }

  private func violations(_ t: Transport, _ port: TunnelPort) -> Int {
    t.interfaceCounts(for: port).protocolViolations
  }

  private func synthesesSent(_ port: TunnelPort) -> [Packet] {
    port.sent.filter { $0.destinationHash == Transport.tunnelSynthesizeHash }
  }

  // MARK: - Emitting

  func testTheSynthesisCarriesASignedExtension() throws {
    let t = Transport()
    let identity = Identity()
    t.transportIdentity = identity
    let port = TunnelPort(name: "tcp")
    port.interfaceState.destinationCost = 17.8
    port.wantsTunnel = true

    t.synthesizeTunnel(port)

    let data = try XCTUnwrap(synthesesSent(port).first).data
    XCTAssertGreaterThan(data.count, 176)
    let extData = data.subdata(in: 176..<data.count)
    guard case .map(let map) = try MsgPack.decode(extData) else { return XCTFail("not a map") }
    func value(_ key: Key) -> MsgPack.Value? {
      map.first { $0.0 == .uint(key.rawValue) }?.1
    }
    XCTAssertEqual(value(.transportImpl), .string(InterfaceDiscoveryHelpers.implementationName))
    XCTAssertEqual(value(.transportVers), .string(InterfaceDiscoveryHelpers.implementationVersion))
    XCTAssertEqual(value(.transport), .bool(t.transportEnabled))
    XCTAssertEqual(value(.dstCost), .double(17.8))
    XCTAssertEqual(value(.prCost), .double(t.stamps.prCost))
    XCTAssertTrue(
      identity.validate(
        signature: data.subdata(in: 112..<176), for: data.subdata(in: 0..<112) + extData))
    XCTAssertEqual(
      port.interfaceState.tunnelSynthesis.localTunnelID,
      Hashes.fullHash(data.subdata(in: 0..<96)))
    XCTAssertTrue(port.interfaceState.tunnelSynthesis.emitted)
    XCTAssertFalse(port.wantsTunnel)
  }

  /// `if interface.online: packet.send()` ... `else: return` (`Transport.py:3199-3201`), and
  /// the jobs loop retries while `wants_tunnel and interface.online` (`:1413`).
  func testAnOfflineInterfaceKeepsItsRequest() {
    let t = Transport()
    t.transportIdentity = Identity()
    let port = TunnelPort(name: "tcp")
    port.isOnline = false
    port.wantsTunnel = true

    t.synthesizeTunnel(port)

    XCTAssertTrue(port.sent.isEmpty)
    XCTAssertTrue(port.wantsTunnel)
    XCTAssertNil(port.interfaceState.tunnelSynthesis.localTunnelID)
  }

  // MARK: - Receiving

  func testAValidSynthesisRecordsTheRemoteAndAnswersInReverse() throws {
    let (t, port) = receiver()
    let remote = Identity()
    let (packet, tunnelID) = try synthesis(from: remote, ext: ext(validExt))

    t.handleIncoming(packet: packet, from: port)

    XCTAssertEqual(violations(t, port), 0)
    XCTAssertNotNil(t.tunnels[tunnelID])
    XCTAssertEqual(port.tunnelID, tunnelID)
    let state = port.interfaceState.tunnelSynthesis
    XCTAssertEqual(state.remoteTransportID, remote.hash)
    XCTAssertEqual(state.remoteImpl, "RNS")
    XCTAssertEqual(state.remoteVers, [1, 6, 1])
    XCTAssertEqual(state.remoteDstCost, Stamps.quantizeCost(17.8))
    XCTAssertEqual(state.remotePrCost, Stamps.quantizeCost(12.0))
    XCTAssertEqual(state.remoteIsTN, true)
    XCTAssertEqual(synthesesSent(port).count, 1, "the reverse synthesis")
    XCTAssertNil(state.localTunnelID, "a reverse synthesis records no local tunnel")
  }

  /// `if not interface.local_tunnel_id: Transport.handle_tunnel(...)` (`Transport.py:3292-3294`).
  func testTheInitiatorRecordsNoTunnel() throws {
    let (t, port) = receiver()
    port.wantsTunnel = true
    t.synthesizeTunnel(port)
    port.sent.removeAll()
    let remote = Identity()
    let (packet, tunnelID) = try synthesis(from: remote, ext: ext(validExt))

    t.handleIncoming(packet: packet, from: port)

    XCTAssertNil(t.tunnels[tunnelID])
    XCTAssertNil(port.tunnelID)
    XCTAssertEqual(port.interfaceState.tunnelSynthesis.remoteTransportID, remote.hash)
    XCTAssertTrue(synthesesSent(port).isEmpty, "already emitted, so no reverse")
  }

  func testALegacySynthesisStillEstablishesATunnel() throws {
    let (t, port) = receiver()
    let (packet, tunnelID) = try synthesis(from: Identity())

    t.handleIncoming(packet: packet, from: port)

    XCTAssertNotNil(t.tunnels[tunnelID])
    XCTAssertEqual(violations(t, port), 0)
    XCTAssertTrue(synthesesSent(port).isEmpty, "only an extended synthesis is answered")
  }

  func testAnInterfaceWithoutTunnelsIgnoresSynthesis() throws {
    let (t, port) = receiver()
    port.allowsTunnels = false
    let (packet, tunnelID) = try synthesis(from: Identity(), ext: ext(validExt))

    t.handleIncoming(packet: packet, from: port)

    XCTAssertNil(t.tunnels[tunnelID])
    XCTAssertFalse(port.interfaceState.tunnelSynthesis.received)
    XCTAssertEqual(violations(t, port), 0)
  }

  // MARK: - Guards

  func testASecondSynthesisIsAViolation() throws {
    let (t, port) = receiver()
    let (first, _) = try synthesis(from: Identity(), ext: ext(validExt))
    t.handleIncoming(packet: first, from: port)
    let (second, secondID) = try synthesis(from: Identity(), ext: ext(validExt))

    t.handleIncoming(packet: second, from: port)

    XCTAssertEqual(violations(t, port), 1)
    XCTAssertNil(t.tunnels[secondID])
  }

  func testSynthesisAfterAFailedOneIsAViolation() throws {
    let (t, port) = receiver()
    var short = try synthesis(from: Identity()).packet
    short.data = short.data.prefix(100)
    t.handleIncoming(packet: short, from: port)
    let (valid, tunnelID) = try synthesis(from: Identity())

    t.handleIncoming(packet: valid, from: port)

    XCTAssertEqual(violations(t, port), 2)
    XCTAssertNil(t.tunnels[tunnelID])
  }

  func testOversizedSynthesisIsAViolation() throws {
    let (t, port) = receiver()
    let (packet, tunnelID) = try synthesis(
      from: Identity(), ext: Data(count: Constants.mdu - 175))

    t.handleIncoming(packet: packet, from: port)

    XCTAssertEqual(violations(t, port), 1)
    XCTAssertNil(t.tunnels[tunnelID])
  }

  func testMalformedExtensionsAreViolations() throws {
    var cases: [(String, Data)] = [
      ("undecodable", Data([0xC1])),
      ("not a map", MsgPack.encode(.array([.string("RNS")]))),
      (
        "bad version",
        ext([(.transportVers, .string("x"))] + validExt.filter { $0.0 != .transportVers })
      ),
      (
        "unsanitary name",
        ext([(.transportImpl, .string(" RNS"))] + validExt.filter { $0.0 != .transportImpl })
      ),
      ("integer cost", ext([(.dstCost, .int(17))] + validExt.filter { $0.0 != .dstCost })),
      ("integer pr cost", ext([(.prCost, .int(12))] + validExt.filter { $0.0 != .prCost })),
      ("transport not bool", ext([(.transport, .int(1))] + validExt.filter { $0.0 != .transport })),
    ]
    for key in [Key.transportImpl, .transportVers, .transport, .dstCost, .prCost] {
      cases.append(("missing \(key)", ext(validExt.filter { $0.0 != key })))
    }
    for (label, extData) in cases {
      let (t, port) = receiver()
      let (packet, tunnelID) = try synthesis(from: Identity(), ext: extData)

      t.handleIncoming(packet: packet, from: port)

      XCTAssertEqual(violations(t, port), 1, label)
      XCTAssertNil(t.tunnels[tunnelID], label)
      XCTAssertNil(port.interfaceState.tunnelSynthesis.remoteTransportID, label)
    }
  }

  // MARK: - Teardown

  /// `_detach_interface(None, interface_instance=interface, internal_forced=True)`
  /// (`Transport.py:3245-3247`).
  func testABadSignatureTearsTheInterfaceDown() throws {
    let (t, port) = receiver()
    let (packet, tunnelID) = try synthesis(
      from: Identity(), ext: ext(validExt), signature: Data(repeating: 0x33, count: 64))

    t.handleIncoming(packet: packet, from: port)

    XCTAssertTrue(port.stopped)
    XCTAssertFalse(t.interfaces.contains { $0 === port })
    XCTAssertNil(t.tunnels[tunnelID])
    XCTAssertEqual(violations(t, port), 0)
  }

  func testABlackholedRemoteTearsTheInterfaceDown() throws {
    let (t, port) = receiver()
    let remote = Identity()
    t.blackholeIdentity(remote.hash)
    let (packet, tunnelID) = try synthesis(from: remote, ext: ext(validExt))

    t.handleIncoming(packet: packet, from: port)

    XCTAssertTrue(port.stopped)
    XCTAssertNil(t.tunnels[tunnelID])
  }

  /// Blackholing a transport identity tears down the interfaces it's the remote of
  /// (`Transport.py:4832-4840`).
  func testBlackholingARemoteTearsDownItsInterfaces() throws {
    let (t, port) = receiver()
    let bystander = TunnelPort(name: "other")
    t.register(interface: bystander)
    let remote = Identity()
    let (packet, _) = try synthesis(from: remote, ext: ext(validExt))
    t.handleIncoming(packet: packet, from: port)

    t.blackholeIdentity(remote.hash)

    XCTAssertTrue(port.stopped)
    XCTAssertFalse(t.interfaces.contains { $0 === port })
    XCTAssertFalse(bystander.stopped)
  }

  // MARK: - Reconnect

  /// `wants_tunnel = True`, `remote_transport = None`, `synthesis_received = False`
  /// (`TCPInterface.py:261-263`).
  func testConnectingClearsTheRemote() {
    let port = TunnelPort(name: "tcp")
    port.interfaceState.tunnelSynthesis.remoteTransportID = Data(repeating: 1, count: 16)
    port.interfaceState.tunnelSynthesis.received = true
    port.interfaceState.tunnelSynthesis.emitted = true

    port.noteConnected()

    XCTAssertTrue(port.wantsTunnel)
    XCTAssertNil(port.interfaceState.tunnelSynthesis.remoteTransportID)
    XCTAssertFalse(port.interfaceState.tunnelSynthesis.received)
    XCTAssertTrue(port.interfaceState.tunnelSynthesis.emitted, "never reset")
  }

  /// A tunnel losing its interface gets `TUNNEL_RECONNECT_WINDOW` to come back
  /// (`Transport.py:1287`).
  func testATunnelThatLostItsInterfaceGetsTheReconnectWindow() {
    let t = Transport()
    let gone = TunnelPort(name: "gone")
    let tunnelID = Data(repeating: 0x7A, count: 32)
    let now = Date()
    t.tunnels[tunnelID] = Transport.TunnelEntry(
      tunnelID: tunnelID, iface: gone, paths: [:],
      expires: now.addingTimeInterval(Transport.tunnelTimeout))

    t.sweepTunnels(now: now)

    let tunnel = t.tunnels[tunnelID]
    XCTAssertNil(tunnel?.iface)
    XCTAssertEqual(
      tunnel?.expires.timeIntervalSince1970 ?? 0,
      now.addingTimeInterval(Transport.tunnelReconnectWindow).timeIntervalSince1970,
      accuracy: 1)
  }

  // MARK: - Ports

  func testTunnelsAreAllowedOnTheTCPBackboneAndI2PInterfaces() {
    let server = TCPServerInterface(name: "srv", port: 4965)
    let i2p = I2PInterface(
      name: "i2p", daemon: MockI2PDaemon(), dataDirectory: URL(fileURLWithPath: "/tmp"))
    let allowed: [any Interface] = [
      TCPClientInterface(name: "c", host: "127.0.0.1", port: 4965),
      server,
      BackboneInterface(name: "b", host: "127.0.0.1", port: 4242),
      TCPServerClientInterface(
        name: "sc", parentServer: server, peerHost: "10.0.0.2", peerPort: 50000),
      i2p,
      I2PInterfacePeer(name: "peer", targetI2PDestination: "abc.b32.i2p", parentInterface: i2p),
    ]
    for iface in allowed { XCTAssertTrue(iface.tunnelsAllowed, iface.name) }
    XCTAssertFalse(UDPInterface(name: "udp", listenPort: 0).tunnelsAllowed)
  }
}
