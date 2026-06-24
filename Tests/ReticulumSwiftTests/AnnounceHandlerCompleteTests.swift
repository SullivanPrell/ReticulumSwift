import XCTest
@testable import ReticulumSwift

/// Comprehensive tests for AnnounceHandler protocol dispatch.
final class AnnounceHandlerCompleteTests: XCTestCase {

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

    final class RecordingHandler: AnnounceHandler {
        var aspectFilter: String?
        var receivePathResponses: Bool = false
        var received: [(destinationHash: Data, identity: Identity, appData: Data?, isPathResponse: Bool)] = []

        func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?,
                              announcePacketHash: Data, isPathResponse: Bool) {
            received.append((destinationHash, identity, appData, isPathResponse))
        }
    }

    // MARK: - Filter by aspect

    func testHandlerWithNilFilterReceivesAllAnnounces() throws {
        let (tA, tB, _, _) = makeTransports()
        let handler = RecordingHandler()
        handler.aspectFilter = nil
        tA.register(announceHandler: handler)

        let bId = Identity()
        let bDest1 = try Destination(identity: bId, direction: .in, kind: .single,
                                     appName: "app1", aspects: [])
        let bDest2 = try Destination(identity: bId, direction: .in, kind: .single,
                                     appName: "app2", aspects: [])

        try tB.announce(destination: bDest1)
        try tB.announce(destination: bDest2)

        XCTAssertEqual(handler.received.count, 2, "nil filter should receive all announces")
        _ = (tA, tB)
    }

    func testHandlerWithAspectFilterOnlyReceivesMatching() throws {
        let (tA, tB, _, _) = makeTransports()
        let handler = RecordingHandler()
        handler.aspectFilter = "lxmf.delivery"
        tA.register(announceHandler: handler)

        let bId = Identity()
        let lxmfDest = try Destination(identity: bId, direction: .in, kind: .single,
                                       appName: "lxmf", aspects: ["delivery"])
        let otherDest = try Destination(identity: bId, direction: .in, kind: .single,
                                        appName: "other", aspects: ["service"])

        try tB.announce(destination: lxmfDest)
        try tB.announce(destination: otherDest)

        XCTAssertEqual(handler.received.count, 1, "filter should only pass matching destination")
        XCTAssertEqual(handler.received.first?.destinationHash, lxmfDest.hash)
        _ = (tA, tB)
    }

    // MARK: - receive_path_responses

    func testPathResponsesBlockedByDefault() throws {
        let (tA, tB, aIface, _) = makeTransports()
        let handler = RecordingHandler()
        handler.aspectFilter = nil
        handler.receivePathResponses = false
        tA.register(announceHandler: handler)

        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: [])

        // Inject a path-response announce directly on A's interface
        var packet = try Announce.make(for: bDest)
        packet = Packet(headerType: packet.headerType, contextFlag: packet.contextFlag,
                        transportType: packet.transportType, destinationType: packet.destinationType,
                        packetType: packet.packetType, hops: packet.hops,
                        destinationHash: packet.destinationHash,
                        context: .pathResponse, data: packet.data)

        aIface.inboundHandler?(packet, aIface)

        XCTAssertEqual(handler.received.count, 0, "path responses should be blocked by default")
        _ = (tA, tB)
    }

    func testPathResponsesAllowedWhenOptedIn() throws {
        let (tA, tB, aIface, _) = makeTransports()
        let handler = RecordingHandler()
        handler.aspectFilter = nil
        handler.receivePathResponses = true
        tA.register(announceHandler: handler)

        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["pr"])

        // Inject a path-response announce directly
        var packet = try Announce.make(for: bDest)
        packet = Packet(headerType: packet.headerType, contextFlag: packet.contextFlag,
                        transportType: packet.transportType, destinationType: packet.destinationType,
                        packetType: packet.packetType, hops: packet.hops,
                        destinationHash: packet.destinationHash,
                        context: .pathResponse, data: packet.data)

        aIface.inboundHandler?(packet, aIface)

        XCTAssertEqual(handler.received.count, 1, "opted-in handler should receive path responses")
        XCTAssertTrue(handler.received.first?.isPathResponse ?? false)
        _ = (tA, tB)
    }

    // MARK: - Deregister

    func testDeregisterStopsDispatching() throws {
        let (tA, tB, _, _) = makeTransports()
        let handler = RecordingHandler()
        tA.register(announceHandler: handler)
        tA.deregister(announceHandler: handler)

        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["dereg"])
        try tB.announce(destination: bDest)

        XCTAssertEqual(handler.received.count, 0, "deregistered handler should not receive")
        _ = (tA, tB)
    }

    // MARK: - Helpers

    struct Transports { let a: Transport; let b: Transport; let aIface: LoopbackInterface; let bIface: LoopbackInterface }

    private func makeTransports() -> (Transport, Transport, LoopbackInterface, LoopbackInterface) {
        let a = Transport(); let b = Transport()
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        a.register(interface: aI); b.register(interface: bI)
        return (a, b, aI, bI)
    }
}

