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

/// Tests for Identity.validate_announce() static method.
///
/// Mirrors Python's `RNS.Identity.validate_announce(packet)`.
final class IdentityValidateAnnounceTests: XCTestCase {

  func testValidateAnnounceTrueForValidPacket() throws {
    let id = Identity()
    let dest = try Destination(
      identity: id, direction: .in, kind: .single,
      appName: "test", aspects: ["valid"])
    let packet = try Announce.make(for: dest)

    // Python: Identity.validate_announce(packet) → True if valid
    let result = Identity.validateAnnounce(packet)
    XCTAssertTrue(result, "valid announce should pass validation")
  }

  func testValidateAnnounceReturnsFalseForInvalidPacket() throws {
    let id = Identity()
    let dest = try Destination(
      identity: id, direction: .in, kind: .single,
      appName: "test", aspects: ["invalid"])
    var packet = try Announce.make(for: dest)
    // Corrupt the signature
    packet.data[packet.data.index(before: packet.data.endIndex)] ^= 0xFF
    let result = Identity.validateAnnounce(packet)
    XCTAssertFalse(result, "corrupted announce should fail validation")
  }

  func testValidateAnnounceReturnsFalseForNonAnnounce() {
    let packet = Packet(
      destinationType: .single,
      packetType: .data,
      destinationHash: Data(repeating: 0xAA, count: 16),
      data: Data("not an announce".utf8)
    )
    let result = Identity.validateAnnounce(packet)
    XCTAssertFalse(result, "non-announce packet should fail validation")
  }

  /// Python's `validate_announce` hangs its whole body off
  /// `if packet.packet_type == RNS.Packet.ANNOUNCE` (`Identity.py:512`) and
  /// falls through to `return False` for anything else.
  ///
  /// The signature-only
  /// path used to carry its own hand-rolled parse with no such gate, so a
  /// DATA packet whose payload happened to be a well-formed announce body
  /// validated as an announce.
  func testSignatureOnlyValidationRejectsANonAnnouncePacketType() throws {
    let id = Identity()
    let dest = try Destination(
      identity: id, direction: .in, kind: .single,
      appName: "test", aspects: ["typegate"])
    var packet = try Announce.make(for: dest)
    packet.packetType = .data

    XCTAssertFalse(
      Identity.validateAnnounce(packet, onlyValidateSignature: true),
      "a DATA packet is not an announce, however announce-shaped its payload"
    )
  }

  /// A regression guard on the shared parser, not a fix for a live bug: the
  /// signature-only path and `Announce.validate` now read the announce layout
  /// through one function, so this pins the ratchet field for both.
  ///
  /// An
  /// announce carries a ratchet exactly when it sets the context flag
  /// (`Identity.py:522-527`), with no length test of its own.
  func testSignatureOnlyValidationAcceptsAnAnnounceCarryingARatchet() throws {
    let id = Identity()
    let dest = try Destination(
      identity: id, direction: .in, kind: .single,
      appName: "test", aspects: ["ratchet"])
    let packet = try Announce.make(for: dest, ratchet: Data(repeating: 0x5A, count: 32))
    XCTAssertEqual(packet.contextFlag, .set, "fixture must actually carry a ratchet")

    XCTAssertTrue(Identity.validateAnnounce(packet, onlyValidateSignature: true))
  }

  func testValidateAnnounceOnlyValidateSignature() throws {
    let id = Identity()
    let dest = try Destination(
      identity: id, direction: .in, kind: .single,
      appName: "test", aspects: ["sigonly"])
    let packet = try Announce.make(for: dest)

    // only_validate_signature=True: skip destination hash check
    let result = Identity.validateAnnounce(packet, onlyValidateSignature: true)
    XCTAssertTrue(result)
  }
}
