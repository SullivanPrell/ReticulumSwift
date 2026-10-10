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
import Foundation
import XCTest

@testable import ReticulumSwift

/// A server interface listens on the address `listen_ip` names, not on every address.
///
/// Python binds the address it resolved: `TCPServerInterface` binds the result of
/// `get_address_for_host(bindip, ...)` (`TCPInterface.py:551`, `:567`, `:573`), and
/// `UDPInterface` binds `(bind_ip, bind_port)` (`UDPInterface.py:101-103`). A Swift server
/// configured with `listen_ip = 127.0.0.1` must be unreachable on the host's other addresses.
final class ListenIPBindTests: XCTestCase {

  func testTCPLoopbackListenIPIsUnreachableOnANonLoopbackAddress() throws {
    let lan = try lanAddress()
    let port = try freeLoopbackPort()
    let server = TCPServerInterface(name: "lo4", port: port, bindIP: "127.0.0.1")
    try server.start()
    defer { server.stop() }
    try waitUntilListening(server)

    XCTAssertTrue(connects("127.0.0.1", port), "listen_ip 127.0.0.1 must accept on loopback")
    XCTAssertFalse(
      connects(lan, port),
      "listen_ip 127.0.0.1 accepted a connection on \(lan):\(port); Python binds loopback only")
  }

  func testTCPIPv6LoopbackListenIPBindsOnlyTheIPv6Loopback() throws {
    let port = try freeLoopbackPort()
    let server = TCPServerInterface(name: "lo6", port: port, bindIP: "::1")
    try server.start()
    defer { server.stop() }
    try waitUntilListening(server)

    XCTAssertTrue(connects("::1", port), "listen_ip ::1 must accept on [::1]")
    XCTAssertFalse(
      connects("127.0.0.1", port),
      "listen_ip ::1 accepted on 127.0.0.1; Python binds ThreadingTCP6Server to ::1 only")
  }

  /// Python passes a host name through `getaddrinfo` and binds the IPv4 entry it prefers
  /// (`TCPInterface.py:490-497`).
  func testTCPHostNameListenIPBindsTheAddressItResolvesTo() throws {
    let lan = try lanAddress()
    let port = try freeLoopbackPort()
    let server = TCPServerInterface(name: "lohost", port: port, bindIP: "localhost")
    try server.start()
    defer { server.stop() }
    try waitUntilListening(server)

    XCTAssertTrue(connects("127.0.0.1", port), "listen_ip localhost must accept on 127.0.0.1")
    XCTAssertFalse(connects(lan, port), "listen_ip localhost accepted on \(lan):\(port)")
  }

  func testUDPLoopbackListenIPDropsADatagramSentToANonLoopbackAddress() throws {
    let lan = try lanAddress()
    let port = try XCTUnwrap(freeUDPPort())
    let iface = UDPInterface(name: "udplo", listenPort: port, bindIP: "127.0.0.1")
    let lock = NSLock()
    var received: Set<String> = []
    iface.rawInboundHandler = { data, _ in
      lock.lock()
      received.insert(String(decoding: data, as: UTF8.self))
      lock.unlock()
    }
    try iface.start()
    defer { iface.stop() }
    func got(_ payload: String) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      return received.contains(payload)
    }

    // `UDPInterface.start()` doesn't wait for the bind, so resend until loopback arrives.
    for _ in 0..<20 where !got("loopback") {
      sendDatagram("lan", to: lan, port: port)
      sendDatagram("loopback", to: "127.0.0.1", port: port)
      Thread.sleep(forTimeInterval: 0.1)
    }
    Thread.sleep(forTimeInterval: 0.2)

    XCTAssertTrue(got("loopback"), "listen_ip 127.0.0.1 must receive a datagram on loopback")
    XCTAssertFalse(
      got("lan"),
      "listen_ip 127.0.0.1 received a datagram sent to \(lan):\(port); Python binds loopback only")
  }

  // MARK: - Helpers

  private func lanAddress() throws -> String {
    guard let lan = nonLoopbackIPv4() else {
      throw XCTSkip("host has no non-loopback IPv4 address to probe the bind against")
    }
    return lan
  }

  private func waitUntilListening(_ server: TCPServerInterface) throws {
    let deadline = Date().addingTimeInterval(3)
    while !server.isOnline, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    XCTAssertTrue(server.isOnline, "listener never reached .ready")
  }

  /// Runs `body` with a socket of `type` and the numeric address `host`:`port`.
  private func withSocket<T>(
    _ host: String, _ port: UInt16, _ type: Int32,
    _ body: (Int32, UnsafeMutablePointer<addrinfo>) -> T
  ) -> T? {
    var hints = addrinfo()
    hints.ai_flags = AI_NUMERICHOST
    hints.ai_socktype = type
    var info: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &info) == 0, let entry = info else { return nil }
    defer { freeaddrinfo(info) }
    let fd = socket(entry.pointee.ai_family, type, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    return body(fd, entry)
  }

  private func connects(_ host: String, _ port: UInt16) -> Bool {
    withSocket(host, port, SOCK_STREAM) { fd, entry in
      var timeout = timeval(tv_sec: 3, tv_usec: 0)
      setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
      return connect(fd, entry.pointee.ai_addr, entry.pointee.ai_addrlen) == 0
    } ?? false
  }

  private func sendDatagram(_ payload: String, to host: String, port: UInt16) {
    _ = withSocket(host, port, SOCK_DGRAM) { fd, entry in
      Array(payload.utf8).withUnsafeBytes {
        sendto(fd, $0.baseAddress, $0.count, 0, entry.pointee.ai_addr, entry.pointee.ai_addrlen)
      }
    }
  }

  /// A UDP port the kernel reported free on every address a moment ago.
  private func freeUDPPort() -> UInt16? {
    withSocket("0.0.0.0", 0, SOCK_DGRAM) { fd, entry in
      guard Darwin.bind(fd, entry.pointee.ai_addr, entry.pointee.ai_addrlen) == 0 else {
        return nil
      }
      var bound = sockaddr_in()
      var size = socklen_t(MemoryLayout<sockaddr_in>.size)
      let named = withUnsafeMutablePointer(to: &bound) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
      }
      return named == 0 ? UInt16(bigEndian: bound.sin_port) : nil
    } ?? nil
  }

  /// The first up, non-loopback, non-link-local IPv4 address this host holds.
  private func nonLoopbackIPv4() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return nil }
    defer { freeifaddrs(list) }
    var cursor = list
    while let entry = cursor {
      cursor = entry.pointee.ifa_next
      guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
        entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
        entry.pointee.ifa_flags & UInt32(IFF_UP) != 0
      else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard
        getnameinfo(
          address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
          NI_NUMERICHOST) == 0
      else { continue }
      let text = String(cString: host)
      if !text.hasPrefix("169.254.") { return text }
    }
    return nil
  }
}
