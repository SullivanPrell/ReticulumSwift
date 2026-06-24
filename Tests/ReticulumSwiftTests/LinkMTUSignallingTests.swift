import XCTest
import CryptoKit
@testable import ReticulumSwift

/// Verify wire compatibility with Python's link MTU signalling.
///
/// Python always appends 3 bytes of MTU+mode signalling to both the
/// link-request packet (LRR) and the link-request-proof packet (LRPR):
///
///   LRR data:  [X25519 pub 32][Ed25519 pub 32][signalling 3]  = 67 bytes
///   LRPR data: [signature 64][X25519 pub 32][signalling 3]   = 99 bytes
///
/// Signalling bytes encode the link MTU (21 bits) and cipher mode (3 bits):
///   bits[23:21] = mode << 5  (AES-256-CBC = 0x01 → 0x20 in top byte)
///   bits[20: 0] = mtu & 0x1FFFFF
///
/// For MTU=500, mode=AES256_CBC: [0x20, 0x01, 0xF4]
final class LinkMTUSignallingTests: XCTestCase {

    // MARK: - Helpers

    final class LoopbackInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []

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

    // MARK: - Signalling byte helpers (matching Python)

    static func signallingBytes(mtu: Int = Constants.mtu, mode: UInt8 = 0x01) -> Data {
        // mode_byte = (mode << 5) & 0xE0
        // signalling_value = mtu | (mode_byte << 16)  [21-bit mtu, 3-bit mode]
        let modeByte = UInt32((mode << 5) & 0xE0)
        let value = (UInt32(mtu) & 0x1FFFFF) | (modeByte << 16)
        return Data([
            UInt8((value >> 16) & 0xFF),
            UInt8((value >>  8) & 0xFF),
            UInt8( value        & 0xFF)
        ])
    }

    // MARK: - Tests

    /// Verify signalling byte computation matches Python's output.
    func testSignallingBytesMatchPython() {
        // Python: Link.signalling_bytes(500, 0x01) == b'\x20\x01\xf4'
        let bytes = LinkMTUSignallingTests.signallingBytes(mtu: 500, mode: 0x01)
        XCTAssertEqual(bytes, Data([0x20, 0x01, 0xF4]))
    }

    /// Responder must accept a 67-byte LRR (with 3 MTU signalling bytes).
    func testResponderAccepts67ByteLinkRequest() throws {
        let responderTransport = Transport()
        let bIdentity = Identity()
        let bDest = try Destination(
            identity: bIdentity, direction: .in, kind: .single, appName: "test"
        )
        responderTransport.ownerIdentity = bIdentity
        responderTransport.register(destination: bDest)

        let iface = LoopbackInterface(name: "in")
        let peer  = LoopbackInterface(name: "peer")
        iface.paired = peer; peer.paired = iface
        responderTransport.register(interface: iface)

        // Build a 67-byte LRR like Python does.
        let initiatorEnc = Curve25519.KeyAgreement.PrivateKey()
        let initiatorSig = Curve25519.Signing.PrivateKey()
        let body = initiatorEnc.publicKey.rawRepresentation
                 + initiatorSig.publicKey.rawRepresentation
                 + LinkMTUSignallingTests.signallingBytes()  // 3 extra bytes

        let lrr = Packet(
            destinationType: .single,
            packetType: .linkRequest,
            destinationHash: bDest.hash,
            data: body
        )

        try peer.send(lrr)

        // Responder must send an LRPR without error.
        // The proof goes to iface (since peer has no transport to process the RTT).
        XCTAssertFalse(iface.sent.isEmpty, "responder must send LRPR")
        let proof = try XCTUnwrap(iface.sent.first)
        XCTAssertEqual(proof.packetType, .proof)
        XCTAssertEqual(proof.context, .lrproof)
        // Proof must include 3 signalling bytes: 64 sig + 32 pub + 3 = 99 bytes.
        XCTAssertEqual(proof.data.count, 64 + 32 + 3, "proof must include MTU signalling")
    }

    /// Initiator must accept a 99-byte LRPR (with 3 MTU signalling bytes)
    /// and validate its signature correctly.
    func testInitiatorAccepts99ByteLinkProof() throws {
        let aT = Transport()
        let bT = Transport()

        let bIdentity = Identity()
        let bDest = try Destination(
            identity: bIdentity, direction: .in, kind: .single, appName: "test"
        )
        bT.ownerIdentity = bIdentity
        bT.register(destination: bDest)

        let aIface = LoopbackInterface(name: "A→B")
        let bIface = LoopbackInterface(name: "B→A")
        aIface.paired = bIface; bIface.paired = aIface
        aT.register(interface: aIface)
        bT.register(interface: bIface)

        let aE = expectation(description: "A established")
        let bE = expectation(description: "B established")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }

        let aLink = try Link.initiate(destination: bDest, transport: aT)
        _ = aLink

