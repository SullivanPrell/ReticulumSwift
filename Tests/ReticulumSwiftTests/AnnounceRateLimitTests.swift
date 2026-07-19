import XCTest
@testable import ReticulumSwift

final class AnnounceRateLimitTests: XCTestCase {

    func testFastPathTransmitsImmediatelyWithNoBitrateCap() {
        let q = AnnounceQueue()
        // bitrate=0 means "unknown" — always transmit.
        let pkt = Packet(destinationType: .single, packetType: .announce,
                         destinationHash: Data(repeating: 0x01, count: 16), data: Data(count: 100))
        let ok = q.shouldTransmit(packet: pkt, now: 1_000, bitrate: 0, emitted: 999)
        XCTAssertTrue(ok)
        XCTAssertTrue(q.isEmpty)
    }

    func testFirstAnnounceTransmitsAndUpdatesAllowedAt() {
        let q = AnnounceQueue()
        let pkt = Packet(destinationType: .single, packetType: .announce,
                         destinationHash: Data(repeating: 0x02, count: 16), data: Data(count: 100))
        let ok = q.shouldTransmit(packet: pkt, now: 1_000, bitrate: 9600, emitted: 999)
        XCTAssertTrue(ok)
        // allowedAt should be > now after consuming bitrate budget.
        XCTAssertGreaterThan(q.allowedAt, 1_000)
    }

    func testSecondAnnounceDuringRateLimitIsQueued() {
        let q = AnnounceQueue()
        let p1 = Packet(destinationType: .single, packetType: .announce,
                        destinationHash: Data(repeating: 0x03, count: 16), data: Data(count: 100))
        let p2 = Packet(destinationType: .single, packetType: .announce,
                        destinationHash: Data(repeating: 0x04, count: 16), data: Data(count: 100))
        _ = q.shouldTransmit(packet: p1, now: 1_000, bitrate: 9600, emitted: 999)
        // Second announce arrives before allowedAt — must be queued.
        let ok2 = q.shouldTransmit(packet: p2, now: 1_000.001, bitrate: 9600, emitted: 999)
        XCTAssertFalse(ok2)
        XCTAssertEqual(q.count, 1)
    }

    func testDrainReleasesQueuedAnnouncesAfterWindow() {
        let q = AnnounceQueue()
        let p1 = Packet(destinationType: .single, packetType: .announce,
                        destinationHash: Data(repeating: 0x05, count: 16), data: Data(count: 100))
        let p2 = Packet(destinationType: .single, packetType: .announce,
                        destinationHash: Data(repeating: 0x06, count: 16), data: Data(count: 100))
        _ = q.shouldTransmit(packet: p1, now: 1_000, bitrate: 9600, emitted: 999)
        _ = q.shouldTransmit(packet: p2, now: 1_000.001, bitrate: 9600, emitted: 999)
        XCTAssertEqual(q.count, 1)

        // Drain at a time well past allowedAt.
        let drained = q.drain(now: q.allowedAt + 100, bitrate: 9600)
        XCTAssertEqual(drained.count, 1)
        XCTAssertTrue(q.isEmpty)
    }

    func testDuplicateDestinationKeepsFresherEntry() {
        let q = AnnounceQueue()
        let dest = Data(repeating: 0x07, count: 16)
        let old = Packet(destinationType: .single, packetType: .announce,
                         destinationHash: dest, data: Data(count: 50))
        let new = Packet(destinationType: .single, packetType: .announce,
                         destinationHash: dest, data: Data(count: 100))

        // First announce occupies the slot.
        _ = q.shouldTransmit(packet: old, now: 1_000, bitrate: 9600, emitted: 900)
        // Same destination with a newer emitted ts — should replace old entry.
        _ = q.shouldTransmit(packet: new, now: 1_000.001, bitrate: 9600, emitted: 950)
        XCTAssertEqual(q.count, 1)
        let drained = q.drain(now: q.allowedAt + 100, bitrate: 9600)
        // The drained packet should be the newer one (larger data count).
        XCTAssertEqual(drained.first?.data.count, 100)
    }

    func testQueueIsBoundedToMaxQueued() {
        let q = AnnounceQueue()
        // Saturate the queue.
        _ = q.shouldTransmit(
            packet: Packet(destinationType: .single, packetType: .announce,
                           destinationHash: Data(repeating: 0x00, count: 16), data: Data(count: 10)),
            now: 1_000, bitrate: 9600, emitted: 999
        )
        for i in 1..<(AnnounceQueue.maxQueued + 5) {
            // Encode i across two bytes so distinct destinations remain distinct
            // for large maxQueued values (16384) without overflowing UInt8.
            let d = Data([UInt8(i & 0xFF), UInt8((i >> 8) & 0xFF)] + Array(repeating: 0, count: 14))
            _ = q.shouldTransmit(
                packet: Packet(destinationType: .single, packetType: .announce,
                               destinationHash: d, data: Data(count: 10)),
                now: 1_000.001, bitrate: 9600, emitted: 999
            )
        }
        XCTAssertEqual(q.count, AnnounceQueue.maxQueued)
    }
}
