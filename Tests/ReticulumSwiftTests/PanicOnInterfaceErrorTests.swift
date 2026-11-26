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

/// `panic_on_interface_error = yes` exits the process when an interface gives up.
///
/// Python sets `Reticulum.panic_on_interface_error` from the config (`Reticulum.py:692-694`), and
/// each interface calls `RNS.panic()`, which is `os._exit(255)` (`__init__.py:355`), where it
/// gives up for good, for example `SerialInterface.py:207` and `TCPInterface.py:453`.
final class PanicOnInterfaceErrorTests: XCTestCase {

  private var savedPanic: (() -> Void)!
  private var panics = 0
  private let panicLock = NSLock()

  override func setUp() {
    super.setUp()
    savedPanic = Reticulum.panic
    Reticulum.panic = { [unowned self] in panicLock.withLock { panics += 1 } }
  }

  override func tearDown() {
    Reticulum.panic = savedPanic
    Reticulum.panicOnInterfaceError = false
    super.tearDown()
  }

  private var panicCount: Int { panicLock.withLock { panics } }

  func testTheConfigTurnsThePanicOn() {
    let reticulum = Reticulum(
      configuration: .init(
        storagePath: FileManager.default.temporaryDirectory
          .appendingPathComponent("panic-\(UUID().uuidString)/storage"),
        shareInstance: false))
    reticulum.applyConfig(ReticulumConfig.parse("[reticulum]\n  panic_on_interface_error = Yes\n"))
    XCTAssertTrue(Reticulum.panicOnInterfaceError)
    reticulum.applyConfig(ReticulumConfig.parse("[reticulum]\n"))
    XCTAssertFalse(Reticulum.panicOnInterfaceError)
  }

  func testALostSerialPortPanicsOnlyWhenConfigured() throws {
    let port = MockSerialPort()
    let iface = SerialInterface(name: "S", port: "/dev/x", transport: port)
    try iface.start()
    defer { iface.stop() }

    port.onTransportError?(SerialInterfaceError.portOpenFailed("/dev/x"))
    XCTAssertEqual(panicCount, 0, "the flag is off")

    try iface.start()
    Reticulum.panicOnInterfaceError = true
    port.onTransportError?(SerialInterfaceError.portOpenFailed("/dev/x"))
    XCTAssertEqual(panicCount, 1)
  }
}
