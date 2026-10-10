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

/// The instance-control listener binds what Python's binds, and says so truthfully (`bugs/040`).
///
/// Python's listener is a BSD socket with `SO_REUSEADDR` bound to `("127.0.0.1", port)`
/// (`Reticulum.py:359`, `:366`, and CPython `multiprocessing/connection.py:638-651`), and a
/// failed bind raises.
final class RPCServerBindTests: XCTestCase {

  private func freePort() -> UInt16 {
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(sock) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    addr.sin_port = 0
    _ = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    var out = sockaddr_in()
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &out) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) }
    }
    return UInt16(bigEndian: out.sin_port)
  }

  /// The listening socket sets `SO_REUSEADDR`, as Python's does.
  ///
  /// CPython's `SocketListener` sets it before binding (`multiprocessing/connection.py:645-648`),
  /// so a restarted daemon rebinds its control port over the previous run's `TIME_WAIT`
  /// sockets. `getsockopt` reads a BSD socket's option back authoritatively.
  func testTheListeningSocketSetsReuseAddress() throws {
    let server = RPCServer(port: freePort(), authkey: Data(repeating: 0x05, count: 32))
    try server.start()
    defer { server.stop() }

    var value: Int32 = 0
    var length = socklen_t(MemoryLayout<Int32>.size)
    let rc = getsockopt(
      server.listeningDescriptorForTesting, SOL_SOCKET, SO_REUSEADDR, &value, &length)
    XCTAssertEqual(rc, 0, "getsockopt failed on the listening descriptor, errno \(errno)")
    XCTAssertNotEqual(
      value, 0,
      """
      the control listener must set SO_REUSEADDR, as Python's SocketListener \
      does; without it a daemon restarted while its control port has TIME_WAIT \
      sockets cannot bind
      """)
  }

  /// A listener that can't bind is a failure, not a log line.
  ///
  /// A socket on the identical address blocks the bind even with `SO_REUSEADDR` on both sides;
  /// only `SO_REUSEPORT` would let two sockets share it.
  func testStartThrowsWhenThePortCannotBeBound() throws {
    let port = freePort()
    let blocker = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(blocker) }
    var one: Int32 = 1
    setsockopt(blocker, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    addr.sin_port = port.bigEndian
    let bound = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(blocker, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    try XCTSkipIf(bound != 0, "could not hold port \(port) to block the listener")
    listen(blocker, 1)

    let server = RPCServer(port: port, authkey: Data(repeating: 0x01, count: 32))
    XCTAssertThrowsError(
      try server.start(),
      """
      a control socket that cannot bind must throw, as Python's \
      SocketListener.__init__ raises; otherwise the daemon runs on with no \
      control socket and every rn* utility reports it missing
      """)
    server.stop()
  }

  /// And the ordinary case still works: a free port binds, and the socket is reachable when
  /// `start()` returns—so a caller may talk to it immediately rather than racing the bind.
  func testStartBindsAndIsReachableOnReturn() throws {
    let port = freePort()
    let server = RPCServer(port: port, authkey: Data(repeating: 0x02, count: 32))
    try server.start()
    defer { server.stop() }

    let probe = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(probe) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    addr.sin_port = port.bigEndian
    let connected = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    XCTAssertEqual(
      connected, 0,
      "the control socket must accept connections once `start()` has returned; "
        + "otherwise every utility racing daemon startup sees "
        + "\"Could not connect to instance control socket\"")
  }

  /// A port held on another local address doesn't stop the control socket binding 127.0.0.1.
  ///
  /// Python binds `("127.0.0.1", port)` with a BSD socket (`Reticulum.py:359`, `:366`, and CPython
  /// `multiprocessing/connection.py:638-651`), which conflicts only with a socket on
  /// 127.0.0.1 or the wildcard. `NWListener` refuses a port held on any local address, so a
  /// port that `bind(("127.0.0.1", 0))` reports free, and that another process holds on a LAN
  /// address, failed with `EADDRINUSE` (`bugs/040`). A socket bound to `[::1]` holds the
  /// port the same way and exists on every host.
  func testStartBindsALoopbackPortHeldOnAnotherAddress() throws {
    let port = freePort()
    let holder = socket(AF_INET6, SOCK_STREAM, 0)
    defer { close(holder) }
    var one: Int32 = 1
    setsockopt(holder, IPPROTO_IPV6, IPV6_V6ONLY, &one, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in6()
    addr.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    addr.sin6_family = sa_family_t(AF_INET6)
    addr.sin6_addr = in6addr_loopback
    addr.sin6_port = port.bigEndian
    let held = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(holder, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
      }
    }
    XCTAssertEqual(held, 0, "could not hold [::1]:\(port), errno \(errno)")

    let server = RPCServer(port: port, authkey: Data(repeating: 0x04, count: 32))
    XCTAssertNoThrow(
      try server.start(),
      """
      127.0.0.1:\(port) is free, and Python's control listener binds it; \
      [::1]:\(port) being held must not stop this one
      """)
    defer { server.stop() }
  }

  /// The listening socket is closed by the time `stop()` returns.
  ///
  /// The accept source's cancel handler closes the descriptor on the source's queue, after
  /// `cancel()` has returned. A caller that stops a server and binds its port again, as a
  /// restarted shared instance does, can find the port still held. On an idle machine the
  /// handler usually wins, so the rounds run beside busy threads that delay it.
  func testStopClosesTheSocketBeforeItReturns() throws {
    let port = try freeLoopbackPort()
    let finished = LockedFlag(false)
    defer { finished.value = true }
    for _ in 0..<(ProcessInfo.processInfo.activeProcessorCount * 2) {
      Thread.detachNewThread { while !finished.value {} }
    }

    for round in 1...2_000 {
      let server = RPCServer(port: port, authkey: Data(repeating: 0x06, count: 32))
      do {
        try server.start()
      } catch {
        return XCTFail("round \(round): the previous server's socket was still open: \(error)")
      }
      server.stop()
      guard loopbackPortState(port) == .refused else {
        return XCTFail("round \(round): a connect after stop() was not refused")
      }
    }
  }

  /// The first non-loopback, non-link-local IPv4 address this host holds, or nil.
  private func nonLoopbackIPv4() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>? = nil
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    var cursor: UnsafeMutablePointer<ifaddrs>? = first
    while let entry = cursor {
      defer { cursor = entry.pointee.ifa_next }
      guard let sa = entry.pointee.ifa_addr,
        sa.pointee.sa_family == sa_family_t(AF_INET),
        (entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
        (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0
      else { continue }
      var addr = sockaddr_in()
      memcpy(&addr, sa, MemoryLayout<sockaddr_in>.size)
      var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      guard inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil
      else { continue }
      let text = String(cString: buffer)
      if text.hasPrefix("169.254.") { continue }
      return text
    }
    return nil
  }

  /// The bind must be loopback-**only**, which reachability alone can't prove.
  ///
  /// Python constructs its control listener on `("127.0.0.1", port)` (`Reticulum.py:359`,
  /// `:366`), so it's unreachable off-host by construction. This is the negative assertion
  /// whose absence let a wildcard bind sit behind 3258 green tests: the preceding test proves
  /// 127.0.0.1 answers, and a listener on `*` passes that too. An authenticated management
  /// socket (path drops, blackholing) must not be reachable from every network the host is on.
  func testTheControlSocketIsNotReachableOnANonLoopbackAddress() throws {
    guard let lanAddress = nonLoopbackIPv4() else {
      throw XCTSkip("host has no non-loopback IPv4 address to probe")
    }
    let port = freePort()
    let server = RPCServer(port: port, authkey: Data(repeating: 0x03, count: 32))
    try server.start()
    defer { server.stop() }

    let probe = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(probe) }
    // Bound: connecting to the host's own address answers immediately (accept or RST),
    // but never let a pathological stack hang the suite.
    var tv = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(probe, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr(lanAddress)
    addr.sin_port = port.bigEndian
    let connected = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    XCTAssertNotEqual(
      connected, 0,
      """
      the control socket accepted a connection on \(lanAddress):\(port) — \
      the listener is bound to the wildcard, so the instance-control RPC \
      port is reachable from every network this host is on, where Python's \
      identical listener binds ("127.0.0.1", port) and is unreachable \
      off-host by construction (Reticulum.py:359, :366)
      """)
  }
}
