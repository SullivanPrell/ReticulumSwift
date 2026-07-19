import XCTest
@testable import ReticulumSwift

/// Announce-replay protection via per-path random blobs.
///
/// SINGLE announces are exempt from the packet-hash dedup filter (so paths can
/// update via multiple routes), which means a captured announce can be replayed
/// into the announce handler. Python guards every `should_add` branch with
/// `if not random_blob in random_blobs`, recording each accepted announce's
/// 10-byte random blob so a replay can't forge or move a path.
final class AnnounceReplayProtectionTests: XCTestCase {

    final class NamedInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws {}
    }

    func testReplayedAnnounceDoesNotMovePath() throws {
        let t = Transport()
        let iface1 = NamedInterface(name: "iface1")
        let iface2 = NamedInterface(name: "iface2")
        t.register(interface: iface1)
        t.register(interface: iface2)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["replay"])

        // Legitimate announce arrives on iface1 → path points to iface1.
        let announce = try Announce.make(for: dest)
        iface1.inboundHandler?(announce, iface1)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "iface1")

        // The SAME announce (same random blob) replayed on iface2 must be
        // rejected — the path must NOT move to the replay interface.
        iface2.inboundHandler?(announce, iface2)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "iface1",
            "replayed announce (already-seen random blob) must not move the path")
    }

    func testFreshAnnounceStillUpdatesPath() throws {
        let t = Transport()
        let iface1 = NamedInterface(name: "iface1")
        let iface2 = NamedInterface(name: "iface2")
        t.register(interface: iface1)
        t.register(interface: iface2)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["fresh"])

        let t0 = Date().timeIntervalSince1970
        let first = try Announce.make(for: dest, timestamp: t0)
        iface1.inboundHandler?(first, iface1)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "iface1")

        // A genuinely new announce (fresh random blob) from the same source on
        // iface2 is a legitimate re-announce / move and MUST update the path. It is
        // emitted later, so it carries a strictly newer timestamp (the freshness
        // gate would tie a same-second announce and keep the first-heard path).
        let second = try Announce.make(for: dest, timestamp: t0 + 2)
        iface2.inboundHandler?(second, iface2)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "iface2",
            "a fresh announce with a new random blob must still update the path")
    }
}
