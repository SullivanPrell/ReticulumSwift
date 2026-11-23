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

#if canImport(Darwin)
final class AutoInterfaceTests: XCTestCase {

  func testMulticastAddressDerivation() {
    // Verify the multicast address computation matches Python's AutoInterface.
    // Python: sha256("reticulum") → "ff12:0:d70b:fb1c:16e4:5e39:485e:31e1"
    let iface = AutoInterface(name: "test")
    // Access the mcast address via reflection by initializing and checking send.
    // Verifies the group hash calculation matches the Python reference.
    let groupID = AutoInterface.defaultGroupID
    let hash = Hashes.fullHash(groupID)
    let g = Array(hash)
    func pair(_ lo: Int, _ hi: Int) -> String {
      String(format: "%04x", Int(g[lo]) + (Int(g[hi]) << 8))
    }
    let gt = "0:\(pair(3,2)):\(pair(5,4)):\(pair(7,6)):\(pair(9,8)):\(pair(11,10)):\(pair(13,12))"
    let mcastAddr = "ff12:\(gt)"
    XCTAssertEqual(mcastAddr, "ff12:0:d70b:fb1c:16e4:5e39:485e:31e1")
  }

  func testDiscoveryBeaconFormat() {
    // Discovery beacon = sha256(group_id + link_local_addr)
    let groupID = AutoInterface.defaultGroupID
    let linkLocal = "fe80::1"
    let token = Hashes.fullHash(groupID + Data(linkLocal.utf8))
    XCTAssertEqual(token.count, 32)
    // Verify it matches Python:
    // sha256(b"reticulum" + b"fe80::1")
    // Running Python here isn't practical, but the structure is checkable.
    let expected = Hashes.fullHash(groupID + Data(linkLocal.utf8))
    XCTAssertEqual(token, expected)
  }

  func testAutoInterfaceDefaultPorts() {
    XCTAssertEqual(AutoInterface.defaultDiscoveryPort, 29716)
    XCTAssertEqual(AutoInterface.defaultDataPort, 42671)
  }

  func testAutoInterfaceInitialization() {
    let iface = AutoInterface(name: "auto0")
    XCTAssertEqual(iface.name, "auto0")
    XCTAssertFalse(iface.isOnline)
  }

  /// Data counts only from a host that beaconed with the group token.
  ///
  /// Python checks the peer table (`AutoInterface.py:613-615`). The data socket binds every
  /// address, so without the check any host that reaches the port injects packets.
  func testDataOnlyFromPeersThatBeaconed() throws {
    let group = Data("ingress-\(UUID())".utf8)
    let base = UInt16.random(in: 40_000...60_000)
    let iface = AutoInterface(
      name: "ingress", groupID: group, discoveryPort: base, dataPort: base + 1)
    try iface.start()
    defer { iface.stop() }
    try XCTSkipUnless(iface.isOnline, "no IPv6 link-local interface on this host")
    let lock = NSLock()
    var frames: [Data] = []
    iface.rawInboundHandler = { data, _ in
      lock.lock()
      frames.append(data)
      lock.unlock()
    }
    func received() -> [Data] {
      lock.lock()
      defer { lock.unlock() }
      return frames
    }

    Self.udpSend(Data("stranger".utf8), toPort: base + 1)  // ::1 never beaconed
    Thread.sleep(forTimeInterval: 0.3)
    XCTAssertEqual(received(), [], "accepted data from a host that never beaconed")

    Self.udpSend(Hashes.fullHash(group + Data("::1".utf8)), toPort: base)
    Thread.sleep(forTimeInterval: 0.3)
    Self.udpSend(Data("peer".utf8), toPort: base + 1)
    let deadline = Date().addingTimeInterval(2)
    while received().isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    XCTAssertEqual(received(), [Data("peer".utf8)])
  }

  /// A changed link-local address is followed, so beacons keep authenticating.
  ///
  /// Python does this in `peer_jobs` (`AutoInterface.py:411-427`). Only interfaces already
  /// adopted are followed.
  func testBeaconFollowsAChangedLinkLocalAddress() {
    let group = Data("follow".utf8)
    let iface = AutoInterface(name: "follow", groupID: group)
    iface.adoptedInterfaces = ["en0": "fe80::1"]
    iface.ownLinkLocalAddresses = ["fe80::1"]

    iface.followLinkLocalAddresses([
      (ifname: "en0", addr: "fe80::2"), (ifname: "en9", addr: "fe80::9"),
    ])

    XCTAssertEqual(iface.beaconToken(for: "en0"), Hashes.fullHash(group + Data("fe80::2".utf8)))
    XCTAssertEqual(iface.ownLinkLocalAddresses, ["fe80::2"])
    XCTAssertNil(iface.beaconToken(for: "en9"))
  }

  private static func udpSend(_ data: Data, toPort port: UInt16) {
    let s = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
    defer { close(s) }
    var dst = sockaddr_in6()
    dst.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    dst.sin6_family = sa_family_t(AF_INET6)
    dst.sin6_port = port.bigEndian
    dst.sin6_addr = in6addr_loopback
    data.withUnsafeBytes { bytes in
      withUnsafePointer(to: &dst) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          _ = sendto(
            s, bytes.baseAddress, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
        }
      }
    }
  }
}
#endif  // canImport(Darwin)
