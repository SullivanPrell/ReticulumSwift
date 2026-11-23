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

final class UDPInterfaceTests: XCTestCase {

  func testDatagramRoundTripBetweenTwoUDPInterfaces() throws {
    // Pick two different ports on loopback. Use high range to avoid
    // collisions in shared CI environments.
    let portA: UInt16 = UInt16.random(in: 40_000...50_000)
    let portB: UInt16 = portA + 1

    let a = UDPInterface(
      name: "A",
      listenPort: portA,
      forwardHost: "127.0.0.1",
      forwardPort: portB
    )
    let b = UDPInterface(
      name: "B",
      listenPort: portB,
      forwardHost: "127.0.0.1",
      forwardPort: portA
    )

    let received = expectation(description: "B receives")
    var got: Packet?
    b.inboundHandler = { pkt, _ in
      got = pkt
      received.fulfill()
    }

    try a.start()
    try b.start()
    defer {
      a.stop()
      b.stop()
    }

    // Give the sockets a moment to actually bind before the send fires.
    Thread.sleep(forTimeInterval: 0.05)

    let pkt = Packet(
      destinationType: .single,
      packetType: .data,
      destinationHash: Data(repeating: 0xCC, count: Constants.truncatedHashLength),
      data: Data("udp-hello".utf8)
    )
    try a.send(pkt)

    wait(for: [received], timeout: 2.0)
    XCTAssertEqual(got?.data, Data("udp-hello".utf8))
    XCTAssertEqual(got?.destinationHash, pkt.destinationHash)
  }

  /// The manual's `forward_ip = 255.255.255.255` block.
  ///
  /// Python sends with `SO_BROADCAST` (`UDPInterface.py:121`); a socket without it gets
  /// `EACCES` and the packet is lost.
  func testBroadcastForwardReachesAListener() throws {
    let port = UInt16.random(in: 40_000...60_000)
    try XCTSkipUnless(Self.hostCanBroadcast(toPort: port + 7), "no IPv4 broadcast route")

    let listener = UDPInterface(name: "L", listenPort: port)
    let sender = UDPInterface(name: "S", forwardHost: "255.255.255.255", forwardPort: port)
    let received = expectation(description: "broadcast received")
    received.assertForOverFulfill = false
    listener.inboundHandler = { pkt, _ in
      if pkt.data == Data("udp-broadcast".utf8) { received.fulfill() }
    }
    try listener.start()
    try sender.start()
    defer {
      listener.stop()
      sender.stop()
    }
    Thread.sleep(forTimeInterval: 0.05)
    try sender.send(
      Packet(
        destinationType: .plain, packetType: .data,
        destinationHash: Data(repeating: 0xBB, count: Constants.truncatedHashLength),
        data: Data("udp-broadcast".utf8)))
    wait(for: [received], timeout: 2.0)
  }

  /// Whether a plain `SO_BROADCAST` socket can send to 255.255.255.255 here, so a host
  /// with no IPv4 network skips instead of failing.
  private static func hostCanBroadcast(toPort port: UInt16) -> Bool {
    let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    defer { close(s) }
    var on: Int32 = 1
    setsockopt(s, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
    var dst = sockaddr_in()
    dst.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    dst.sin_family = sa_family_t(AF_INET)
    dst.sin_port = port.bigEndian
    dst.sin_addr.s_addr = INADDR_BROADCAST
    let byte: UInt8 = 0
    return withUnsafePointer(to: &dst) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        withUnsafePointer(to: byte) { b in
          sendto(s, b, 1, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) == 1
        }
      }
    }
  }
}
