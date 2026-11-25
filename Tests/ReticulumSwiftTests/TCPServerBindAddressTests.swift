//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Darwin
import Network
import XCTest

@testable import ReticulumSwift

/// A server binds the address `listen_ip` names, as Python's does (`TCPInterface.py:551`).
final class TCPServerBindAddressTests: XCTestCase {

  /// A listening `IPV6_V6ONLY` socket on `[::1]:port`, or `nil` where IPv6 loopback can't bind.
  private func holdIPv6Loopback(_ port: UInt16) -> Int32? {
    let fd = socket(AF_INET6, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var one: Int32 = 1
    setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &one, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_in6()
    address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    address.sin6_family = sa_family_t(AF_INET6)
    address.sin6_port = port.bigEndian
    address.sin6_addr = in6addr_loopback
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
      }
    }
    guard bound == 0, Darwin.listen(fd, 1) == 0 else {
      close(fd)
      return nil
    }
    return fd
  }

  /// A server bound to `127.0.0.1` starts while another socket holds `[::1]` on its port.
  ///
  /// `NWListener` refuses a port any local address holds (`bugs/040`).
  func testAHeldIPv6LoopbackPortDoesNotStopAnIPv4LoopbackServer() throws {
    let port = try freeLoopbackPort()
    guard let squatter = holdIPv6Loopback(port) else {
      throw XCTSkip("[::1] can't be bound on this machine")
    }
    defer { close(squatter) }

    let server = TCPServerInterface(name: "bind", port: port, bindIP: "127.0.0.1")
    let connected = expectation(description: "a client connected over 127.0.0.1")
    server.onClientConnected = { _ in connected.fulfill() }
    try server.start()
    defer { server.stop() }

    let client = TCPClientInterface(name: "dial", host: "127.0.0.1", port: port)
    defer { client.stop() }
    try? client.start()
    wait(for: [connected], timeout: 5)
    XCTAssertTrue(server.isOnline)
  }

  /// A port held on the same address fails `start()` with an error naming it.
  ///
  /// Python's bind raises (`TCPInterface.py:567-573`).
  func testAPortHeldOnTheSameAddressThrowsNamingIt() throws {
    let port = try freeLoopbackPort()
    let first = TCPServerInterface(name: "first", port: port, bindIP: "127.0.0.1")
    try first.start()
    defer { first.stop() }
    let second = TCPServerInterface(name: "second", port: port, bindIP: "127.0.0.1")
    XCTAssertThrowsError(try second.start()) { error in
      XCTAssertTrue("\(error)".contains("127.0.0.1:\(port)"), "\(error)")
    }
    XCTAssertFalse(second.isOnline)
  }
}
