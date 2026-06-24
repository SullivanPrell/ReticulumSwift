import XCTest
@testable import ReticulumSwift

/// Tests that path response announces are NOT forwarded to other interfaces.
/// Python: "if context != PATH_RESPONSE: forward to other interfaces"
final class PathResponseForwardingTests: XCTestCase {

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
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    func testRegularAnnounceIsForwarded() throws {
        let t = Transport()
        t.transportEnabled = true

        let in1 = RecordingInterface(name: "in1")
        let in2 = RecordingInterface(name: "in2")
        let out = RecordingInterface(name: "out")
        t.register(interface: in1)
        t.register(interface: in2)
        t.register(interface: out)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["fwd"])

        var packet = try Announce.make(for: dest)
        // Regular announce (not path response)
        XCTAssertNotEqual(packet.context, .pathResponse)

        // Inject on in1
        in1.inboundHandler?(packet, in1)

        // Should be forwarded to in2 and out (not back to in1)
        let sentNames = (in2.sent + out.sent).filter { $0.packetType == .announce }
        XCTAssertGreaterThan(sentNames.count, 0, "regular announce should be forwarded")
    }

    func testPathResponseAnnounceIsNOTForwarded() throws {
        let t = Transport()
        t.transportEnabled = true

        let in1 = RecordingInterface(name: "in1")
        let in2 = RecordingInterface(name: "in2")
        let out = RecordingInterface(name: "out")
        t.register(interface: in1)
        t.register(interface: in2)
        t.register(interface: out)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["nofwd"])

        var packet = try Announce.make(for: dest)
        // Make it a path response
        packet = Packet(
            headerType: packet.headerType, contextFlag: packet.contextFlag,
            transportType: packet.transportType, destinationType: packet.destinationType,
            packetType: packet.packetType, hops: packet.hops,
            destinationHash: packet.destinationHash,
            context: .pathResponse, data: packet.data
        )

        // Inject path response on in1
        in1.inboundHandler?(packet, in1)

        // Should NOT be forwarded to in2 or out
        let forwarded = (in2.sent + out.sent).filter { $0.packetType == .announce }
        XCTAssertEqual(forwarded.count, 0, "path response announce must NOT be forwarded")
    }
}
