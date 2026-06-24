import XCTest
@testable import ReticulumSwift

/// Tests for Identity.validate_announce() static method.
/// Mirrors Python's `RNS.Identity.validate_announce(packet)`.
final class IdentityValidateAnnounceTests: XCTestCase {

    func testValidateAnnounceTrueForValidPacket() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["valid"])
        let packet = try Announce.make(for: dest)

        // Python: Identity.validate_announce(packet) → True if valid
        let result = Identity.validateAnnounce(packet)
        XCTAssertTrue(result, "valid announce should pass validation")
    }

    func testValidateAnnounceReturnsFalseForInvalidPacket() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
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

    func testValidateAnnounceOnlyValidateSignature() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["sigonly"])
        let packet = try Announce.make(for: dest)

        // only_validate_signature=True: skip destination hash check
        let result = Identity.validateAnnounce(packet, onlyValidateSignature: true)
        XCTAssertTrue(result)
    }
}
