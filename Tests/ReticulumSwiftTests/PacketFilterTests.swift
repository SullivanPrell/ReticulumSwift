import XCTest
@testable import ReticulumSwift

final class PacketFilterTests: XCTestCase {

    private func makeDataPacket() -> Packet {
        Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0x01, count: 16),
            context: .none,
            data: Data(repeating: 0xFF, count: 4)
        )
    }

    private func makeAnnouncePacket() -> Packet {
        Packet(
            destinationType: .single,
            packetType: .announce,
            destinationHash: Data(repeating: 0x02, count: 16),
            context: .none,
            data: Data(repeating: 0xAA, count: 4)
        )
    }

    // MARK: - addPacketHash

    func testAddPacketHashInsertedIntoHashlist() {
        let transport = Transport()
        let hash = Data(repeating: 0x99, count: 16)
        XCTAssertFalse(transport.testContainsPacketHash(hash))
        transport.addPacketHash(hash)
        XCTAssertTrue(transport.testContainsPacketHash(hash))
    }

    func testAddPacketHashIdempotent() {
        let transport = Transport()
        let hash = Data(repeating: 0x88, count: 16)
        transport.addPacketHash(hash)
        transport.addPacketHash(hash)
        XCTAssertTrue(transport.testContainsPacketHash(hash))
    }

    // MARK: - packetFilter

    func testPacketFilterTrueForUnseen() throws {
        let transport = Transport()
        let packet = makeDataPacket()
        XCTAssertTrue(transport.packetFilter(packet))
    }

    func testPacketFilterFalseForSeenDataPacket() throws {
        let transport = Transport()
        let packet = makeDataPacket()
        // Pre-insert the packet's truncated hash
        let hash = try packet.truncatedPacketHash()
        transport.addPacketHash(hash)
        XCTAssertFalse(transport.packetFilter(packet))
    }

    func testPacketFilterTrueForSeenAnnouncePacket() throws {
        let transport = Transport()
        let packet = makeAnnouncePacket()
        let hash = try packet.truncatedPacketHash()
        transport.addPacketHash(hash)
        // SINGLE ANNOUNCE always passes even if seen (Python parity)
        XCTAssertTrue(transport.packetFilter(packet))
    }

    func testPacketFilterTrueForDifferentPacket() throws {
        let transport = Transport()
        let p1 = makeDataPacket()
        let p2 = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0x03, count: 16),
            context: .none,
            data: Data(repeating: 0x55, count: 4)
        )
        let hash1 = try p1.truncatedPacketHash()
        transport.addPacketHash(hash1)
        // p2 is a different packet — should pass
        XCTAssertTrue(transport.packetFilter(p2))
    }
}
