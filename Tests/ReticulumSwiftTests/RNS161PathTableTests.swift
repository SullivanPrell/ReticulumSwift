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

/// RNS 1.6.1's defaults and path-table culling (`Transport.py:194-195`, `:226-238`,
/// `:1181-1229`, `Interface.py:71`).
final class RNS161PathTableTests: XCTestCase {

  final class Hop: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  final class LocalClients: Interface, LocalClientServingInterface {
    var name = "local-clients"
    var bitrate: Int = 0
    var isOnline: Bool = true
    var clientCount = 1
    var inboundHandler: ((Packet, any Interface) -> Void)?
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  private func dst(_ n: Int) -> Data {
    Data([UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF)]) + Data(repeating: 0xD1, count: 14)
  }

  private func path(
    _ n: Int, via hop: any Interface, hops: UInt8 = 1, heard: Date, expires: Date? = nil,
    used: Date? = nil
  ) -> Transport.PathEntry {
    var entry = Transport.PathEntry(
      destinationHash: dst(n), nextHopInterface: hop, hops: hops, lastHeard: heard,
      identityHash: Data(repeating: 0x01, count: 16), expires: expires)
    entry.used = used
    return entry
  }

  func testDefaultsMatchRNS161() {
    let stamps = StampSettings()
    XCTAssertTrue(stamps.stampDestinations)
    XCTAssertTrue(stamps.stampPRs)
    XCTAssertEqual(Transport.reverseTimeout, 3 * 60)
    XCTAssertEqual(Transport.pathPoolUnusedMax, 1536)
    XCTAssertEqual(Transport.pathPoolUnusedMin, 512)
    XCTAssertEqual(Transport.pathPoolUsedTarget, 2048)
    XCTAssertEqual(Transport.tunnelReconnectWindow, 10 * 60)
    XCTAssertEqual(IngressControlState.maxHeldAnnounces, 64)
  }

  /// A path of 0 hops, which leads to a local client, neither expires nor lingers out.
  ///
  /// `if now > path_expiry and path_hops != 0` and `elif path_hops != 0 and path_used == 0`
  /// (`Transport.py:1204`, `:1212`).
  func testAZeroHopPathNeitherExpiresNorLingersOut() {
    let t = Transport()
    let local = LocalClients()
    let hop = Hop(name: "one-hop")
    t.register(interface: local)
    t.register(interface: hop)
    let now = Date()
    let old = now.addingTimeInterval(-Transport.unusedPathLinger * 20)
    t.restore(
      path: path(1, via: local, hops: 0, heard: old, expires: now.addingTimeInterval(-1)),
      forDestination: dst(1))
    t.restore(
      path: path(2, via: hop, hops: 0, heard: old, expires: now.addingTimeInterval(-1)),
      forDestination: dst(2))

    t.sweepExpiredPaths(now: now)

    XCTAssertTrue(t.hasPath(to: dst(1)))
    XCTAssertFalse(t.hasPath(to: dst(2)))
  }

  /// A path longer than the hop limiter is removed.
  ///
  /// `elif path_hops > Transport.HOP_LIMITER` (`Transport.py:1216-1219`). A path stores the
  /// wire count, one less than Python's.
  func testAPathBeyondTheHopLimiterIsRemoved() {
    let t = Transport()
    t.hopLimiter = 4
    let hop = Hop(name: "far")
    t.register(interface: hop)
    let now = Date()
    let expires = now.addingTimeInterval(3600)
    t.restore(
      path: path(1, via: hop, hops: 4, heard: now, expires: expires, used: now),
      forDestination: dst(1))
    t.restore(
      path: path(2, via: hop, hops: 3, heard: now, expires: expires, used: now),
      forDestination: dst(2))

    t.sweepExpiredPaths(now: now)

    XCTAssertFalse(t.hasPath(to: dst(1)))
    XCTAssertTrue(t.hasPath(to: dst(2)))
  }

  /// The never-used pool target is `max(MIN, MAX - max(0, used - USED_TARGET))`
  /// (`Transport.py:1221-1222`).
  func testTheUnusedPoolShrinksAsUsedPathsPassTheirTarget() {
    let t = Transport()
    let hop = Hop(name: "pool")
    t.register(interface: hop)
    let now = Date()
    let expires = now.addingTimeInterval(86_400)
    let used = Transport.pathPoolUsedTarget + 600
    for n in 0..<used {
      t.restore(
        path: path(n, via: hop, heard: now, expires: expires, used: now), forDestination: dst(n))
    }
    let unused = 1000
    for n in used..<(used + unused) {
      t.restore(path: path(n, via: hop, heard: now, expires: expires), forDestination: dst(n))
    }

    t.sweepExpiredPaths(now: now.addingTimeInterval(Transport.poolSizeCheckInterval + 1))

    let target = max(Transport.pathPoolUnusedMin, Transport.pathPoolUnusedMax - 600)
    XCTAssertEqual(t.paths.count, used + target)
  }
}
