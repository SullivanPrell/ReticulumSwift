import XCTest
import CryptoKit
@testable import ReticulumSwift

/// In-memory loopback interface — `send` on one side delivers straight to
/// the inbound handler of the paired interface, on the same Transport.
final class LoopbackInterface: Interface {
    var name: String
    var bitrate: Int = 0
    var isOnline: Bool = true
    weak var paired: LoopbackInterface?
    var inboundHandler: ((Packet, any Interface) -> Void)?

    init(name: String) { self.name = name }

    func start() throws { isOnline = true }
    func stop() { isOnline = false }

    func send(_ packet: Packet) throws {
        let raw = try packet.pack()
        let copy = try Packet.unpack(raw)
        paired?.inboundHandler?(copy, paired!)
    }
}

final class LinkTests: XCTestCase {

    func testThreePacketHandshakeOverLoopback() throws {
        // Responder side: a Transport that owns a destination.
        let responderIdentity = Identity()
        let responderDestination = try Destination(
            identity: responderIdentity,
            direction: .in,
            kind: .single,
            appName: "lxmf",
            aspects: ["delivery"]
        )

        let responderTransport = Transport()
        responderTransport.ownerIdentity = responderIdentity
        responderTransport.register(destination: responderDestination)

        // Initiator side: empty Transport that knows the responder via the
        // destination object directly (no announce machinery here).
        let initiatorTransport = Transport()

        let ifaceA = LoopbackInterface(name: "A")
        let ifaceB = LoopbackInterface(name: "B")
        ifaceA.paired = ifaceB
        ifaceB.paired = ifaceA
        initiatorTransport.register(interface: ifaceA)
        responderTransport.register(interface: ifaceB)

        let initiatorEstablished = expectation(description: "initiator established")
        let responderEstablished = expectation(description: "responder established")

        initiatorTransport.onLinkEstablished = { _ in initiatorEstablished.fulfill() }
        responderTransport.onLinkEstablished = { _ in responderEstablished.fulfill() }

        let link = try Link.initiate(destination: responderDestination, transport: initiatorTransport)
        XCTAssertEqual(link.role, .initiator)

        wait(for: [initiatorEstablished, responderEstablished], timeout: 1.0)

        XCTAssertEqual(link.status, .active)
        XCTAssertEqual(link.linkID?.count, Constants.truncatedHashLength)

        // Both sides must agree on the link id and shared key.
        let responderLink = responderTransport.links[link.linkID!]
        XCTAssertNotNil(responderLink)
        XCTAssertEqual(responderLink?.derivedKey, link.derivedKey)
        XCTAssertEqual(responderLink?.linkID, link.linkID)

        // Encrypted data round-trips.
        let plaintext = Data("ping".utf8)
        let ciphertext = try link.encrypt(plaintext)
        XCTAssertEqual(try responderLink?.decrypt(ciphertext), plaintext)
    }

    func testValidateProofRejectsBadSignature() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let transport = Transport()
        let link = try Link.initiate(destination: destination, transport: transport)

        // Forge a proof packet with a random, valid-length signature.
        let badSig = Data(repeating: 0xAB, count: Constants.signatureLength)
        let randomPub = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let proof = Packet(
            destinationType: .link,
            packetType: .proof,
            destinationHash: link.linkID!,
            context: .lrproof,
            data: badSig + randomPub
        )

        XCTAssertThrowsError(try link.validateProof(proof)) { error in
            XCTAssertEqual(error as? Link.LinkError, .invalidSignature)
        }
    }

    func testDataRoundTripOverEstablishedLink() throws {
        let pair = try makeEstablishedLinkPair()
        let received = expectation(description: "responder received data")
        var got: Data?
        pair.responderLink.onDataReceived = { data, _ in
            got = data
            received.fulfill()
        }
        try pair.initiator.send(Data("hello world".utf8))
        wait(for: [received], timeout: 1.0)
        XCTAssertEqual(got, Data("hello world".utf8))
    }

    func testTeardownClosesBothSides() throws {
        let pair = try makeEstablishedLinkPair()
        let closed = expectation(description: "responder side closed")
        pair.responderLink.onClosed = { _ in closed.fulfill() }

        try pair.initiator.teardown()
        wait(for: [closed], timeout: 1.0)

        XCTAssertEqual(pair.initiator.status, .closed)
        XCTAssertEqual(pair.responderLink.status, .closed)
        XCTAssertNil(pair.responderTransport.links[pair.initiator.linkID!])
    }

    // MARK: - Helpers

    struct LinkPair {
        let initiator: Link
        let responderLink: Link
        let initiatorTransport: Transport
        let responderTransport: Transport
    }

    func makeEstablishedLinkPair() throws -> LinkPair {
        let responderIdentity = Identity()
        let responderDestination = try Destination(
            identity: responderIdentity, direction: .in, kind: .single,
            appName: "lxmf", aspects: ["delivery"]
        )
        let responderTransport = Transport()
        responderTransport.ownerIdentity = responderIdentity
        responderTransport.register(destination: responderDestination)

        let initiatorTransport = Transport()
        let ifaceA = LoopbackInterface(name: "A")
        let ifaceB = LoopbackInterface(name: "B")
        ifaceA.paired = ifaceB; ifaceB.paired = ifaceA
        initiatorTransport.register(interface: ifaceA)
        responderTransport.register(interface: ifaceB)

        let link = try Link.initiate(destination: responderDestination, transport: initiatorTransport)
        let responderLink = try XCTUnwrap(responderTransport.links[link.linkID!])
        XCTAssertEqual(link.status, .active)
        XCTAssertEqual(responderLink.status, .active)
        return LinkPair(
            initiator: link,
            responderLink: responderLink,
            initiatorTransport: initiatorTransport,
            responderTransport: responderTransport
        )
    }

    func testMsgPackFloatRoundTrip() throws {
        let original = 0.12345
        let encoded = MsgPack.encodeDouble(original)
        XCTAssertEqual(encoded.count, 9)
        XCTAssertEqual(encoded[0], 0xCB)
        XCTAssertEqual(try MsgPack.decodeDouble(encoded), original)
    }
}
