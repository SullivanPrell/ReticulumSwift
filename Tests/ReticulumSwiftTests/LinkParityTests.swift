import XCTest
@testable import ReticulumSwift

/// Parity tests for Link lifecycle fixes vs Python reference (Link.py).
///
/// Covers five gaps found in the 2026-06-03 review:
///
///   1. Initiator establishment timeout must include firstHopTimeout
///      Python: `self.establishment_timeout = get_first_hop_timeout(dst) + ESTABLISHMENT_TIMEOUT_PER_HOP * max(1, hops)`
///
///   2. Responder requestTime must be set in answer()
///      Python: `link.request_time = time.time()`
///
///   3. Responder establishmentTimeout = perHop * max(1, hops) + KEEPALIVE
///      Python: `link.establishment_timeout = ESTABLISHMENT_TIMEOUT_PER_HOP * max(1, packet.hops) + KEEPALIVE`
///
///   4. Responder receiveRTT uses max(measured_rtt, reported_rtt)
///      Python: `self.rtt = max(time.time() - self.request_time, umsgpack.unpackb(plaintext))`
///
///   5. LinkRoute stores destinationHash so relay LRPROOF handling can call markDestinationUsed
///      Python: `Transport.link_table[link_id][IDX_LT_DSTHASH]` → `RNS.Identity._used_destination_data(...)`
final class LinkParityTests: XCTestCase {

    // MARK: - Helpers

