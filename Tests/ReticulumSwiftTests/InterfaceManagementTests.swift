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

/// Attaching, detaching and reloading interfaces on a running instance, as RNS 1.5.5 does.
///
/// `Reticulum._attach_interface`, `_detach_interface` and `_reload_interface`
/// (`Reticulum.py:771-841`) return `True`, `False` or `None`. The shared instance serves them
/// over RPC as `{"manage": "attach_interface" | "detach_interface" | "reload_interface",
/// "name": …}` (`Reticulum.py:1394-1398`), and `enable_interface_management = no` refuses all
/// three to callers (`Reticulum.py:553-556`).
final class InterfaceManagementTests: XCTestCase {

  final class Stub: Interface {
    var name: String
    var bitrate: Int = 1_000_000
    var isOnline = true
    var stopped = false
    var inboundHandler: ((Packet, any Interface) -> Void)?
    let interfaceState = InterfaceState()
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {
      stopped = true
      isOnline = false
    }
    func send(_ packet: Packet) throws {}
  }

  private var dir: URL!
  private var reticulum: Reticulum!

  override func setUp() {
    super.setUp()
    dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("iface-mgmt-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    reticulum = Reticulum(
      configuration: .init(
        storagePath: dir.appendingPathComponent("storage"),
        configPath: dir.appendingPathComponent("config"),
        shareInstance: false))
    Reticulum.storedInterfaceManagementEnabled = true
  }

  override func tearDown() {
    for iface in reticulum.transport.interfaces { iface.stop() }
    Reticulum.storedInterfaceManagementEnabled = true
    try? FileManager.default.removeItem(at: dir)
    super.tearDown()
  }

