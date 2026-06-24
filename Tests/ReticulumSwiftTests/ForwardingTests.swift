import XCTest
@testable import ReticulumSwift

final class ForwardingTests: XCTestCase {

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

    /// A relay node with two interfaces: one toward the source, one toward
    /// a known destination. Returns the relay transport plus its source
    /// and destination side recording interfaces (the *paired* sides
    /// dummy-stand in for upstream/downstream nodes).
    func makeRelay(destination: Data) -> (
        relay: Transport,
        sourceSide: RecordingInterface,
        destSide: RecordingInterface,
        upstream: RecordingInterface,
        downstream: RecordingInterface
    ) {
        let relay = Transport()
        let sourceSide = RecordingInterface(name: "src")
        let destSide = RecordingInterface(name: "dst")
        let upstream = RecordingInterface(name: "up")
        let downstream = RecordingInterface(name: "down")
        sourceSide.paired = upstream; upstream.paired = sourceSide
        destSide.paired = downstream; downstream.paired = destSide
        relay.register(interface: sourceSide)
        relay.register(interface: destSide)

        // Pre-seed the path table so the relay knows to send dst-bound
        // packets out destSide.
        relay.restore(
            path: Transport.PathEntry(
                destinationHash: destination,
                nextHopInterfaceName: destSide.name,
                hops: 1,
                lastHeard: Date(),
                identityHash: Data(repeating: 0, count: 16)
            ),
            forDestination: destination
        )
        return (relay, sourceSide, destSide, upstream, downstream)
    }

    func testDataPacketForwardedToNextHopWithIncrementedHops() throws {
        let destHash = Hashes.truncatedHash(Data("dst".utf8))
        let r = makeRelay(destination: destHash)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            hops: 0,
            destinationHash: destHash,
            data: Data("payload".utf8)
        )
        try r.upstream.send(packet)

        XCTAssertEqual(r.destSide.sent.count, 1)
        XCTAssertEqual(r.destSide.sent.first?.hops, 1)
        XCTAssertEqual(r.destSide.sent.first?.destinationHash, destHash)
        XCTAssertEqual(r.sourceSide.sent.count, 0)  // never bounce back
    }

    func testForwardingDropsAtHopLimit() throws {
        let destHash = Hashes.truncatedHash(Data("dst".utf8))
        let r = makeRelay(destination: destHash)
        r.relay.propagationLimit = 3

        var packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: destHash,
            data: Data()
        )
        packet.hops = 3
        try r.upstream.send(packet)

        XCTAssertEqual(r.destSide.sent.count, 0)
    }

    func testForwardingDisabledOnEdgeNode() throws {
        let destHash = Hashes.truncatedHash(Data("dst".utf8))
        let r = makeRelay(destination: destHash)
        r.relay.transportEnabled = false

        let packet = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: destHash, data: Data()
        )
        try r.upstream.send(packet)
        XCTAssertEqual(r.destSide.sent.count, 0)
    }

    func testLocalDestinationStillDeliveredNotForwarded() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let r = makeRelay(destination: destination.hash)
        r.relay.register(destination: destination)

        let delivered = expectation(description: "delivered locally")
        r.relay.onPacketDelivered = { _, dest, _ in
            XCTAssertEqual(dest.hash, destination.hash)
            delivered.fulfill()
        }

        let packet = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: destination.hash, data: Data()
        )
        try r.upstream.send(packet)
        wait(for: [delivered], timeout: 1.0)
        XCTAssertEqual(r.destSide.sent.count, 0)
    }

    func testNoPathDropsPacket() throws {
        let r = makeRelay(destination: Hashes.truncatedHash(Data("known".utf8)))
        let unknownDest = Hashes.truncatedHash(Data("unknown".utf8))

        let packet = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: unknownDest, data: Data()
        )
        try r.upstream.send(packet)
        XCTAssertEqual(r.destSide.sent.count, 0)
        XCTAssertEqual(r.sourceSide.sent.count, 0)
    }
}
