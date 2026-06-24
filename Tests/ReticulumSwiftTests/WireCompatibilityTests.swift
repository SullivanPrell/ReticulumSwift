import XCTest
@testable import ReticulumSwift

/// Tests verifying that the wire format of packets matches Python's reference implementation.
/// These verify byte-level compatibility.
final class WireCompatibilityTests: XCTestCase {

    // MARK: - Packet context values

    func testContextValues() {
        // Python: Packet.NONE = 0x00, RESOURCE = 0x01, etc.
        XCTAssertEqual(Packet.Context.none.rawValue, 0x00)
        XCTAssertEqual(Packet.Context.resource.rawValue, 0x01)
        XCTAssertEqual(Packet.Context.resourceAdvertisement.rawValue, 0x02)
        XCTAssertEqual(Packet.Context.resourceRequest.rawValue, 0x03)
        XCTAssertEqual(Packet.Context.resourceHashmapUpdate.rawValue, 0x04)
        XCTAssertEqual(Packet.Context.resourceProof.rawValue, 0x05)
        XCTAssertEqual(Packet.Context.resourceInitiatorCancel.rawValue, 0x06)
        XCTAssertEqual(Packet.Context.resourceReceiverCancel.rawValue, 0x07)
        XCTAssertEqual(Packet.Context.cacheRequest.rawValue, 0x08)
        XCTAssertEqual(Packet.Context.request.rawValue, 0x09)
        XCTAssertEqual(Packet.Context.response.rawValue, 0x0A)
        XCTAssertEqual(Packet.Context.pathResponse.rawValue, 0x0B)
        XCTAssertEqual(Packet.Context.command.rawValue, 0x0C)
        XCTAssertEqual(Packet.Context.commandStatus.rawValue, 0x0D)
        XCTAssertEqual(Packet.Context.channel.rawValue, 0x0E)
        XCTAssertEqual(Packet.Context.keepalive.rawValue, 0xFA)
        XCTAssertEqual(Packet.Context.linkIdentify.rawValue, 0xFB)
        XCTAssertEqual(Packet.Context.linkClose.rawValue, 0xFC)
        XCTAssertEqual(Packet.Context.linkProof.rawValue, 0xFD)
        XCTAssertEqual(Packet.Context.lrrtt.rawValue, 0xFE)
        XCTAssertEqual(Packet.Context.lrproof.rawValue, 0xFF)
    }

    // MARK: - Packet type values

    func testPacketTypeValues() {
        // Python: Packet.DATA = 0x00, ANNOUNCE = 0x01, LINKREQUEST = 0x02, PROOF = 0x03
        XCTAssertEqual(Packet.PacketType.data.rawValue, 0x00)
        XCTAssertEqual(Packet.PacketType.announce.rawValue, 0x01)
        XCTAssertEqual(Packet.PacketType.linkRequest.rawValue, 0x02)
        XCTAssertEqual(Packet.PacketType.proof.rawValue, 0x03)
    }

    // MARK: - Destination type values

    func testDestinationTypeValues() {
        // Python: Destination.SINGLE = 0x00, GROUP = 0x01, PLAIN = 0x02, LINK = 0x03
        XCTAssertEqual(Packet.DestinationType.single.rawValue, 0x00)
        XCTAssertEqual(Packet.DestinationType.group.rawValue, 0x01)
        XCTAssertEqual(Packet.DestinationType.plain.rawValue, 0x02)
        XCTAssertEqual(Packet.DestinationType.link.rawValue, 0x03)
    }

    // MARK: - Known packet wire format

    func testPacketWireFormatHeader1() throws {
        let destHash = Data(repeating: 0xAA, count: 16)
        let payload = Data("test".utf8)
        let packet = Packet(
            headerType: .type1,
            contextFlag: .unset,
            transportType: .broadcast,
            destinationType: .single,
            packetType: .data,
            hops: 0,
            destinationHash: destHash,
            context: .none,
            data: payload
        )
        let raw = try packet.pack()

        // Verify header structure:
        // byte 0: flags = (header=0 << 6) | (context=0 << 5) | (transport=0 << 4) | (dest=0 << 2) | (type=0) = 0x00
        XCTAssertEqual(raw[0], 0x00)
        // byte 1: hops = 0
        XCTAssertEqual(raw[1], 0x00)
        // bytes 2..17: destHash (16 bytes)
        XCTAssertEqual(Data(raw[2..<18]), destHash)
        // byte 18: context = 0x00 (none)
        XCTAssertEqual(raw[18], 0x00)
        // bytes 19+: payload
        XCTAssertEqual(Data(raw[19...]), payload)
    }

    func testPacketWireFormatHeader2() throws {
        let transportID = Data(repeating: 0xBB, count: 16)
        let destHash = Data(repeating: 0xCC, count: 16)
        let payload = Data("test2".utf8)
        let packet = Packet(
            headerType: .type2,
            contextFlag: .set,
            transportType: .broadcast,
            destinationType: .single,
            packetType: .announce,
            hops: 3,
            transportID: transportID,
            destinationHash: destHash,
            context: .none,
            data: payload
        )
        let raw = try packet.pack()

        // byte 0: flags = (header=1 << 6) | (context=1 << 5) | (transport=0 << 4) | (dest=0 << 2) | (type=1)
        //       = 0x40 | 0x20 | 0x00 | 0x00 | 0x01 = 0x61
        XCTAssertEqual(raw[0], 0x61)
        // byte 1: hops = 3
        XCTAssertEqual(raw[1], 0x03)
        // bytes 2..17: transportID
        XCTAssertEqual(Data(raw[2..<18]), transportID)
        // bytes 18..33: destHash
        XCTAssertEqual(Data(raw[18..<34]), destHash)
        // byte 34: context = 0x00
        XCTAssertEqual(raw[34], 0x00)
        // bytes 35+: payload
        XCTAssertEqual(Data(raw[35...]), payload)
    }

    // MARK: - Round-trip pack/unpack

    func testPackUnpackRoundTrip() throws {
        let transportID = Data(repeating: 0xDD, count: 16)
        let destHash = Data(repeating: 0xEE, count: 16)
        let original = Packet(
            headerType: .type2,
            contextFlag: .set,
            transportType: .broadcast,
            destinationType: .link,
            packetType: .proof,
            hops: 5,
            transportID: transportID,
            destinationHash: destHash,
            context: .lrproof,
            data: Data("proof data".utf8)
        )
        let raw = try original.pack()
        let recovered = try Packet.unpack(raw)

        XCTAssertEqual(recovered.headerType, original.headerType)
        XCTAssertEqual(recovered.contextFlag, original.contextFlag)
        XCTAssertEqual(recovered.transportType, original.transportType)
        XCTAssertEqual(recovered.destinationType, original.destinationType)
        XCTAssertEqual(recovered.packetType, original.packetType)
        XCTAssertEqual(recovered.hops, original.hops)
        XCTAssertEqual(recovered.transportID, original.transportID)
        XCTAssertEqual(recovered.destinationHash, original.destinationHash)
        XCTAssertEqual(recovered.context, original.context)
        XCTAssertEqual(recovered.data, original.data)
    }
}
