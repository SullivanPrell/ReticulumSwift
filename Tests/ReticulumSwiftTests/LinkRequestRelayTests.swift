import XCTest
@testable import ReticulumSwift

/// Tests for LINKREQUEST relay through a transport node.
///
/// Python reference: `Transport.py` lines 1559–1633 — when the relay receives a
/// HEADER_2 LINKREQUEST addressed to it, it must:
///   - If `remaining_hops == 1` (Swift: `path.hops == 0`): strip transport header
///     and forward as HEADER_1 so the final destination can accept it.
///   - If `remaining_hops > 1`  (Swift: `path.hops > 0`): update transport_id to
///     the next hop's transport ID and forward as HEADER_2.
///
/// Topology for all tests:
///   B (initiator) <---> R (relay, transportEnabled) <---> A (responder)
///
/// B knows path to A with R's transport_id (stored from HEADER_2 announce).
/// R knows path to A with 0 hops (A is directly reachable via R→A interface).
final class LinkRequestRelayTests: XCTestCase {

    // MARK: - Spy interface

    /// Loopback interface that delivers packets to its pair AND records them.
    final class SpyInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        weak var paired: SpyInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sentPackets: [Packet] = []

        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            sentPackets.append(packet)
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    // MARK: - Helpers

    /// Wire up B ↔ R ↔ A and seed path tables so B sends HEADER_2 and R relays it.
    ///
    /// Returns (bTransport, rTransport, aTransport, aDest, rToA, aIface)
    private func makeTopology() throws -> (
        bT: Transport, rT: Transport, aT: Transport,
        aDest: Destination,
        rToA: SpyInterface, aIface: SpyInterface
    ) {
        let bT = Transport()
        let rT = Transport()
        let aT = Transport()

        // rT is the relay — must have transport enabled.
        rT.transportEnabled = true

        // A registers a link-accepting destination.
        let aIdentity = Identity()
        let aDest = try Destination(
            identity: aIdentity, direction: .in, kind: .single,
            appName: "test", aspects: ["relay"]
        )
        aT.ownerIdentity = aIdentity
        aT.register(destination: aDest)

        // Wire: B ↔ R
        let bIface  = SpyInterface(name: "B→R")
        let rFromB  = SpyInterface(name: "R←B")
        bIface.paired = rFromB; rFromB.paired = bIface
        bT.register(interface: bIface)
        rT.register(interface: rFromB)

        // Wire: R ↔ A
        let rToA  = SpyInterface(name: "R→A")
        let aIface = SpyInterface(name: "A←R")
        rToA.paired = aIface; aIface.paired = rToA
        rT.register(interface: rToA)
        aT.register(interface: aIface)

        // R knows A is directly reachable (hops = 0, no further relay).
        rT.restore(
            path: Transport.PathEntry(
                destinationHash: aDest.hash,
                nextHopInterfaceName: rToA.name,
                hops: 0,
                lastHeard: Date(),
                identityHash: aIdentity.hash
            ),
            forDestination: aDest.hash
        )

        // B knows A is reachable via R as relay (hops = 1, nextHopTransportID = R's ID).
        // In real operation, B learns this by receiving a HEADER_2 announce from R.
        // Here we seed it directly to keep the test focused on LINKREQUEST relay.
        bT.restore(
            path: Transport.PathEntry(
                destinationHash: aDest.hash,
                nextHopInterfaceName: bIface.name,
                hops: 1,
                lastHeard: Date(),
                identityHash: aIdentity.hash,
                nextHopTransportID: rT.transportInstanceID
            ),
            forDestination: aDest.hash
        )

        return (bT, rT, aT, aDest, rToA, aIface)
    }

    // MARK: - Tests

