import XCTest
@testable import ReticulumSwift

/// A transport node retransmits each forwarded announce once more
/// (Python `PATHFINDER_R = 1`) after a grace period, unless it hears
/// neighbours carry the announce on (the "passed on" / local-rebroadcast
/// cancel). Mirrors Python's `Transport.announce_table` mechanism in
/// `Transport.jobs()` + the receive-side cancel in `Transport.inbound()`.
///
/// Swift keeps the immediate first forward (interop-safe, equivalent to
/// Python's first jobs-loop transmit, which always fires because the cancel
/// only applies once `retries > 0`) and layers the single retry on top via
/// `processAnnounceRetries(now:)`, which the jobs timer drives in production
/// and tests drive with an explicit clock.
final class AnnounceRetryTests: XCTestCase {

    final class RecordingInterface: Interface {
        var name: String; var bitrate: Int = 1_000_000; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    private func makeNode() -> (Transport, RecordingInterface, RecordingInterface) {
        let t = Transport()
        t.transportEnabled = true
        let inbound = RecordingInterface(name: "in")
        let outbound = RecordingInterface(name: "out")
        t.register(interface: inbound)
        t.register(interface: outbound)
        return (t, inbound, outbound)
    }

    private func makeAnnounce(_ aspect: String) throws -> (Packet, Data) {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [aspect])
        return (try Announce.make(for: dest), dest.hash)
    }

    /// After the immediate forward, exactly one retransmission fires once the
    /// grace period elapses; a further job pass does nothing (retry limit hit).
    func testRetransmitsOnceAfterGrace() throws {
        let (t, inbound, outbound) = makeNode()
        let (announce, _) = try makeAnnounce("retry")

        inbound.inboundHandler?(announce, inbound)
        XCTAssertEqual(outbound.sent.count, 1, "fresh announce forwarded immediately once")
        let firstHops = outbound.sent[0].hops

        // Before the grace window elapses, no retry.
        t.processAnnounceRetries(now: Date().timeIntervalSince1970)
        XCTAssertEqual(outbound.sent.count, 1, "no retry before the grace window")

        // After the grace window, exactly one retransmission.
        t.processAnnounceRetries(now: Date().timeIntervalSince1970 + 60)
        XCTAssertEqual(outbound.sent.count, 2, "one retransmission after grace (PATHFINDER_R=1)")
        XCTAssertEqual(outbound.sent[1].headerType, .type2, "retransmit is a HEADER_2 transport announce")
        XCTAssertEqual(outbound.sent[1].hops, firstHops, "retransmit carries the same hop count as the first forward")
        XCTAssertEqual(outbound.sent[1].transportID, t.transportInstanceID)

        // No further retries — the retry limit has been reached.
        t.processAnnounceRetries(now: Date().timeIntervalSince1970 + 120)
        XCTAssertEqual(outbound.sent.count, 2, "no further retransmissions beyond PATHFINDER_R")
    }

    /// Hearing the announce passed on by a downstream node (hops == stored+2)
    /// before our retry fires cancels the pending retransmission.
    func testPassedOnDownstreamCancelsRetry() throws {
        let (t, inbound, outbound) = makeNode()
        let (announce, _) = try makeAnnounce("passedon")

        inbound.inboundHandler?(announce, inbound)
        XCTAssertEqual(outbound.sent.count, 1)

        // A downstream node re-broadcast our forward one hop further on.
        var passedOn = announce
        passedOn.headerType = .type2
        passedOn.transportID = Data(repeating: 0xAB, count: 16)
        passedOn.hops = 2   // entry.hops(0) + 2
        inbound.inboundHandler?(passedOn, inbound)

        t.processAnnounceRetries(now: Date().timeIntervalSince1970 + 60)
        XCTAssertEqual(outbound.sent.count, 1, "retry cancelled after announce was passed on downstream")
    }

    /// Hearing LOCAL_REBROADCASTS_MAX sibling rebroadcasts (hops == stored+1)
    /// cancels the pending retransmission.
    func testLocalRebroadcastLimitCancelsRetry() throws {
        let (t, inbound, outbound) = makeNode()
        let (announce, _) = try makeAnnounce("localrb")

        inbound.inboundHandler?(announce, inbound)
        XCTAssertEqual(outbound.sent.count, 1)

        // Two sibling transport nodes at our own distance re-broadcast it.
        for _ in 0..<Transport.localRebroadcastsMax {
            var sibling = announce
            sibling.headerType = .type2
            sibling.transportID = Data(repeating: 0xCD, count: 16)
            sibling.hops = 1   // entry.hops(0) + 1
            inbound.inboundHandler?(sibling, inbound)
        }

        t.processAnnounceRetries(now: Date().timeIntervalSince1970 + 60)
        XCTAssertEqual(outbound.sent.count, 1, "retry cancelled after enough local rebroadcasts heard")
    }

    /// An edge (non-transport) node never schedules a retry — it does not
    /// forward announces at all.
    func testNonTransportNodeSchedulesNoRetry() throws {
        let t = Transport()
        t.transportEnabled = false
        let inbound = RecordingInterface(name: "in")
        let outbound = RecordingInterface(name: "out")
        t.register(interface: inbound)
        t.register(interface: outbound)

        let (announce, _) = try makeAnnounce("edge")
        inbound.inboundHandler?(announce, inbound)
        XCTAssertEqual(outbound.sent.count, 0, "edge node does not forward announces")

        t.processAnnounceRetries(now: Date().timeIntervalSince1970 + 60)
        XCTAssertEqual(outbound.sent.count, 0, "edge node schedules no retransmission")
    }
}
