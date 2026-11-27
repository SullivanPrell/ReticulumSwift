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

/// RNS 1.3.7: a non-transport node runs behind a fresh ephemeral transport
/// identity for privacy, while keeping its persistent identity as
/// `internal_identity()` (used for example, for the RPC auth key).
///
/// The
/// `static_transport_identity` option restores the old stable-identity behavior.
final class RNS137EphemeralTransportIdentityTests: XCTestCase {
  var tmp: URL!

  override func setUpWithError() throws {
    tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("rns137-eti-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tmp)
  }

  private func makeReticulum(storage: URL, configText: String) throws -> Reticulum {
    let cfgPath = tmp.appendingPathComponent("config-\(UUID().uuidString)")
    try configText.write(to: cfgPath, atomically: true, encoding: .utf8)
    let cfg = Reticulum.Configuration(
      storagePath: storage, configPath: cfgPath, shareInstance: false)
    return Reticulum(configuration: cfg)
  }

  func testNonTransportNodeUsesEphemeralTransportIdentity() throws {
    let storage = tmp.appendingPathComponent("storage")
    let r = try makeReticulum(
      storage: storage, configText: "[reticulum]\nenable_transport = False\n")
    try r.start()
    defer { r.stop() }

    let internalHash = r.transport.internalIdentity?.hash
    let transportHash = r.transport.transportIdentity?.hash
    XCTAssertNotNil(internalHash)
    XCTAssertNotNil(transportHash)
    XCTAssertNotEqual(
      internalHash, transportHash,
      "non-transport node must use an ephemeral transport identity distinct from its persistent one"
    )
    XCTAssertEqual(
      r.transport.transportInstanceID, transportHash,
      "transportInstanceID must track the (ephemeral) transport identity")
  }

  func testStaticTransportIdentityUsesPersistentIdentity() throws {
    let storage = tmp.appendingPathComponent("storage")
    let r = try makeReticulum(
      storage: storage,
      configText: "[reticulum]\nenable_transport = False\nstatic_transport_identity = True\n")
    try r.start()
    defer { r.stop() }

    XCTAssertEqual(
      r.transport.internalIdentity?.hash, r.transport.transportIdentity?.hash,
      "static_transport_identity must keep the transport identity equal to the persistent one")
  }

  func testTransportEnabledNodeUsesPersistentIdentity() throws {
    let storage = tmp.appendingPathComponent("storage")
    let r = try makeReticulum(
      storage: storage, configText: "[reticulum]\nenable_transport = True\n")
    try r.start()
    defer { r.stop() }

    XCTAssertEqual(
      r.transport.internalIdentity?.hash, r.transport.transportIdentity?.hash,
      "a transport-enabled node keeps a stable transport identity")
  }

  func testEphemeralChangesAcrossRunsButInternalPersists() throws {
    let storage = tmp.appendingPathComponent("storage")
    let text = "[reticulum]\nenable_transport = False\n"

    func run() throws -> (internalHash: Data, transportHash: Data) {
      let r = try makeReticulum(storage: storage, configText: text)
      try r.start()
      defer { r.stop() }
      return (r.transport.internalIdentity!.hash, r.transport.transportIdentity!.hash)
    }

    let a = try run()
    let b = try run()
    XCTAssertEqual(
      a.internalHash, b.internalHash,
      "persistent internal identity must be stable across runs")
    XCTAssertNotEqual(
      a.transportHash, b.transportHash,
      "ephemeral transport identity must be regenerated each run")
  }

  // MARK: - RNS 606a1691: a discoverable interface no longer makes the identity static

  /// The warning at `Reticulum.py:1195-1203`, from upstream `606a1691` (in no released tag).
  ///
  /// The interface's `discoverable` is turned off, so the ephemeral identity stays unlinkable.
  private let discoverableWarning = [
    "",
    "The interface \"Discoverable\" was configured discoverable, but this instance has transport disabled",
    "and is using an ephemeral transport identity. To make interfaces discoverable for non-transport",
    "instances, you will have explicitly enable using static transport identity in the config file,",
    "by adding \"static_transport_identity = yes\" to the [reticulum] section.",
    "",
  ]

  private func discoverableConfig(
    transport: Bool = false, staticIdentity: Bool = false, enabled: Bool = true
  ) throws -> String {
    """
    [reticulum]
    enable_transport = \(transport ? "True" : "False")
    static_transport_identity = \(staticIdentity ? "True" : "False")

    [interfaces]
      [[Discoverable]]
        type = TCPServerInterface
        interface_enabled = \(enabled ? "Yes" : "No")
        listen_ip = 127.0.0.1
        listen_port = \(try freeLoopbackPort())
        discoverable = Yes
    """
  }

  private struct Node {
    var persistent: Bool
    var discoverable: Bool
    var discoveryEnabled: Bool
    var warnings: [String]
  }

  /// Starts a node, then builds its one interface block the way `rnsd` does after `start()`.
  private func startNode(_ configText: String) throws -> Node {
    var warnings: [String] = []
    let saved = Reticulum.logHandler
    let savedLatch = Reticulum.storedDiscoveryEnabled
    Reticulum.storedDiscoveryEnabled = false
    Reticulum.logHandler = { message, level in if level == .warning { warnings.append(message) } }
    defer {
      Reticulum.logHandler = saved
      Reticulum.storedDiscoveryEnabled = savedLatch
    }
    let r = try makeReticulum(
      storage: tmp.appendingPathComponent("storage"), configText: configText)
    try r.start()
    defer { r.stop() }
    let iface = try XCTUnwrap(try r.synthesizeInterface(XCTUnwrap(r.config?.interfaces.first)))
    defer { iface.stop() }
    return Node(
      persistent: r.transport.internalIdentity?.hash == r.transport.transportIdentity?.hash,
      discoverable: iface.discoverable, discoveryEnabled: Reticulum.discoveryEnabled(),
      warnings: warnings)
  }

  private func warned(_ node: Node) -> Bool {
    node.warnings.contains { $0.contains("was configured discoverable") }
  }

  func testADiscoverableInterfaceOnANonTransportNodeIsTurnedOff() throws {
    let node = try startNode(discoverableConfig())
    XCTAssertFalse(node.persistent, "the transport identity stays ephemeral")
    XCTAssertFalse(node.discoverable)
    XCTAssertFalse(node.discoveryEnabled, "nothing latches the announcer on")
    XCTAssertEqual(node.warnings, discoverableWarning)
  }

  func testATransportNodeKeepsADiscoverableInterface() throws {
    let node = try startNode(discoverableConfig(transport: true))
    XCTAssertTrue(node.persistent)
    XCTAssertTrue(node.discoverable)
    XCTAssertTrue(node.discoveryEnabled)
    XCTAssertFalse(warned(node))
  }

  func testAConfiguredStaticIdentityKeepsADiscoverableInterface() throws {
    let node = try startNode(discoverableConfig(staticIdentity: true))
    XCTAssertTrue(node.persistent)
    XCTAssertTrue(node.discoverable)
    XCTAssertTrue(node.discoveryEnabled)
    XCTAssertFalse(warned(node))
  }

  /// The old pre-scan promoted the identity for a disabled block too; nothing does now.
  func testADisabledDiscoverableInterfaceLeavesTheIdentityEphemeral() throws {
    let storage = tmp.appendingPathComponent("storage")
    let r = try makeReticulum(storage: storage, configText: discoverableConfig(enabled: false))
    try r.start()
    defer { r.stop() }
    XCTAssertNotEqual(r.transport.internalIdentity?.hash, r.transport.transportIdentity?.hash)
  }
}