        wait(for: [aE, bE], timeout: 2.0)
    }

    /// Swift initiator sends 67-byte LRR; Python-aware responder echoes
    /// back 99-byte LRPR; Swift initiator accepts it.
    func testFullRoundTripWithSignalling() throws {
        // This test simulates the full handshake as Python would do it
        // by intercepting the LRR and injecting a Python-style LRPR.
        let aT = Transport()

        let bIdentity = Identity()
        let bDest = try Destination(
            identity: bIdentity, direction: .in, kind: .single, appName: "test"
        )

        let aIface = LoopbackInterface(name: "A")
        let fakePeer = LoopbackInterface(name: "peer")
        aIface.paired = fakePeer; fakePeer.paired = aIface
        aT.register(interface: aIface)

        let aE = expectation(description: "A established")
        aT.onLinkEstablished = { _ in aE.fulfill() }

        let aLink = try Link.initiate(destination: bDest, transport: aT)

        // Verify LRR has 67 bytes (aIface records what aT sent through it).
        let lrr = try XCTUnwrap(aIface.sent.first, "must receive LRR")
        XCTAssertEqual(lrr.packetType, .linkRequest)
        XCTAssertEqual(lrr.data.count, 67, "LRR must include 3 signalling bytes")

        // Simulate Python's prove() — build a 99-byte proof.
        let linkID = aLink.linkID!
        let sig = LinkMTUSignallingTests.signallingBytes()
        let responderEph = Curve25519.KeyAgreement.PrivateKey()
        let responderPubBytes = responderEph.publicKey.rawRepresentation
        let responderSigPubBytes = bIdentity.signingPublicKey.rawRepresentation
        let signedData = linkID + responderPubBytes + responderSigPubBytes + sig
        let signature = try bIdentity.sign(signedData)

        let lrpr = Packet(
            destinationType: .link,
            packetType: .proof,
            destinationHash: linkID,
            context: .lrproof,
            data: signature + responderPubBytes + sig
        )

        try fakePeer.send(lrpr)

        wait(for: [aE], timeout: 1.0)
        XCTAssertEqual(aLink.status, .active)
    }

    /// When the next-hop interface has a known HW MTU (AUTOCONFIGURE_MTU or
    /// FIXED_MTU), Link.initiate signals that MTU instead of the default 500.
    /// Mirrors Python: Transport.next_hop_interface_hw_mtu → Link.signalling_bytes.
    func testInitiatorSignalsHwMtuWhenPathKnown() throws {
        final class HighMtuInterface: Interface {
            var name: String = "highMtu"
            var bitrate: Int = 10_000_000
            var isOnline: Bool = true
            var hwMtu: Int? = 262_144
            var autoconfigureMtu: Bool = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            var sent: [Packet] = []
            func start() throws { isOnline = true }
            func stop() { isOnline = false }
            func send(_ packet: Packet) throws { sent.append(packet) }
        }

        let aT = Transport()
        let bIdentity = Identity()
        let bDest = try Destination(
            identity: bIdentity, direction: .in, kind: .single, appName: "mtudisco"
        )
        let aIface = HighMtuInterface()
        aT.register(interface: aIface)

        // Seed a path to bDest via aIface.
        aT.restore(
            path: Transport.PathEntry(
                destinationHash: bDest.hash,
                nextHopInterfaceName: "highMtu",
                hops: 1,
                lastHeard: Date(),
                identityHash: bIdentity.hash
            ),
            forDestination: bDest.hash
        )

        _ = try Link.initiate(destination: bDest, transport: aT)

        let lrr = try XCTUnwrap(aIface.sent.first)
        XCTAssertEqual(lrr.data.count, 67)

        // Extract the 3 signalling bytes at the end of LRR data.
        let sigBytes = lrr.data.suffix(3)
        // Parse: bits[20:0] = mtu, bits[23:21] = mode
        let b0 = UInt32(sigBytes[sigBytes.startIndex])
        let b1 = UInt32(sigBytes[sigBytes.startIndex + 1])
        let b2 = UInt32(sigBytes[sigBytes.startIndex + 2])
        let value = (b0 << 16) | (b1 << 8) | b2
        let signaledMtu = Int(value & 0x1FFFFF)
        XCTAssertEqual(signaledMtu, 262_144, "LRR must signal HW MTU 262144")
    }

    /// When no path is known, initiator falls back to signalling Constants.mtu (500).
    func testInitiatorFallsBackToDefaultMtuWhenNoPath() throws {
        let aT = Transport()
        let bIdentity = Identity()
        let bDest = try Destination(
            identity: bIdentity, direction: .in, kind: .single, appName: "nomtu"
        )
        let iface = LoopbackInterface(name: "x")
        let peer  = LoopbackInterface(name: "y")
        iface.paired = peer; peer.paired = iface
        aT.register(interface: iface)

        _ = try Link.initiate(destination: bDest, transport: aT)

        let lrr = try XCTUnwrap(iface.sent.first)
        XCTAssertEqual(lrr.data.count, 67)

        let sigBytes = lrr.data.suffix(3)
        let b0 = UInt32(sigBytes[sigBytes.startIndex])
        let b1 = UInt32(sigBytes[sigBytes.startIndex + 1])
        let b2 = UInt32(sigBytes[sigBytes.startIndex + 2])
        let value = (b0 << 16) | (b1 << 8) | b2
        let signaledMtu = Int(value & 0x1FFFFF)
        XCTAssertEqual(signaledMtu, Constants.mtu, "should fall back to default MTU 500")
    }
}
