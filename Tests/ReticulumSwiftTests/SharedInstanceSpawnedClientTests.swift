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

/// Each connection the shared instance accepts is an interface of its own.
///
/// Python's `LocalServerInterface.incoming_connection` builds a `LocalClientInterface` for
/// every accepted socket and adds it to `Transport.interfaces` and
/// `Transport.local_client_interfaces` (`LocalInterface.py:416-460`). The server's own
/// `process_outgoing` does nothing (`LocalInterface.py:462-463`).
///
/// This port collapsed every connection into the one `PosixTCPServer`, whose `send` wrote to
/// all of them. Two local clients therefore shared one interface. A link request from one to
/// the other arrived on the interface its path left through, and `handleLinkRequest`'s
/// `outbound !== interface` guard dropped it, so two programs on one Swift shared instance
/// couldn't open a link to each other. Everything sent to one client was also written to
/// every other.
final class SharedInstanceSpawnedClientTests: XCTestCase {

  final class MeshIface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
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

  private func startServer() throws -> PosixTCPServer {
    for _ in 0..<8 {
      guard let port = try? freeLoopbackPort() else { continue }
      let candidate = PosixTCPServer(name: "Shared Instance", port: port)
      do {
        try candidate.start()
        server = candidate
        return candidate
      } catch {
        continue
      }
    }
    throw XCTSkip("no free port available for the shared-instance server")
  }

  /// A non-transport shared instance, as most `rnsd` installs are.
  private func startHub() throws -> (Transport, PosixTCPServer) {
    let server = try startServer()
    let hub = Transport()
    hub.transportEnabled = false
    hub.register(interface: server)
    transports.append(hub)
    return (hub, server)
  }

  /// A program attached to the shared instance, as `InstanceConnection.attach` sets one up.
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

  private func connections(of server: PosixTCPServer, in hub: Transport) -> [any Interface] {
    hub.interfaces.filter { ($0 as? any SpawnedInterface)?.spawningInterface === server }
  }

  private func waitUntil(
    _ description: String, timeout: TimeInterval = 5, _ condition: () -> Bool
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { usleep(20_000) }
    XCTAssertTrue(condition(), description)
  }

  /// Counts the frames addressed to `hash` that reach `iface`, then hands them on.
  private func countArrivals(at iface: LocalInterface, for hash: Data) -> () -> Int {
    let lock = NSLock()
    var count = 0
    let original = iface.rawInboundHandler
    iface.rawInboundHandler = { data, source in
      if let packet = try? Packet.unpack(data), packet.destinationHash == hash {
        lock.lock()
        count += 1
        lock.unlock()
      }
      original?(data, source)
    }
    return {
      lock.lock()
      defer { lock.unlock() }
      return count
    }
  }

