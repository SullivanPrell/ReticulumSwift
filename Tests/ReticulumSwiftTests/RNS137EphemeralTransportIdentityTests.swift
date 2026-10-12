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

  // MARK: - RNS 1.5.6: a discoverable interface keeps the identity static

  /// `Reticulum.py:993`.
  private let discoverableWarning =
    "Discoverable interface was configured, enabling static transport identity on non-transport instance"

  private func discoverableConfig(
    transport: Bool = false, staticIdentity: Bool = false, enabled: Bool = true,
    discoverable: Bool = true
  ) -> String {
    """
    [reticulum]
    enable_transport = \(transport ? "True" : "False")
    static_transport_identity = \(staticIdentity ? "True" : "False")

    [interfaces]
      [[Discoverable]]
        type = TCPServerInterface
        interface_enabled = \(enabled ? "Yes" : "No")
        listen_ip = 127.0.0.1
        listen_port = 4242
        discoverable = \(discoverable ? "Yes" : "No")
    """
  }

  /// Whether the node ran under its persistent identity, and the warnings `start()` logged.
  private func startNode(_ configText: String) throws -> (persistent: Bool, warnings: [String]) {
    var warnings: [String] = []
    let saved = Reticulum.logHandler
    Reticulum.logHandler = { message, level in if level == .warning { warnings.append(message) } }
    defer { Reticulum.logHandler = saved }
    let r = try makeReticulum(
      storage: tmp.appendingPathComponent("storage"), configText: configText)
    try r.start()
    defer { r.stop() }
    return (r.transport.internalIdentity?.hash == r.transport.transportIdentity?.hash, warnings)
  }

  func testADiscoverableInterfaceKeepsANonTransportIdentityStatic() throws {
    let node = try startNode(discoverableConfig())
    XCTAssertTrue(node.persistent, "Reticulum.py:992-994 sets static_transport_identity")
    XCTAssertEqual(node.warnings.filter { $0 == discoverableWarning }.count, 1)
  }

  func testAnInterfaceThatIsNotDiscoverableLeavesTheIdentityEphemeral() throws {
    let node = try startNode(discoverableConfig(discoverable: false))
    XCTAssertFalse(node.persistent)
    XCTAssertFalse(node.warnings.contains(discoverableWarning))
  }

  func testATransportNodeWithADiscoverableInterfaceLogsNoWarning() throws {
    let node = try startNode(discoverableConfig(transport: true))
    XCTAssertTrue(node.persistent)
    XCTAssertFalse(node.warnings.contains(discoverableWarning))
  }

  func testAConfiguredStaticIdentityWithADiscoverableInterfaceLogsNoWarning() throws {
    let node = try startNode(discoverableConfig(staticIdentity: true))
    XCTAssertTrue(node.persistent)
    XCTAssertFalse(node.warnings.contains(discoverableWarning))
  }

  /// The `discoverable` block (`Reticulum.py:988-994`) runs before the enabled check (`:1108`).
  func testADisabledDiscoverableInterfaceStillKeepsTheIdentityStatic() throws {
    let node = try startNode(discoverableConfig(enabled: false))
    XCTAssertTrue(node.persistent)
    XCTAssertEqual(node.warnings.filter { $0 == discoverableWarning }.count, 1)
  }
}
