import XCTest
@testable import ReticulumSwift

/// Tests for the Transport tunnel system:
///   * synthesizeTunnel() — sends a PLAIN DATA packet to rnstransport.tunnel.synthesize
///   * tunnel_synthesize_handler — validates the packet, creates a TunnelEntry
///   * Announces received on a tunneled interface are recorded in tunnel paths
/// Matches Python's Transport.synthesize_tunnel / tunnel_synthesize_handler.
final class TunnelTests: XCTestCase {

    // MARK: - Well-known destination hash

    func testTunnelSynthesizeHashIsStable() {
        let h1 = Transport.tunnelSynthesizeHash
        let h2 = Transport.tunnelSynthesizeHash
        XCTAssertEqual(h1, h2)
        XCTAssertEqual(h1.count, Constants.truncatedHashLength)
    }

    // MARK: - synthesizeTunnel

    func testSynthesizeTunnelSendsDataPacketOnInterface() throws {
        let transport = Transport()
        let identity = Identity()
        transport.ownerIdentity = identity

        let iface = TunnelTestIface(name: "tun0")
        let exp = expectation(description: "packet sent")
        exp.assertForOverFulfill = false
        var sentPacket: Packet?
        iface.onSend = { p in sentPacket = p; exp.fulfill() }

        transport.synthesizeTunnel(iface)
        wait(for: [exp], timeout: 1.0)

        let pkt = try XCTUnwrap(sentPacket)
        XCTAssertEqual(pkt.packetType, .data)
        XCTAssertEqual(pkt.headerType, .type1)
        XCTAssertEqual(pkt.destinationType, .plain)
        XCTAssertEqual(pkt.destinationHash, Transport.tunnelSynthesizeHash)
        // Wire: public_key(64) + interface_hash(32) + random_hash(16) + signature(64) = 176
        XCTAssertEqual(pkt.data.count, 64 + 32 + 16 + 64)
    }

    func testSynthesizeTunnelNilIdentityDoesNothing() {
        let transport = Transport()
        // No ownerIdentity set — should not crash or send
        let iface = TunnelTestIface(name: "no-id")
        transport.synthesizeTunnel(iface)
        XCTAssertNil(iface.lastSentPacket)
    }

    func testSynthesizeTunnelClearsWantsTunnel() throws {
        let transport = Transport()
        transport.ownerIdentity = Identity()
        let iface = TunnelTestIface(name: "tun-clr")
        iface.wantsTunnel = true
        iface.onSend = { _ in }
        transport.synthesizeTunnel(iface)
        XCTAssertFalse(iface.wantsTunnel)
    }

    // MARK: - tunnelSynthesizeHandler (via inbound dispatch)

    func testTunnelSynthesizeHandlerCreatesEntry() throws {
        let transport = Transport()
        let remoteIdentity = Identity()

        // Build valid synthesize data: public_key + interface_hash + random_hash + signature
        let ifaceName = "tunnel-src"
        let publicKey = remoteIdentity.publicKeyBytes          // 64 bytes
        let ifaceHash = Hashes.fullHash(Data(ifaceName.utf8)) // 32 bytes
        let tunnelIDData = publicKey + ifaceHash
        let tunnelID = Hashes.fullHash(tunnelIDData)           // 32 bytes
        let randomHash = Hashes.randomHash()                   // 16 bytes
        let signedData = tunnelIDData + randomHash
        let signature = try remoteIdentity.sign(signedData)    // 64 bytes
        let data = tunnelIDData + randomHash + signature        // 176 bytes

        let synthPacket = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.tunnelSynthesizeHash,
            data: data
        )

        // Register a receiving interface and deliver the packet
        let iface = TunnelTestIface(name: "recv0")
        transport.register(interface: iface)
        iface.inboundHandler?(synthPacket, iface)

