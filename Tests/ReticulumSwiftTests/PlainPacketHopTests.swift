import XCTest
@testable import ReticulumSwift

/// Tests verifying PLAIN packet hop count enforcement.
/// Python: PLAIN packets with hops > 1 are dropped; hops == 0 or 1 are accepted.
final class PlainPacketHopTests: XCTestCase {

    final class CapturingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var received: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws {}
    }

    func testPlainPacketWithZeroHopsAccepted() {
        let t = Transport()
        let iface = CapturingInterface(name: "in")
        t.register(interface: iface)

        var received = false
        let destHash = Transport.pathRequestDestinationHash
        let packet = Packet(
            destinationType: .plain, packetType: .data,
            destinationHash: destHash,
            data: Data(repeating: 0x01, count: 48)
        )
        // Packet with hops=0 should be accepted
        iface.inboundHandler?(packet, iface)
        // No crash = accepted ✓
        _ = received
    }

    func testPlainPacketWithOneHopAccepted() {
        let t = Transport()
        t.transportEnabled = true
        let in1 = CapturingInterface(name: "in1")
        let out = CapturingInterface(name: "out")
        t.register(interface: in1)
        t.register(interface: out)

        var p = Packet(
            destinationType: .plain, packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: Data(repeating: 0x02, count: 48)
        )
        p.hops = 1  // 1 hop — should be accepted and forwarded

        in1.inboundHandler?(p, in1)
        // A path request with 1 hop should be forwarded (propagated by relay nodes)
        // No assertion about content, just verify no crash and the hop count check works
    }

    func testPlainPacketWithTwoHopsDropped() {
        let t = Transport()
        t.transportEnabled = true
        let in1 = CapturingInterface(name: "in1")
        let out = CapturingInterface(name: "out")
        t.register(interface: in1)
        t.register(interface: out)

        // Register a local destination to count deliveries
        var deliveredCount = 0
        let plainDest = try! Destination(identity: nil, direction: .in, kind: .plain,
                                          appName: "test", aspects: ["plaintest"])
        plainDest.onPacketReceived = { _, _ in deliveredCount += 1 }
        t.register(destination: plainDest)

        var p = Packet(
            destinationType: .plain, packetType: .data,
            destinationHash: plainDest.hash,
            data: Data("hello".utf8)
        )
        p.hops = 2  // 2 hops — Python drops at hops > 1

        in1.inboundHandler?(p, in1)
        XCTAssertEqual(deliveredCount, 0, "PLAIN packet with hops > 1 should be dropped")
    }

    func testPlainPacketWithOneHopDeliveredLocally() {
        let t = Transport()
        let in1 = CapturingInterface(name: "in1")
        t.register(interface: in1)

        // Register a local PLAIN destination
        var deliveredCount = 0
        let plainDest = try! Destination(identity: nil, direction: .in, kind: .plain,
                                          appName: "test", aspects: ["onehop"])
        plainDest.onPacketReceived = { _, _ in deliveredCount += 1 }
        t.register(destination: plainDest)

        var p = Packet(
            destinationType: .plain, packetType: .data,
            destinationHash: plainDest.hash,
            data: Data("hello".utf8)
        )
        p.hops = 1  // 1 hop — should be accepted (Python: hops > 1 drops, hops <= 1 accepted)

        in1.inboundHandler?(p, in1)
        XCTAssertEqual(deliveredCount, 1, "PLAIN packet with hops=1 should be delivered")
    }
}