    /// When B sends a HEADER_2 LINKREQUEST addressed to R's transport_id,
    /// R must forward it to A as HEADER_1 (transport header stripped).
    ///
    /// Python: remaining_hops == 1 → strip transport header, transmit HEADER_1.
    /// Swift:  path.hops == 0     → strip transport header, transmit HEADER_1.
    func testRelayConvertsHeader2LinkRequestToHeader1() throws {
        // NB: rT and aT must be held alive or the inboundHandler's [weak self] becomes nil.
        let (bT, rT, aT, aDest, rToA, _) = try makeTopology()
        _ = rT; _ = aT  // suppress "unused" warnings while keeping strong refs

        _ = try Link.initiate(destination: aDest, transport: bT)
        // Give the relay a moment to process and forward.
        Thread.sleep(forTimeInterval: 0.05)

        // rToA.sentPackets should contain the forwarded LINKREQUEST.
        let lrr = rToA.sentPackets.first(where: { $0.packetType == .linkRequest })
        XCTAssertNotNil(lrr, "Relay must forward the LINKREQUEST to A's interface")
        XCTAssertEqual(lrr?.headerType, .type1,
                       "Relay must strip transport header (HEADER_2→HEADER_1) when path.hops == 0")
        XCTAssertNil(lrr?.transportID,
                     "Forwarded LINKREQUEST must have no transport_id (HEADER_1)")
    }

    /// End-to-end: B initiates link via relay R to destination A.
    /// After the fix, A receives HEADER_1 and answers. The link is established.
    func testRelayedLinkEstablishes() throws {
        // NB: rT must be held alive or the relay's inboundHandler becomes nil.
        let (bT, rT, aT, aDest, _, _) = try makeTopology()
        _ = rT  // keep relay alive

        let bEstablished = expectation(description: "B link established")
        let aEstablished = expectation(description: "A link established")
        bT.onLinkEstablished = { _ in bEstablished.fulfill() }
        aT.onLinkEstablished = { _ in aEstablished.fulfill() }

        _ = try Link.initiate(destination: aDest, transport: bT)

        wait(for: [bEstablished, aEstablished], timeout: 2.0)
    }

    /// Verify the link_id computed by B and R are identical, so that the LRPROOF
    /// forwarded back by R (using the link_id as destination hash) is correctly
    /// matched by B.
    func testRelayedLinkIDMatchesBetweenInitiatorAndRelay() throws {
        // NB: aT must be held alive for the link to be answered.
        let (bT, rT, aT, aDest, _, _) = try makeTopology()
        _ = aT  // keep responder alive

        let bEstablished = expectation(description: "B established")
        var bLink: Link?
        bT.onLinkEstablished = { l in bLink = l; bEstablished.fulfill() }

        _ = try Link.initiate(destination: aDest, transport: bT)
        wait(for: [bEstablished], timeout: 2.0)

        guard let linkID = bLink?.linkID else { XCTFail("linkID not set"); return }
        // R must have stored a link route for this link_id.
        rT.lock.lock()
        let route = rT.linkRoutes[linkID]
        rT.lock.unlock()
        XCTAssertNotNil(route, "Relay must have a link route for the established link_id")
    }

    /// A relay must clamp/strip the link-request MTU signalling for the next hop,
    /// mirroring Python `Transport.inbound()` (lines ~1604-1626): when the
    /// outbound interface declares no HW MTU (Swift's default for every
    /// interface), MTU upgrade is disabled and the trailing `LINK_MTU_SIZE`
    /// signalling bytes are removed before forwarding. Otherwise a Python-
    /// initiated MTU upgrade would pass through a Swift relay unclamped and the
    /// endpoints could negotiate a link MTU larger than a relay hop can carry.
    /// Stripping does not change the link_id (both sides hash the packet with
    /// signalling bytes removed), so routing is unaffected.
    func testRelayStripsMTUSignallingWhenNextHopHasNoHWMTU() throws {
        let rT = Transport()
        rT.transportEnabled = true

        let rFromB = SpyInterface(name: "R←B")   // initiator side
        let rToA   = SpyInterface(name: "R→A")   // next hop (paired left nil: records only)
        rT.register(interface: rFromB)
        rT.register(interface: rToA)

        let aIdentity = Identity()
        let aDest = try Destination(identity: aIdentity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["relaymtu"])
        // A is directly reachable on rToA (hops == 0 → relay strips header too).
        rT.restore(
            path: Transport.PathEntry(
                destinationHash: aDest.hash,
                nextHopInterfaceName: rToA.name,
                hops: 0,
                lastHeard: Date(),
                identityHash: aIdentity.hash
            ),
            forDestination: aDest.hash
        )

        // Craft a HEADER_2 link request addressed to R, carrying a 1500-byte MTU
        // upgrade in its 3-byte signalling tail (64 key bytes + 3 signalling).
        let keyBytes = Data((0..<Constants.keySize).map { UInt8($0 & 0xFF) })
        let body = keyBytes + Link.mtuSignallingBytes(mtu: 1500)
        XCTAssertEqual(body.count, Constants.keySize + 3)
        var lrr = Packet(
            destinationType: .single,
            packetType: .linkRequest,
            destinationHash: aDest.hash,
            data: body
        )
        lrr.headerType = .type2
        lrr.transportType = .transport
        lrr.transportID = rT.transportInstanceID

        rFromB.inboundHandler?(lrr, rFromB)

        let forwarded = rToA.sentPackets.first(where: { $0.packetType == .linkRequest })
        XCTAssertNotNil(forwarded, "relay must forward the link request to the next hop")
        XCTAssertEqual(forwarded?.data.count, Constants.keySize,
                       "relay must strip the MTU signalling when the next hop has no HW MTU")
    }

