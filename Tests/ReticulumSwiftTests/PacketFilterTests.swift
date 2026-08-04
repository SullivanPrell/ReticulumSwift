import XCTest
@testable import ReticulumSwift

/// `swift_devel/bugs/038` — the public filter and the production recorder must agree on the key.
///
/// Python keys `packet_filter` on `packet.packet_hash`, the **full** 32-byte hash
/// (`Transport.py:1417`, `Packet.py:342-344`), and every production insertion stores the same
/// (`Transport.py:1344,1545,1733,2314`). The port's `packetFilter` keyed on the 16-byte
/// truncated hash while `filterAndRecord` stored full hashes — a 16-byte `Data` never equals a
/// 32-byte one, so "seen" was always false and the public filter suppressed nothing.
///
/// The previous tests could not observe this: they pre-inserted `truncatedPacketHash()` by
/// hand — the same wrong key the function computed — so filter and fixture agreed with each
/// other and disagreed with production. Every "seen" state below comes from the production
/// recording path instead; no test computes a hashlist key.
final class PacketFilterTests: XCTestCase {

    private func makeDataPacket(fill: UInt8 = 0x01) -> Packet {
        Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: fill, count: 16),
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

    func testPacketFilterTrueForUnseen() {
        let transport = Transport()
        XCTAssertTrue(transport.packetFilter(makeDataPacket()))
    }

    func testPacketFilterFalseForAPacketTheStackRecorded() {
        let transport = Transport()
        let packet = makeDataPacket()
        XCTAssertTrue(transport.filterAndRecord(packet: packet),
                      "first sight must record and pass")
        XCTAssertFalse(transport.packetFilter(packet),
                       """
                       the public filter missed a packet the production path recorded — it is \
                       keying on a different hash width than the hashlist stores (bugs/038; \
                       Python keys packet_filter on the full packet_hash, Transport.py:1417)
                       """)
    }

    func testPacketFilterPassesASeenSingleAnnounce() {
        let transport = Transport()
        let announce = makeAnnouncePacket()
        _ = transport.filterAndRecord(packet: announce)
        _ = transport.filterAndRecord(packet: announce)
        XCTAssertTrue(transport.packetFilter(announce),
                      "a SINGLE announce passes even when seen, so path tables can update "
                      + "via multiple routes (Python parity)")
    }

    func testPacketFilterTrueForADifferentPacket() {
        let transport = Transport()
        _ = transport.filterAndRecord(packet: makeDataPacket(fill: 0x01))
        XCTAssertTrue(transport.packetFilter(makeDataPacket(fill: 0x03)))
    }
}
