//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import CryptoKit
import XCTest

@testable import ReticulumSwift

/// A link request reaches a local destination only when it's addressed to nobody or to this
/// node: `packet.transport_id == None or packet.transport_id == Transport.identity.hash`
/// (`Transport.py:2541`).
///
/// A shared-instance client's packet filter passes everything (`Transport.py:1627`), and its
/// transport identity is ephemeral (`Transport.py:332-335`). A link request still in transport
/// to the instance reaches the check with the instance's transport ID.
final class LocalLinkRequestTransportIDTests: XCTestCase {

  private final class RecordingInterface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private(set) var sent: [Packet] = []
    init(name: String) { self.name = name }
    func start() throws {}
    func stop() {}
    func send(_ packet: Packet) throws { sent.append(packet) }
  }

  // `register(interface:)` captures the transport weakly, so the test holds it.
  private var client: Transport!
  private var toInstance: RecordingInterface!
  private var destination: Destination!

  /// A client of a shared instance, set up as `Reticulum` sets one up with transport off.
  override func setUpWithError() throws {
    client = Transport()
    client.isConnectedToSharedInstance = true
    let ephemeral = Identity()
    client.transportIdentity = ephemeral
    client.transportInstanceID = ephemeral.hash
    toInstance = RecordingInterface(name: "shared-instance")
    client.register(interface: toInstance)
    destination = try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "test", aspects: ["local"])
    client.register(destination: destination)
  }

  override func tearDown() {
    client = nil
    toInstance = nil
    destination = nil
  }

  private func receiveLinkRequest(transportID: Data?) throws {
    let keys =
      Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
      + Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    let request: Packet
    if let transportID {
      request = Packet(
        headerType: .type2, transportType: .transport, destinationType: .single,
        packetType: .linkRequest, transportID: transportID,
        destinationHash: destination.hash, data: keys)
    } else {
      request = Packet(
        destinationType: .single, packetType: .linkRequest,
        destinationHash: destination.hash, data: keys)
    }
    toInstance.inboundHandler?(try Packet.unpack(request.pack()), toInstance)
  }

  private var linkProofs: [Packet] {
    toInstance.sent.filter { $0.packetType == .proof && $0.context == .lrproof }
  }

  func testAClientDropsALinkRequestInTransportToItsInstance() throws {
    let instanceID = Identity().hash
    XCTAssertNotEqual(instanceID, client.transportInstanceID)

    try receiveLinkRequest(transportID: instanceID)

    XCTAssertEqual(
      linkProofs.count, 0,
      "`if packet.transport_id == None or packet.transport_id == Transport.identity.hash`"
        + " (Transport.py:2541)")
  }

  func testAClientAnswersALinkRequestAddressedToNobody() throws {
    try receiveLinkRequest(transportID: nil)

    XCTAssertEqual(linkProofs.count, 1)
  }

  func testAClientAnswersALinkRequestInTransportToItself() throws {
    try receiveLinkRequest(transportID: client.transportInstanceID)

    XCTAssertEqual(linkProofs.count, 1)
  }
}