    /// A SpyInterface variant that declares a HW MTU and supports MTU
    /// autoconfiguration, so the relay's clamp branch (not just the strip
    /// branch) is exercised. Production Swift interfaces all report `hwMtu == nil`.
    final class MtuSpyInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sentPackets: [Packet] = []
        let declaredHwMtu: Int
        var hwMtu: Int? { declaredHwMtu }
        var autoconfigureMtu: Bool { true }
        init(name: String, hwMtu: Int) { self.name = name; self.declaredHwMtu = hwMtu }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws { sentPackets.append(packet) }
    }

    /// When the next hop declares a HW MTU below the requested path MTU, the
    /// relay must clamp the signalling to that HW MTU (rather than strip it).
    /// Mirrors Python's clamp branch; here the prev hop reports no HW MTU, so
    /// the clamp target is the next-hop MTU (Swift forwards rather than dropping,
    /// the documented divergence from Python's `min(None)` crash-drop).
    func testRelayClampsMTUSignallingToNextHopHWMTU() throws {
        let rT = Transport()
        rT.transportEnabled = true

        let rFromB = SpyInterface(name: "R←B")                 // prev hop: hwMtu nil
        let rToA   = MtuSpyInterface(name: "R→A", hwMtu: 600)   // next hop: 600, autoconfig
        rT.register(interface: rFromB)
        rT.register(interface: rToA)

        let aIdentity = Identity()
        let aDest = try Destination(identity: aIdentity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["clampmtu"])
        rT.restore(
            path: Transport.PathEntry(
                destinationHash: aDest.hash,
                nextHopInterfaceName: rToA.name,
                hops: 0,
                lastHeard: Date(),
                identityHash: aIdentity.hash
            ),
            forDestination: aDest.hash
        )

        let keyBytes = Data((0..<Constants.keySize).map { UInt8($0 & 0xFF) })
        let body = keyBytes + Link.mtuSignallingBytes(mtu: 1500)   // request 1500 (> 600)
        var lrr = Packet(
            destinationType: .single,
            packetType: .linkRequest,
            destinationHash: aDest.hash,
            data: body
        )
        lrr.headerType = .type2
        lrr.transportType = .transport
        lrr.transportID = rT.transportInstanceID

        rFromB.inboundHandler?(lrr, rFromB)

        let forwarded = rToA.sentPackets.first(where: { $0.packetType == .linkRequest })
        XCTAssertNotNil(forwarded, "relay must forward the link request to the next hop")
        XCTAssertEqual(forwarded?.data.count, Constants.keySize + 3,
                       "clamp keeps the 3-byte signalling tail (does not strip)")
        let signalled = forwarded.map { Link.mtuFromSignalling(Data($0.data.suffix(3))) } ?? nil
        XCTAssertEqual(signalled, 600,
                       "relay must clamp the link MTU down to the next-hop HW MTU")
    }
}