        // TunnelEntry should have been created
        let entry = transport.tunnels[tunnelID]
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.tunnelID, tunnelID)
        XCTAssertTrue(entry?.iface === iface)
    }

    func testTunnelSynthesizeHandlerRejectsInvalidSignature() throws {
        let transport = Transport()
        let remoteIdentity = Identity()

        let ifaceName = "bad-sig"
        let publicKey = remoteIdentity.publicKeyBytes
        let ifaceHash = Hashes.fullHash(Data(ifaceName.utf8))
        let tunnelIDData = publicKey + ifaceHash
        let tunnelID = Hashes.fullHash(tunnelIDData)
        let randomHash = Hashes.randomHash()
        let data = tunnelIDData + randomHash + Data(count: 64)  // 64 zero bytes = bad sig

        let synthPacket = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.tunnelSynthesizeHash,
            data: data
        )

        let iface = TunnelTestIface(name: "recv-bad")
        transport.register(interface: iface)
        iface.inboundHandler?(synthPacket, iface)

        XCTAssertNil(transport.tunnels[tunnelID])
    }

    func testTunnelSynthesizeHandlerRejectsWrongLength() {
        let transport = Transport()
        let synthPacket = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.tunnelSynthesizeHash,
            data: Data(count: 100)  // wrong length
        )
        let iface = TunnelTestIface(name: "recv-short")
        transport.register(interface: iface)
        iface.inboundHandler?(synthPacket, iface)
        XCTAssertTrue(transport.tunnels.isEmpty)
    }

    // MARK: - Interface wantsTunnel / tunnelID defaults

    func testInterfaceWantsTunnelDefaultFalse() {
        let iface = TunnelTestIface(name: "default")
        XCTAssertFalse(iface.wantsTunnel)
        XCTAssertNil(iface.tunnelID)
    }

    func testRegisterInterfaceWithWantsTunnelAutoSynthesizes() throws {
        let transport = Transport()
        transport.ownerIdentity = Identity()

        let iface = TunnelTestIface(name: "auto-tun")
        iface.wantsTunnel = true

        let exp = expectation(description: "synthesize sent on register")
        exp.assertForOverFulfill = false
        iface.onSend = { _ in exp.fulfill() }

        transport.register(interface: iface)
        wait(for: [exp], timeout: 1.0)
        // synthesize clears the flag
        XCTAssertFalse(iface.wantsTunnel)
    }

    // MARK: - Announce recorded in tunnel paths

    func testAnnounceOnTunneledInterfaceRecordedInTunnelPaths() throws {
        let transport = Transport()

        let iface = TunnelTestIface(name: "tun-ann")
        transport.register(interface: iface)

        // Manually install a tunnel entry linked to this interface
        let tunnelID = Hashes.randomHash()
        iface.tunnelID = tunnelID
        transport.tunnels[tunnelID] = Transport.TunnelEntry(
            tunnelID: tunnelID,
            iface: iface,
            paths: [:],
            expires: Date().addingTimeInterval(Transport.tunnelTimeout)
        )

        // Send a valid announce through this interface
        let destId = Identity()
        let dest = try Destination(identity: destId, direction: .in, kind: .single, appName: "app", aspects: [])
        let announcePacket = try Announce.make(for: dest)
        iface.inboundHandler?(announcePacket, iface)

        // Path should appear in tunnel entry's paths dict
        let entry = transport.tunnels[tunnelID]
        XCTAssertNotNil(entry?.paths[dest.hash])
    }
}

// MARK: - Test double

private final class TunnelTestIface: Interface {
    let name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    var rawInboundHandler: ((Data, any Interface) -> Void)?
    var ifacIdentity: Identity?
    var ifacKey: Data?
    var ifacSize: Int = Constants.defaultIfacSize
    var wantsTunnel: Bool = false
    var tunnelID: Data?

    var onSend: ((Packet) -> Void)?
    private(set) var lastSentPacket: Packet?

    init(name: String) { self.name = name }

    func send(_ packet: Packet) throws {
        lastSentPacket = packet
        onSend?(packet)
    }
    func start() throws {}
    func stop() {}
}
