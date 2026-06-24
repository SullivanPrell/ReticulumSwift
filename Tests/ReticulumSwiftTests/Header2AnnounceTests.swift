import XCTest
@testable import ReticulumSwift

/// Tests for announces arriving with HEADER_2 (transport header).
/// When an announce arrives via a relay (HEADER_2), the relay's transport ID
/// should be stored as the next-hop transport ID in the path table.
final class Header2AnnounceTests: XCTestCase {

    final class CapturingInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    func testAnnounceViaHeader2StoresTransportID() throws {
        let t = Transport()
        let iface = CapturingInterface(name: "in")
        t.register(interface: iface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["h2"])

        // Create an announce as if it came via a relay (HEADER_2 with transport ID)
        var announce = try Announce.make(for: dest)
        announce.headerType = .type2
        announce.hops = 1
        let relayTransportID = Data(repeating: 0xAB, count: 16)
        announce.transportID = relayTransportID

        iface.inboundHandler?(announce, iface)

        // Path table should have the relay's transport ID as next-hop
        let path = t.paths[dest.hash]
        XCTAssertNotNil(path, "should have path after receiving announce")
        XCTAssertEqual(path?.hops, 1)
        XCTAssertEqual(path?.nextHopTransportID, relayTransportID,
            "next-hop transport ID should be stored from HEADER_2 announce")
    }

    func testAnnounceDirectHeader1HasNilTransportID() throws {
        let t = Transport()
        let iface = CapturingInterface(name: "in")
        t.register(interface: iface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["h1"])

        // Direct announce (HEADER_1, no transport ID)
        let announce = try Announce.make(for: dest)
        XCTAssertEqual(announce.headerType, .type1)

        iface.inboundHandler?(announce, iface)

        let path = t.paths[dest.hash]
        XCTAssertNil(path?.nextHopTransportID,
            "direct announce should have nil next-hop transport ID")
    }

    func testOutboundPacketUsesStoredTransportID() throws {
        let t = Transport()
        let outIface = CapturingInterface(name: "out")
        t.register(interface: outIface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["outbound"])
        t.restore(identity: id, forDestination: dest.hash)

        let relayTransportID = Data(repeating: 0xCC, count: 16)
        t.restore(path: Transport.PathEntry(
            destinationHash: dest.hash,
            nextHopInterfaceName: outIface.name,
            hops: 2,
            lastHeard: Date(),
            identityHash: id.hash,
            nextHopTransportID: relayTransportID
        ), forDestination: dest.hash)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("test".utf8))
        )
        try t.send(packet, generateReceipt: false)

        // The sent packet should have HEADER_2 with the stored transport ID
        let sent = outIface.sent.first(where: { $0.packetType == .data })
        XCTAssertEqual(sent?.headerType, .type2, "should use HEADER_2 for multi-hop paths")
        XCTAssertEqual(sent?.transportID, relayTransportID, "should use stored next-hop transport ID")
    }

    /// Regression test for single-hop paths via a backbone transport node.
    ///
    /// When the destination is 1 hop away but the announce arrived as HEADER_2
    /// (i.e. the path goes through a backbone), `send()` must wrap the outbound
    /// packet in HEADER_2 with the backbone's transport ID.  Without this the
    /// backbone drops the packet because it has no transport_id to route on.
    func testOutboundPacketUsesTransportIDForOneHopBackbonePath() throws {
        let t = Transport()
        let outIface = CapturingInterface(name: "backbone-tcp")
        t.register(interface: outIface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["1hop-backbone"])
        t.restore(identity: id, forDestination: dest.hash)

        // Simulate learning the path via a HEADER_2 announce (hops == 1 but
        // came through a backbone relay, so nextHopTransportID is populated).
        let backboneTransportID = Data(repeating: 0xBB, count: 16)
        t.restore(path: Transport.PathEntry(
            destinationHash: dest.hash,
            nextHopInterfaceName: outIface.name,
            hops: 1,                             // ← 1 hop, NOT > 1
            lastHeard: Date(),
            identityHash: id.hash,
            nextHopTransportID: backboneTransportID   // ← backbone transport ID
        ), forDestination: dest.hash)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("ping".utf8))
        )
        try t.send(packet, generateReceipt: false)

        let sent = outIface.sent.first(where: { $0.packetType == .data })
        XCTAssertEqual(sent?.headerType, .type2,
            "1-hop backbone path must use HEADER_2 so the backbone can route it")
        XCTAssertEqual(sent?.transportID, backboneTransportID,
            "transport ID must be the backbone's identity hash")
    }

    /// Direct 1-hop peer (no intermediate transport) must stay HEADER_1.
    func testOutboundPacketIsHeader1ForDirectPeer() throws {
        let t = Transport()
        let outIface = CapturingInterface(name: "direct")
        t.register(interface: outIface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["1hop-direct"])
        t.restore(identity: id, forDestination: dest.hash)

        // Direct peer: announce came as HEADER_1, so nextHopTransportID is nil.
        t.restore(path: Transport.PathEntry(
            destinationHash: dest.hash,
            nextHopInterfaceName: outIface.name,
            hops: 1,
            lastHeard: Date(),
            identityHash: id.hash,
            nextHopTransportID: nil               // ← no transport node
        ), forDestination: dest.hash)

        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: dest.hash,
            data: try id.encrypt(Data("ping".utf8))
        )
        try t.send(packet, generateReceipt: false)

        let sent = outIface.sent.first(where: { $0.packetType == .data })
        XCTAssertEqual(sent?.headerType, .type1,
            "direct 1-hop peer must stay HEADER_1")
        XCTAssertNil(sent?.transportID,
            "direct 1-hop peer must not have a transport ID")
    }
}
