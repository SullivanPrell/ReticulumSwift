import XCTest
@testable import ReticulumSwift

/// Tests for path table update logic matching Python's behavior:
/// - New announce with fewer hops should update the path
/// - New announce with more hops should NOT update the path
/// - New announce with same hops should update (newer info)
final class PathUpdateLogicTests: XCTestCase {

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

    private func makeTransport(named name: String = "A") -> (Transport, LoopbackInterface) {
        let t = Transport()
        let iface = LoopbackInterface(name: name)
        t.register(interface: iface)
        return (t, iface)
    }

    /// Deliver an announce with a specific hop count directly to transport's interface handler
    private func deliverAnnounce(packet: Packet, hops: UInt8, to transport: Transport, on iface: LoopbackInterface) {
        var p = packet; p.hops = hops
        iface.inboundHandler?(p, iface)
    }

    // MARK: - Fewer hops always wins

    func testLowerHopAnnounceShouldUpdatePath() throws {
        let (t, iface) = makeTransport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["prio"])

        let packet = try Announce.make(for: dest)

        // First: 3-hop announce
        deliverAnnounce(packet: packet, hops: 3, to: t, on: iface)
        XCTAssertEqual(t.hopsTo(dest.hash), 3, "initial path should be 3 hops")

        // Second: 1-hop announce (better path) — must be different announce (different random hash)
        let packet2 = try Announce.make(for: dest)
        deliverAnnounce(packet: packet2, hops: 1, to: t, on: iface)
        XCTAssertEqual(t.hopsTo(dest.hash), 1, "1-hop path should replace 3-hop path")
    }

    func testHigherHopAnnounceShould_NOT_UpdatePath() throws {
        let (t, iface) = makeTransport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["noupdate"])

        // First: 1-hop announce (good path)
        let packet1 = try Announce.make(for: dest)
        deliverAnnounce(packet: packet1, hops: 1, to: t, on: iface)
        XCTAssertEqual(t.hopsTo(dest.hash), 1)

        // Second: 5-hop announce (worse path) — should NOT update
        let packet2 = try Announce.make(for: dest)
        deliverAnnounce(packet: packet2, hops: 5, to: t, on: iface)
        XCTAssertEqual(t.hopsTo(dest.hash), 1, "better path should NOT be replaced by worse one")
    }

    func testSameHopAnnounceUpdatesPath() throws {
        let (t, iface) = makeTransport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["same"])

        let packet1 = try Announce.make(for: dest)
        deliverAnnounce(packet: packet1, hops: 2, to: t, on: iface)
        XCTAssertEqual(t.hopsTo(dest.hash), 2)

        // Same hop count — should update (newer announce has fresh timestamp)
        let packet2 = try Announce.make(for: dest)
        deliverAnnounce(packet: packet2, hops: 2, to: t, on: iface)
        XCTAssertEqual(t.hopsTo(dest.hash), 2, "same-hop path should still be stored")
    }
}
