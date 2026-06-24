import XCTest
@testable import ReticulumSwift

final class Header2BindingTests: XCTestCase {

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

    func testForwardedAnnounceIsHeader2WithRelayTransportID() throws {
        let relay = Transport()
        let inIface = RecordingInterface(name: "in")
        let outIface = RecordingInterface(name: "out")
        let inPair = RecordingInterface(name: "inPair")
        let outPair = RecordingInterface(name: "outPair")
        inIface.paired = inPair; inPair.paired = inIface
        outIface.paired = outPair; outPair.paired = outIface
        relay.register(interface: inIface)
        relay.register(interface: outIface)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "lxmf"
        )
        let announce = try Announce.make(for: destination)
        try inPair.send(announce)

        // Relay rebroadcasts on outIface as HEADER_2 with its own
        // transport ID stamped into the packet.
        XCTAssertEqual(outIface.sent.count, 1)
        let forwarded = try XCTUnwrap(outIface.sent.first)
        XCTAssertEqual(forwarded.headerType, .type2)
        XCTAssertEqual(forwarded.transportID, relay.transportInstanceID)
        XCTAssertEqual(forwarded.hops, 1)
    }

    func testReceivedHeader2AnnounceIsRecordedAsNextHopTransportID() throws {
        // Simulate: an upstream relay (with a known transportID) sends a
        // HEADER_2 announce to us. We should learn its transport ID into
        // the path entry.
        let receiver = Transport()
        let iface = RecordingInterface(name: "edge")
        let pair = RecordingInterface(name: "pair")
        iface.paired = pair; pair.paired = iface
        receiver.register(interface: iface)

        let upstreamID = Data(repeating: 0x42, count: Constants.truncatedHashLength)
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "lxmf"
        )
        var announce = try Announce.make(for: destination)
        announce.headerType = .type2
        announce.transportID = upstreamID
        announce.hops = 2

        try pair.send(announce)

        let path = try XCTUnwrap(receiver.paths[destination.hash])
        XCTAssertEqual(path.nextHopTransportID, upstreamID)
        XCTAssertEqual(path.hops, 2)
    }

    func testForwardedDataPacketStampsNextHopTransportID() throws {
        // Relay knows a path (via prior announce) where next-hop
        // transport ID is X. When a non-local data packet arrives for
        // that destination, the relay rewrites HEADER_2 with X.
        let relay = Transport()
        let inIface = RecordingInterface(name: "in")
        let outIface = RecordingInterface(name: "out")
        let inPair = RecordingInterface(name: "inPair")
        let outPair = RecordingInterface(name: "outPair")
        inIface.paired = inPair; inPair.paired = inIface
        outIface.paired = outPair; outPair.paired = outIface
        relay.register(interface: inIface)
        relay.register(interface: outIface)

        let nextHopID = Data(repeating: 0xAB, count: Constants.truncatedHashLength)
        let destHash = Hashes.truncatedHash(Data("dest".utf8))
        relay.restore(
            path: Transport.PathEntry(
                destinationHash: destHash,
                nextHopInterfaceName: outIface.name,
                hops: 1,
                lastHeard: Date(),
                identityHash: Data(repeating: 0, count: Constants.truncatedHashLength),
                nextHopTransportID: nextHopID
            ),
            forDestination: destHash
        )

        let pkt = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: destHash,
            data: Data("hi".utf8)
        )
        try inPair.send(pkt)

        XCTAssertEqual(outIface.sent.count, 1)
        let forwarded = try XCTUnwrap(outIface.sent.first)
        XCTAssertEqual(forwarded.headerType, .type2)
        XCTAssertEqual(forwarded.transportID, nextHopID)
    }
}
