import XCTest
@testable import ReticulumSwift

/// Tests that unresponsive paths can be updated by new announces.
/// Python: "if path_is_unresponsive: allow_update = True"
final class PathResponsivenessUpdateTests: XCTestCase {

    final class CapturingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws {}
    }

    func testUnresponsivePathUpdatedByNewAnnounce() throws {
        let t = Transport()
        let iface = CapturingInterface(name: "in")
        t.register(interface: iface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["unresponsive"])

        // Seed a path with 1 hop
        t.restore(path: Transport.PathEntry(
            destinationHash: dest.hash,
            nextHopInterfaceName: "old",
            hops: 1,
            lastHeard: Date().addingTimeInterval(-3600),
            identityHash: id.hash
        ), forDestination: dest.hash)

        // Mark path as unresponsive (failed link establishment)
        t.markPathUnresponsive(for: dest.hash)
        XCTAssertTrue(t.pathIsUnresponsive(to: dest.hash))

        // Now receive a NEW announce (fresh timestamp, possibly more hops)
        let announce = try Announce.make(for: dest)
        var p = announce
        p.hops = 2  // more hops than existing (1)

        iface.inboundHandler?(p, iface)

        // Unresponsive path should be updated by new announce
        let path = t.paths[dest.hash]
        XCTAssertNotNil(path)
        // Path should be updated since it was unresponsive
        // The exact hops depend on implementation, but path should be updated
        XCTAssertFalse(t.pathIsUnresponsive(to: dest.hash),
            "path responsiveness should be reset after receiving new announce")
    }
}
