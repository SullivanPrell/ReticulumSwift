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

/// The routing half of `medium_path_timeout`: which process's interfaces the answer describes.
///
/// A utility attached as a local client has its own `Transport`, whose only interface is the
/// loopback `LocalInterface`. Asking it for the slowest online bitrate reports the loopback's,
/// so the timeout would never be extended on exactly the nodes that need it—the daemon
/// holding the LoRa radio is a different process. Python guards the accessor with
/// `if self.is_connected_to_shared_instance:` and proxies over the management socket
/// (`Reticulum.py:1766-1784`); these tests pin both arms.
final class MediumPathTimeoutWiringTests: XCTestCase {

  private final class Iface: Interface {
    var name: String
    var bitrate: Int
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String, bitrate: Int) {
      self.name = name
      self.bitrate = bitrate
    }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  private func transport(bitrate: Int) -> Transport {
    let t = Transport()
    t.register(interface: Iface(name: "iface", bitrate: bitrate))
    t.prioritizeInterfaces()
    return t
  }

  // MARK: - Local vs shared routing

  func testAStandaloneProcessAnswersFromItsOwnTransport() {
    let t = transport(bitrate: 1200)
    XCTAssertEqual(
      InstanceConnection.mediumPathTimeout(rpc: nil, transport: t),
      t.mediumPathTimeout(), accuracy: 1e-9)
    XCTAssertGreaterThan(t.mediumPathTimeout(), Constants.defaultPerHopTimeout)
  }

  /// Python logs the exception and returns `0` (`Reticulum.py:1780-1781`)—not the local
  /// value.
  ///
  /// Falling back to the local transport here would be worse than useless: it would
  /// answer with the client's loopback bitrate and read as a successful, fast link.
  func testAFailedRPCAnswersZeroRatherThanTheClientsOwnBitrate() {
    let t = transport(bitrate: 1200)
    // Nothing is listening on this port, so every call throws.
    let dead = RPCClient(host: "127.0.0.1", port: 1, authkey: Data(count: 32), timeout: 0.2)
    XCTAssertEqual(InstanceConnection.mediumPathTimeout(rpc: dead, transport: t), 0)
  }

  // MARK: - The probe's own timeout shape

  /// `timeout or max(DEFAULT_TIMEOUT+first_hop_timeout, medium_path_timeout)`
  /// (rnprobe.py:84).
  ///
  /// The `max` is inside the `or`, so an explicit `-t` still wins outright.
  func testProbeTimeoutTakesTheLargerOfTheHopSumAndTheMediumTimeout() {
    // Medium timeout loses: 12 + 6 = 18 > 7.
    XCTAssertEqual(
      NetworkProbe.effectiveTimeout(nil, firstHopTimeout: 6, mediumPathTimeout: 7),
      NetworkProbe.defaultTimeout + 6, accuracy: 1e-9)
    // Medium timeout wins.
    XCTAssertEqual(
      NetworkProbe.effectiveTimeout(nil, firstHopTimeout: 6, mediumPathTimeout: 900),
      900, accuracy: 1e-9)
  }

  func testAnExplicitProbeTimeoutOverridesBoth() {
    XCTAssertEqual(
      NetworkProbe.effectiveTimeout(3, firstHopTimeout: 6, mediumPathTimeout: 900),
      3, accuracy: 1e-9)
  }

  /// `-t 0` is falsy in Python, so it means "unset" rather than "give up immediately", and
  /// the medium timeout still applies.
  func testZeroStillMeansUnset() {
    XCTAssertEqual(
      NetworkProbe.effectiveTimeout(0, firstHopTimeout: 6, mediumPathTimeout: 900),
      900, accuracy: 1e-9)
  }

  // MARK: - rnpath's spinner deadline

  /// The runner-level half of `limit = time.time()+max(timeout, medium_path_timeout())`
  /// (rnpath.py:455).
  ///
  /// Driven by an advancing clock and a destination that never resolves, so
  /// the number of polls before the loop gives up *is* the deadline.
  private func pollsBeforeGivingUp(timeout: TimeInterval, mediumPathTimeout: TimeInterval) -> Int {
    var options = RNPathOptions()
    options.destination = String(repeating: "ab", count: 16)
    options.timeout = timeout

    let management = StubManagement()
    management.stubMediumPathTimeout = mediumPathTimeout
    let resolver = NeverResolves()

    // One second per observation of the clock. The loop reads it once per iteration after
    // capturing the deadline, so the poll count tracks the deadline directly.
    var tick: TimeInterval = 0
    let runner = RNPathRunner(
      options: options,
      management: management,
      resolver: resolver,
      now: {
        tick += 1
        return Date(timeIntervalSince1970: 1_700_000_000 + tick)
      },
      sleep: { _ in },
      output: { _ in })
    _ = runner.run()
    return resolver.hasPathCalls
  }

  func testTheSpinnerDeadlineIsFlooredAtTheMediumPathTimeout() {
    let short = pollsBeforeGivingUp(timeout: 5, mediumPathTimeout: 0)
    let floored = pollsBeforeGivingUp(timeout: 5, mediumPathTimeout: 60)
    XCTAssertGreaterThan(
      floored, short + 40,
      "a 60 s floor must outlast a 5 s -w by roughly the difference")
  }

  /// The floor only ever raises: a user who asks for longer than the medium timeout keeps it.
  func testAnExplicitTimeoutLongerThanTheFloorIsNotShortened() {
    XCTAssertEqual(
      pollsBeforeGivingUp(timeout: 60, mediumPathTimeout: 5),
      pollsBeforeGivingUp(timeout: 60, mediumPathTimeout: 0))
  }
}

private final class StubManagement: RNPathManagementSource {
  var localTransportIdentityHash: Data?
  var stubMediumPathTimeout: TimeInterval = 0
  func mediumPathTimeout() -> TimeInterval { stubMediumPathTimeout }
  func pathTable(maxHops: UInt8?) throws -> [RNPathTableEntry] { [] }
  func rateTable() throws -> [RNPathRateEntry] { [] }
  func blackholedIdentities() throws -> [RNPathBlackholeEntry] { [] }
  func dropPath(_ destinationHash: Data) throws -> Bool { false }
  func dropAllVia(_ transportHash: Data) throws -> Int { 0 }
  func dropAnnounceQueues() throws {}
  func blackholeIdentity(_ identityHash: Data, until: TimeInterval?, reason: String?) throws
    -> Bool?
  { nil }
  func unblackholeIdentity(_ identityHash: Data) throws -> Bool? { nil }
  func nextHop(for destinationHash: Data) throws -> Data? { nil }
  func nextHopInterfaceName(for destinationHash: Data) throws -> String? { nil }
}

private final class NeverResolves: RNPathPathResolver {
  private(set) var hasPathCalls = 0
  func hasPath(to destinationHash: Data) -> Bool {
    hasPathCalls += 1
    return false
  }
  func requestPath(for destinationHash: Data) {}
  func hopsTo(_ destinationHash: Data) -> UInt8? { nil }
}
