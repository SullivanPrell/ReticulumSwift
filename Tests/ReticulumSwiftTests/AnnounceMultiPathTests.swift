import XCTest
@testable import ReticulumSwift

/// Path-table behavior when the *same* announce arrives via multiple paths.
///
/// SINGLE announces bypass the packet-hash dedup filter (so paths can update via
/// multiple routes), but Python's per-path `random_blobs` guard means a node
/// keeps the FIRST-heard path for a given announce: a later copy of the *same*
/// announce (identical random blob) is rejected regardless of hop count — this
/// is the announce replay/loop protection. Hop-count optimization happens across
/// DIFFERENT announces (the source re-announces periodically), not within a
/// single announce flood.
final class AnnounceMultiPathTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { }
    }

    /// The same announce (same random blob) arriving later via a fewer-hops path
    /// must NOT replace the first-heard path. Mirrors Python's `random_blobs`
    /// guard (`if not random_blob in random_blobs` is false → should_add=False).
    func testSameAnnounceKeepsFirstHeardPath() throws {
        let t = Transport()
        t.transportEnabled = true

        let if1 = LoopbackInterface(name: "if1")
        let if2 = LoopbackInterface(name: "if2")
        t.register(interface: if1)
        t.register(interface: if2)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["multipath"])

        let packet = try Announce.make(for: dest)

        // First arrival: 3 hops via if1.
        var p3 = packet; p3.hops = 3
        if1.inboundHandler?(p3, if1)
        XCTAssertEqual(t.hopsTo(dest.hash), 3, "initial path should be 3 hops")

        // Second arrival: 1 hop via if2 — but it's the SAME announce (same blob),
        // so it is rejected as a replay and the first-heard path is kept.
        var p1 = packet; p1.hops = 1
        if2.inboundHandler?(p1, if2)
        XCTAssertEqual(t.hopsTo(dest.hash), 3,
            "a replayed copy of the same announce must not move/optimize the path")
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "if1")
    }

    /// A genuinely different announce (fresh random blob) with fewer hops IS a
    /// legitimate re-announce and must optimize the path.
    func testFreshAnnounceWithFewerHopsOptimizesPath() throws {
        let t = Transport()
        t.transportEnabled = true

        let if1 = LoopbackInterface(name: "if1")
        let if2 = LoopbackInterface(name: "if2")
        t.register(interface: if1)
        t.register(interface: if2)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["reannounce"])

        let t0 = Date().timeIntervalSince1970
        var first = try Announce.make(for: dest, timestamp: t0); first.hops = 3
        if1.inboundHandler?(first, if1)
        XCTAssertEqual(t.hopsTo(dest.hash), 3)

        // A fresh announce (new random blob) at 1 hop optimizes the path. A genuine
        // re-announce is emitted later, so it carries a strictly newer timestamp —
        // required by the freshness gate (a same-second announce would tie).
        var second = try Announce.make(for: dest, timestamp: t0 + 2); second.hops = 1
        if2.inboundHandler?(second, if2)
        XCTAssertEqual(t.hopsTo(dest.hash), 1,
            "a fresh announce with fewer hops should update to the better path")
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "if2")
    }
}