  /// Write a config whose interfaces are UDP blocks with no ports, so nothing binds.
  private func writeConfig(_ blocks: [(name: String, enabled: Bool)]) throws {
    var text = "[reticulum]\n  share_instance = No\n\n[interfaces]\n"
    for block in blocks {
      text += """
          [[\(block.name)]]
            type = UDPInterface
            interface_enabled = \(block.enabled ? "True" : "False")

        """
    }
    try text.write(
      to: dir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
  }

  private func attached(_ name: String) -> [any Interface] {
    reticulum.transport.interfaces.filter { $0.name == name }
  }

  // MARK: - Attach

  func testAttachBuildsTheInterfaceFromTheConfigFileEvenWhenDisabled() throws {
    try writeConfig([("Segment", false)])
    XCTAssertEqual(reticulum.attachInterface(named: "Segment"), true)
    XCTAssertEqual(attached("Segment").count, 1, "force_attach ignores interface_enabled")
    XCTAssertTrue(attached("Segment").first is UDPInterface)
  }

  func testAttachingAnAttachedInterfaceIsRefused() throws {
    try writeConfig([("Segment", true)])
    reticulum.transport.register(interface: Stub(name: "Segment"))
    XCTAssertEqual(reticulum.attachInterface(named: "Segment"), false)
    XCTAssertEqual(attached("Segment").count, 1)
  }

  func testAttachingAnInterfaceWithNoConfigEntryReturnsNil() throws {
    try writeConfig([("Segment", true)])
    XCTAssertNil(reticulum.attachInterface(named: "Elsewhere"))
    XCTAssertTrue(reticulum.transport.interfaces.isEmpty)
  }

  func testAttachingFromAConfigWithNoInterfacesSectionIsRefused() throws {
    try "[reticulum]\n  share_instance = No\n".write(
      to: dir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    XCTAssertEqual(reticulum.attachInterface(named: "Segment"), false, "Reticulum.py:783-797")
  }

  func testAttachingATypeThisPortDoesNotBuildIsRefused() throws {
    try """
    [interfaces]
      [[Pipe]]
        type = PipeInterface
        interface_enabled = True
        command = cat
    """.write(to: dir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    XCTAssertEqual(reticulum.attachInterface(named: "Pipe"), false, "nothing was attached")
  }

  func testAttachingWithAnUnreadableConfigReturnsNil() {
    XCTAssertNil(reticulum.attachInterface(named: "Segment"), "no config file")
  }

  // MARK: - Detach

  func testDetachStopsAndRemovesTheInterface() {
    let stub = Stub(name: "Peer")
    reticulum.transport.register(interface: stub)
    XCTAssertEqual(reticulum.detachInterface(named: "Peer"), true)
    XCTAssertTrue(stub.stopped)
    XCTAssertTrue(attached("Peer").isEmpty)
  }

  func testDetachingAnUnknownInterfaceReturnsNil() {
    XCTAssertNil(reticulum.detachInterface(named: "Nowhere"))
  }

  func testLocalAndI2PInterfacesCannotBeDetached() {
    let refused: [any Interface] = [
      LocalInterface(name: "Local", port: 37428),
      PosixTCPServer(name: "Shared", port: 4243),
      I2PInterface(
        name: "Tunnel", daemon: MockI2PDaemon(), dataDirectory: URL(fileURLWithPath: "/tmp")),
    ]
    for iface in refused {
      reticulum.transport.register(interface: iface)
      XCTAssertEqual(reticulum.detachInterface(named: iface.name), false, iface.name)
      XCTAssertEqual(attached(iface.name).count, 1, iface.name)
    }
  }

  func testDetachTakesTheInterfacesItSpawnedWithIt() {
    let server = TCPServerInterface(name: "Listener", port: 4965)
    let client = TCPServerClientInterface(
      name: "Client on Listener", parentServer: server, peerHost: "10.0.0.2", peerPort: 50000)
    reticulum.transport.register(interface: server)
    reticulum.transport.register(interface: client)
    XCTAssertEqual(reticulum.detachInterface(named: "Listener"), true)
    XCTAssertTrue(reticulum.transport.interfaces.isEmpty)
    XCTAssertFalse(client.isOnline)
  }

  // MARK: - Reload

  func testReloadReplacesTheInterfaceWithAFreshOne() throws {
    try writeConfig([("Segment", true)])
    XCTAssertEqual(reticulum.attachInterface(named: "Segment"), true)
    let before = try XCTUnwrap(attached("Segment").first)
    XCTAssertEqual(reticulum.reloadInterface(named: "Segment"), true)
    let after = try XCTUnwrap(attached("Segment").first)
    XCTAssertEqual(attached("Segment").count, 1)
    XCTAssertFalse(before === after)
  }

  func testReloadingAnUnknownInterfaceReturnsNil() throws {
    try writeConfig([("Segment", true)])
    XCTAssertNil(reticulum.reloadInterface(named: "Segment"))
  }

  func testReloadingAnInterfaceThatCannotBeDetachedFails() throws {
    reticulum.transport.register(interface: LocalInterface(name: "Local", port: 37428))
    XCTAssertEqual(reticulum.reloadInterface(named: "Local"), false)
  }

  // MARK: - enable_interface_management

  func testManagementCanBeTurnedOff() throws {
    try writeConfig([("Segment", true)])
    reticulum.transport.register(interface: Stub(name: "Peer"))
    Reticulum.storedInterfaceManagementEnabled = false
    XCTAssertEqual(reticulum.attachInterface(named: "Segment"), false)
    XCTAssertEqual(reticulum.detachInterface(named: "Peer"), false)
    XCTAssertEqual(reticulum.reloadInterface(named: "Peer"), false)
    XCTAssertEqual(reticulum.transport.interfaces.count, 1)

    XCTAssertEqual(
      reticulum.detachInterface(named: "Peer", internalForced: true), true,
      "the stack's own callers pass internal_forced")
  }

  func testTheOptionIsReadFromConfigAndDefaultsOn() {
    XCTAssertTrue(ReticulumConfig.parse("[reticulum]\n").reticulum.enableInterfaceManagement)
    let off = ReticulumConfig.parse(
      """
      [reticulum]
        enable_interface_management = no
      """)
    XCTAssertFalse(off.reticulum.enableInterfaceManagement)
    XCTAssertFalse(off.unrecognisedKeys.contains("reticulum.enable_interface_management"))
  }

  // MARK: - RPC

  private func rpc(_ pairs: [(String, MsgPack.Value)], server: RPCServer) throws -> MsgPack.Value {
    let call = MsgPack.encode(.map(pairs.map { (.string($0.0), $0.1) }))
    return try MsgPack.decode(server.respond(to: call))
  }

  func testTheSharedInstanceServesManageCalls() throws {
    try writeConfig([("Segment", false)])
    let server = RPCServer(port: 0, authkey: Data(count: 32))
    server.transport = reticulum.transport
    server.reticulum = reticulum

    XCTAssertEqual(
      try rpc(
        [("manage", .string("attach_interface")), ("name", .string("Segment"))], server: server),
      .bool(true))
    XCTAssertEqual(
      try rpc(
        [("manage", .string("reload_interface")), ("name", .string("Segment"))], server: server),
      .bool(true))
    XCTAssertEqual(
      try rpc(
        [("manage", .string("detach_interface")), ("name", .string("Segment"))], server: server),
      .bool(true))
    XCTAssertEqual(
      try rpc(
        [("manage", .string("detach_interface")), ("name", .string("Segment"))], server: server),
      .nil)
    XCTAssertTrue(reticulum.transport.interfaces.isEmpty)
  }

  func testManageCallsAreRefusedWhenManagementIsOff() throws {
    reticulum.transport.register(interface: Stub(name: "Peer"))
    Reticulum.storedInterfaceManagementEnabled = false
    let server = RPCServer(port: 0, authkey: Data(count: 32))
    server.transport = reticulum.transport
    server.reticulum = reticulum
    XCTAssertEqual(
      try rpc(
        [("manage", .string("detach_interface")), ("name", .string("Peer"))], server: server),
      .bool(false))
    XCTAssertEqual(reticulum.transport.interfaces.count, 1)
  }

  func testTheClientSendsManageCalls() throws {
    var authkey = Data(count: 32)
    authkey[0] = 7
    let reticulum = try XCTUnwrap(self.reticulum)
    reticulum.transport.register(interface: Stub(name: "Peer"))
    var lastError: Error?
    for _ in 0..<20 {
      let port = UInt16.random(in: 41_000...48_000)
      let server = RPCServer(port: port, authkey: authkey)
      server.transport = reticulum.transport
      server.reticulum = reticulum
      do {
        try server.start()
      } catch {
        lastError = error
        continue
      }
      defer { server.stop() }
      let deadline = Date().addingTimeInterval(2)
      while Date() < deadline, !RPCClient.isSharedInstanceRunning(port: port, timeout: 0.2) {
        usleep(20_000)
      }
      let client = RPCClient(host: "127.0.0.1", port: port, authkey: authkey, timeout: 3)
      XCTAssertEqual(try client.detachInterface(named: "Peer"), true)
      XCTAssertNil(try client.detachInterface(named: "Peer"))
      XCTAssertNil(try client.reloadInterface(named: "Peer"))
      try writeConfig([("Peer", false)])
      XCTAssertEqual(try client.attachInterface(named: "Peer"), true)
      return
    }
    throw try XCTUnwrap(lastError, "could not bind any loopback port")
  }
}
