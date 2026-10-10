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

/// The shared-instance server keeps a local client attached for as long as its socket is open.
///
/// Python's `LocalClientInterface.read_loop` (`LocalInterface.py:276-295`) reads up to 4096
/// bytes at a time and gives up on the client only when `recv` returns nothing. Each
/// `PosixTCPServer` client asked `DispatchIO` for 4096 bytes and treated the read's
/// completion as the socket closing. A stream read also completes once it has delivered the
/// length it asked for, so the server dropped every client after its first 4 KB.
///
/// Requests, path lookups and announces fit in 4 KB, so short-lived utilities never noticed.
/// A client sending a file stalled: `rncp` behind a Swift `rnsd` got its first two windows
/// of resource parts through, then the server discarded every request the receiver sent
/// back, and the transfer timed out at 20%.
final class SharedInstanceClientReadTests: XCTestCase {

  private var server: PosixTCPServer?
  private var client: LocalInterface?

  override func tearDown() {
    client?.stop()
    server?.stop()
    client = nil
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

  /// Calls `handler` for every frame the server reads, from whichever connection.
  ///
  /// Each connection is an interface of its own, so the frames arrive on it, not on the server.
  private func onEveryFrame(of server: PosixTCPServer, _ handler: @escaping () -> Void) {
    server.onClientConnected = { connection in
      connection.rawInboundHandler = { _, _ in handler() }
    }
  }

  private func frame(_ index: Int, size: Int) -> Packet {
    Packet(
      destinationType: .plain,
      packetType: .data,
      destinationHash: Data(repeating: UInt8(truncatingIfNeeded: index), count: 16),
      data: Data(repeating: 0x5A, count: size))
  }

  /// Frames sent once the server has read 4 KB still arrive.
  ///
  /// Twenty 400-byte frames are about 8.5 KB, two reads' worth. A second batch goes out only
  /// after the first has arrived, so it needs a read the server started afterwards.
  ///
  /// The unfixed loop passes this: it started a read on every partial delivery, and the
  /// pile-up kept reading after the server dropped the client. It fails a loop that stops reading
  /// at the first completed read.
  func testFramesSentAfterTheFirstFourKilobytesStillArrive() throws {
    let server = try startServer()
    let lock = NSLock()
    var received = 0
    var target = 20
    var reached: XCTestExpectation? = expectation(description: "the first 20 frames arrived")
    onEveryFrame(of: server) {
      lock.lock()
      received += 1
      let hit = received == target ? reached : nil
      if hit != nil { reached = nil }
      lock.unlock()
      hit?.fulfill()
    }

    let client = LocalInterface(host: "127.0.0.1", port: server.port)
    self.client = client
    try client.start()
    for index in 0..<20 { try client.send(frame(index, size: 400)) }
    waitForExpectations(timeout: 5)

    let second = expectation(description: "the next 5 frames arrived")
    lock.lock()
    target = 25
    reached = second
    lock.unlock()
    for index in 20..<25 { try client.send(frame(index, size: 400)) }

    let outcome = XCTWaiter().wait(for: [second], timeout: 5)
    lock.lock()
    let arrived = received
    lock.unlock()
    XCTAssertEqual(
      outcome, .completed,
      "\(arrived) of 25 frames arrived; the server stopped reading the client after 4 KB")
  }

  /// The half that stalled the transfer: what the server sends back after that point.
  func testTheServerStillReachesAClientThatHasSentMoreThanFourKilobytes() throws {
    let server = try startServer()
    let count = 20
    let lock = NSLock()
    var received = 0
    let all = expectation(description: "all \(count) frames reached the server")
    var connection: (any Interface)?
    server.onClientConnected = { spawned in
      lock.lock()
      connection = spawned
      lock.unlock()
      spawned.rawInboundHandler = { _, _ in
        lock.lock()
        received += 1
        let done = received == count
        lock.unlock()
        if done { all.fulfill() }
      }
    }

    let client = LocalInterface(host: "127.0.0.1", port: server.port)
    self.client = client
    let reply = expectation(description: "the client received the server's frame")
    client.rawInboundHandler = { _, _ in reply.fulfill() }
    try client.start()
    for index in 0..<count { try client.send(frame(index, size: 400)) }
    _ = XCTWaiter().wait(for: [all], timeout: 5)

    XCTAssertEqual(server.clientCount, 1, "the server let go of a client whose socket is open")
    lock.lock()
    let spawned = connection
    lock.unlock()
    try XCTUnwrap(spawned).send(frame(0xEE, size: 64))
    wait(for: [reply], timeout: 5)
  }

  /// The server reports a hang-up once, because only one read is outstanding.
  ///
  /// The unfixed loop started another read on every partial delivery, so a busy client's
  /// outstanding reads grew without bound, and each one reported the hang-up when the client
  /// left.
  func testAClientThatHangsUpIsDetachedOnce() throws {
    let server = try startServer()
    let lock = NSLock()
    var received = 0
    var detaches = 0
    let all = expectation(description: "all 20 frames reached the server")
    onEveryFrame(of: server) {
      lock.lock()
      received += 1
      let done = received == 20
      lock.unlock()
      if done { all.fulfill() }
    }
    server.clientDetachedHandlerForTesting = {
      lock.lock()
      detaches += 1
      lock.unlock()
    }

    let client = LocalInterface(host: "127.0.0.1", port: server.port)
    try client.start()
    for index in 0..<20 {
      try client.send(frame(index, size: 400))
      usleep(2_000)
    }
    wait(for: [all], timeout: 5)
    client.stop()

    let deadline = Date().addingTimeInterval(5)
    while server.clientCount != 0, Date() < deadline { usleep(20_000) }
    usleep(200_000)
    lock.lock()
    let count = detaches
    lock.unlock()
    XCTAssertEqual(count, 1, "one hang-up was reported \(count) times, once per outstanding read")
  }

  /// Stopping the server hangs up on its clients.
  ///
  /// `DispatchIO.close()` without `.stop` lets pending operations finish first, and the one
  /// outstanding read finishes only when the client hangs up. So the server has to cancel
  /// it, or a stopped shared instance leaves every client connected.
  func testStoppingTheServerHangsUpOnItsClients() throws {
    let server = try startServer()
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    XCTAssertGreaterThanOrEqual(fd, 0)
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = server.port.bigEndian
    inet_aton("127.0.0.1", &addr.sin_addr)
    let rc = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    XCTAssertEqual(rc, 0)
    let deadline = Date().addingTimeInterval(5)
    while server.clientCount != 1, Date() < deadline { usleep(20_000) }
    XCTAssertEqual(server.clientCount, 1)

    server.stop()

    var timeout = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var byte: UInt8 = 0
    let n = recv(fd, &byte, 1, 0)
    XCTAssertEqual(
      n, 0, "the client's socket stayed open after the server stopped (errno \(errno))")
  }

  /// The client closing its socket still detaches it.
  func testAClientThatClosesItsSocketIsDetached() throws {
    let server = try startServer()
    let arrived = expectation(description: "the frame reached the server")
    onEveryFrame(of: server) { arrived.fulfill() }

    let client = LocalInterface(host: "127.0.0.1", port: server.port)
    try client.start()
    try client.send(frame(1, size: 32))
    wait(for: [arrived], timeout: 5)
    XCTAssertEqual(server.clientCount, 1)

    client.stop()
    let deadline = Date().addingTimeInterval(5)
    while server.clientCount != 0, Date() < deadline { usleep(20_000) }
    XCTAssertEqual(server.clientCount, 0, "a client that hung up is still attached")
  }
}
