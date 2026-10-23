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

/// An interface block that can't be built fails the way `_synthesize_interface` fails it: two
/// `LOG_ERROR` lines naming the interface and the exception, then `RNS.panic()`
/// (`Reticulum.py:1211-1215`, RNS 1.5.5).
final class InterfaceCreationFailureTests: XCTestCase {

  private var tempDir: URL!
  private var stack: Reticulum?
  private var savedLogHandler: ((String, Reticulum.LogLevel) -> Void)?
  private var logged: [(String, Reticulum.LogLevel)] = []

  override func setUp() {
    super.setUp()
    tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("rns_ifacefail_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    savedLogHandler = Reticulum.logHandler
    Reticulum.logHandler = { [unowned self] message, level in logged.append((message, level)) }
  }

  override func tearDown() {
    stack?.stop()
    stack = nil
    Reticulum.logHandler = savedLogHandler
    try? FileManager.default.removeItem(at: tempDir)
    super.tearDown()
  }

  private func synthesize(_ block: String) throws {
    let cfg = ReticulumConfig.parse(
      """
      [reticulum]
        enable_transport = no
        share_instance = no

      [interfaces]
      \(block)
      """)
    let stack = Reticulum(configuration: .init(storagePath: tempDir, shareInstance: false))
    self.stack = stack
    try stack.synthesizeInterfaces(from: cfg)
  }

  /// On anything but Linux or Android, `BackboneInterface.__init__` raises (`BackboneInterface.py:127-128`),
  /// and a block with no `target_host` builds that class (`Reticulum.py:1124-1126`).
  func testABackboneListenerBlockFailsAsItDoesOffLinux() {
    XCTAssertThrowsError(
      try synthesize(
        """
          [[Backbone Listener]]
            type = BackboneInterface
            enabled = yes
            listen_on = 0.0.0.0
            port = 4242
        """)
    ) { error in
      XCTAssertEqual(
        error.localizedDescription,
        "BackboneInterface is only supported on Linux-based operating systems")
    }
  }

  func testAFailedBlockLogsPythonsTwoLinesWithItsName() {
    XCTAssertThrowsError(
      try synthesize(
        """
          [[Backbone Listener]]
            type = BackboneInterface
            enabled = yes
            port = 4242
        """))

    let errors = logged.filter { $0.1 == .error }.map(\.0)
    XCTAssertEqual(
      errors,
      [
        "The interface \"Backbone Listener\" could not be created. Check your configuration file "
          + "for errors!",
        "The contained exception was: BackboneInterface is only supported on Linux-based "
          + "operating systems",
      ])
  }

  /// A dialing block still builds, so only the listener form is refused.
  func testABackboneClientBlockStillBuilds() throws {
    try synthesize(
      """
        [[Backbone Client]]
          type = BackboneInterface
          enabled = yes
          remote = 127.0.0.1
          target_port = 1
      """)
    XCTAssertEqual(stack?.transport.interfaces.map(\.name), ["Backbone Client"])
  }
}
