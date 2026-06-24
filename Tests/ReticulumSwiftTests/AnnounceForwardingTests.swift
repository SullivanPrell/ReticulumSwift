import XCTest
@testable import ReticulumSwift

final class AnnounceForwardingTests: XCTestCase {

    /// A loopback interface that records every outbound packet so a test
    /// can assert what the Transport sent through it.
    final class RecordingInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        weak var paired: RecordingInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []

        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            sent.append(packet)
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    func testAnnounceIsRelayedToOtherInterfacesWithIncrementedHops() throws {
        // Topology: A -> [Transport with two interfaces] -> C
        //           ifaceFromA  is the inbound side
        //           ifaceToC    is where the relay should appear
        let transport = Transport()

        let ifaceFromA = RecordingInterface(name: "fromA")
        let ifaceToC = RecordingInterface(name: "toC")
        let upstream = RecordingInterface(name: "upstream")  // pair for fromA
        let downstream = RecordingInterface(name: "downstream") // pair for toC
        ifaceFromA.paired = upstream; upstream.paired = ifaceFromA
        ifaceToC.paired = downstream; downstream.paired = ifaceToC

        transport.register(interface: ifaceFromA)
        transport.register(interface: ifaceToC)

        // Build a real announce on a separate identity, send it from
        // upstream so it arrives on ifaceFromA's inbound handler.
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single,
            appName: "lxmf", aspects: ["delivery"]
        )
        let announce = try Announce.make(for: destination, appData: Data("hi".utf8))
        try upstream.send(announce)

        XCTAssertEqual(ifaceToC.sent.count, 1)
        XCTAssertEqual(ifaceToC.sent.first?.packetType, .announce)
        XCTAssertEqual(ifaceToC.sent.first?.hops, 1)
        // Source-direction interface must NOT see the relay.
        XCTAssertEqual(ifaceFromA.sent.count, 0)
        // Path table records the destination via the inbound interface.
        XCTAssertEqual(transport.paths[destination.hash]?.nextHopInterfaceName, "fromA")
    }

    func testDuplicateAnnounceIsNotRelayed() throws {
        let transport = Transport()
        let ifaceFromA = RecordingInterface(name: "fromA")
        let ifaceToC = RecordingInterface(name: "toC")
        let upstream = RecordingInterface(name: "upstream")
        let downstream = RecordingInterface(name: "downstream")
        ifaceFromA.paired = upstream; upstream.paired = ifaceFromA
        ifaceToC.paired = downstream; downstream.paired = ifaceToC
        transport.register(interface: ifaceFromA)
        transport.register(interface: ifaceToC)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let announce = try Announce.make(for: destination)

        try upstream.send(announce)
        try upstream.send(announce)

        XCTAssertEqual(ifaceToC.sent.count, 1)
    }

    func testTransportDisabledNodeDoesNotForward() throws {
        let transport = Transport()
        transport.transportEnabled = false
        let ifaceFromA = RecordingInterface(name: "fromA")
        let ifaceToC = RecordingInterface(name: "toC")
        let upstream = RecordingInterface(name: "upstream")
        let downstream = RecordingInterface(name: "downstream")
        ifaceFromA.paired = upstream; upstream.paired = ifaceFromA
        ifaceToC.paired = downstream; downstream.paired = ifaceToC
        transport.register(interface: ifaceFromA)
        transport.register(interface: ifaceToC)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        try upstream.send(try Announce.make(for: destination))

        XCTAssertEqual(ifaceToC.sent.count, 0)
        // Path is still recorded — the node consumed the announce locally.
        XCTAssertNotNil(transport.paths[destination.hash])
    }

    func testHopLimitDropsForwarding() throws {
        let transport = Transport()
        transport.propagationLimit = 2
        let ifaceFromA = RecordingInterface(name: "fromA")
        let ifaceToC = RecordingInterface(name: "toC")
        let upstream = RecordingInterface(name: "upstream")
        let downstream = RecordingInterface(name: "downstream")
        ifaceFromA.paired = upstream; upstream.paired = ifaceFromA
        ifaceToC.paired = downstream; downstream.paired = ifaceToC
        transport.register(interface: ifaceFromA)
        transport.register(interface: ifaceToC)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        var announce = try Announce.make(for: destination)
        announce.hops = 2  // already at the limit
        try upstream.send(announce)

        XCTAssertEqual(ifaceToC.sent.count, 0)
    }
}
