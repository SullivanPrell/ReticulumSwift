import XCTest
@testable import ReticulumSwift

/// Tests for path request handling with requestor transport ID and discovery propagation.
///
/// Python reference (Transport.path_request_handler / Transport.path_request):
/// - When body > 32 bytes: bytes 16..32 = requestingTransportInstance
/// - If next hop == requestingTransportInstance → suppress path response (avoid loop)
/// - When transport is enabled + interface.mode in DISCOVER_PATHS_FOR + path unknown:
///   propagate path request on all *other* interfaces (excluding egress-limited ones)
final class PathRequestTransportIDTests: XCTestCase {

    final class RecordingInterface: Interface {
        var name: String
        var bitrate: Int = 100_000
        var isOnline: Bool = true
        weak var paired: RecordingInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []
        var mode: InterfaceMode = .full
        var egressControl: Bool = false

        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {
            sent.append(packet)
            if let paired {
                let raw = try packet.pack()
                let copy = try Packet.unpack(raw)
                paired.inboundHandler?(copy, paired)
            }
        }
    }

    /// Make a paired requester/relay interface duo. Returns (requesterSide, relaySide).
    /// Sending on requesterSide delivers to relay's inbound handler via relaySide.
    private func makePair(requesterName: String, relayName: String)
        -> (requester: RecordingInterface, relay: RecordingInterface)
    {
        let req = RecordingInterface(name: requesterName)
        let rel = RecordingInterface(name: relayName)
        req.paired = rel
        rel.paired = req
        return (req, rel)
    }

