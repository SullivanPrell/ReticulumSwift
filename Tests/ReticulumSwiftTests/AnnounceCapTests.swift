import XCTest
@testable import ReticulumSwift

/// Tests verifying announce bandwidth cap behavior.
/// Python: Transport uses ANNOUNCE_CAP = 2% of interface bandwidth for announces.
final class AnnounceCapTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Disable random jitter so tests are deterministic.
        AnnounceQueue.jitterMultiplierOverride = 0.0
    }

    override func tearDown() {
        AnnounceQueue.jitterMultiplierOverride = nil
        super.tearDown()
    }

    final class BandwidthInterface: Interface {
        var name: String; var bitrate: Int; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        init(name: String, bitrate: Int) { self.name = name; self.bitrate = bitrate }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    // MARK: - AnnounceQueue cap behavior

    func testFastInterfaceTransmitsImmediately() {
        let queue = AnnounceQueue()
        let highBitrate = 1_000_000  // 1 Mbps
        let now = 0.0

        let packet = makeAnnounce(hops: 0, dest: 0xAA)
        let result = queue.shouldTransmit(packet: packet, now: now, bitrate: highBitrate, emitted: 0)
        XCTAssertTrue(result, "high-bitrate interface should transmit immediately")
        XCTAssertTrue(queue.isEmpty, "queue should be empty after immediate transmit")
    }

    func testSecondAnnounceQueued_WhenBandwidthUsed() {
        let queue = AnnounceQueue()
        let bitrate = 9600  // 9600 bps (low rate)
        let now = 0.0

        let p1 = makeAnnounce(hops: 0, dest: 0xAA)
        let p2 = makeAnnounce(hops: 0, dest: 0xBB)

        let r1 = queue.shouldTransmit(packet: p1, now: now, bitrate: bitrate, emitted: 0)
        let r2 = queue.shouldTransmit(packet: p2, now: now, bitrate: bitrate, emitted: 0)

        XCTAssertTrue(r1, "first packet should transmit immediately")
        XCTAssertFalse(r2, "second packet should be queued when bandwidth used")
        XCTAssertEqual(queue.count, 1)
    }

    func testAnnouncesTransmitAfterBandwidthWindow() {
        let queue = AnnounceQueue()
        let bitrate = 9600
        let now = 0.0

        let p1 = makeAnnounce(hops: 0, dest: 0xAA)
        let p2 = makeAnnounce(hops: 0, dest: 0xBB)

        _ = queue.shouldTransmit(packet: p1, now: now, bitrate: bitrate, emitted: 0)
        _ = queue.shouldTransmit(packet: p2, now: now, bitrate: bitrate, emitted: 0)

        // After sufficient time, drain should release queued packet.
        let drained = queue.drain(now: now + 1000, bitrate: bitrate)
        XCTAssertGreaterThan(drained.count, 0, "queued announce should drain after window")
    }

    // MARK: - Bandwidth cap formula verification

    func testAnnounceCap2Percent() {
        // The cap is 2% of interface bandwidth for announces
        XCTAssertEqual(AnnounceQueue.announceCap, 0.02, accuracy: 0.001)
        XCTAssertEqual(Transport.announceCap, 2) // in percent
    }

    // MARK: - Random jitter (Python parity)

    /// Python's `Transport.outbound` adds `random() * tx_time/cap` jitter so that
    /// simultaneously-hearing nodes don't all rebroadcast at exactly the same moment.
    /// With jitterMultiplierOverride = 0 the window equals exactly txTime/cap.
    func testAllowedAtAdvancedByCapWindowNoJitter() {
        let queue = AnnounceQueue()
        let bitrate = 9600
        let now = 1000.0
        let packet = makeAnnounce(hops: 0, dest: 0xCC)

        _ = queue.shouldTransmit(packet: packet, now: now, bitrate: bitrate, emitted: 0)

        let txTime = Double(packet.rawByteCount) * 8.0 / Double(bitrate)
        let expectedWindow = txTime / AnnounceQueue.announceCap
        // With zero jitter, allowedAt == now + capWindow.
        XCTAssertEqual(queue.allowedAt, now + expectedWindow, accuracy: 0.001)
    }

    /// With jitter = 1.0 (maximum), allowedAt == now + 2 * capWindow.
    func testAllowedAtWithMaxJitter() {
        AnnounceQueue.jitterMultiplierOverride = 1.0
        let queue = AnnounceQueue()
        let bitrate = 9600
        let now = 1000.0
        let packet = makeAnnounce(hops: 0, dest: 0xDD)

        _ = queue.shouldTransmit(packet: packet, now: now, bitrate: bitrate, emitted: 0)

        let txTime = Double(packet.rawByteCount) * 8.0 / Double(bitrate)
        let capWindow = txTime / AnnounceQueue.announceCap
        // With jitter = 1.0: allowedAt == now + capWindow + 1.0 * capWindow = now + 2*capWindow.
        XCTAssertEqual(queue.allowedAt, now + 2.0 * capWindow, accuracy: 0.001)
    }

    /// Second announce is still queued even when jitter extends the cap window.
    func testSecondAnnounceQueuedWithJitter() {
        AnnounceQueue.jitterMultiplierOverride = 1.0
        let queue = AnnounceQueue()
        let bitrate = 9600
        let now = 0.0

        let p1 = makeAnnounce(hops: 0, dest: 0xEE)
        let p2 = makeAnnounce(hops: 0, dest: 0xFF)

        let r1 = queue.shouldTransmit(packet: p1, now: now, bitrate: bitrate, emitted: 0)
        let r2 = queue.shouldTransmit(packet: p2, now: now, bitrate: bitrate, emitted: 0)

        XCTAssertTrue(r1, "first packet transmits immediately regardless of jitter")
        XCTAssertFalse(r2, "second packet queued — jitter extends the hold window")
    }

    /// Jitter override nil → production path uses real random; just verify no crash
    /// and that allowedAt > now + capWindow (i.e., jitter >= 0).
    func testProductionJitterIsNonNegative() {
        AnnounceQueue.jitterMultiplierOverride = nil
        let queue = AnnounceQueue()
        let bitrate = 9600
        let now = 500.0
        let packet = makeAnnounce(hops: 0, dest: 0x11)

        _ = queue.shouldTransmit(packet: packet, now: now, bitrate: bitrate, emitted: 0)

        let txTime = Double(packet.rawByteCount) * 8.0 / Double(bitrate)
        let minWindow = now + txTime / AnnounceQueue.announceCap
        XCTAssertGreaterThanOrEqual(queue.allowedAt, minWindow,
            "allowedAt must be at least now + capWindow (jitter is non-negative)")
    }

    // MARK: - Helpers

    private func makeAnnounce(hops: UInt8, dest: UInt8) -> Packet {
        Packet(
            headerType: .type1, contextFlag: .unset, transportType: .broadcast,
            destinationType: .single, packetType: .announce, hops: hops,
            destinationHash: Data(repeating: dest, count: 16),
            context: .none, data: Data(count: 50)
        )
    }
}
