import XCTest
@testable import ReticulumSwift

/// Mirrors Python `Transport.packet_filter`'s transport-instance filter:
///
///   if packet.transport_id != None and packet.packet_type != ANNOUNCE:
///       if packet.transport_id != Transport.identity.hash:
///           return False
///
/// Without this, a HEADER_2 packet addressed (via transport_id) to one
/// transport node is also forwarded by every *other* transport node that
/// hears it on a shared medium — causing duplicate forwarding / loops.
final class TransportIDFilterTests: XCTestCase {

    private func header2Packet(transportID: Data,
                               packetType: Packet.PacketType = .data,
                               destinationType: Packet.DestinationType = .single,
                               data: Data = Data("payload".utf8)) -> Packet {
        Packet(
            headerType: .type2,
            transportType: .transport,
            destinationType: destinationType,
            packetType: packetType,
            transportID: transportID,
            destinationHash: Data(repeating: 0x42, count: 16),
            data: data
        )
    }

    func testForeignTransportIDIsFiltered() throws {
        let transport = Transport()
        // transport_id names a *different* instance than ours → drop.
        let foreign = Data(repeating: 0xAB, count: 16)
        XCTAssertNotEqual(foreign, transport.transportInstanceID)
        let pkt = header2Packet(transportID: foreign)
        XCTAssertFalse(transport.filterAndRecord(packet: pkt))
    }

    func testOwnTransportIDPasses() throws {
        let transport = Transport()
        // Addressed to us as the next-hop relay → keep.
        let pkt = header2Packet(transportID: transport.transportInstanceID)
        XCTAssertTrue(transport.filterAndRecord(packet: pkt))
    }

    func testForeignAnnounceIsExempt() throws {
        let transport = Transport()
        // Announces are flooded — they carry the upstream transport_id but
        // must still propagate regardless of which node they name.
        let foreign = Data(repeating: 0xCD, count: 16)
        let pkt = header2Packet(transportID: foreign,
                                packetType: .announce,
                                destinationType: .single,
                                data: Data(count: 167))
        XCTAssertTrue(transport.filterAndRecord(packet: pkt))
    }

    func testHeader1PacketHasNoTransportIDAndPasses() throws {
        let transport = Transport()
        let pkt = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0x42, count: 16),
            data: Data("payload".utf8)
        )
        XCTAssertNil(pkt.transportID)
        XCTAssertTrue(transport.filterAndRecord(packet: pkt))
    }

    func testSharedInstanceClientSkipsTransportIDFilter() throws {
        let transport = Transport()
        // A node attached as a client to a shared instance must NOT re-filter;
        // the shared instance already did the routing. Mirrors Python's
        // `if Transport.owner.is_connected_to_shared_instance: return True`.
        transport.isConnectedToSharedInstance = true
        let foreign = Data(repeating: 0xAB, count: 16)
        let pkt = header2Packet(transportID: foreign)
        XCTAssertTrue(transport.filterAndRecord(packet: pkt))
    }
}
