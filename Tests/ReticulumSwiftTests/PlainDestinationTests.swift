import XCTest
@testable import ReticulumSwift

/// Tests verifying PLAIN destination behavior matches Python's protocol.
/// Python: PLAIN packets are NOT transported over multiple hops.
final class PlainDestinationTests: XCTestCase {

    final class RecordingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        weak var paired: RecordingInterface?
        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {
            sent.append(packet)
            if let raw = try? packet.pack(), let copy = try? Packet.unpack(raw) {
                paired?.inboundHandler?(copy, paired!)
            }
        }
    }

    func testPlainDestinationPacketNotForwarded() throws {
        let t = Transport()
        t.transportEnabled = true

        let in1 = RecordingInterface(name: "in1")
        let out = RecordingInterface(name: "out")
        t.register(interface: in1)
        t.register(interface: out)

        // Create a PLAIN destination packet
        let plainDest = try Destination(identity: nil, direction: .in, kind: .plain,
                                        appName: "broadcast", aspects: ["test"])
        let packet = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: plainDest.hash,
            data: Data("broadcast".utf8)
        )

        // Seed a path so R would try to forward (if it had the wrong behavior)
        t.restore(
            path: Transport.PathEntry(
                destinationHash: plainDest.hash,
                nextHopInterfaceName: out.name,
                hops: 1,
                lastHeard: Date(),
                identityHash: Data(repeating: 0x00, count: 16)
            ),
            forDestination: plainDest.hash
        )

        // Inject on in1
        in1.inboundHandler?(packet, in1)

        // out should NOT receive the packet (PLAIN not forwarded over multiple hops)
        let forwardedData = out.sent.filter { $0.destinationType == .plain }
        XCTAssertEqual(forwardedData.count, 0, "PLAIN destination packets must NOT be forwarded")
    }

    func testSingleDestinationPacketIsForwarded() throws {
        let t = Transport()
        t.transportEnabled = true

        let in1 = RecordingInterface(name: "in1")
        let out = RecordingInterface(name: "out")
        in1.paired = out; out.paired = in1
        t.register(interface: in1)
        t.register(interface: out)

        let destHash = Data(repeating: 0xAA, count: 16)
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: destHash,
            data: Data(repeating: 0x00, count: 10)
        )

        t.restore(
            path: Transport.PathEntry(
                destinationHash: destHash,
                nextHopInterfaceName: out.name,
                hops: 1,
                lastHeard: Date(),
                identityHash: Data(repeating: 0x11, count: 16)
            ),
            forDestination: destHash
        )

        in1.inboundHandler?(packet, in1)

        let forwarded = out.sent.filter { $0.destinationType == .single }
        XCTAssertGreaterThan(forwarded.count, 0, "SINGLE destination packets should be forwarded")
    }
}
