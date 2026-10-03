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

/// The shared instance's broadcasts reach its local clients.
///
/// Python's `LocalServerInterface` copies its outbound flag onto each connection it spawns
/// (`LocalInterface.py:450`, `Reticulum.py:403`), so every loop in `Transport.outbound` that
/// broadcasts to `Transport.interfaces` reaches the local clients (`Transport.py:1449`). So
/// does the recursive path-request search (`Transport.py:3574-3583`). A plain broadcast is
/// also relayed between the local clients and every other interface
/// (`Transport.py:1977-1991`).
///
/// This port kept the local clients out of its broadcast loops, so a shared instance's own
/// announces and path requests never reached them, and plain broadcasts stopped at the
/// shared instance.
final class SharedInstanceBroadcastTests: XCTestCase {

  final class MeshIface: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var mode: InterfaceMode = .full
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

  private var server: PosixTCPServer?
  private var transports: [Transport] = []
  private var clients: [LocalInterface] = []

  override func tearDown() {
    for client in clients { client.stop() }
    server?.stop()
    for transport in transports { transport.stop() }
    clients = []
    transports = []
    server = nil
    super.tearDown()
  }

  private func startHub(transportEnabled: Bool = false) throws -> (Transport, PosixTCPServer) {
    for _ in 0..<8 {
      guard let port = try? freeLoopbackPort() else { continue }
      let candidate = PosixTCPServer(name: "Shared Instance", port: port)
      do {
        try candidate.start()
      } catch {
        continue
      }
      server = candidate
      let hub = Transport()
      hub.transportEnabled = transportEnabled
      hub.register(interface: candidate)
      transports.append(hub)
      return (hub, candidate)
    }
    throw XCTSkip("no free port available for the shared-instance server")
  }

  private func attachClient(to server: PosixTCPServer) throws -> (Transport, LocalInterface) {
    let transport = Transport()
    transport.transportEnabled = false
    transport.isConnectedToSharedInstance = true
    let iface = LocalInterface(host: "127.0.0.1", port: server.port)
    clients.append(iface)
    transport.register(interface: iface)
    try iface.start()
    transports.append(transport)
    return (transport, iface)
  }

  private func connectionCount(of server: PosixTCPServer, in hub: Transport) -> Int {
    hub.interfaces.filter { ($0 as? any SpawnedInterface)?.spawningInterface === server }.count
  }

  private func waitUntil(
    _ description: String, timeout: TimeInterval = 5, _ condition: () -> Bool
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { usleep(20_000) }
    XCTAssertTrue(condition(), description)
  }

  /// Records the frames addressed to `hash` that reach `iface`, then hands them on.
  private func arrivals(at iface: LocalInterface, for hash: Data) -> () -> [Packet] {
    let lock = NSLock()
    var seen: [Packet] = []
    let original = iface.rawInboundHandler
    iface.rawInboundHandler = { data, source in
      if let packet = try? Packet.unpack(data), packet.destinationHash == hash {
        lock.lock()
        seen.append(packet)
        lock.unlock()
      }
      original?(data, source)
    }
    return {
      lock.lock()
      defer { lock.unlock() }
      return seen
    }
  }

