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

/// A destination proves an inbound `DATA` packet only once it decrypts:
/// `Transport.py:2599-2600` proves when `Destination.receive` returns `True`, which it does
/// only for a packet whose plaintext isn't `None` (`Destination.py:419-429`).
final class InboundPacketProofTests: XCTestCase {

  final class RecordingInterface: Interface {
    var name = "recording"
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private(set) var sent: [Packet] = []
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(try Packet.unpack(try packet.pack())) }
  }

  private var transport: Transport!
  private var interface: RecordingInterface!
  private var destination: Destination!
  private var received: [Data] = []

  override func setUpWithError() throws {
    transport = Transport()
    interface = RecordingInterface()
    transport.register(interface: interface)
    let identity = Identity()
    destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "spec", aspects: ["proof"])
    destination.setProofStrategy(.proveAll)
    destination.setPacketCallback { [unowned self] plaintext, _ in received.append(plaintext) }
    transport.ownerIdentity = identity
    transport.register(destination: destination)
  }

  private func deliver(_ data: Data) throws {
    let packet = Packet(
      destinationType: .single, packetType: .data, destinationHash: destination.hash, data: data)
    let inbound = try Packet.unpack(try packet.pack())
    try XCTUnwrap(interface.inboundHandler)(inbound, interface)
  }

  private var proofsSent: Int { interface.sent.filter { $0.packetType == .proof }.count }

  func testADecryptedPacketIsProven() throws {
    try deliver(try destination.encrypt(Data("plaintext".utf8)))

    XCTAssertEqual(received, [Data("plaintext".utf8)])
    XCTAssertEqual(proofsSent, 1)
  }

  func testAPacketThatDoesNotDecryptIsNotProven() throws {
    try deliver(Data(repeating: 0xA5, count: 96))

    XCTAssertEqual(received, [])
    XCTAssertEqual(proofsSent, 0)
  }

  func testAPacketThatDoesNotDecryptIsNotProvenWithoutAPacketCallback() throws {
    destination.onPacketReceived = nil

    try deliver(Data(repeating: 0xA5, count: 96))

    XCTAssertEqual(proofsSent, 0)
  }
}
