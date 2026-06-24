import XCTest
@testable import ReticulumSwift

/// Tests that the AnnounceQueue prioritizes announces with fewer hops.
/// Mirrors Python's ANNOUNCE_CAP behavior: "Reticulum will always prioritise
/// propagating announces with fewer hops."
final class AnnounceHopPriorityTests: XCTestCase {

    private func makeAnnounce(hops: UInt8, dest: UInt8) -> Packet {
        Packet(
            headerType: .type1, contextFlag: .unset, transportType: .broadcast,
            destinationType: .single, packetType: .announce, hops: hops,
            destinationHash: Data(repeating: dest, count: 16),
            context: .none,
            data: Data(count: 50)
        )
    }

    func testQueueDrainsLowHopFirst() {
        let queue = AnnounceQueue()
        let bitrate = 9600
        let now = 0.0

        // Fill the queue: first transmit one to use up bandwidth
        let first = makeAnnounce(hops: 0, dest: 0xFF)
        _ = queue.shouldTransmit(packet: first, now: now, bitrate: bitrate, emitted: 0)

        // Queue a high-hop announce first
        let highHop = makeAnnounce(hops: 10, dest: 0x01)
        let lowHop  = makeAnnounce(hops: 1,  dest: 0x02)

        _ = queue.shouldTransmit(packet: highHop, now: now, bitrate: bitrate, emitted: 0)
        _ = queue.shouldTransmit(packet: lowHop, now: now, bitrate: bitrate, emitted: 0)

        XCTAssertEqual(queue.count, 2, "both should be queued")

        // Drain entries: sort should happen, and we get items as window allows.
        // Drain at t=100, t=200 to get both (each drain gets one due to rate limiting).
        var drained: [Packet] = []
        for t in stride(from: 100.0, through: 10000.0, by: 100.0) {
            drained += queue.drain(now: t, bitrate: bitrate)
            if drained.count >= 2 { break }
        }
        guard drained.count >= 2 else {
            XCTFail("expected at least 2 drained, got \(drained.count)"); return
        }
        XCTAssertEqual(drained[0].hops, 1, "lowest hop count should drain first")
        XCTAssertEqual(drained[1].hops, 10)
    }
}
