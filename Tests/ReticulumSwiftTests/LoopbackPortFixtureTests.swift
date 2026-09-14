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
import XCTest

@testable import ReticulumSwift

/// Covers the port fixture the socket suites pick throwaway ports with.
///
/// Several suites assert that connecting somewhere fails, and the port they connect to is
/// the whole setup for that assertion. While the port was a random pick out of a range,
/// nothing checked it: a collision with any listener on the machine turned
/// `LocalInterfaceReadinessTests.testStartThrowsWhenNothingIsListening` into
/// "XCTAssertThrowsError failed: did not throw an error"—a failure about the host rather
/// than about the interface. Six consecutive full-suite runs on one tree scored
/// 0, 5, 0, 2, 0, 0 failures, and both failing runs were that test.
///
/// So the fixture proves the port instead, and these cases pin the proof: each condition a
/// real port can be in is staged with a socket of this file's own and fed to the fixture.
final class LoopbackPortFixtureTests: XCTestCase {

  private var sockets: [Int32] = []

  override func tearDown() {
    for socket in sockets { Darwin.close(socket) }
    sockets = []
    super.tearDown()
  }

  /// Opens a loopback socket on a kernel-assigned port, listening or not, and returns its port.
  ///
  /// Binding to port 0 sidesteps the very problem under test: the caller never has to name a
  /// port it hopes is free.
  private func openSocket(listening: Bool) throws -> UInt16 {
    let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    try XCTSkipUnless(fd >= 0, "could not open a loopback socket")
    sockets.append(fd)

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    Darwin.inet_aton("127.0.0.1", &addr.sin_addr)
    let bound = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    try XCTSkipUnless(bound == 0, "could not bind a loopback socket")
    if listening {
      try XCTSkipUnless(Darwin.listen(fd, 4) == 0, "could not listen on a loopback socket")
    }

    var assigned = sockaddr_in()
    var size = socklen_t(MemoryLayout<sockaddr_in>.size)
    let named = withUnsafeMutablePointer(to: &assigned) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.getsockname(fd, $0, &size)
      }
    }
    try XCTSkipUnless(named == 0, "could not read back the bound port")
    return UInt16(bigEndian: assigned.sin_port)
  }

  // MARK: - The probe

  func testAListeningPortReadsAsAccepting() throws {
    let port = try openSocket(listening: true)
    XCTAssertEqual(loopbackPortState(port), .accepting)
  }

  func testAnUnusedPortReadsAsRefused() throws {
    let port = try XCTUnwrap(kernelAssignedLoopbackPort())
    XCTAssertEqual(loopbackPortState(port), .refused)
  }

  /// A port bound without a listener is the case that a plain "did the connect fail?" check
  /// gets wrong in the expensive direction.
  ///
  /// macOS drops the incoming segment rather than resetting it, so the connect fails only
  /// after the client's own timeout. Handing such a port to a test that expects a fast
  /// refusal trades a wrong answer for a slow one.
  func testABoundPortWithNoListenerReadsAsUnanswered() throws {
    let port = try openSocket(listening: false)
    XCTAssertEqual(loopbackPortState(port, timeout: 0.2), .unanswered)
  }

  // MARK: - Choosing a port

  /// The defect itself: a candidate that something is already listening on must not come back.
  func testACandidateThatIsInUseIsRejected() throws {
    let busy = try openSocket(listening: true)
    guard let spare = kernelAssignedLoopbackPort() else {
      throw XCTSkip("no kernel-assigned port available")
    }

    var queue = [busy, busy, spare]
    let chosen = try freeLoopbackPort(nextCandidate: { queue.isEmpty ? nil : queue.removeFirst() })

    XCTAssertNotEqual(chosen, busy, "a port with a live listener is not free")
    XCTAssertEqual(chosen, spare)
  }

  /// The other half of the same check: a port that swallows connects is no use either.
  func testACandidateThatSwallowsConnectsIsRejected() throws {
    let silent = try openSocket(listening: false)
    guard let spare = kernelAssignedLoopbackPort() else {
      throw XCTSkip("no kernel-assigned port available")
    }

    var queue = [silent, spare]
    let chosen = try freeLoopbackPort(nextCandidate: { queue.isEmpty ? nil : queue.removeFirst() })

    XCTAssertEqual(chosen, spare)
  }

  /// Running out of candidates has to end the test, not hand back a busy port anyway.
  func testGivingUpThrowsRatherThanReturningABusyPort() throws {
    let busy = try openSocket(listening: true)
    XCTAssertThrowsError(try freeLoopbackPort(attempts: 3, nextCandidate: { busy })) { error in
      XCTAssertTrue(error is XCTSkip, "exhaustion is an environment problem, not a failure")
    }
  }

  func testTheChosenPortRefusesConnections() throws {
    let port = try freeLoopbackPort()
    XCTAssertEqual(loopbackPortState(port), .refused)
  }

  /// The other contract callers rely on: a server can still bind what the fixture returned.
  func testTheChosenPortCanBeBound() throws {
    let server = PosixTCPServer(name: "Shared Instance", port: try freeLoopbackPort())
    XCTAssertNoThrow(try server.start())
    defer { server.stop() }
    XCTAssertEqual(loopbackPortState(server.port), .accepting)
  }
}
