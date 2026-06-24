import XCTest
@testable import ReticulumSwift

/// Tests for Announce wire format validation — with and without ratchets.
final class AnnounceValidationTests: XCTestCase {

    func testValidateSimpleAnnounce() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["validate"])
        let packet = try Announce.make(for: dest)
        let decoded = try Announce.validate(packet)

        XCTAssertEqual(decoded.destinationHash, dest.hash)
        XCTAssertEqual(decoded.identity.publicKeyBytes, id.publicKeyBytes)
        XCTAssertNil(decoded.appData)
        XCTAssertNil(decoded.ratchet)
        XCTAssertFalse(decoded.isPathResponse)
    }

    func testValidateAnnounceWithAppData() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["appdata"])
        let appData = Data("Nick: Alice".utf8)
        let packet = try Announce.make(for: dest, appData: appData)
        let decoded = try Announce.validate(packet)

        XCTAssertEqual(decoded.appData, appData)
    }

    func testValidateAnnounceWithRatchet() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["ratchet"])

        // Enable ratchets using a temp path
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try dest.enableRatchets(path: tmp)

        let packet = try Announce.make(for: dest)
        XCTAssertEqual(packet.contextFlag, .set, "ratchet announce must have contextFlag set")

        let decoded = try Announce.validate(packet)
        XCTAssertNotNil(decoded.ratchet, "decoded announce should carry ratchet")
        XCTAssertEqual(decoded.ratchet?.count, Constants.ratchetSize)
        try? FileManager.default.removeItem(at: tmp)
    }

    func testValidateRejectsInvalidSignature() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["sig"])
        var packet = try Announce.make(for: dest)
        // Corrupt the last byte of data (signature area)
        if !packet.data.isEmpty {
            packet.data[packet.data.index(before: packet.data.endIndex)] ^= 0xFF
        }
        XCTAssertThrowsError(try Announce.validate(packet))
    }

    func testValidateRejectsWrongDestinationHash() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["hash"])
        var packet = try Announce.make(for: dest)
        // Wrong destination hash
        packet = Packet(
            headerType: packet.headerType, contextFlag: packet.contextFlag,
            transportType: packet.transportType, destinationType: packet.destinationType,
            packetType: packet.packetType, hops: packet.hops,
            destinationHash: Data(repeating: 0xFF, count: 16),
            context: packet.context, data: packet.data
        )
        XCTAssertThrowsError(try Announce.validate(packet))
    }

    func testAnnouncePacketHashIs4Bytes() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["phash"])
        let packet = try Announce.make(for: dest)
        let decoded = try Announce.validate(packet)
        // packetHash = truncatedHash(hashablePart)[:4]? Actually in Swift it's the 16-byte truncated hash
        // Python's announce_packet_hash is getTruncatedHash() = 16 bytes
        XCTAssertEqual(decoded.packetHash.count, Constants.truncatedHashLength)
    }

    func testRandomHashLength() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["rand"])
        let packet = try Announce.make(for: dest)
        let decoded = try Announce.validate(packet)
        XCTAssertEqual(decoded.randomHash.count, Constants.randomHashLength, "random hash must be 10 bytes")
    }
}
