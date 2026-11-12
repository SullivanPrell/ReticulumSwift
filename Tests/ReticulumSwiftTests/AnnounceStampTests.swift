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

/// The 18-byte stamp trailer RNS 1.6.0 appends to announce app data
/// (`Destination.py:348-357`), and how a receiver validates and strips it
/// (`Identity.py:840-889`).
///
/// The two announces come from `scripts/capture-stamp-vectors.py` against RNS 1.6.0: identity
/// `bytes(range(64))`, `rs160.stamped`, link cost 7.25, stamped at value 8.01953125.
final class AnnounceStampTests: XCTestCase {

  static let withAppData = Data(
    hex:
      "0100cb20bb86f3256654f6ca46b3139b1187008f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7530513f75d8be3b9751c4af4918ed1006af52f4a6d9d4e97183039b3dc8801b0385aba2ca3110228221367cbfda511c51ea66557f582d53dcf7f2f7c9190ea03809e0d0e193f19293c3846e75ec2faf33a55bd0f68656c6c6fc100ef945fcf52863d090fdcad0c5a624007"
  )!
  static let withoutAppData = Data(
    hex:
      "0100cb20bb86f3256654f6ca46b3139b1187008f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f29acbae141bccaf0b22e1a94d34d0bc7361e526d0bfe12c89794bc9322966dd7530513f75d8be3b9751c354f1e7a03006af52f4ae1e72f3824a59373fff7dd35019ae05890a12c0ed65c3a198b7014969dc6617101b15bbd046534385586d8d46303c1ad3cafd0cd46d9a1d34596e5cd7993ee04c100ef945fcf52863d090fdcad0c5a624007"
  )!
  static let stamp = Data(hex: "ef945fcf52863d090fdcad0c5a62")!
  static let trailer = Data(hex: "c100ef945fcf52863d090fdcad0c5a624007")!

  func testAValidStampIsReadAndStripped() throws {
    let decoded = try Announce.validate(Packet.unpack(Self.withAppData), requiredValue: 8)
    XCTAssertEqual(decoded.appData, Data("hello".utf8))
    XCTAssertEqual(decoded.stamp, Self.stamp)
    XCTAssertEqual(decoded.stampValue, 8.01953125)
    XCTAssertEqual(decoded.lrCost, 7.25)
    XCTAssertEqual(decoded.identity.appData, Data("hello".utf8))

    let bare = try Announce.validate(Packet.unpack(Self.withoutAppData), requiredValue: 8)
    XCTAssertNil(bare.appData, "a trailer alone strips to no app data")
    XCTAssertEqual(bare.lrCost, 7.25)
  }

  /// Below the required value the stamp is still read and valued, but the trailer stays on
  /// the app data and no link cost is taken from it (`Identity.py:865-870`, `915-918`).
  func testAnInsufficientStampStaysOnTheAppData() throws {
    let decoded = try Announce.validate(Packet.unpack(Self.withAppData))
    XCTAssertEqual(decoded.appData, Data("hello".utf8) + Self.trailer)
    XCTAssertEqual(decoded.stamp, Self.stamp)
    XCTAssertEqual(decoded.stampValue, 8.01953125)
    XCTAssertNil(decoded.lrCost)
  }

  func testDisabledStampsLeaveTheTrailerUnread() throws {
    var stamps = StampSettings()
    stamps.enabled = false
    let decoded = try Announce.validate(
      Packet.unpack(Self.withAppData), stamps: stamps, requiredValue: 8)
    XCTAssertEqual(decoded.appData, Data("hello".utf8) + Self.trailer)
    XCTAssertNil(decoded.stamp)
    XCTAssertNil(decoded.stampValue)
  }

  func testEnforcementRejectsMissingAndInsufficientStamps() throws {
    var stamps = StampSettings()
    stamps.enforced = true
    XCTAssertThrowsError(try Announce.validate(Packet.unpack(Self.withAppData), stamps: stamps)) {
      XCTAssertEqual($0 as? Announce.AnnounceError, .invalidStamp)
    }
    XCTAssertNoThrow(
      try Announce.validate(Packet.unpack(Self.withAppData), stamps: stamps, requiredValue: 8))

    let unstamped = try Announce.make(for: destination(), appData: Data("plain".utf8))
    XCTAssertThrowsError(try Announce.validate(unstamped, stamps: stamps, requiredValue: 0)) {
      XCTAssertEqual($0 as? Announce.AnnounceError, .noStamp)
    }
  }

  /// A trailer whose reserved bit is set, or whose marker is wrong, isn't a stamp at all
  /// (`Identity.py:852-857`), so it stays app data even under enforcement's "no stamp".
  func testAnUnknownTrailerFormatIsNotAStamp() throws {
    var reserved = Self.trailer
    reserved[reserved.count - 1] |= 0x80
    for appData in [reserved, Data([0xC0]) + Self.trailer.dropFirst()] {
      let packet = try Announce.make(for: destination(), appData: appData)
      let decoded = try Announce.validate(packet, requiredValue: 0)
      XCTAssertEqual(decoded.appData, appData)
      XCTAssertNil(decoded.stamp)
    }
  }

  // MARK: - Emission

