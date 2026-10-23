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

/// The tunnel-table cull in Python's jobs loop (`Transport.py:1015-1064`, popped at
/// `:1127-1131`, RNS 1.5.7).
final class TunnelTableCullTests: XCTestCase {

  private let transport = Transport()
  private let iface = PathRequestResponderTests.CapturingInterface(name: "eth0")
  private let now = Date()

  override func setUp() {
    super.setUp()
    transport.register(interface: iface)
  }

  /// A random blob whose last five bytes carry `emittedAt` (`Transport.py:3725-3726`).
  private func blob(emittedAt: TimeInterval) -> Data {
    var data = Data(Hashes.randomHash().prefix(5))
    for shift in stride(from: 32, through: 0, by: -8) {
      data.append(UInt8(truncatingIfNeeded: UInt64(emittedAt) >> shift))
    }
    return data
  }

  private func path(to destinationHash: Data, heard: Date, emittedAt: TimeInterval = 1000)
    -> Transport.PathEntry
  {
    Transport.PathEntry(
      destinationHash: destinationHash, nextHopInterface: iface, hops: 1, lastHeard: heard,
      identityHash: Hashes.randomHash().prefix(16), cachedAnnounceHash: Hashes.randomHash(),
      randomBlobs: [blob(emittedAt: emittedAt)])
  }

  @discardableResult
  private func tunnel(
    expires: Date, paths: [Transport.PathEntry] = [], through endpoint: (any Interface)? = nil
  ) -> Data {
    let tunnelID = Hashes.randomHash()
    transport.restore(
      tunnel: Transport.TunnelEntry(
        tunnelID: tunnelID, iface: endpoint ?? iface,
        paths: Dictionary(uniqueKeysWithValues: paths.map { ($0.destinationHash, $0) }),
        expires: expires))
    return tunnelID
  }

  private func destination() -> Data { Data(Hashes.randomHash().prefix(16)) }

  func testAnExpiryMoreThanTwiceTheTimeoutAheadIsRemoved() {
    let atLimit = tunnel(expires: now.addingTimeInterval(Transport.tunnelTimeout * 2))
    let past = tunnel(expires: now.addingTimeInterval(Transport.tunnelTimeout * 2 + 1))
    transport.sweepTunnels(now: now)
    XCTAssertNotNil(transport.tunnels[atLimit], "`>` at Transport.py:1022")
    XCTAssertNil(transport.tunnels[past])
  }

  func testAnExpiredTunnelIsRemoved() {
    let atExpiry = tunnel(expires: now)
    let expired = tunnel(expires: now.addingTimeInterval(-1))
    transport.sweepTunnels(now: now)
    XCTAssertNotNil(transport.tunnels[atExpiry], "`>` at Transport.py:1026")
    XCTAssertNil(transport.tunnels[expired])
  }

  func testAnExpiredTunnelGoesWithItsFreshPaths() {
    let expired = tunnel(
      expires: now.addingTimeInterval(-1), paths: [path(to: destination(), heard: now)])
    transport.sweepTunnels(now: now)
    XCTAssertNil(transport.tunnels[expired])
  }

  /// The test holds the interface, so only the cull can clear the weak reference.
  func testALiveTunnelForgetsADetachedInterface() {
    let detached = PathRequestResponderTests.CapturingInterface(name: "gone")
    transport.register(interface: detached)
    let tunnelID = tunnel(
      expires: now.addingTimeInterval(Transport.tunnelTimeout), through: detached)
    transport.deregister(interface: detached)
    transport.sweepTunnels(now: now)
    XCTAssertNotNil(transport.tunnels[tunnelID], "the tunnel stays (Transport.py:1031-1033)")
    XCTAssertNil(transport.tunnels[tunnelID]?.iface)
  }

  func testATunnelPathOlderThanTheTimeoutIsRemovedAndTheTunnelStays() {
    let atLimit = path(
      to: destination(), heard: now.addingTimeInterval(-Transport.tunnelPathTimeout))
    let stale = path(
      to: destination(), heard: now.addingTimeInterval(-Transport.tunnelPathTimeout - 1))
    let tunnelID = tunnel(
      expires: now.addingTimeInterval(Transport.tunnelTimeout), paths: [atLimit, stale])
    transport.sweepTunnels(now: now)
    XCTAssertEqual(
      transport.tunnels[tunnelID].map { Set($0.paths.keys) }, [atLimit.destinationHash],
      "`>` at Transport.py:1040")
  }

  func testATunnelPathSupersededByALaterTablePathIsRemoved() {
    let superseded = path(to: destination(), heard: now, emittedAt: 1000)
    let equal = path(to: destination(), heard: now, emittedAt: 1000)
    let unrivalled = path(to: destination(), heard: now, emittedAt: 1000)
    transport.restore(
      path: path(to: superseded.destinationHash, heard: now, emittedAt: 1001),
      forDestination: superseded.destinationHash)
    transport.restore(
      path: path(to: equal.destinationHash, heard: now, emittedAt: 1000),
      forDestination: equal.destinationHash)
    let tunnelID = tunnel(
      expires: now.addingTimeInterval(Transport.tunnelTimeout),
      paths: [superseded, equal, unrivalled])
    transport.sweepTunnels(now: now)
    XCTAssertEqual(
      transport.tunnels[tunnelID].map { Set($0.paths.keys) },
      [equal.destinationHash, unrivalled.destinationHash], "strict `>` at Transport.py:1055")
  }

  func testAFreshTunnelIsUntouched() {
    let fresh = path(to: destination(), heard: now)
    let tunnelID = tunnel(expires: now.addingTimeInterval(Transport.tunnelTimeout), paths: [fresh])
    transport.sweepTunnels(now: now)
    XCTAssertEqual(transport.tunnels[tunnelID]?.paths[fresh.destinationHash], fresh)
    XCTAssertTrue(transport.tunnels[tunnelID]?.iface === iface)
  }

  func testTheJobsLoopCullsTheTunnelTable() {
    let expired = tunnel(expires: Date().addingTimeInterval(-1))
    transport.runJobs()
    XCTAssertNil(transport.tunnels[expired])
  }

  func testTheTunnelStoreOmitsWhatTheCullRemoved() {
    let expired = tunnel(
      expires: now.addingTimeInterval(-1), paths: [path(to: destination(), heard: now)])
    let stale = path(
      to: destination(), heard: now.addingTimeInterval(-Transport.tunnelPathTimeout - 1))
    let live = tunnel(expires: now.addingTimeInterval(Transport.tunnelTimeout), paths: [stale])
    func stored() -> [Data: Int] {
      Dictionary(
        uniqueKeysWithValues: TunnelStore.snapshot(of: transport).entries.map {
          ($0.tunnelID, $0.paths.count)
        })
    }
    XCTAssertEqual(stored(), [expired: 1, live: 1], "test premise: the store writes both")
    transport.sweepTunnels(now: now)
    XCTAssertEqual(stored(), [live: 0])
  }
}
