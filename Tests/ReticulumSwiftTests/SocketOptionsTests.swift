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

/// `bugs/023`—every socket this port opens must carry the reference socket options, in both
/// directions.
///
/// The gate here is unusual, and deliberately so (design D4 / risk R5). There is no authoritative
/// way to ask a live connection whether keepalive is on: Network.framework publishes no getters
/// for TCP options, and `NWParameters.defaultProtocolStack.transportProtocol` hands back a
/// *different* `NWProtocolTCP.Options` instance than the one given to `NWParameters(tls:tcp:)`,
/// reporting framework defaults on some OS versions. That's what CI's one deliberately skipped
/// test from 1.7.0 records. And proving keepalive *fires* needs a peer that stops answering
/// without the kernel sending FIN—packet-level filtering, not `close()`.
///
/// So the enforceable invariant is **construction-site uniqueness**: one factory builds the
/// options, and every socket-opening site takes them from it. That's a weaker claim than
/// "keepalive works", and it's stated as such rather than dressed up. Where a real readback
/// exists—the POSIX shared-instance server—this suite uses it.
final class SocketOptionsTests: XCTestCase {

  // MARK: - The factory's values

  func testFactoryCarriesThePythonTCPOptionValues() {
    let options = RNSSocketOptions.tcpOptions()
    // TCPInterface.py:83-86 and set_timeouts_osx / set_timeouts_linux at :181-206.
    XCTAssertTrue(options.enableKeepalive, "Python sets SO_KEEPALIVE on every TCP socket")
    XCTAssertEqual(options.keepaliveIdle, 5, "TCP_PROBE_AFTER")
    XCTAssertEqual(options.keepaliveInterval, 2, "TCP_PROBE_INTERVAL")
    XCTAssertEqual(options.keepaliveCount, 12, "TCP_PROBES")
    XCTAssertEqual(options.connectionDropTime, 24, "TCP_USER_TIMEOUT")
    // Linux's TCP_USER_TIMEOUT also ends a zero-window peer; Darwin needs the persist timer,
    // or a peer that stops reading queues every relayed frame in memory.
    XCTAssertEqual(options.persistTimeout, 24, "TCP_USER_TIMEOUT over a zero window")
    XCTAssertTrue(options.noDelay, "TCPInterface.py:149, :241 — TCP_NODELAY on every socket")
  }

  /// The shared-instance option set is `TCP_NODELAY` only.
  ///
  /// Python's `LocalClientInterface`
  /// calls no `set_timeouts_*` on either its dial (`LocalInterface.py:147`) or the sockets its
  /// server accepts (`:100`), so enabling keepalive there would exceed the reference.
  func testFactoryLeavesKeepaliveOffForTheSharedInstanceOptionSet() {
    let options = RNSSocketOptions.localOptions()
    XCTAssertTrue(options.noDelay, "LocalInterface.py:100, :147 — TCP_NODELAY")
    XCTAssertFalse(
      options.enableKeepalive,
      "Python's LocalClientInterface sets no keepalive; its only one is the "
        + "application-level phy_keepalive flag on Android, not a socket option")
  }

  /// A fresh instance per call, because one already handed to a live connection can't be
  /// reused—and because a shared mutable options object would let one interface's
  /// configuration leak into another's socket.
  func testFactoryReturnsAFreshInstancePerCall() {
    XCTAssertFalse(RNSSocketOptions.tcpOptions() === RNSSocketOptions.tcpOptions())
    XCTAssertFalse(
      RNSSocketOptions.tcpParameters().parameters
        === RNSSocketOptions.tcpParameters().parameters)
  }

  // MARK: - The handed-over object, per site

  /// The server accepts on a BSD socket (`bugs/040`), so `getsockopt` reads the accepted
  /// descriptor's options back: keepalive, Python's three timers, the user timeout, the persist
  /// timeout and `TCP_NODELAY` (`TCPInterface.py:241`, `:259-261`, `bugs/023`).
  func testAcceptedTCPServerSocketCarriesTheFactoryOptions() throws {
    let port = try freeLoopbackPort()
    let server = TCPServerInterface(name: "optaccept", port: port, bindIP: "127.0.0.1")
    let accepted = expectation(description: "accepted")
    var read: [String: Int32] = [:]
    server.acceptedDescriptorHandlerForTesting = { fd in
      func get(_ level: Int32, _ name: Int32) -> Int32 {
        var value: Int32 = -1
        var length = socklen_t(MemoryLayout<Int32>.size)
        _ = getsockopt(fd, level, name, &value, &length)
        return value
      }
      read = [
        "keepalive": get(SOL_SOCKET, SO_KEEPALIVE),
        "idle": get(Int32(IPPROTO_TCP), TCP_KEEPALIVE),
        "interval": get(Int32(IPPROTO_TCP), TCP_KEEPINTVL),
        "count": get(Int32(IPPROTO_TCP), TCP_KEEPCNT),
        "drop": get(Int32(IPPROTO_TCP), TCP_RXT_CONNDROPTIME),
        "persist": get(Int32(IPPROTO_TCP), PERSIST_TIMEOUT),
        "nodelay": get(Int32(IPPROTO_TCP), TCP_NODELAY),
      ]
      accepted.fulfill()
    }
    try server.start()
    defer { server.stop() }

    let client = NWConnection(
      to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
      using: RNSSocketOptions.tcpParameters().parameters)
    client.start(queue: .global())
    defer { client.cancel() }
    wait(for: [accepted], timeout: 5.0)

    XCTAssertNotEqual(read["keepalive"], 0)
    XCTAssertEqual(read["idle"], Int32(RNSSocketOptions.probeAfter))
    XCTAssertEqual(read["interval"], Int32(RNSSocketOptions.probeInterval))
    XCTAssertEqual(read["count"], Int32(RNSSocketOptions.probes))
    XCTAssertEqual(read["drop"], Int32(RNSSocketOptions.userTimeout))
    XCTAssertEqual(read["persist"], Int32(RNSSocketOptions.userTimeout), "zero-window peer")
    XCTAssertNotEqual(read["nodelay"], 0)
  }

