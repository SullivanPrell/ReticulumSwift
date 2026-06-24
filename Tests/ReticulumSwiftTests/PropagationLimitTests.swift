import XCTest
@testable import ReticulumSwift

/// Tests for propagation limit (hop count enforcement).
/// Python: Transport.PATHFINDER_M = 128 max hops.
final class PropagationLimitTests: XCTestCase {

    final class CapturingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    func testPropagationLimitDefault() {
        // Python: PATHFINDER_M = 128
        let t = Transport()
        XCTAssertEqual(t.propagationLimit, 128)
    }

    func testAnnounceWithMaxHopsNotForwarded() throws {
        let t = Transport()
        t.transportEnabled = true

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["hoplimit"])

        let in1 = CapturingInterface(name: "in1")
        let out = CapturingInterface(name: "out")
        t.register(interface: in1)
        t.register(interface: out)

        // Announce with hops = propagationLimit (128) should NOT be forwarded
        let packet = try Announce.make(for: dest)
        var maxHopPacket = packet
        maxHopPacket.hops = UInt8(t.propagationLimit)

        in1.inboundHandler?(maxHopPacket, in1)

        let forwarded = out.sent.filter { $0.packetType == .announce }
        XCTAssertEqual(forwarded.count, 0, "announce at max hops should not be forwarded")
    }

    func testAnnounceJustBelowMaxHopsIsForwarded() throws {
        let t = Transport()
        t.transportEnabled = true

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["belowmax"])

        let in1 = CapturingInterface(name: "in1")
        let out = CapturingInterface(name: "out")
        t.register(interface: in1)
        t.register(interface: out)

        let packet = try Announce.make(for: dest)
        var nearMaxPacket = packet
        nearMaxPacket.hops = UInt8(t.propagationLimit - 1)

        in1.inboundHandler?(nearMaxPacket, in1)

        // This should be forwarded (with hops + 1 = max, but still < limit on arrival)
        let forwarded = out.sent.filter { $0.packetType == .announce }
        XCTAssertGreaterThan(forwarded.count, 0, "announce below max hops should be forwarded")
    }

    func testDataPacketAtHopLimitDropped() throws {
        let t = Transport()
        t.transportEnabled = true

        let destHash = Data(repeating: 0xAA, count: 16)
        t.restore(path: Transport.PathEntry(
            destinationHash: destHash,
            nextHopInterfaceName: "out",
            hops: 1,
            lastHeard: Date(),
            identityHash: Data(repeating: 0x00, count: 16)
        ), forDestination: destHash)

        let in1 = CapturingInterface(name: "in1")
        let out = CapturingInterface(name: "out")
        t.register(interface: in1)
        t.register(interface: out)

        var packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: destHash,
            data: Data(count: 10)
        )
        packet.hops = UInt8(t.propagationLimit)  // at the limit

        in1.inboundHandler?(packet, in1)

        // Should be dropped (forwarding would exceed limit)
        XCTAssertEqual(out.sent.count, 0, "packet at hop limit should not be forwarded")
    }
}
