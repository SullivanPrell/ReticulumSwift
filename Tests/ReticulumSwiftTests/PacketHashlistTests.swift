import XCTest
@testable import ReticulumSwift

final class PacketHashlistTests: XCTestCase {

    func testDuplicatePacketIsFiltered() throws {
        let transport = Transport()
        let pkt = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0x01, count: 16),
            data: Data("hello".utf8)
        )
        XCTAssertTrue(transport.filterAndRecord(packet: pkt))   // first time: pass
        XCTAssertFalse(transport.filterAndRecord(packet: pkt))  // duplicate: drop
    }

    func testDifferentPacketsPassThrough() throws {
        let transport = Transport()
        let p1 = Packet(destinationType: .single, packetType: .data,
                        destinationHash: Data(repeating: 0x01, count: 16), data: Data("a".utf8))
        let p2 = Packet(destinationType: .single, packetType: .data,
                        destinationHash: Data(repeating: 0x02, count: 16), data: Data("b".utf8))
        XCTAssertTrue(transport.filterAndRecord(packet: p1))
        XCTAssertTrue(transport.filterAndRecord(packet: p2))
    }

    func testLinkRequestPacketsAreNotDeduped() throws {
        // LRR packets are exempt — they need to pass through on retransmit.
        let transport = Transport()
        let pkt = Packet(
            destinationType: .single,
            packetType: .linkRequest,
            destinationHash: Data(repeating: 0x01, count: 16),
            data: Data(count: 64)
        )
        XCTAssertTrue(transport.filterAndRecord(packet: pkt))
        XCTAssertTrue(transport.filterAndRecord(packet: pkt))  // second pass also OK
    }

    func testRotatesHashlistAtSizeLimit() throws {
        let transport = Transport()
        transport.hashlistMaxSize = 3  // very small limit for testing

        // Fill the hashlist to the limit.
        for i in 0..<3 {
            let pkt = Packet(destinationType: .single, packetType: .data,
                             destinationHash: Data([UInt8(i)] + Array(repeating: 0, count: 15)),
                             data: Data([UInt8(i)]))
            XCTAssertTrue(transport.filterAndRecord(packet: pkt))
        }

        // Adding one more triggers rotation (current → prev, current = empty).
        let pkt4 = Packet(destinationType: .single, packetType: .data,
                          destinationHash: Data([0xFF] + Array(repeating: 0, count: 15)),
                          data: Data([0xFF]))
        XCTAssertTrue(transport.filterAndRecord(packet: pkt4))

        // The first 3 should still be found in the prev generation.
        for i in 0..<3 {
            let pkt = Packet(destinationType: .single, packetType: .data,
                             destinationHash: Data([UInt8(i)] + Array(repeating: 0, count: 15)),
                             data: Data([UInt8(i)]))
            XCTAssertFalse(transport.filterAndRecord(packet: pkt), "Packet \(i) should be in prev")
        }
    }

    func testDuplicatesBlockedEvenAfterRotation() throws {
        let transport = Transport()
        transport.hashlistMaxSize = 2

        let pkt = Packet(destinationType: .single, packetType: .data,
                         destinationHash: Data(repeating: 0x01, count: 16), data: Data("dup".utf8))
        XCTAssertTrue(transport.filterAndRecord(packet: pkt))

        // Force rotation with two more packets.
        for i in 0..<2 {
            let p = Packet(destinationType: .single, packetType: .data,
                           destinationHash: Data([UInt8(i+2)] + Array(repeating: 0, count: 15)),
                           data: Data([UInt8(i)]))
            _ = transport.filterAndRecord(packet: p)
        }

        // Original pkt should still be blocked (it's in prev after rotation).
        XCTAssertFalse(transport.filterAndRecord(packet: pkt))
    }
}