  func testTCPClientDialIsBuiltFromTheFactoryOptions() throws {
    // Dials a closed port: `connect()` runs and records its options regardless of whether
    // the connection ever reaches .ready, which is what this asserts.
    let client = TCPClientInterface(name: "optclient", host: "127.0.0.1", port: 45_932)
    try client.start()
    defer { client.stop() }

    let handed = try XCTUnwrap(client.handedOverTCPOptionsForTesting)
    XCTAssertTrue(handed.enableKeepalive)
    XCTAssertTrue(handed.noDelay)
  }

  func testLocalInterfaceDialIsBuiltFromTheSharedInstanceOptionSet() throws {
    let local = LocalInterface(name: "optlocal", port: 45_933)
    // Nothing is listening, so start() won't come up; the dial still happens.
    try? local.start()
    defer { local.stop() }

    let handed = try XCTUnwrap(
      local.handedOverTCPOptionsForTesting,
      "LocalInterface.connect() used NWConnection(to:using: .tcp) "
        + "before bugs/023 — the framework's defaults, which do not "
        + "include the TCP_NODELAY Python sets at LocalInterface.py:147")
    XCTAssertTrue(handed.noDelay)
    XCTAssertFalse(handed.enableKeepalive, "matches LocalInterface.py, which sets no keepalive")
  }

  /// The one site with a real readback. `PosixTCPServer` binds with POSIX sockets, and Python
  /// sets `TCP_NODELAY` on every socket its shared-instance server accepts
  /// (`LocalInterface.py:98-100`), so `getsockopt` can be asked directly.
  func testAcceptedSharedInstanceSocketHasNoDelaySet() throws {
    let server = PosixTCPServer(name: "Shared Instance", port: 45_935)
    try server.start()
    defer { server.stop() }

    let accepted = expectation(description: "accepted")
    server.acceptedDescriptorHandlerForTesting = { _ in accepted.fulfill() }

    let client = NWConnection(
      to: .hostPort(host: "127.0.0.1", port: 45_935),
      using: RNSSocketOptions.localParameters().parameters)
    client.start(queue: .global())
    defer { client.cancel() }
    wait(for: [accepted], timeout: 5.0)

    let fd = try XCTUnwrap(server.lastAcceptedDescriptorForTesting)
    var value: Int32 = 0
    var length = socklen_t(MemoryLayout<Int32>.size)
    let rc = getsockopt(fd, Int32(IPPROTO_TCP), TCP_NODELAY, &value, &length)
    XCTAssertEqual(rc, 0, "getsockopt failed on the accepted descriptor")
    XCTAssertNotEqual(
      value, 0,
      """
      TCP_NODELAY is off on the socket the shared-instance server accepted. \
      Python sets it at LocalInterface.py:100, on the accepted socket, in the \
      same branch the dial path sets it. This port set only SO_NOSIGPIPE — \
      the accept-path half of bugs/023, in the POSIX server rather than the \
      Network.framework one.
      """)
  }

  // MARK: - Construction-site uniqueness

  /// The structural guard, and the actual enforcement (D4).
  ///
  /// A behavioural test can't see this defect—that's why 1.7.0 shipped claiming "every
  /// socket" while two of the four sites still took framework defaults. A test that fails on
  /// any socket opened with stock parameters, anywhere in `Sources/`, can.
  func testNoSocketIsOpenedOutsideTheSharedFactory() throws {
    let sourcesDir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // ReticulumSwiftTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // package root
      .appendingPathComponent("Sources")

    /// The file that's *allowed* to construct options—the factory itself.
    let sanctioned = "SocketOptions.swift"

    /// Patterns that mean "a socket configured by something other than the factory".
    /// `.udp` isn't listed: Python opens its UDP sockets with no TCP options at all
    /// (`UDPInterface.py`), so a stock UDP parameter set is correct.
    let banned: [(pattern: String, why: String)] = [
      (
        "NWProtocolTCP.Options(",
        "constructs TCP options outside the factory — use RNSSocketOptions"
      ),
      (
        "using: .tcp",
        "opens a TCP socket with Network.framework's defaults, which have keepalive off "
          + "and Nagle on (TCPInterface.py:145-149, :241, :259-261)"
      ),
      (
        "NWParameters(tls:",
        "assembles its own parameters — use RNSSocketOptions.tcpParameters() / "
          + "localParameters()"
      ),
    ]

    var offences: [String] = []
    let files = FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil)
    while let url = files?.nextObject() as? URL {
      guard url.pathExtension == "swift", url.lastPathComponent != sanctioned else { continue }
      let src = try String(contentsOf: url, encoding: .utf8)
      for (index, line) in src.components(separatedBy: .newlines).enumerated() {
        // Comments cite these strings freely; only code counts.
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//"), !code.hasPrefix("///"), !code.hasPrefix("*") else {
          continue
        }
        for entry in banned where code.contains(entry.pattern) {
          offences.append(
            "  \(url.lastPathComponent):\(index + 1) — \(entry.why)\n"
              + "      \(code)")
        }
      }
    }

    XCTAssertTrue(
      offences.isEmpty,
      """
      \(offences.count) socket-opening site(s) bypass RNSSocketOptions:
      \(offences.joined(separator: "\n"))
      There must be exactly one place these options are constructed. Fixing the
      sites a failing test happens to touch is what left bugs/023 half-done
      through 1.7.0.
      """)
  }
}
