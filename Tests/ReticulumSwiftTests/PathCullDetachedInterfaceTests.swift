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

/// The jobs loop removes a path whose attached interface is no longer in `Transport.interfaces`
/// (`Transport.py:972-976`, RNS 1.5.5).
final class PathCullDetachedInterfaceTests: XCTestCase {

  private func makeAnnounce(_ aspect: String) throws -> (packet: Packet, destinationHash: Data) {
    let destination = try Destination(
      identity: Identity(), direction: .in, kind: .single,
      appName: "pathcull", aspects: [aspect])
    return (try Announce.make(for: destination), destination.hash)
  }

  /// Learns a path through `iface`, which `transport` already holds registered.
  private func learnPath(
    on transport: Transport, through iface: LoopbackInterface, aspect: String
  ) throws -> Data {
    let (announce, destinationHash) = try makeAnnounce(aspect)
    iface.inboundHandler?(announce, iface)
    XCTAssertTrue(
      transport.paths[destinationHash]?.nextHopInterface === iface,
      "precondition: the announce installs a path through the interface")
    return destinationHash
  }

  // MARK: - The cull

  func testAPathThroughADeregisteredInterfaceIsCulled() throws {
    let transport = Transport()
    let iface = LoopbackInterface(name: "eth0")
    transport.register(interface: iface)
    let destinationHash = try learnPath(on: transport, through: iface, aspect: "deregistered")
    XCTAssertTrue(transport.markPathUnresponsive(for: destinationHash))

    transport.runJobs()
    XCTAssertNotNil(
      transport.paths[destinationHash], "a path through a registered interface stays")

    transport.deregister(interface: iface)
    transport.runJobs()

    XCTAssertNil(
      transport.paths[destinationHash],
      """
      the interface is still alive but no longer registered, so the path goes \
      (Transport.py:972-976)
      """)
    XCTAssertNil(transport.nextHopInterface(for: destinationHash))
    XCTAssertFalse(
      transport.pathIsUnresponsive(to: destinationHash),
      "the path's responsiveness state leaves with it (Transport.py:858-861)")
  }

  func testAPathThroughADetachedInterfaceIsCulled() throws {
    let transport = Transport()
    let iface = LoopbackInterface(name: "eth0")
    transport.register(interface: iface)
    let destinationHash = try learnPath(on: transport, through: iface, aspect: "detached")

    transport.detach(interface: iface)
    transport.runJobs()

    XCTAssertNil(transport.paths[destinationHash])
  }

  /// A deallocated interface leaves the weak reference `nil`.
  ///
  /// Python's `None in Transport.interfaces` is false, so it culls that case too.
  func testAPathWhoseInterfaceWasDeallocatedIsCulled() throws {
    let transport = Transport()
    var destinationHash = Data()
    // The pool releases what the Objective-C runtime autoreleased while the path was learned.
    try autoreleasepool {
      let iface = LoopbackInterface(name: "eth0")
      transport.register(interface: iface)
      destinationHash = try learnPath(on: transport, through: iface, aspect: "deallocated")
      transport.deregister(interface: iface)
    }
    XCTAssertNotNil(transport.paths[destinationHash])
    XCTAssertNil(
      transport.paths[destinationHash]?.nextHopInterface,
      "precondition: nothing else holds the interface")

    transport.runJobs()

    XCTAssertNil(transport.paths[destinationHash])
  }

  // MARK: - What the cull keeps

  /// A path through a sub-interface stays while the multi-radio parent is registered.
  ///
  /// The port registers only the parent, which delivers each sub-interface's traffic. Python
  /// registers every sub-interface (`RNodeMultiInterface.py:381`).
  func testAPathThroughASubInterfaceOfARegisteredMultiInterfaceStays() throws {
    let transport = Transport()
    let sub = RNodeSubInterface(
      name: "sub0", index: 0, interfaceType: "SX127X",
      frequency: 867_200_000, bandwidth: 125_000, txPower: 0, sf: 8, cr: 5)
    let multi = try RNodeMultiInterface(
      name: "multi0", transport: MockRNodeTransport(), subInterfaces: [sub])
    transport.register(interface: multi)

    let (announce, destinationHash) = try makeAnnounce("subinterface")
    multi.rawInboundHandler?(try announce.pack(), sub)
    XCTAssertTrue(
      transport.paths[destinationHash]?.nextHopInterface === sub,
      "precondition: the path records the sub-interface, not the parent")

    transport.runJobs()
    XCTAssertNotNil(transport.paths[destinationHash])

    transport.deregister(interface: multi)
    transport.runJobs()
    XCTAssertNil(
      transport.paths[destinationHash],
      "the sub-interface leaves with its parent")
  }

  /// A restored entry waits outside the path table until its interface registers
  /// (`bugs/041`), so the cull can't reach it early.
  func testAParkedRestoreSurvivesTheCullAndInstallsLater() throws {
    let storage = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns-pathcull-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: storage) }
    let cache = storage.appendingPathComponent("cache")

    let live = Transport()
    live.cacheDirectory = cache
    let liveIface = LoopbackInterface(name: "eth0")
    live.register(interface: liveIface)
    let destinationHash = try installPersistablePath(
      on: live, through: liveIface, aspect: "parked"
    ).destinationHash
    let store = PathStore.snapshot(of: live)
    XCTAssertEqual(store.entries.count, 1)

    let revived = Transport()
    revived.cacheDirectory = cache
    store.apply(to: revived)
    revived.runJobs()
    XCTAssertEqual(revived.pendingPathRestores.count, 1, "still waiting for `eth0`")

    let iface = LoopbackInterface(name: "eth0")
    revived.register(interface: iface)
    revived.runJobs()

    XCTAssertTrue(revived.paths[destinationHash]?.nextHopInterface === iface)
  }

  /// Python culls the path table entry and keeps the tunnel's copy of the path, which
  /// `handle_tunnel` restores when the endpoint reappears (`Transport.py:1031-1033`,
  /// `:2820-2867`).
  func testATunnelKeepsItsPathWhenThePathTableEntryIsCulled() throws {
    let transport = Transport()
    let iface = LoopbackInterface(name: "eth0")
    let tunnelID = Data(repeating: 0x7A, count: 32)
    transport.register(interface: iface)
    iface.tunnelID = tunnelID
    transport.restore(
      tunnel: Transport.TunnelEntry(
        tunnelID: tunnelID, iface: iface, paths: [:],
        expires: Date().addingTimeInterval(Transport.tunnelTimeout)))
    let destinationHash = try learnPath(on: transport, through: iface, aspect: "tunnel")
    XCTAssertNotNil(transport.tunnels[tunnelID]?.paths[destinationHash])

    transport.deregister(interface: iface)
    transport.runJobs()

    XCTAssertNil(transport.paths[destinationHash])
    XCTAssertNotNil(
      transport.tunnels[tunnelID]?.paths[destinationHash],
      "the tunnel table holds the path for the endpoint's return")
  }
}