  private func announcedDestination(on transport: Transport) throws -> Destination {
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "spawned",
      aspects: ["test"])
    transport.register(destination: destination)
    _ = try transport.announce(destination: destination)
    return destination
  }

  // MARK: - Registration

  func testEachConnectionRegistersItsOwnInterface() throws {
    let (hub, server) = try startHub()
    _ = try attachClient(to: server)
    _ = try attachClient(to: server)
    waitUntil("the hub registered one interface per connection") {
      connections(of: server, in: hub).count == 2
    }

    let spawned = connections(of: server, in: hub)
    guard spawned.count == 2 else { return }
    XCTAssertFalse(spawned[0] === spawned[1])
    XCTAssertEqual(server.clientCount, 2)
    for iface in spawned {
      XCTAssertTrue(hub.isLocalClientInterface(iface), "\(iface.displayName)")
      XCTAssertNotNil(UInt16(iface.name), "named by the client's port, as Python does")
      XCTAssertEqual(iface.displayName, "LocalInterface[\(iface.name)]")
      XCTAssertEqual(iface.statsTypeName, "LocalClientInterface")
    }
    XCTAssertFalse(
      hub.isLocalClientInterface(server),
      "Python's is_local_client_interface is false for the server, which has no parent")
  }

  func testAConnectionThatHangsUpIsDeregistered() throws {
    let (hub, server) = try startHub()
    let (_, first) = try attachClient(to: server)
    _ = try attachClient(to: server)
    waitUntil("both connections registered") { connections(of: server, in: hub).count == 2 }

    first.stop()
    waitUntil("the hung-up connection left the transport") {
      connections(of: server, in: hub).count == 1
    }
    XCTAssertEqual(server.clientCount, 1)
  }

  // MARK: - Routing

  /// The reported failure: `rncp` between two programs on one Swift `rnsd` timed out
  /// establishing its link.
  func testTwoLocalClientsOfOneSharedInstanceCanLink() throws {
    let (_, server) = try startHub()
    let (a, _) = try attachClient(to: server)
    let (b, _) = try attachClient(to: server)

    let destination = try announcedDestination(on: b)
    waitUntil("client A learned a path to client B's destination") {
      a.hasPath(to: destination.hash) && a.recall(identity: destination.hash) != nil
    }
    let identity = try XCTUnwrap(a.recall(identity: destination.hash))
    let remote = try Destination(
      identity: identity, direction: .out, kind: .single, appName: "spawned", aspects: ["test"])

    let established = expectation(description: "the link between the two clients came up")
    a.onLinkEstablished = { _ in established.fulfill() }
    let link = try Link.initiate(destination: remote, transport: a)
    a.register(link: link)
    wait(for: [established], timeout: 8)
  }

  /// The shared instance used to write everything for one client to all of them.
  func testAPacketForOneLocalClientReachesOnlyThatClient() throws {
    let (hub, server) = try startHub()
    let mesh = MeshIface(name: "mesh")
    hub.register(interface: mesh)
    let (_, aIface) = try attachClient(to: server)
    let (b, bIface) = try attachClient(to: server)

    let destination = try announcedDestination(on: b)
    waitUntil("the hub learned a path to client B's destination") {
      hub.hasPath(to: destination.hash)
    }
    let atA = countArrivals(at: aIface, for: destination.hash)
    let atB = countArrivals(at: bIface, for: destination.hash)

    let packet = Packet(
      destinationType: .single, packetType: .data, destinationHash: destination.hash,
      data: Data(repeating: 0x42, count: 64))
    mesh.inboundHandler?(packet, mesh)

    waitUntil("client B received the packet addressed to it") { atB() == 1 }
    usleep(300_000)
    XCTAssertEqual(atA(), 0, "client A received a packet addressed to client B")
  }

  // MARK: - Traffic

  /// Traffic counts on the connection and on the shared instance.
  ///
  /// `LocalClientInterface.process_incoming` and `process_outgoing` add to the connection
  /// and to its parent (`LocalInterface.py:204-243`). Received bytes are the unframed
  /// frame, sent bytes the HDLC-framed one.
  func testTrafficCountsOnTheConnectionAndOnTheSharedInstance() throws {
    let (hub, server) = try startHub()
    let (_, client) = try attachClient(to: server)
    waitUntil("the connection registered") { connections(of: server, in: hub).count == 1 }
    let spawned = try XCTUnwrap(connections(of: server, in: hub).first)

    let inbound = Packet(
      destinationType: .plain, packetType: .data, destinationHash: Data(repeating: 1, count: 16),
      data: Data(repeating: 0x7E, count: 40))
    try client.send(inbound)
    let rawIn = try inbound.pack().count
    waitUntil("the connection counted the frame") { spawned.rxBytes == rawIn }
    XCTAssertEqual(server.rxBytes, rawIn)

    let outbound = Packet(
      destinationType: .plain, packetType: .data, destinationHash: Data(repeating: 2, count: 16),
      data: Data(repeating: 0x7D, count: 40))
    try spawned.send(outbound)
    let framedOut = HDLC.frame(try outbound.pack()).count
    XCTAssertEqual(spawned.txBytes, framedOut)
    XCTAssertEqual(server.txBytes, framedOut)
  }

  /// The shared instance's own interface sends nothing.
  ///
  /// `LocalServerInterface.process_outgoing` is `pass` (`LocalInterface.py:462-463`).
  func testTheSharedInstanceInterfaceItselfSendsNothing() throws {
    let (hub, server) = try startHub()
    let (_, client) = try attachClient(to: server)
    waitUntil("the connection registered") { connections(of: server, in: hub).count == 1 }
    let hash = Data(repeating: 3, count: 16)
    let arrivals = countArrivals(at: client, for: hash)

    try server.send(
      Packet(destinationType: .plain, packetType: .data, destinationHash: hash, data: Data([1])))
    usleep(300_000)
    XCTAssertEqual(arrivals(), 0)
    XCTAssertEqual(server.txBytes, 0)
  }
}
