import XCTest
@testable import ReticulumSwift

/// Cluster B + D2 — the path-table freshness gate.
///
/// Ports Python's `should_add` ladder (Transport.inbound, Transport.py:1801-1875)
/// exactly. The invariant: an announce only replaces an existing path when it is
/// genuinely NEWER (emission second strictly greater than the max emission across
/// the path's recorded random blobs), or when it is the same announce arriving via
/// an alternate route to revive a path previously marked unresponsive. Emission
/// timestamps are second-resolution, so same-second announces tie and neither
/// displaces the other; hop-count convergence happens across successive (later)
/// announces, not within one announce flood.
final class PathFreshnessGateTests: XCTestCase {

    final class NamedInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws {}
    }

    /// Fixed base emission second so timestamps are deterministic and controllable.
    private let baseTime: TimeInterval = 1_700_000_000

    // MARK: - Freshness gate (B1/B2/B3)

    /// A fewer-hop announce emitted in the SAME second as the existing path must
    /// NOT replace it. (Old "fewer hops always wins" behavior — the bug.)
    func testSameSecondFewerHopsDoesNotReplace() throws {
        let t = Transport()
        let a = NamedInterface(name: "A"); let b = NamedInterface(name: "B")
        t.register(interface: a); t.register(interface: b)
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["same-second"])

        var first = try Announce.make(for: dest, timestamp: baseTime); first.hops = 3
        a.inboundHandler?(first, a)
        XCTAssertEqual(t.hopsTo(dest.hash), 3)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "A")

        // Different announce (new blob), fewer hops, SAME second → rejected.
        var second = try Announce.make(for: dest, timestamp: baseTime); second.hops = 1
        b.inboundHandler?(second, b)
        XCTAssertEqual(t.hopsTo(dest.hash), 3,
            "a same-second fewer-hop announce must not replace the existing path")
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "A")
    }

    /// A fewer-hop announce emitted in a LATER second is a genuine re-announce and
    /// must optimize the path.
    func testLaterEmissionFewerHopsReplaces() throws {
        let t = Transport()
        let a = NamedInterface(name: "A"); let b = NamedInterface(name: "B")
        t.register(interface: a); t.register(interface: b)
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["later"])

        var first = try Announce.make(for: dest, timestamp: baseTime); first.hops = 3
        a.inboundHandler?(first, a)
        XCTAssertEqual(t.hopsTo(dest.hash), 3)

        var second = try Announce.make(for: dest, timestamp: baseTime + 2); second.hops = 1
        b.inboundHandler?(second, b)
        XCTAssertEqual(t.hopsTo(dest.hash), 1,
            "a later-emitted fewer-hop announce should optimize the path")
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "B")
    }

    /// More hops but a strictly newer emission replaces (the source route changed).
    func testMoreHopsNewerEmissionReplaces() throws {
        let t = Transport()
        let a = NamedInterface(name: "A"); let b = NamedInterface(name: "B")
        t.register(interface: a); t.register(interface: b)
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["morehops-newer"])

        var first = try Announce.make(for: dest, timestamp: baseTime); first.hops = 2
        a.inboundHandler?(first, a)
        XCTAssertEqual(t.hopsTo(dest.hash), 2)

        var second = try Announce.make(for: dest, timestamp: baseTime + 5); second.hops = 4
        b.inboundHandler?(second, b)
        XCTAssertEqual(t.hopsTo(dest.hash), 4,
            "a more-hops but newer announce should replace the path")
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "B")
    }

    /// More hops AND an older emission is ignored (a stale announce arriving late).
    func testMoreHopsOlderEmissionRejected() throws {
        let t = Transport()
        let a = NamedInterface(name: "A"); let b = NamedInterface(name: "B")
        t.register(interface: a); t.register(interface: b)
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["morehops-older"])

        var first = try Announce.make(for: dest, timestamp: baseTime + 5); first.hops = 2
        a.inboundHandler?(first, a)
        XCTAssertEqual(t.hopsTo(dest.hash), 2)

        var second = try Announce.make(for: dest, timestamp: baseTime); second.hops = 4
        b.inboundHandler?(second, b)
        XCTAssertEqual(t.hopsTo(dest.hash), 2,
            "a stale (older, more-hops) announce must not replace the path")
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "A")
    }

    // MARK: - Unresponsive revival (D2)

    /// The SAME announce (same blob, same emission second) arriving via a longer
    /// alternate route MUST revive a path that was marked unresponsive.
    func testSameBlobMoreHopsRevivesUnresponsivePath() throws {
        let t = Transport()
        let a = NamedInterface(name: "A"); let b = NamedInterface(name: "B")
        t.register(interface: a); t.register(interface: b)
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["revive"])

        // Same announce instance carried over both routes (identical random blob).
        let announce = try Announce.make(for: dest, timestamp: baseTime)

        var viaA = announce; viaA.hops = 2
        a.inboundHandler?(viaA, a)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "A")
        XCTAssertEqual(t.hopsTo(dest.hash), 2)

        // Shorter route dies.
        t.markPathUnresponsive(for: dest.hash)
        XCTAssertTrue(t.pathIsUnresponsive(to: dest.hash))

        // The same announce arrives via the longer route B → revive onto B.
        var viaB = announce; viaB.hops = 3
        b.inboundHandler?(viaB, b)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "B",
            "an unresponsive path must be revived by the same announce via an alternate route")
        XCTAssertEqual(t.hopsTo(dest.hash), 3)
        XCTAssertFalse(t.pathIsUnresponsive(to: dest.hash),
            "responsiveness state should reset after the path is updated")
    }

    /// Control: while the path is RESPONSIVE, the same announce via a longer route
    /// must NOT move the path (the duplicate early-return handles it).
    func testSameBlobMoreHopsDoesNotReplaceResponsivePath() throws {
        let t = Transport()
        let a = NamedInterface(name: "A"); let b = NamedInterface(name: "B")
        t.register(interface: a); t.register(interface: b)
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["no-revive"])

        let announce = try Announce.make(for: dest, timestamp: baseTime)
        var viaA = announce; viaA.hops = 2
        a.inboundHandler?(viaA, a)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "A")

        var viaB = announce; viaB.hops = 3
        b.inboundHandler?(viaB, b)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "A",
            "a responsive path must not move to a longer route for the same announce")
        XCTAssertEqual(t.hopsTo(dest.hash), 2)
    }
}