    private func makePathRequest(destHash: Data, requestorID: Data? = nil) -> Packet {
        var tag = Data(count: 16)
        _ = tag.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let body: Data
        if let rid = requestorID {
            body = destHash + rid + tag
        } else {
            body = destHash + tag
        }
        return Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: body
        )
    }

    // MARK: - Requestor transport ID: suppress answer when next hop is requestor

    func testPathResponseSuppressedWhenNextHopIsRequestor() throws {
        let relay = Transport()
        relay.transportEnabled = true

        let (requesterIface, relayInIface) = makePair(requesterName: "req-s", relayName: "relay-in-s")
        let relayOutIface = RecordingInterface(name: "relay-out-s")
        relay.register(interface: relayInIface)
        relay.register(interface: relayOutIface)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single,
            appName: "test", aspects: ["suppress"]
        )

        var requestorTransportID = Data(count: 16)
        _ = requestorTransportID.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }

        let announce = try Announce.make(for: destination, appData: nil)
        relay.cacheAnnounce(announce, forDestination: destination.hash)
        relay.injectPath(destination.hash,
                         nextHop: requestorTransportID,
                         receivedOn: relayOutIface,
                         hops: 2,
                         announcePacketHash: nil)

        let pathReq = makePathRequest(destHash: destination.hash, requestorID: requestorTransportID)

        // Send from requester side → relay processes via relayInIface.
        let countBefore = relayInIface.sent.count
        try requesterIface.send(pathReq)

        // Relay should NOT send an announce back (suppress: next hop == requestor).
        let newAnnounces = relayInIface.sent.dropFirst(countBefore).filter { $0.packetType == .announce }
        XCTAssertEqual(newAnnounces.count, 0,
            "relay must suppress path response when next hop is the requesting transport")
    }

    // MARK: - Requestor transport ID: answer when next hop differs from requestor

    func testPathResponseSentWhenNextHopDifferentFromRequestor() throws {
        let relay = Transport()
        relay.transportEnabled = true

        let (requesterIface, relayInIface) = makePair(requesterName: "req-d", relayName: "relay-in-d")
        let relayOutIface = RecordingInterface(name: "relay-out-d")
        relay.register(interface: relayInIface)
        relay.register(interface: relayOutIface)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single,
            appName: "test", aspects: ["diff"]
        )

        var nextHop = Data(count: 16)
        _ = nextHop.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        var requestorTransportID = Data(count: 16)
        _ = requestorTransportID.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        requestorTransportID[0] = nextHop[0] ^ 0xFF

        let announce = try Announce.make(for: destination, appData: nil)
        relay.cacheAnnounce(announce, forDestination: destination.hash)
        relay.injectPath(destination.hash,
                         nextHop: nextHop,
                         receivedOn: relayOutIface,
                         hops: 2,
                         announcePacketHash: nil)

        let pathReq = makePathRequest(destHash: destination.hash, requestorID: requestorTransportID)

        let countBefore = relayInIface.sent.count
        try requesterIface.send(pathReq)

        let newAnnounces = relayInIface.sent.dropFirst(countBefore).filter { $0.packetType == .announce }
        XCTAssertEqual(newAnnounces.count, 1,
            "relay must answer path request when next hop differs from requesting transport")
    }

    // MARK: - No requestor ID: answer normally

    func testPathResponseSentWithoutRequestorTransportID() throws {
        let relay = Transport()
        relay.transportEnabled = true

        let (requesterIface, relayInIface) = makePair(requesterName: "req-n", relayName: "relay-in-n")
        relay.register(interface: relayInIface)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single,
            appName: "test", aspects: ["noid"]
        )
        let announce = try Announce.make(for: destination, appData: nil)
        relay.cacheAnnounce(announce, forDestination: destination.hash)
        // A path response is only sent for a KNOWN PATH (Python: dest in path_table),
        // so seed a real path entry alongside the cached announce packet.
        relay.injectPath(destination.hash, nextHop: Data(repeating: 0xAA, count: 16),
                         receivedOn: relayInIface, hops: 1, announcePacketHash: nil)

        let pathReq = makePathRequest(destHash: destination.hash, requestorID: nil)

        let countBefore = relayInIface.sent.count
        try requesterIface.send(pathReq)

        let newAnnounces = relayInIface.sent.dropFirst(countBefore).filter { $0.packetType == .announce }
        XCTAssertEqual(newAnnounces.count, 1,
            "relay must answer path request when no requestor transport ID is present")
    }

    // MARK: - Discovery propagation: DISCOVER_PATHS_FOR mode + unknown path

    func testDiscoveryPropagationOnUnknownPathGatewayMode() throws {
        let relay = Transport()
        relay.transportEnabled = true

        let (requesterIface, relayInIface) = makePair(requesterName: "req-gw", relayName: "relay-in-gw")
        relayInIface.mode = .gateway

        let outIface1 = RecordingInterface(name: "out-gw1")
        let outIface2 = RecordingInterface(name: "out-gw2")
        relay.register(interface: relayInIface)
        relay.register(interface: outIface1)
        relay.register(interface: outIface2)

        var destHash = Data(count: 16)
        _ = destHash.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let pathReq = makePathRequest(destHash: destHash)
        try requesterIface.send(pathReq)

        let out1PRs = outIface1.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        let out2PRs = outIface2.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        XCTAssertEqual(out1PRs.count, 1, "discovery propagation must forward PR on outIface1")
        XCTAssertEqual(out2PRs.count, 1, "discovery propagation must forward PR on outIface2")
    }

    func testDiscoveryPropagationInRoamingMode() throws {
        let relay = Transport()
        relay.transportEnabled = true

        let (requesterIface, relayInIface) = makePair(requesterName: "req-rm", relayName: "relay-in-rm")
        relayInIface.mode = .roaming

        let outIface = RecordingInterface(name: "out-rm")
        relay.register(interface: relayInIface)
        relay.register(interface: outIface)

        var destHash = Data(count: 16)
        _ = destHash.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let pathReq = makePathRequest(destHash: destHash)
        try requesterIface.send(pathReq)

        let outPRs = outIface.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        XCTAssertEqual(outPRs.count, 1, "roaming-mode interface should trigger discovery propagation")
    }

    // MARK: - No discovery propagation in full mode

    func testNoDiscoveryPropagationInFullMode() throws {
        let relay = Transport()
        relay.transportEnabled = true

        let (requesterIface, relayInIface) = makePair(requesterName: "req-fm", relayName: "relay-in-fm")
        relayInIface.mode = .full  // NOT in DISCOVER_PATHS_FOR

        let outIface = RecordingInterface(name: "out-fm")
        relay.register(interface: relayInIface)
        relay.register(interface: outIface)

        var destHash = Data(count: 16)
        _ = destHash.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let pathReq = makePathRequest(destHash: destHash)
        try requesterIface.send(pathReq)

        let outPRs = outIface.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        XCTAssertEqual(outPRs.count, 0, "full-mode interface must not trigger discovery propagation")
    }

    // MARK: - Discovery propagation: egress-limited interface skipped

    func testDiscoveryPropagationSkipsEgressLimitedInterface() throws {
        let relay = Transport()
        relay.transportEnabled = true

        let (requesterIface, relayInIface) = makePair(requesterName: "req-el", relayName: "relay-in-el")
        relayInIface.mode = .gateway

        let freeIface = RecordingInterface(name: "free-el")
        let limitedIface = RecordingInterface(name: "limited-el")
        limitedIface.egressControl = true
        relay.register(interface: relayInIface)
        relay.register(interface: freeIface)
        relay.register(interface: limitedIface)

        // Flood outgoing PRs on limitedIface within the current decay window.
        let now = Date().timeIntervalSince1970
        for i in 0..<20 {
            relay.notifyOutgoingPathRequest(on: limitedIface, at: now - 1.0 + Double(i) * 0.05)
        }

        var destHash = Data(count: 16)
        _ = destHash.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let pathReq = makePathRequest(destHash: destHash)
        try requesterIface.send(pathReq)

        let freeOut = freeIface.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        let limitedOut = limitedIface.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        XCTAssertEqual(freeOut.count, 1, "discovery PR must be forwarded on the non-limited interface")
        XCTAssertEqual(limitedOut.count, 0, "discovery PR must NOT be forwarded on the egress-limited interface")
    }

    // MARK: - No path entry: stay silent (Python: answer requires dest in path_table)

    func testNoAnswerWhenCachedAnnounceButNoPathEntry() throws {
        // A cached announce alone is NOT a known path. Python answers a path
        // request only when `destination_hash in Transport.path_table`
        // (Transport.py:2969); answering from a stale cached announce with no
        // live path would black-hole traffic to a route we cannot actually use.
        let relay = Transport()
        relay.transportEnabled = true

        let (requesterIface, relayInIface) = makePair(requesterName: "req-np", relayName: "relay-in-np")
        relay.register(interface: relayInIface)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single,
            appName: "test", aspects: ["nopathentry"]
        )
        let announce = try Announce.make(for: destination, appData: nil)
        relay.cacheAnnounce(announce, forDestination: destination.hash)   // cache only, no path

        var requestorID = Data(count: 16)
        _ = requestorID.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let pathReq = makePathRequest(destHash: destination.hash, requestorID: requestorID)

        let countBefore = relayInIface.sent.count
        try requesterIface.send(pathReq)

        let newAnnounces = relayInIface.sent.dropFirst(countBefore).filter { $0.packetType == .announce }
        XCTAssertEqual(newAnnounces.count, 0,
            "relay must NOT answer a path request without a known path entry")
    }
}
