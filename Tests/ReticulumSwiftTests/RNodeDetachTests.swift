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

/// What an RNode is told as it's detached, as RNS 1.5.5's `detach` tells it.
///
/// `RNodeInterface.detach` turns off the external framebuffer where the device has a display,
/// turns the radio off and sends the host-left command, then closes the port
/// (`RNodeInterface.py:1190-1209`). `RNodeMultiInterface.detach` does the same with every
/// sub-interface's radio (`RNodeMultiInterface.py:911-919`). A device is taken to have a
/// display once it's detected on an ESP32 or NRF52 platform (`RNodeInterface.py:459`,
/// `RNodeMultiInterface.py:347-349`).
final class RNodeDetachTests: XCTestCase {

  private struct WriteFailed: Error {}

  /// A transport that records what it's sent, and fails every write once told to.
  private final class RecordingTransport: RNodeTransport {
    var onTransportError: ((Error) -> Void)?
    var byteHandler: ((Data) -> Void)?
    var written: [Data] = []
    var isOpen = true
    var failWrites = false

    func open() throws { isOpen = true }
    func close() { isOpen = false }
    func write(_ data: Data) throws {
      if failWrites { throw WriteFailed() }
      written.append(data)
    }
  }

  private static let framebufferOff = Data([KISS.fend, KISS.cmdFbExt, 0x00, KISS.fend])
  private static let radioOff = Data([KISS.fend, KISS.cmdRadioState, 0x00, KISS.fend])
  private static let leave = Data([KISS.fend, KISS.cmdLeave, 0xFF, KISS.fend])

  /// The radio behind sub-interface `index`, turned off.
  private static func radioOff(selecting index: UInt8) -> Data {
    Data([KISS.fend, KISS.cmdSelInt, index, KISS.fend]) + radioOff
  }

  /// A detected RNode on `platform`, over `transport`.
  private func radio(on platform: UInt8?, detected: Bool = true, over transport: RecordingTransport)
    -> RNodeInterface
  {
    let iface = RNodeInterface(name: "lora", transport: transport)
    iface.detected = detected
    iface.platform = platform
    return iface
  }

  func testStopTurnsTheRadioOffAndLeavesBeforeClosing() {
    let transport = RecordingTransport()
    let iface = radio(on: KISS.platformAVR, over: transport)
    iface.stop()
    XCTAssertEqual(transport.written, [Self.radioOff, Self.leave])
    XCTAssertEqual(iface.state, KISS.radioStateOff)
    XCTAssertFalse(transport.isOpen)
    XCTAssertFalse(iface.isOnline)
  }

  func testStopTurnsTheFramebufferOffWhereTheDeviceHasADisplay() {
    for platform in [KISS.platformESP32, KISS.platformNRF52] {
      let transport = RecordingTransport()
      radio(on: platform, over: transport).stop()
      XCTAssertEqual(transport.written, [Self.framebufferOff, Self.radioOff, Self.leave])
    }
  }

  /// `display` is set only once the device answers detect.
  func testAnUndetectedDeviceHasNoDisplayToTurnOff() {
    let transport = RecordingTransport()
    radio(on: KISS.platformESP32, detected: false, over: transport).stop()
    XCTAssertEqual(transport.written, [Self.radioOff, Self.leave])
  }

  /// Python logs the failure, skips the rest of the sequence and still closes the port.
  func testAFailedWriteStillClosesThePort() {
    let transport = RecordingTransport()
    transport.failWrites = true
    let iface = radio(on: KISS.platformESP32, over: transport)
    iface.stop()
    XCTAssertEqual(transport.written, [])
    XCTAssertFalse(transport.isOpen)
    XCTAssertFalse(iface.isOnline)
  }

  func testStoppingAMultiInterfaceTurnsEveryRadioOffAndLeavesBeforeClosing() throws {
    let transport = RecordingTransport()
    let subInterfaces = [0, 1].map {
      RNodeSubInterface(
        name: "ch\($0)", index: $0, interfaceType: "SX127X",
        frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
    }
    let multi = try RNodeMultiInterface(
      name: "multi", transport: transport, subInterfaces: subInterfaces)
    multi.detected = true
    multi.platform = KISS.platformNRF52
    multi.stop()
    XCTAssertEqual(
      transport.written,
      [Self.framebufferOff, Self.radioOff(selecting: 0), Self.radioOff(selecting: 1), Self.leave])
    XCTAssertFalse(transport.isOpen)
    XCTAssertFalse(multi.isOnline)
  }

  func testAMultiInterfaceWithoutADisplayLeavesTheFramebufferAlone() throws {
    let transport = RecordingTransport()
    let multi = try RNodeMultiInterface(
      name: "multi", transport: transport,
      subInterfaces: [
        RNodeSubInterface(
          name: "ch0", index: 0, interfaceType: "SX127X",
          frequency: 868_000_000, bandwidth: 125_000, txPower: 14, sf: 7, cr: 5)
      ])
    multi.detected = true
    multi.platform = KISS.platformAVR
    multi.stop()
    XCTAssertEqual(transport.written, [Self.radioOff(selecting: 0), Self.leave])
  }
}