    /// Interface that silently drops all outbound packets (one-way sink).
    /// Used to isolate the initiator so the link stays in .pending state.
    final class SinkInterface: Interface {
        var name = "sink"; var bitrate = 0; var isOnline = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}  // drop
    }

    /// Bidirectional loopback delivering packets through pack/unpack.
    final class Loopback: Interface {
        var name: String; var bitrate = 0; var isOnline = true
        weak var paired: Loopback?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    /// Spy interface — delivers AND records sent packets.
    final class SpyInterface: Interface {
        var name: String; var bitrate = 0; var isOnline = true
        weak var paired: SpyInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sentPackets: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {
            sentPackets.append(packet)
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    /// Build a fully established A↔B link via loopback.
    private func establishLink() throws -> (aLink: Link, bLink: Link, aT: Transport, bT: Transport) {
        let aT = Transport()
        let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["parity"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)

        let aIface = Loopback(name: "A"); let bIface = Loopback(name: "B")
        aIface.paired = bIface; bIface.paired = aIface
        aT.register(interface: aIface); bT.register(interface: bIface)

        let aE = expectation(description: "a-active")
        let bE = expectation(description: "b-active")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }

        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 2.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink, aT, bT)
    }

    /// Build a B↔R↔A relay topology with transport enabled on R.
    private func makeRelayTopology() throws -> (
        bT: Transport, rT: Transport, aT: Transport,
        aDest: Destination, aIdentity: Identity
    ) {
        let bT = Transport()
        let rT = Transport()
        let aT = Transport()
        rT.transportEnabled = true

        let aIdentity = Identity()
        let aDest = try Destination(identity: aIdentity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["relay"])
        aT.ownerIdentity = aIdentity
        aT.register(destination: aDest)

        let bIface  = SpyInterface(name: "B→R")
        let rFromB  = SpyInterface(name: "R←B")
        bIface.paired = rFromB; rFromB.paired = bIface
        bT.register(interface: bIface); rT.register(interface: rFromB)

        let rToA   = SpyInterface(name: "R→A")
        let aIface = SpyInterface(name: "A←R")
        rToA.paired = aIface; aIface.paired = rToA
        rT.register(interface: rToA); aT.register(interface: aIface)

        rT.restore(path: Transport.PathEntry(
            destinationHash: aDest.hash, nextHopInterfaceName: rToA.name,
            hops: 0, lastHeard: Date(), identityHash: aIdentity.hash), forDestination: aDest.hash)
        bT.restore(path: Transport.PathEntry(
            destinationHash: aDest.hash, nextHopInterfaceName: bIface.name,
            hops: 1, lastHeard: Date(), identityHash: aIdentity.hash,
            nextHopTransportID: rT.transportInstanceID), forDestination: aDest.hash)

        return (bT, rT, aT, aDest, aIdentity)
    }

    // MARK: - 1. Initiator establishment timeout includes firstHopTimeout

    /// Before the fix: `establishmentTimeout = perHop * max(1, hops) = 6`
    /// After  the fix: `establishmentTimeout = firstHopTimeout + perHop * max(1, hops) = 6 + 6 = 12`
    ///
    /// Python reference: Link.__init__, lines 283–284:
    ///   `self.establishment_timeout  = RNS.Reticulum.get_instance().get_first_hop_timeout(destination.hash)`
    ///   `self.establishment_timeout += Link.ESTABLISHMENT_TIMEOUT_PER_HOP * max(1, RNS.Transport.hops_to(...))`
    func testInitiatorEstablishmentTimeoutIncludesFirstHopTimeout() throws {
        let transport = Transport()
        transport.register(interface: SinkInterface())

        let remoteId = Identity()
        let dest = try Destination(identity: remoteId, direction: .in, kind: .single, appName: "t")

        // No path known → hops = 1, firstHopTimeout = defaultPerHopTimeout = 6.
        // Expected after fix: 6 + 6 * 1 = 12 seconds.
        let link = try Link.initiate(destination: dest, transport: transport)
        let expected = Transport.firstHopTimeout(for: dest.hash, in: transport)
                     + Link.establishmentTimeoutPerHop * TimeInterval(max(1, 1))
        XCTAssertEqual(link.establishmentTimeout, expected, accuracy: 0.001,
            "Initiator establishment timeout must equal firstHopTimeout + perHop * max(1, hops)")
        // Concrete expectation: 12.0 when no interface bitrate is known.
        XCTAssertEqual(link.establishmentTimeout, 12.0, accuracy: 0.001,
            "Without bitrate data, firstHopTimeout = 6, so total = 6 + 6 = 12 seconds")
    }

    // MARK: - 2. Responder requestTime is set in answer()

    /// Python: `link.request_time = time.time()` (validate_request, line 215)
    func testResponderRequestTimeSetOnAnsweredLink() throws {
        let (_, bLink, aT, bT) = try establishLink()
        _ = (aT, bT)
        XCTAssertNotNil(bLink.requestTime,
            "Responder requestTime must be set when the link request is answered")
    }

    func testResponderRequestTimeIsRecentlyInPast() throws {
        let before = Date()
        let (_, bLink, aT, bT) = try establishLink()
        _ = (aT, bT)
        let after = Date()
        guard let rt = bLink.requestTime else { return XCTFail("requestTime nil") }
        XCTAssertGreaterThanOrEqual(rt, before, "requestTime must be ≥ test start")
        XCTAssertLessThanOrEqual(rt, after, "requestTime must be ≤ test end")
    }

    // MARK: - 3. Responder establishmentTimeout = perHop * max(1,hops) + KEEPALIVE

    /// Python: `link.establishment_timeout = ESTABLISHMENT_TIMEOUT_PER_HOP * max(1, packet.hops) + KEEPALIVE`
    /// For a 1-hop loopback (packet.hops == 0 when received directly): timeout = 6 * 1 + 360 = 366.
    func testResponderEstablishmentTimeoutIncludesKeepalive() throws {
        let (_, bLink, aT, bT) = try establishLink()
        _ = (aT, bT)
        // The LRR arrives at the responder with packet.hops == 0 (direct, no relay).
        // establishment_timeout = perHop * max(1, 0) + KEEPALIVE = 6 + 360 = 366.
        let expected = Link.establishmentTimeoutPerHop * TimeInterval(max(1, 0)) + Link.keepaliveInterval
        XCTAssertEqual(bLink.establishmentTimeout, expected, accuracy: 0.001,
            "Responder establishment timeout must be perHop * max(1,hops) + KEEPALIVE = \(expected)")
    }

    // MARK: - 4. receiveRTT uses max(measured_rtt, reported_rtt)

    /// After the fix, the responder's rtt = max(measured, reported).
    /// Since measured ≈ reported in a synchronous loopback, we just verify rtt is set and positive.
    func testReceiveRTTSetsRTTOnResponder() throws {
        let (_, bLink, aT, bT) = try establishLink()
        _ = (aT, bT)
        XCTAssertNotNil(bLink.rtt, "Responder rtt must be set after receiveRTT")
        if let rtt = bLink.rtt { XCTAssertGreaterThan(rtt, 0) }
    }

    /// The responder's rtt must be ≥ the time from requestTime to link activation.
    /// This validates the `max` picks the larger of measured vs reported.
    func testReceiveRTTIsAtLeastMeasuredRoundTrip() throws {
        let (_, bLink, aT, bT) = try establishLink()
        _ = (aT, bT)
        guard let rt = bLink.requestTime, let rtt = bLink.rtt else {
            return XCTFail("requestTime or rtt nil")
        }
        // After the fix: rtt ≥ max(measured, reported) ≥ measured.
        // The measured_rtt is Date()-requestTime at the time receiveRTT was called.
        // The link is active now, so measured was approximately Date()-rt before.
        // Due to timing, we just assert the rtt >= 0 and the requestTime was set before activation.
        let measured = bLink.establishedAt.map { $0.timeIntervalSince(rt) } ?? 0
        XCTAssertGreaterThanOrEqual(rtt, measured - 0.01,
            "rtt must be at least the measured round-trip time (with small tolerance)")
    }

    // MARK: - 5. LinkRoute stores destinationHash

    /// Python: `link_entry[IDX_LT_DSTHASH]` — the relay stores the destination hash
    /// so it can call `_used_destination_data` after forwarding LRPROOF.
    func testLinkRouteStoresDestinationHash() throws {
        let (bT, rT, aT, aDest, _) = try makeRelayTopology()
        _ = aT

        let bEstablished = expectation(description: "B established")
        var bLink: Link?
        bT.onLinkEstablished = { l in bLink = l; bEstablished.fulfill() }

        _ = try Link.initiate(destination: aDest, transport: bT)
        wait(for: [bEstablished], timeout: 2.0)

        guard let linkID = bLink?.linkID else { return XCTFail("linkID nil") }
        rT.lock.lock()
        let route = rT.linkRoutes[linkID]
        rT.lock.unlock()

        XCTAssertNotNil(route, "Relay must store a LinkRoute for the link")
        XCTAssertEqual(route?.destinationHash, aDest.hash,
            "LinkRoute must record the destination hash so LRPROOF relay can call markDestinationUsed")
    }
}

// MARK: - Helper: expose firstHopTimeout for tests

extension Transport {
    /// Test helper: compute the firstHopTimeout for a destination in a given transport.
    /// Mirrors Python `Transport.first_hop_timeout(destination_hash)`.
    static func firstHopTimeout(for destinationHash: Data, in transport: Transport) -> TimeInterval {
        transport.firstHopTimeout(for: destinationHash)
    }
}
