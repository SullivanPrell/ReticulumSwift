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

/// `TCPClientInterface.start()` and `BackboneInterface.start()` return once the initial
/// connect has an outcome, as Python's constructors do (`SYNCHRONOUS_START = True`,
/// `TCPInterface.py:162-165`, `BackboneInterface.py:909-912`).
///
/// `send()` discards packets while the interface is offline, so a path request or announce
/// issued on the line after `start()` was lost while the dial was in flight. An RRC client
/// that requested the hub's path at startup then waited 40 s for a path that never came.
final class ClientInterfaceSynchronousStartTests: XCTestCase {

  private var servers: [PosixTCPServer] = []
  private var clients: [any Interface] = []

  override func tearDown() {
    for client in clients { client.stop() }
    for server in servers { server.stop() }
    clients = []
    servers = []
    super.tearDown()
  }

  private func startServer() throws -> PosixTCPServer {
    for _ in 0..<8 {
      guard let port = try? freeLoopbackPort() else { continue }
      let server = PosixTCPServer(name: "Backbone", port: port)
      do {
        try server.start()
        servers.append(server)
        return server
      } catch {
        continue
      }
    }
    throw XCTSkip("no free port available for the server")
  }

  private func probe() -> Packet {
    Packet(
      destinationType: .plain,
      packetType: .data,
      destinationHash: Data(repeating: 0xAB, count: 16),
      data: Data("startup".utf8))
  }

  /// Once `start()` returns, the first `send()` reaches the peer. No sleep, no polling.
  private func assertFirstSendArrives(_ make: (UInt16) -> any Interface) throws {
    let server = try startServer()
    let received = expectation(description: "server received the frame")
    received.assertForOverFulfill = false
    server.onClientConnected = { connection in
      connection.rawInboundHandler = { _, _ in received.fulfill() }
    }
    let client = make(server.port)
    clients.append(client)
    try client.start()

    XCTAssertTrue(client.isOnline, "start() returned before the connection could send")
    try client.send(probe())
    wait(for: [received], timeout: 5)
  }

  /// A refused peer is an outcome too: `start()` returns at once without throwing, and the
  /// interface stays offline and keeps retrying (`initial_connect` starts `reconnect()`).
  private func assertRefusedPeerReturnsPromptly(_ make: (UInt16) -> any Interface) throws {
    let client = make(try freeLoopbackPort())
    clients.append(client)
    let began = Date()
    XCTAssertNoThrow(try client.start())
    XCTAssertLessThan(Date().timeIntervalSince(began), 4, "a refused dial waited for the timeout")
    XCTAssertFalse(client.isOnline)
  }

  func testTCPClientFirstSendAfterStartArrives() throws {
    try assertFirstSendArrives { TCPClientInterface(name: "client", host: "127.0.0.1", port: $0) }
  }

  func testBackboneClientFirstSendAfterStartArrives() throws {
    try assertFirstSendArrives { BackboneInterface(name: "client", host: "127.0.0.1", port: $0) }
  }

  func testTCPClientStartReturnsPromptlyWhenRefused() throws {
    try assertRefusedPeerReturnsPromptly {
      TCPClientInterface(name: "client", host: "127.0.0.1", port: $0)
    }
  }

  func testBackboneClientStartReturnsPromptlyWhenRefused() throws {
    try assertRefusedPeerReturnsPromptly {
      BackboneInterface(name: "client", host: "127.0.0.1", port: $0)
    }
  }

  /// Python: `INITIAL_CONNECT_TIMEOUT = 5` on both (`TCPInterface.py:89`,
  /// `BackboneInterface.py:848`).
  func testInitialConnectTimeoutMatchesPython() {
    XCTAssertEqual(TCPClientInterface.initialConnectTimeout, 5)
    XCTAssertEqual(BackboneInterface.initialConnectTimeout, 5)
  }
}
