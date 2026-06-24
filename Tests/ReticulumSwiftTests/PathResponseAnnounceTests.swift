import XCTest
@testable import ReticulumSwift

/// Tests for path response announces (announced in response to path requests).
/// Path response announces have context = .pathResponse and are NOT forwarded.
final class PathResponseAnnounceTests: XCTestCase {

    func testAnnounceWithPathResponseContext() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["pr"])

        let packet = try Announce.make(for: dest, isPathResponse: true)
        XCTAssertEqual(packet.context, .pathResponse, "path response announce must have .pathResponse context")
    }

    func testRegularAnnounceHasNoneContext() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["normal"])

        let packet = try Announce.make(for: dest)
        XCTAssertEqual(packet.context, .none, "regular announce must have .none context")
    }

    func testPathResponseAnnounceValidates() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["prval"])

        let packet = try Announce.make(for: dest, isPathResponse: true)
        let decoded = try Announce.validate(packet)
        XCTAssertTrue(decoded.isPathResponse)
        XCTAssertEqual(decoded.destinationHash, dest.hash)
    }

    func testTransportAnnounceWithPathResponseFlag() throws {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["transport"])
        t.ownerIdentity = id
        t.register(destination: dest)

        final class CapturingInterface: Interface {
            var name: String = "capture"; var bitrate: Int = 0; var isOnline: Bool = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            var sent: [Packet] = []
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws { sent.append(packet) }
        }

        let iface = CapturingInterface()
        t.register(interface: iface)

        try t.announce(destination: dest, isPathResponse: true)

        guard let sent = iface.sent.first(where: { $0.packetType == .announce }) else {
            return XCTFail("no announce sent")
        }
        XCTAssertEqual(sent.context, .pathResponse)
    }
}
