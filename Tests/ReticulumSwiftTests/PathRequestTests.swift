import XCTest
@testable import ReticulumSwift

final class PathRequestTests: XCTestCase {

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

    func testWellKnownPathRequestDestinationHashIsStable() {
        // Locked-in to the same value the Python reference computes from
        // "rnstransport.path.request" via Destination.hash.
        let h = Transport.pathRequestDestinationHash
        XCTAssertEqual(h.count, Constants.truncatedHashLength)

        let nameHash = Destination.computeNameHash(
            appName: "rnstransport",
            aspects: ["path", "request"]
        )
        let recomputed = Destination.computeHash(identity: nil, nameHash: nameHash, kind: .plain)
        XCTAssertEqual(h, recomputed)
    }

    func testCachedAnnounceIsReplayedToAnsweringPathRequest() throws {
        // Topology:
        //   requester  <-> relay  (relay has the cached announce)
        //   relay      <-> dest   (announce originates here)
        let relay = Transport()

        let requesterIface = RecordingInterface(name: "requester")
        let relayFromRequester = RecordingInterface(name: "fromRequester")
        let relayFromDest = RecordingInterface(name: "fromDest")
        let destIface = RecordingInterface(name: "dest")
        requesterIface.paired = relayFromRequester
        relayFromRequester.paired = requesterIface
        relayFromDest.paired = destIface
        destIface.paired = relayFromDest

        relay.register(interface: relayFromRequester)
        relay.register(interface: relayFromDest)

        // 1) Dest announces — relay caches.
        let destIdentity = Identity()
        let destination = try Destination(
            identity: destIdentity, direction: .in, kind: .single,
            appName: "lxmf", aspects: ["delivery"]
        )
        let announce = try Announce.make(for: destination, appData: Data("hi".utf8))
        try destIface.send(announce)

        XCTAssertNotNil(relay.cachedAnnounces[destination.hash])

        // 2) Requester sends a path request for dest.
        // We construct the request body manually so we don't need a full
        // Transport on the requester side.
        var tag = Data(count: Constants.truncatedHashLength)
        _ = tag.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, Constants.truncatedHashLength, $0.baseAddress!)
        }
        let body = destination.hash + Data(repeating: 0, count: Constants.truncatedHashLength) + tag
        let pathReq = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: body
        )
        let countBefore = relayFromRequester.sent.count
        let destSideBefore = relayFromDest.sent.count
        try requesterIface.send(pathReq)

        // Relay echoes the cached announce back on the request-side
        // interface only. (Dest-side already saw nothing during the
        // initial announce-forwarding step, since that's where the
        // announce came from.)
        let newReplies = relayFromRequester.sent.dropFirst(countBefore)
        XCTAssertEqual(newReplies.count, 1)
        XCTAssertEqual(newReplies.first?.packetType, .announce)
        XCTAssertEqual(newReplies.first?.destinationHash, destination.hash)
        XCTAssertEqual(relayFromDest.sent.count, destSideBefore)
    }

    func testDuplicatePathRequestIsIgnored() throws {
        let relay = Transport()
        let inIface = RecordingInterface(name: "in")
        let outIface = RecordingInterface(name: "out")
        let inPair = RecordingInterface(name: "inPair")
        let outPair = RecordingInterface(name: "outPair")
        inIface.paired = inPair; inPair.paired = inIface
        outIface.paired = outPair; outPair.paired = outIface
        relay.register(interface: inIface)
        relay.register(interface: outIface)

        // Cache an announce so we'd otherwise reply twice.
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        try outPair.send(try Announce.make(for: destination))

        let tag = Data(repeating: 0xAB, count: Constants.truncatedHashLength)
        let body = destination.hash + Data(repeating: 0, count: Constants.truncatedHashLength) + tag
        let pathReq = Packet(
            destinationType: .plain, packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: body
        )
        let baseline = inIface.sent.count
        try inPair.send(pathReq)
        try inPair.send(pathReq)  // exact duplicate

        let replies = inIface.sent.dropFirst(baseline)
        XCTAssertEqual(replies.count, 1)
        XCTAssertEqual(replies.first?.packetType, .announce)
    }

    func testUnknownDestinationNotForwardedOnFullModeInterface() throws {
        // Python parity: full-mode interfaces are NOT in DISCOVER_PATHS_FOR.
        // Unknown path requests received on a full-mode interface are silently ignored.
        let relay = Transport()
        let inIface = RecordingInterface(name: "in")
        let outIface = RecordingInterface(name: "out")
        let inPair = RecordingInterface(name: "inPair")
        let outPair = RecordingInterface(name: "outPair")
        inIface.paired = inPair; inPair.paired = inIface
        outIface.paired = outPair; outPair.paired = outIface
        relay.register(interface: inIface)
        relay.register(interface: outIface)
        // inIface.mode defaults to .full — not in DISCOVER_PATHS_FOR

        let unknownDest = Hashes.truncatedHash(Data("unknown".utf8))
        let tag = Data(repeating: 0xCD, count: Constants.truncatedHashLength)
        let body = unknownDest + Data(repeating: 0, count: Constants.truncatedHashLength) + tag
        let pathReq = Packet(
            destinationType: .plain, packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: body
        )
        try inPair.send(pathReq)

        // Full-mode interface: no discovery propagation, path is unknown → ignored.
        XCTAssertEqual(outIface.sent.count, 0,
            "full-mode interface must not propagate unknown path requests (Python parity)")
        XCTAssertEqual(inIface.sent.count, 0)
    }

    func testRequestPathHelperEmitsRequestPacket() throws {
        let transport = Transport()
        let iface = RecordingInterface(name: "x")
        transport.register(interface: iface)

        let target = Hashes.truncatedHash(Data("target".utf8))
        try transport.requestPath(for: target)

        XCTAssertEqual(iface.sent.count, 1)
        let pkt = try XCTUnwrap(iface.sent.first)
        XCTAssertEqual(pkt.destinationType, .plain)
        XCTAssertEqual(pkt.destinationHash, Transport.pathRequestDestinationHash)
        XCTAssertEqual(pkt.data.prefix(Constants.truncatedHashLength), target)
        XCTAssertEqual(
            pkt.data.count,
            Constants.truncatedHashLength * 3
        )
    }
}
