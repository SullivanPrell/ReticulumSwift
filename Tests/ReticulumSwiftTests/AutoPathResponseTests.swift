import XCTest
@testable import ReticulumSwift

/// Tests for automatic path response generation when a path request arrives
/// for a locally registered destination. Mirrors Python's
/// Transport.path_request_handler → destination.announce(path_response=True).
final class AutoPathResponseTests: XCTestCase {

    final class RecordingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        weak var paired: RecordingInterface?
        var mode: InterfaceMode = .full
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    func testPathRequestForLocalDestinationGeneratesPathResponse() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["autopr"])
        t.ownerIdentity = id
        t.register(destination: dest)

        let iface = RecordingInterface(name: "req")
        t.register(interface: iface)

        // Construct a path request for dest.hash
        let pathRequestBody = dest.hash + t.transportInstanceID + Data(repeating: 0x42, count: 16)
        let pathReq = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: pathRequestBody
        )

        // Inject the path request
        iface.inboundHandler?(pathReq, iface)

        // Transport should automatically reply with a path response announce
        let responses = iface.sent.filter { $0.packetType == .announce && $0.context == .pathResponse }
        XCTAssertGreaterThan(responses.count, 0,
            "local destination should auto-respond to path request with path response announce")

        // Validate the response announce
        if let response = responses.first {
            let decoded = try Announce.validate(response)
            XCTAssertEqual(decoded.destinationHash, dest.hash)
            XCTAssertTrue(decoded.isPathResponse)
        }
    }

    func testPathRequestForUnknownDestinationPropagatesToOtherInterfaces() throws {
        let t = Transport()
        t.transportEnabled = true

        let iface1 = RecordingInterface(name: "req")
        iface1.mode = .gateway  // DISCOVER_PATHS_FOR: gateway triggers discovery propagation
        let iface2 = RecordingInterface(name: "fwd")
        t.register(interface: iface1)
        t.register(interface: iface2)

        let unknownHash = Data(repeating: 0xBB, count: 16)
        let pathRequestBody = unknownHash + t.transportInstanceID + Data(repeating: 0x11, count: 16)
        let pathReq = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: pathRequestBody
        )

        iface1.inboundHandler?(pathReq, iface1)

        // Should be forwarded to iface2 (not back to iface1)
        let forwarded = iface2.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        XCTAssertGreaterThan(forwarded.count, 0, "unknown path request should be propagated")
    }
}
