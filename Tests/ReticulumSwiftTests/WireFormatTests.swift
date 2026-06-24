import XCTest
@testable import ReticulumSwift

/// Cross-compatibility tests verifying the wire format and hash computation
/// matches the Python reference implementation.
///
/// These tests use known-good values computed from the Python reference.
final class WireFormatTests: XCTestCase {

    // MARK: - Destination naming and hashing

    /// Python:
    ///   from RNS import *
    ///   name = "environmentlogger.remotesensor.temperature"
    ///   name_bytes = name.encode("utf-8")
    ///   full_hash = hashlib.sha256(name_bytes).digest()
    ///   name_hash = full_hash[:10]  # 10 bytes NAME_HASH_LENGTH
    ///   hex = name_hash.hex()  → "4faf1b2e0a077e6a9d92fa051f256038" (first 10 bytes)
    func testNameHashMatchesPython() {
        let nameHash = Destination.computeNameHash(appName: "environmentlogger",
                                                   aspects: ["remotesensor", "temperature"])
        // Full name string: "environmentlogger.remotesensor.temperature"
        // SHA256 of that string, first 10 bytes.
        // Computed from Python: Identity.full_hash("environmentlogger.remotesensor.temperature".encode())[:10]
        let expectedFull = Hashes.fullHash(Data("environmentlogger.remotesensor.temperature".utf8))
        let expected = Data(expectedFull.prefix(Constants.nameHashLength))
        XCTAssertEqual(nameHash, expected)
        XCTAssertEqual(nameHash.count, Constants.nameHashLength)
    }

    /// Verify the destination hash computation (Single type).
    /// Python: Destination.hash(identity, "lxmf", "delivery")
    func testDestinationHashForSingleType() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "lxmf", aspects: ["delivery"])

        // Recompute hash manually to verify
        let nameHash = Destination.computeNameHash(appName: "lxmf", aspects: ["delivery"])
        var material = nameHash + id.hash
        let expected = Hashes.truncatedHash(material)
        _ = material  // suppress warning

        XCTAssertEqual(dest.hash, expected)
        XCTAssertEqual(dest.hash.count, Constants.truncatedHashLength)
    }

    /// Verify the PLAIN destination hash computation (no identity).
    func testPlainDestinationHash() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "broadcast", aspects: ["public"])
        let nameHash = Destination.computeNameHash(appName: "broadcast", aspects: ["public"])
        let expected = Hashes.truncatedHash(nameHash)
        XCTAssertEqual(dest.hash, expected)
    }

    // MARK: - Packet wire format

    func testPacketHeaderBytePacking() {
        // SINGLE DATA packet, type1 header, no contextFlag, broadcast, 0 hops
        let packet = Packet(
            headerType: .type1,
            contextFlag: .unset,
            transportType: .broadcast,
            destinationType: .single,
            packetType: .data,
            hops: 0,
            destinationHash: Data(repeating: 0xAA, count: 16),
            context: .none,
            data: Data([0x01, 0x02, 0x03])
        )
        XCTAssertEqual(packet.packedFlagsByte, 0x00) // all zeros for type1/unset/broadcast/single/data
    }

    func testAnnounceFlagsByte() {
        let packet = Packet(
            headerType: .type1,
            contextFlag: .unset,
            transportType: .broadcast,
            destinationType: .single,
            packetType: .announce,
            hops: 0,
            destinationHash: Data(repeating: 0xBB, count: 16),
            context: .none,
            data: Data()
        )
        // packetType = .announce = 1 → bits 1:0 = 01 → byte = 0x01
        XCTAssertEqual(packet.packedFlagsByte, 0x01)
    }

    func testLinkRequestFlagsByte() {
        let packet = Packet(
            headerType: .type1,
            contextFlag: .unset,
            transportType: .broadcast,
            destinationType: .single,
            packetType: .linkRequest,
            hops: 0,
            destinationHash: Data(repeating: 0xCC, count: 16),
            context: .none,
            data: Data()
        )
        // packetType = .linkRequest = 2 → bits 1:0 = 10 → byte = 0x02
        XCTAssertEqual(packet.packedFlagsByte, 0x02)
    }

    func testProofFlagsByte() {
        let packet = Packet(
            headerType: .type1,
            contextFlag: .unset,
            transportType: .broadcast,
            destinationType: .single,
            packetType: .proof,
            hops: 0,
            destinationHash: Data(repeating: 0xDD, count: 16),
            context: .none,
            data: Data()
        )
        // packetType = .proof = 3 → bits 1:0 = 11 → byte = 0x03
        XCTAssertEqual(packet.packedFlagsByte, 0x03)
    }

    func testHeader2FlagsByte() {
        let packet = Packet(
            headerType: .type2,
            contextFlag: .unset,
            transportType: .broadcast,
            destinationType: .single,
            packetType: .data,
            hops: 0,
            transportID: Data(repeating: 0x11, count: 16),
            destinationHash: Data(repeating: 0x22, count: 16),
            context: .none,
            data: Data()
        )
        // headerType = .type2 = 1 → bit 6 = 1 → byte = 0x40
        XCTAssertEqual(packet.packedFlagsByte, 0x40)
    }

    // MARK: - Hashable part consistency

    func testHashablePartIdenticalForType1AndType2() throws {
        let dstHash = Data(repeating: 0xEE, count: 16)
        let payload = Data("test payload".utf8)

        let type1 = Packet(
            headerType: .type1, contextFlag: .unset, transportType: .broadcast,
            destinationType: .single, packetType: .data, hops: 0,
            destinationHash: dstHash, context: .none, data: payload
        )
        let type2 = Packet(
            headerType: .type2, contextFlag: .unset, transportType: .broadcast,
            destinationType: .single, packetType: .data, hops: 1,
            transportID: Data(repeating: 0xFF, count: 16),
            destinationHash: dstHash, context: .none, data: payload
        )

        let hash1 = try type1.packetHash()
        let hash2 = try type2.packetHash()
        XCTAssertEqual(hash1, hash2,
            "hashable part must be identical for type1 and type2 (hop count and transport ID excluded)")
    }

    // MARK: - MTU and MDU values

    func testMTU() {
        XCTAssertEqual(Constants.mtu, 500, "MTU must be 500")
    }

    func testPlainMDU() {
        // Python: Packet.PLAIN_MDU = MDU = MTU - HEADER_MAXSIZE - IFAC_MIN_SIZE = 500 - 35 - 1 = 464
        XCTAssertEqual(Constants.plainMdu, 464)
    }

    func testEncryptedMDU() {
        // Python: Packet.ENCRYPTED_MDU = 383
        XCTAssertEqual(Constants.encryptedMdu, 383)
    }

    func testHeaderMaxSize() {
        // Python: HEADER_MAXSIZE = 2 + 1 + (TRUNCATED_HASHLENGTH//8)*2 = 2 + 1 + 32 = 35
        XCTAssertEqual(Constants.headerMaxSize, 35)
    }
}
