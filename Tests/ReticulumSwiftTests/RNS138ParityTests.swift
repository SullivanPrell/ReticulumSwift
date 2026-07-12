import XCTest
@testable import ReticulumSwift

/// Parity tests for the RNS 1.3.8 changes:
///  - Packet.unpack rejects hop counts >= PATHFINDER_M (hop-count serialization
///    hardening, commit a0f0f318).
///  - Interface.holdAnnounce skips announces at/near the max hop count
///    (commit a0f0f318).
///  - Link.expectedHops on the initiator side (commit b7068888; the responder
///    side is covered in LinkParityTests).
final class RNS138ParityTests: XCTestCase {

    // A no-op interface so `Transport.register`/`send` succeed without real I/O.
    final class NoopInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws {}
    }

    // MARK: - Packet.unpack hop-count guard (PATHFINDER_M = 128)

    /// Build a valid packed packet, then return a copy with the hop byte forced
    /// to `hops`. Byte 1 of the header is the hop count.
    private func packedPacket(withHopByte hops: UInt8) throws -> Data {
        let packet = Packet(
            headerType: .type1,
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xAB, count: Constants.truncatedHashLength),
            context: .none,
            data: Data("hop-guard".utf8)
        )
        var raw = try packet.pack()
        raw[raw.startIndex + 1] = hops
        return raw
    }

    func testUnpackAcceptsHopsBelowMax() throws {
        // 127 is the highest legal hop count (PATHFINDER_M - 1).
        let raw = try packedPacket(withHopByte: 127)
        let decoded = try Packet.unpack(raw)
        XCTAssertEqual(decoded.hops, 127, "hops == 127 must unpack (it is below PATHFINDER_M)")
    }

    func testUnpackRejectsHopsAtMax() throws {
        let raw = try packedPacket(withHopByte: 128)   // == PATHFINDER_M
        XCTAssertThrowsError(try Packet.unpack(raw),
            "hops == PATHFINDER_M (128) must be rejected as malformed")
    }

    func testUnpackRejectsHopsAboveMax() throws {
        let raw = try packedPacket(withHopByte: 255)
        XCTAssertThrowsError(try Packet.unpack(raw),
            "hops == 255 must be rejected as malformed")
    }

    func testPathfinderMIs128() {
        XCTAssertEqual(Transport.pathfinderM, 128, "Python: Transport.PATHFINDER_M = 128")
    }

    // MARK: - holdAnnounce near-max-hop skip (PATHFINDER_M - 1 = 127)

    private func announcePacket(hops: UInt8, tag: String) -> Packet {
        var pkt = Packet(
            destinationType: .single,
            packetType: .announce,
            destinationHash: Hashes.truncatedHash(Data(tag.utf8)),
            data: Data(count: 10)
        )
        pkt.hops = hops
        return pkt
    }

    func testHoldAnnounceHoldsBelowNearMax() {
        let t = Transport()
        let iface = NoopInterface(name: "hold-lo")
        t.register(interface: iface)
        let pkt = announcePacket(hops: 126, tag: "lo")
        t.holdAnnounce(pkt, destinationHash: pkt.destinationHash, on: iface)
        XCTAssertEqual(t.heldAnnounceCount(for: iface), 1,
            "An announce with hops < PATHFINDER_M-1 must be held")
    }

    func testHoldAnnounceSkipsAtNearMax() {
        let t = Transport()
        let iface = NoopInterface(name: "hold-hi")
        t.register(interface: iface)
        let pkt = announcePacket(hops: 127, tag: "hi")   // == PATHFINDER_M - 1
        t.holdAnnounce(pkt, destinationHash: pkt.destinationHash, on: iface)
        XCTAssertEqual(t.heldAnnounceCount(for: iface), 0,
            "An announce with hops >= PATHFINDER_M-1 must NOT be held (would exceed hop limit on replay)")
    }

    // MARK: - Link.expectedHops on the initiator side

    func testInitiatorExpectedHopsFromPathTable() throws {
        let t = Transport()
        let iface = NoopInterface(name: "nh")
        t.register(interface: iface)

        let id = Identity()
        let dest = try Destination(identity: id, direction: .out, kind: .single,
                                   appName: "test", aspects: ["expectedhops"])
        // Inject a known path with hops = 3.
        t.restore(path: Transport.PathEntry(
            destinationHash: dest.hash, nextHopInterfaceName: iface.name,
            hops: 3, lastHeard: Date(), identityHash: id.hash),
            forDestination: dest.hash)

        let link = try Link.initiate(destination: dest, transport: t)
        XCTAssertEqual(link.expectedHops, 3,
            "Initiator expectedHops must equal the path-table hop count to the destination")
    }

    func testInitiatorExpectedHopsNilWhenNoPath() throws {
        let t = Transport()
        let iface = NoopInterface(name: "nh2")
        t.register(interface: iface)
        let id = Identity()
        let dest = try Destination(identity: id, direction: .out, kind: .single,
                                   appName: "test", aspects: ["nopath"])
        let link = try Link.initiate(destination: dest, transport: t)
        XCTAssertNil(link.expectedHops,
            "expectedHops must be nil when no path to the destination is known")
    }
}
