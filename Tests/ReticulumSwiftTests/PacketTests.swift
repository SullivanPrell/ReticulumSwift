import XCTest
@testable import ReticulumSwift

final class PacketTests: XCTestCase {

    func testPackUnpackRoundTripHeader1() throws {
        let packet = Packet(
            headerType: .type1,
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xAA, count: Constants.truncatedHashLength),
            context: .none,
            data: Data("payload".utf8)
        )
        let raw = try packet.pack()
        let decoded = try Packet.unpack(raw)
        XCTAssertEqual(decoded, packet)
    }

    func testPackUnpackRoundTripHeader2() throws {
        let packet = Packet(
            headerType: .type2,
            destinationType: .single,
            packetType: .data,
            transportID: Data(repeating: 0x77, count: Constants.truncatedHashLength),
            destinationHash: Data(repeating: 0xCC, count: Constants.truncatedHashLength),
            context: .none,
            data: Data("via transport".utf8)
        )
        let raw = try packet.pack()
        let decoded = try Packet.unpack(raw)
        XCTAssertEqual(decoded.transportID, packet.transportID)
        XCTAssertEqual(decoded.destinationHash, packet.destinationHash)
        XCTAssertEqual(decoded.data, packet.data)
    }

    func testFlagsByteEncoding() {
        let packet = Packet(
            headerType: .type2,
            contextFlag: .set,
            transportType: .broadcast,
            destinationType: .link,
            packetType: .announce,
            destinationHash: Data(repeating: 0, count: 16),
            data: Data()
        )
        // type2(1<<6) | flag(1<<5) | dst-type link (3<<2) | announce (1) = 0b01101101 = 0x6D
        XCTAssertEqual(packet.packedFlagsByte, 0x6D)
    }

    func testRejectsOversizedPayload() {
        let oversize = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0, count: 16),
            data: Data(repeating: 0xFF, count: Constants.mtu)
        )
        XCTAssertThrowsError(try oversize.pack())
    }

    func testHashablePartIgnoresTransportID() throws {
        let h = Data(repeating: 0x11, count: 16)
        let payload = Data("same payload".utf8)
        let p1 = Packet(
            headerType: .type1, destinationType: .single, packetType: .data,
            destinationHash: h, data: payload
        )
        let p2 = Packet(
            headerType: .type2, destinationType: .single, packetType: .data,
            transportID: Data(repeating: 0x99, count: 16),
            destinationHash: h, data: payload
        )
        XCTAssertEqual(try p1.hashablePart(), try p2.hashablePart())
    }
}
