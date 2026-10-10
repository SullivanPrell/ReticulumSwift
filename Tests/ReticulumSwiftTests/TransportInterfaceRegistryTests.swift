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

final class TransportInterfaceRegistryTests: XCTestCase {

  // Minimal stub interface for registry tests.
  private final class StubIface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)? = nil
    init(_ name: String = "stub") { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws {}
  }

  func testRegisterInterfaceAppearsInList() {
    let transport = Transport()
    let iface = StubIface()
    transport.register(interface: iface)
    XCTAssertTrue(transport.interfaces.contains { $0 === iface })
  }

  func testDeregisterInterfaceRemovedFromList() {
    let transport = Transport()
    let iface = StubIface()
    transport.register(interface: iface)
    XCTAssertTrue(transport.interfaces.contains { $0 === iface })
    transport.deregister(interface: iface)
    XCTAssertFalse(transport.interfaces.contains { $0 === iface })
  }

  func testDeregisterUnregisteredInterfaceIsNoop() {
    let transport = Transport()
    let iface = StubIface()
    transport.deregister(interface: iface)  // must not crash
    XCTAssertFalse(transport.interfaces.contains { $0 === iface })
  }

  func testRegisterThenDeregisterLeavesOthers() {
    let transport = Transport()
    let iface1 = StubIface("iface1")
    let iface2 = StubIface("iface2")
    transport.register(interface: iface1)
    transport.register(interface: iface2)
    transport.deregister(interface: iface1)
    XCTAssertFalse(transport.interfaces.contains { $0 === iface1 })
    XCTAssertTrue(transport.interfaces.contains { $0 === iface2 })
  }

  /// `stop()` and `detachInterfaces()` race no concurrent `deregister(interface:)`.
  ///
  /// A shared instance's local client deregisters itself on a network-callback thread while the
  /// transport stops. Run under `--sanitize=thread`: a plain run doesn't report the data race.
  func testStoppingRacesNoConcurrentDeregister() {
    for round in 0..<20 {
      let transport = Transport()
      let ifaces = (0..<32).map { StubIface("stub\($0)") }
      for iface in ifaces { transport.register(interface: iface) }
      DispatchQueue.concurrentPerform(iterations: 2) { worker in
        if worker == 1 {
          for iface in ifaces { transport.deregister(interface: iface) }
        } else if round.isMultiple(of: 2) {
          transport.stop()
        } else {
          transport.detachInterfaces()
        }
      }
      XCTAssertTrue(transport.interfaces.isEmpty)
    }
  }
}
