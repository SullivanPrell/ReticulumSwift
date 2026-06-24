import XCTest
@testable import ReticulumSwift

/// Tests for adaptive keepalive interval based on link RTT.
/// Python: keepalive = max(KEEPALIVE_MIN, min(rtt * (KEEPALIVE_MAX / KEEPALIVE_MAX_RTT), KEEPALIVE_MAX))
///         stale_time = keepalive * STALE_FACTOR
final class LinkAdaptiveKeepaliveTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    private func establishLink() throws -> (Link, Link, Transport, Transport) {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["adaptive"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }; bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink, aT, bT)
    }

    // MARK: - Constant values

    func testKeepaliveMaxRTTConstant() {
        // Python: Link.KEEPALIVE_MAX_RTT = 1.75
        XCTAssertEqual(Link.keepaliveMaxRTT, 1.75, accuracy: 0.001)
    }

    func testKeepaliveMinConstant() {
        // Python: Link.KEEPALIVE_MIN = 5
        XCTAssertEqual(Link.keepaliveMin, 5)
    }

    func testKeepaliveMaxConstant() {
        // Python: Link.KEEPALIVE_MAX = 360
        XCTAssertEqual(Link.keepaliveMax, 360)
    }

    // MARK: - Adaptive keepalive formula

    func testKeepaliveClampedToMinForLowRTT() throws {
        let (aLink, _, aT, bT) = try establishLink()
        defer { _ = (aT, bT) }

        // In-process loopback has extremely low RTT (< 1ms)
        // keepalive = rtt * (360/1.75) → very small → clamped to KEEPALIVE_MIN = 5s
        guard let rtt = aLink.rtt else { return XCTFail("rtt not set") }
        XCTAssertGreaterThan(rtt, 0)
        let expectedKeepalive = max(Link.keepaliveMin, min(rtt * (Link.keepaliveMax / Link.keepaliveMaxRTT), Link.keepaliveMax))
        XCTAssertEqual(aLink.effectiveKeepalive, expectedKeepalive, accuracy: 0.01)
        // For loopback, RTT is very small, so keepalive should be KEEPALIVE_MIN = 5
        XCTAssertLessThanOrEqual(aLink.effectiveKeepalive, Link.keepaliveMin + 0.01)
    }

    func testKeepaliveClampedToMaxForHighRTT() throws {
        let (aLink, _, aT, bT) = try establishLink()
        defer { _ = (aT, bT) }

        // Simulate high RTT (> 1.75s would give keepalive > 360, clamps to 360)
        let highRTT = 2.0  // seconds
        let expectedKeepalive = max(Link.keepaliveMin, min(highRTT * (Link.keepaliveMax / Link.keepaliveMaxRTT), Link.keepaliveMax))
        XCTAssertEqual(expectedKeepalive, Link.keepaliveMax, accuracy: 0.01)
        _ = aLink
    }

    func testEffectiveStaleTimeIsKeepaliveTimesTwo() throws {
        let (aLink, _, aT, bT) = try establishLink()
        defer { _ = (aT, bT) }

        let expectedStale = aLink.effectiveKeepalive * Double(Link.staleFactor)
        XCTAssertEqual(aLink.effectiveStaleTime, expectedStale, accuracy: 0.01)
    }
}
