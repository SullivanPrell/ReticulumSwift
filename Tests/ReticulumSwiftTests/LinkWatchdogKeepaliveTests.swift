import XCTest
@testable import ReticulumSwift

/// bugs/034 — an idle but healthy link must keep itself alive.
///
/// Python clamps EVERY watchdog sleep to WATCHDOG_MAX_SLEEP = 5 s
/// (RNS/Link.py:776 `sleep_time = min(sleep_time, Link.WATCHDOG_MAX_SLEEP)`,
/// constant at RNS/Link.py:108), so after establishment the initiator
/// re-evaluates the link at least every 5 s and sends a keepalive once
/// inbound/outbound idle reaches the RTT-scaled keepalive interval
/// (RNS/Link.py:749-751; 5 s floor on low-RTT links, RNS/Link.py:795-797).
///
/// The Swift watchdog scheduled its next tick at requestTime +
/// establishmentTimeout while the link was still `.pending` — uncapped — so a
/// link that established AFTER the first 0.1 s tick got NO watchdog tick until
/// the establishment deadline. No keepalive was ever sent, and the first
/// `.active` tick could land past effectiveStaleTime (2 x 5 s on low-RTT
/// links), tearing the healthy link down.
final class LinkWatchdogKeepaliveTests: XCTestCase {

    /// Loopback that delivers each packet asynchronously after `delay`, so
    /// link establishment completes AFTER the watchdog's first 0.1 s tick
    /// (as on any real network) instead of synchronously inside initiate().
    final class DelayedLoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: DelayedLoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        let delay: TimeInterval
        init(name: String, delay: TimeInterval) { self.name = name; self.delay = delay }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            let target = paired
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                guard let copy = try? Packet.unpack(raw), let t = target else { return }
                t.inboundHandler?(copy, t)
            }
        }
    }

    func testInitiatorKeepsIdleLinkAliveWithinStaleWindow() throws {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["watchdog"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let aI = DelayedLoopbackInterface(name: "A", delay: 0.25)
        let bI = DelayedLoopbackInterface(name: "B", delay: 0.25)
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)

        let established = expectation(description: "established")
        aT.onLinkEstablished = { _ in established.fulfill() }

        let aLink = try Link.initiate(destination: bDest, transport: aT)
        // A slow first hop: the establishment deadline is far out. The defect
        // is that the watchdog's next tick was scheduled AT this deadline
        // while the link was still pending, with no 5 s cap.
        aLink.establishmentTimeout = 60

        wait(for: [established], timeout: 5.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])

        // Low-RTT link: keepalive floors at 5 s, stale time at 10 s
        // (RNS/Link.py:795-797). Set both sides so the responder's 0xFE echo
        // rate limit (keepalive interval) matches the initiator's cadence,
        // exactly as both sides measure on a local link.
        aLink.testSetRtt(0.001)
        bLink.testSetRtt(0.001)

        // Idle past the keepalive interval but inside the stale window.
        Thread.sleep(forTimeInterval: 7.5)

        XCTAssertNotNil(aLink.lastKeepalive,
            "initiator sent no keepalive within 7.5 s of an idle active link " +
            "(keepalive interval floors at 5 s; the watchdog slept until the " +
            "establishment deadline instead of Python's 5 s WATCHDOG_MAX_SLEEP cap)")
        XCTAssertEqual(aLink.status, .active,
            "idle healthy link did not stay active (torn down as stale without " +
            "a keepalive ever being sent)")
    }
}
