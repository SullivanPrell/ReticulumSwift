import XCTest
@testable import ReticulumSwift

/// A transport node must forward an announce only when it would update its path
/// table (Python forwards inside `if should_add:`). SINGLE announces bypass the
/// packet-hash dedup filter, so without this gate a duplicate announce would be
/// re-forwarded on every arrival — an announce storm on shared media.
final class AnnounceForwardDedupTests: XCTestCase {

    final class RecordingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    func testDuplicateAnnounceIsNotReforwarded() throws {
        let t = Transport()
        t.transportEnabled = true
        let inbound = RecordingInterface(name: "in")
        let outbound = RecordingInterface(name: "out")
        t.register(interface: inbound)
        t.register(interface: outbound)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["dedup"])
        let announce = try Announce.make(for: dest)

        // First arrival → forwarded once.
        inbound.inboundHandler?(announce, inbound)
        XCTAssertEqual(outbound.sent.count, 1, "fresh announce should be forwarded once")

        // Same announce again (same random blob) → must NOT be re-forwarded.
        inbound.inboundHandler?(announce, inbound)
        XCTAssertEqual(outbound.sent.count, 1, "duplicate announce must not be re-forwarded")
    }

    func testFreshReannounceIsForwardedAgain() throws {
        let t = Transport()
        t.transportEnabled = true
        let inbound = RecordingInterface(name: "in")
        let outbound = RecordingInterface(name: "out")
        t.register(interface: inbound)
        t.register(interface: outbound)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["reannounce"])

        inbound.inboundHandler?(try Announce.make(for: dest), inbound)
        XCTAssertEqual(outbound.sent.count, 1)

        // A genuinely new announce (fresh random blob) is forwarded again.
        inbound.inboundHandler?(try Announce.make(for: dest), inbound)
        XCTAssertEqual(outbound.sent.count, 2, "a fresh re-announce should be forwarded again")
    }
}
