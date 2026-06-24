import XCTest
@testable import ReticulumSwift

/// Tests for Packet hash methods mirroring Python's Packet.get_hash() and Packet.getTruncatedHash().
final class PacketHashMethodsTests: XCTestCase {

    func testGetHashReturnsFullSHA256() throws {
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xAA, count: 16),
            data: Data("payload".utf8)
        )
        let hash = try packet.packetHash()
        XCTAssertEqual(hash.count, Constants.fullHashLength, "get_hash must return 32-byte SHA-256")
    }

    func testGetTruncatedHashReturns16Bytes() throws {
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xBB, count: 16),
            data: Data("test".utf8)
        )
        let trunc = try packet.truncatedPacketHash()
        XCTAssertEqual(trunc.count, Constants.truncatedHashLength, "getTruncatedHash must return 16 bytes")
    }

    func testTruncatedHashIsPrefixOfFullHash() throws {
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xCC, count: 16),
            data: Data("abc".utf8)
        )
        let full = try packet.packetHash()
        let trunc = try packet.truncatedPacketHash()
        XCTAssertEqual(trunc, Data(full.prefix(Constants.truncatedHashLength)))
    }

    func testHashIsConsistentAcrossCalls() throws {
        let packet = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Data(repeating: 0xDD, count: 16),
            data: Data("consistent".utf8)
        )
        let h1 = try packet.packetHash()
        let h2 = try packet.packetHash()
        XCTAssertEqual(h1, h2)
    }

    // verify that identical hashable content produces identical hash
    // even when packet header type differs (type1 vs type2)
    func testSameHashablePartGivesSameHash() throws {
        let destHash = Data(repeating: 0xEE, count: 16)
        let data = Data("same payload".utf8)

        let t1 = Packet(headerType: .type1, contextFlag: .unset, transportType: .broadcast,
                        destinationType: .single, packetType: .data, hops: 0,
                        destinationHash: destHash, context: .none, data: data)
        let t2 = Packet(headerType: .type2, contextFlag: .unset, transportType: .broadcast,
                        destinationType: .single, packetType: .data, hops: 3,
                        transportID: Data(repeating: 0xFF, count: 16),
                        destinationHash: destHash, context: .none, data: data)

        XCTAssertEqual(try t1.packetHash(), try t2.packetHash(),
            "packets with same hashable part must produce the same hash regardless of hops/transportID")
    }
}