  func testTrailerLayoutMatchesPython() throws {
    let identity = try Identity(privateKeyBytes: Data(0..<64))
    let dest = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "rs160", aspects: ["stamped"])
    dest.setLinkCost(7.25)
    dest.stamp = Self.stamp
    dest.stampValue = 8.01953125
    XCTAssertEqual(dest.stampTrailer(StampSettings()), Self.trailer)
    XCTAssertEqual(
      dest.stampMaterial, dest.hash + identity.publicKeyBytes + dest.nameHash)
  }

  func testStampedDestinationAnnouncesAValidStamp() throws {
    var stamps = StampSettings()
    stamps.stampDestinations = true
    stamps.destinationValue = 6
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    let dest = try destination()
    dest.setLinkCost(3.5)
    XCTAssertTrue(dest.awaitStamp(stamps, directory: dir))
    let packet = try Announce.make(
      for: dest, appData: Data("app".utf8), stampTrailer: dest.stampTrailer(stamps))
    let decoded = try Announce.validate(packet, requiredValue: 6)
    XCTAssertEqual(decoded.appData, Data("app".utf8))
    XCTAssertEqual(decoded.lrCost, 3.5)
    XCTAssertGreaterThanOrEqual(try XCTUnwrap(decoded.stampValue), 6)

    // The stamp persisted, so a fresh destination object loads it instead of grinding.
    let again = try Destination(
      identity: dest.identity!, direction: .in, kind: .single, appName: "rs160",
      aspects: ["emitted"])
    XCTAssertTrue(again.awaitStamp(stamps, directory: dir))
    XCTAssertEqual(again.stamp, dest.stamp)
  }

  func testValueAndLinkCostClamp() throws {
    let dest = try destination()
    var stamps = StampSettings()
    stamps.lrCost = 12.5
    XCTAssertEqual(dest.getLinkCost(stamps), 12.5, "unset falls back to LR_COST")
    dest.setLinkCost(90)
    XCTAssertEqual(dest.getLinkCost(stamps), 40, "capped at LINK_COST_CAP")
    dest.setLinkCost(-1)
    XCTAssertEqual(dest.getLinkCost(stamps), 0)
    dest.setValue(3)
    XCTAssertEqual(dest.targetValue(stamps), 25, "never below DESTINATION_VALUE")
    dest.setValue(200)
    XCTAssertEqual(dest.targetValue(stamps), 100, "capped at STAMP_COST_CAP")
  }

  // MARK: - Identity value

  func testIdentityValueMatchesPython() throws {
    XCTAssertEqual(try Identity(privateKeyBytes: Data(0..<64)).getValue(), 3.890625)
    let stamped = try XCTUnwrap(Identity(value: 5))
    XCTAssertGreaterThanOrEqual(stamped.getValue(), 5)
    XCTAssertTrue(stamped.hasPrivateKey)
  }

  // MARK: - Transport

  func testTransportRemembersStampValueAndLinkCost() throws {
    let t = Transport()
    t.stamps.destinationCost = 8
    let iface = UDPInterface(name: "in", listenPort: 4392, forwardPort: 4393)
    t.register(interface: iface)
    defer { t.deregister(interface: iface) }
    let packet = try Packet.unpack(Self.withAppData)

    t.handleIncoming(packet: packet, from: iface)

    XCTAssertEqual(t.recallAppData(forDestination: packet.destinationHash), Data("hello".utf8))
    XCTAssertEqual(t.recallStampValue(forDestination: packet.destinationHash), 8.01953125)
    XCTAssertEqual(t.recallLinkCost(forDestination: packet.destinationHash), 7.25)

    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    try t.saveKnownDestinations(to: file)
    guard case .map(let pairs) = try MsgPack.decode(Data(contentsOf: file)) else {
      return XCTFail("not a map")
    }
    let fields = try XCTUnwrap(pairs.first?.1.asArray)
    XCTAssertEqual(fields.count, 8, "RNS 1.6.0's legacy entry carries stamp, value and lr_cost")
    XCTAssertEqual(fields[5].asData, Self.stamp)
    XCTAssertEqual(fields[6].asDouble, 8.01953125)
    XCTAssertEqual(fields[7].asDouble, 7.25)

    let restored = Transport()
    try restored.loadKnownDestinations(from: file)
    XCTAssertEqual(restored.recallStampValue(forDestination: packet.destinationHash), 8.01953125)
    XCTAssertEqual(restored.recallLinkCost(forDestination: packet.destinationHash), 7.25)
  }

  /// The interface's own `destination_cost` overrides the transport-wide one
  /// (`Interface.py:350-353`), and an enforced shortfall drops silently rather than
  /// counting a protocol violation (`Transport.py:2046-2049`).
  func testEnforcementAtAdmissionUsesTheInterfaceCost() throws {
    let t = Transport()
    t.stamps.enforced = true
    t.stamps.destinationCost = 8
    let iface = UDPInterface(name: "in", listenPort: 4394, forwardPort: 4395)
    iface.destinationCost = 9
    t.register(interface: iface)
    defer { t.deregister(interface: iface) }
    let packet = try Packet.unpack(Self.withAppData)

    t.handleIncoming(packet: packet, from: iface)

    XCTAssertNil(t.recall(identity: packet.destinationHash))
    let stats = try XCTUnwrap(
      InterfaceStatsPayload.build(t).asDictionary?["interfaces"]?.asArray?.first?.asDictionary)
    XCTAssertEqual(stats["protocol_violations"]?.asInt, 0)

    iface.destinationCost = nil
    t.handleIncoming(packet: packet, from: iface)
    XCTAssertNotNil(t.recall(identity: packet.destinationHash))
  }

  private func destination() throws -> Destination {
    try Destination(
      identity: Identity(), direction: .in, kind: .single, appName: "rs160", aspects: ["emitted"])
  }
}
