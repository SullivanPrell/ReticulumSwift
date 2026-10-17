//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Network
import XCTest

@testable import ReticulumSwift

/// A `BackboneInterface` client redials every `reconnectWait` until it's online, whether it
/// lost its peer or never reached it (`BackboneClientInterface.reconnect()`,
/// `BackboneInterface.py:1004-1031`).
final class BackboneInterfaceReconnectTests: XCTestCase {

  private var servers: [PosixTCPServer] = []
  private var clients: [BackboneInterface] = []

  override func tearDown() {
    for client in clients { client.stop() }
    for server in servers { server.stop() }
    clients = []
    servers = []
    super.tearDown()
  }

  private func makeClient(port: UInt16) -> BackboneInterface {
    let client = BackboneInterface(
      name: "client", host: "127.0.0.1", port: port, reconnectWait: 0.3)
    clients.append(client)
    return client
  }

  /// A peer on `port` that reports each accepted connection.
  private func startServer(
    port: UInt16, onAccept: @escaping (any Interface) -> Void
  ) throws -> PosixTCPServer {
    let server = PosixTCPServer(name: "Backbone", port: port)
    server.onClientConnected = onAccept
    try server.start()
    servers.append(server)
    return server
  }

  private func waitUntil(
    _ description: String, timeout: TimeInterval = 5,
    file: StaticString = #filePath, line: UInt = #line, _ predicate: @escaping () -> Bool
  ) {
    let met = expectation(for: NSPredicate { _, _ in predicate() }, evaluatedWith: nil)
    met.expectationDescription = description
    wait(for: [met], timeout: timeout)
  }

  /// The peer is down for the first dial and comes up later.
  ///
  /// Network.framework reports a refused dial as `.waiting` and retries only when the network
  /// path changes, so a client that leaves it there never reaches a peer that comes back.
  func testAPeerThatComesUpLaterIsReached() throws {
    let port = try freeLoopbackPort()
    let client = makeClient(port: port)
    try client.start()
    Thread.sleep(forTimeInterval: 0.5)
    XCTAssertFalse(client.isOnline)

    let lock = NSLock()
    var accepted = 0
    _ = try startServer(port: port) { _ in
      lock.lock()
      accepted += 1
      lock.unlock()
    }
    waitUntil("the client to reach the peer") {
      lock.lock()
      defer { lock.unlock() }
      return accepted >= 1
    }
  }

  /// The peer hangs up an established connection: the client redials, and the connection
  /// it dropped is cancelled rather than left in `CLOSE_WAIT` (`bugs/013`).
  func testTheDroppedConnectionIsCancelledAndReplaced() throws {
    let lock = NSLock()
    var peers: [any Interface] = []
    let server = try startServer(port: try freeLoopbackPort()) { peer in
      lock.lock()
      peers.append(peer)
      lock.unlock()
    }
    let accepts: () -> Int = {
      lock.lock()
      defer { lock.unlock() }
      return peers.count
    }
    let client = makeClient(port: server.port)
    try client.start()
    waitUntil("the client to come up") { client.isOnline && accepts() == 1 }
    let first = try XCTUnwrap(client.currentConnectionForTesting)

    lock.lock()
    let firstPeer = peers[0]
    lock.unlock()
    firstPeer.stop()

    waitUntil("a redial") { accepts() == 2 && client.isOnline }
    waitUntil("the dropped connection to be cancelled") {
      if case .cancelled = first.state { return true }
      return false
    }
  }

  /// Once redialled, the new connection stays up.
  ///
  /// The dropped one's late callbacks must not take it offline or start another redial.
  func testTheReplacementConnectionStaysUp() throws {
    let lock = NSLock()
    var peers: [any Interface] = []
    let server = try startServer(port: try freeLoopbackPort()) { peer in
      lock.lock()
      peers.append(peer)
      lock.unlock()
    }
    let accepts: () -> Int = {
      lock.lock()
      defer { lock.unlock() }
      return peers.count
    }
    let client = makeClient(port: server.port)
    try client.start()
    waitUntil("the client to come up") { client.isOnline && accepts() == 1 }
    lock.lock()
    let firstPeer = peers[0]
    lock.unlock()
    firstPeer.stop()
    waitUntil("a redial") { accepts() == 2 && client.isOnline }

    Thread.sleep(forTimeInterval: 1.5)  // five reconnectWait periods
    XCTAssertTrue(client.isOnline, "the replacement connection was taken offline")
    XCTAssertEqual(accepts(), 2, "the client redialled a healthy connection")
  }
}
