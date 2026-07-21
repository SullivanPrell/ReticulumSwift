import XCTest
@testable import ReticulumSwift

/// Regression tests for bug 010 — Swift Transport silently dropped every inbound
/// link packet larger than the base MTU (500 B) because `Packet.hashablePart()`
/// went through the MTU-guarded `pack()`, so the packet hash threw and
/// `Transport.filterAndRecord()` treated the nil hash as a drop.
///
/// Reticulum links negotiate their MTU upward (a TCP link commonly reaches 8192),
/// so a peer legitimately sends single link packets far larger than 500 B — e.g.
/// a Python NomadNet node serving any real page. Packet identity (hash / dedup)
/// and byte accounting must be independent of the transmit MTU, matching Python
/// where `get_hashable_part()` slices the already-packed bytes and only `pack()`
/// enforces `self.MTU`.
final class PacketOversizeMTUTests: XCTestCase {

    /// A link data packet whose wire size exceeds the base MTU (mirrors a large
    /// NomadNet page RESPONSE sent over a link with a negotiated MTU > 500).
    private func oversizeLinkPacket(byte: UInt8 = 0x11) -> Packet {
        // data alone is well over Constants.mtu (500) so the packed packet is oversize.
        Packet(
            destinationType: .link,
            packetType: .data,
            destinationHash: Data(repeating: byte, count: Constants.truncatedHashLength),
            context: .response,
            data: Data(repeating: 0xAB, count: 2000)
        )
    }

    // MARK: - Packet level

    func testPackedBytesReturnsFullOversizePacket() throws {
        let pkt = oversizeLinkPacket()
        let raw = try pkt.packedBytes()
        XCTAssertGreaterThan(raw.count, Constants.mtu,
            "packedBytes() must return the full wire bytes even when they exceed the base MTU")
    }

    func testHashablePartDoesNotThrowForOversizePacket() throws {
        let pkt = oversizeLinkPacket()
        // Before the fix these threw PackError.exceedsMTU via pack().
        XCTAssertNoThrow(try pkt.hashablePart())
        XCTAssertNoThrow(try pkt.packetHash())
        XCTAssertNoThrow(try pkt.truncatedPacketHash())
        XCTAssertEqual(try pkt.truncatedPacketHash().count, Constants.truncatedHashLength)
    }

    func testHashablePartMatchesManualSliceForOversizePacket() throws {
        // Hash is computed over the same bytes packedBytes() produces (type1: drop
        // the 2-byte header prefix, keep the flags-nibble + dest + context + data).
        let pkt = oversizeLinkPacket()
        let raw = try pkt.packedBytes()
        var expected = Data()
        expected.append(raw[raw.startIndex] & 0b0000_1111)
        expected.append(raw.suffix(from: raw.startIndex + 2))
        XCTAssertEqual(try pkt.hashablePart(), expected)
    }

    func testPackStillEnforcesTransmitMTU() {
        // The outbound transmit guard is intentionally preserved: pack() must still
        // reject oversize packets so the base-MTU send path is unchanged.
        let pkt = oversizeLinkPacket()
        XCTAssertThrowsError(try pkt.pack()) { error in
            guard case Packet.PackError.exceedsMTU = error else {
                return XCTFail("expected exceedsMTU, got \(error)")
            }
        }
    }

    // MARK: - Transport inbound dedup

    func testOversizeLinkPacketSurvivesFilterAndRecord() {
        let transport = Transport()
        let pkt = oversizeLinkPacket(byte: 0x22)
        // Before the fix this returned false (nil hash → treated as a drop).
        XCTAssertTrue(transport.filterAndRecord(packet: pkt),
            "an oversize inbound link packet must pass the dedup filter, not be silently dropped")
    }

    func testOversizeLinkPacketStillDedupsOnReplay() {
        let transport = Transport()
        let pkt = oversizeLinkPacket(byte: 0x33)
        XCTAssertTrue(transport.filterAndRecord(packet: pkt), "first sighting passes")
        XCTAssertFalse(transport.filterAndRecord(packet: pkt),
            "a replay of the same oversize packet must still be deduplicated")
    }
}