  private func destination(on transport: Transport) throws -> Destination {
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "broadcast",
      aspects: ["test"])
    transport.register(destination: destination)
    return destination
  }

  private func plainBroadcast(_ marker: UInt8) -> Packet {
    Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Data(repeating: marker, count: 16),
      data: Data(repeating: marker, count: 24))
  }

  // MARK: - The shared instance's own broadcasts

  /// The shared instance's own announce reaches its clients.
  ///
  /// `Destination.announce` goes out through the broadcast loop in `Transport.outbound`.
  func testTheSharedInstancesOwnAnnounceReachesItsClients() throws {
    let (hub, server) = try startHub()
    let (client, _) = try attachClient(to: server)
    waitUntil("the client's connection registered") { connectionCount(of: server, in: hub) == 1 }

    let local = try destination(on: hub)
    _ = try hub.announce(destination: local)
    waitUntil("the client learned a path to the shared instance's destination") {
      client.hasPath(to: local.hash)
    }
  }

  /// A plain packet the shared instance sends reaches its clients.
  func testAPlainBroadcastFromTheSharedInstanceReachesItsClients() throws {
    let (hub, server) = try startHub()
    let (_, clientIface) = try attachClient(to: server)
    waitUntil("the client's connection registered") { connectionCount(of: server, in: hub) == 1 }

    let packet = plainBroadcast(0x31)
    let seen = arrivals(at: clientIface, for: packet.destinationHash)
    try hub.send(packet)
    waitUntil("the client received the broadcast") { seen().count == 1 }
  }

  /// `request_path` without an interface broadcasts on every interface
  /// (`Transport.py:3299`), so a client hosting the destination hears it and answers.
  func testTheSharedInstanceFindsAPathAClientHolds() throws {
    let (hub, server) = try startHub()
    let (client, _) = try attachClient(to: server)
    waitUntil("the client's connection registered") { connectionCount(of: server, in: hub) == 1 }

    let unannounced = try destination(on: client)
    try hub.requestPath(for: unannounced.hash)
    waitUntil("the shared instance learned the path from the client's answer") {
      hub.hasPath(to: unannounced.hash)
    }
  }

  /// A transport instance searching for an unknown destination asks every interface but the
  /// requester's, the local clients included (`Transport.py:3574-3583`).
  func testATransportSharedInstanceSearchesItsClients() throws {
    let (hub, server) = try startHub(transportEnabled: true)
    let mesh = MeshIface(name: "mesh")
    // Gateway interfaces discover paths for unknown destinations (`DISCOVER_PATHS_FOR`).
    mesh.mode = .gateway
    hub.register(interface: mesh)
    let (client, _) = try attachClient(to: server)
    waitUntil("the client's connection registered") { connectionCount(of: server, in: hub) == 1 }

    let unannounced = try destination(on: client)
    let request = Packet(
      destinationType: .plain, packetType: .data,
      destinationHash: Transport.pathRequestDestinationHash,
      data: unannounced.hash + SecureRandom.bytes(Constants.truncatedHashLength))
    mesh.inboundHandler?(request, mesh)

    waitUntil("the answer went back to the mesh") {
      mesh.sent.contains { $0.packetType == .announce && $0.destinationHash == unannounced.hash }
    }
  }

  // MARK: - Announces between clients

  /// A client records a sibling's destination at the hop count of the copy the shared instance
  /// sends it straight away (`Transport.py:2400-2429`), not at the count of the relayed
  /// copy, which carries one hop more.
  func testAClientSeesASiblingsDestinationAtTheImmediateCopysHopCount() throws {
    let (hub, server) = try startHub()
    let (a, _) = try attachClient(to: server)
    let (b, _) = try attachClient(to: server)
    waitUntil("both connections registered") { connectionCount(of: server, in: hub) == 2 }

    let local = try destination(on: a)
    _ = try a.announce(destination: local)
    waitUntil("client B learned the path") { b.hasPath(to: local.hash) }
    usleep(300_000)
    XCTAssertEqual(b.hopsTo(local.hash), 0)
  }

  // MARK: - Plain broadcasts

  /// `Transport.py:1983-1986`: from a local client, to every other interface.
  func testAPlainBroadcastFromAClientReachesTheMeshAndTheOtherClients() throws {
    let (hub, server) = try startHub()
    let mesh = MeshIface(name: "mesh")
    hub.register(interface: mesh)
    let (a, _) = try attachClient(to: server)
    let (_, bIface) = try attachClient(to: server)
    waitUntil("both connections registered") { connectionCount(of: server, in: hub) == 2 }

    let packet = plainBroadcast(0x32)
    let atB = arrivals(at: bIface, for: packet.destinationHash)
    try a.send(packet)

    waitUntil("the mesh received the broadcast") {
      mesh.sent.contains { $0.destinationHash == packet.destinationHash }
    }
    waitUntil("client B received the broadcast") { atB().count == 1 }
  }

  /// `Transport.py:1989-1991`: from anywhere else, to every local client.
  func testAPlainBroadcastFromTheMeshReachesEveryClient() throws {
    let (hub, server) = try startHub()
    let mesh = MeshIface(name: "mesh")
    hub.register(interface: mesh)
    let (_, aIface) = try attachClient(to: server)
    let (_, bIface) = try attachClient(to: server)
    waitUntil("both connections registered") { connectionCount(of: server, in: hub) == 2 }

    let packet = plainBroadcast(0x33)
    let atA = arrivals(at: aIface, for: packet.destinationHash)
    let atB = arrivals(at: bIface, for: packet.destinationHash)
    mesh.inboundHandler?(packet, mesh)

    waitUntil("client A received the broadcast") { atA().count == 1 }
    waitUntil("client B received the broadcast") { atB().count == 1 }
  }

  /// The relay leaves path requests to the path-request handler.
  ///
  /// Path requests are control traffic (`Transport.py:359`, `:1980`). The path-request
  /// handler asks the clients with a request of its own, under a fresh tag
  /// (`Transport.py:3589-3590`).
  func testAPathRequestIsntRelayedAsAPlainBroadcast() throws {
    let (hub, server) = try startHub()
    let mesh = MeshIface(name: "mesh")
    hub.register(interface: mesh)
    let (_, clientIface) = try attachClient(to: server)
    waitUntil("the client's connection registered") { connectionCount(of: server, in: hub) == 1 }

    let target = SecureRandom.bytes(Constants.truncatedHashLength)
    let tag = SecureRandom.bytes(Constants.truncatedHashLength)
    let seen = arrivals(at: clientIface, for: Transport.pathRequestDestinationHash)
    mesh.inboundHandler?(
      Packet(
        destinationType: .plain, packetType: .data,
        destinationHash: Transport.pathRequestDestinationHash, data: target + tag),
      mesh)

    waitUntil("the shared instance asked its client") {
      seen().contains { $0.data.prefix(Constants.truncatedHashLength) == target }
    }
    usleep(300_000)
    XCTAssertFalse(
      seen().contains { $0.data.suffix(Constants.truncatedHashLength) == tag },
      "the mesh's request reached the client verbatim")
  }
}
