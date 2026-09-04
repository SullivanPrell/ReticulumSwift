import XCTest
@testable import ReticulumSwift

/// A relay must validate the signature on a link-request proof before forwarding it.
///
/// Python checks the proof against the responder's recalled identity and branches hard on the
/// result (`Transport.py:2657-2669`): it forwards a valid proof and marks the link-table entry
/// validated, and it drops an invalid one and raises a protocol violation on the receiving
/// interface. It also requires the proof to arrive on the link's next-hop interface—the side
/// facing the responder—since that's the only direction a proof can legitimately come from.
///
/// This port forwarded any well-formed proof whose link ID was in the table, from either side,
/// without looking at the signature. A link endpoint still validates, so a forged proof can't
/// establish a link; what the gap bought an attacker was a Swift transport node that would
/// carry the forgery for them and never count it.
final class RelayLinkProofValidationTests: XCTestCase {

    // MARK: - Harness

    /// Records what the relay put on the wire, so these assertions are about transmission
    /// rather than about an internal flag.
    private final class RecordingHop: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    /// A relay holding one link-table entry, with the responder's identity recalled the way a
    /// prior announce would have left it.
    private struct Relay {
        let transport: Transport
        let towardInitiator: RecordingHop
        let towardResponder: RecordingHop
        let responder: Identity
        let linkID: Data
        let destinationHash: Data
    }

    private func makeRelay() -> Relay {
        let t = Transport()
        let responder = Identity()
        let destinationHash = Data(repeating: 0x4D, count: Constants.truncatedHashLength)
        let linkID = Data(repeating: 0x71, count: Constants.truncatedHashLength)

        let towardInitiator = RecordingHop(name: "R←A")
        let towardResponder = RecordingHop(name: "R→B")
        t.register(interface: towardInitiator)
        t.register(interface: towardResponder)

        t.restore(identity: responder, forDestination: destinationHash)
        t.restore(linkRoute: Transport.LinkRoute(
            linkID: linkID,
            initiatorSideInterface: towardInitiator,
            responderSideInterface: towardResponder,
            initiatorSideInterfaceName: towardInitiator.name,
            responderSideInterfaceName: towardResponder.name,
            destinationHash: destinationHash,
            lastHeard: Date()))

        return Relay(transport: t, towardInitiator: towardInitiator, towardResponder: towardResponder,
                     responder: responder, linkID: linkID, destinationHash: destinationHash)
    }

    /// A structurally valid proof: 64 signature bytes then the responder's 32-byte ephemeral
    /// public key. `signedBy` nil produces the forged case—right shape, wrong signature.
    private func proof(for relay: Relay, signedBy signer: Identity?) throws -> Packet {
        let ephemeral = Data((0..<Constants.halfKeySize).map { UInt8(($0 &* 7) &+ 3) })
        let signature: Data
        if let signer {
            // Python signs `packet.destination_hash + peer_pub_bytes + peer_sig_pub_bytes`
            // (`Transport.py:2655`), where the destination hash of an LRPROOF is the link ID.
            let signed = relay.linkID + ephemeral
                + relay.responder.signingPublicKey.rawRepresentation
            signature = try signer.sign(signed)
        } else {
            signature = Data(repeating: 0xFF, count: Constants.signatureLength)
        }
        return Packet(destinationType: .link,
                      packetType: .proof,
                      destinationHash: relay.linkID,
                      context: .lrproof,
                      data: signature + ephemeral)
    }

    // MARK: - The forged proof

    func testAProofWithAnInvalidSignatureIsNotForwarded() throws {
        let relay = makeRelay()
        let forged = try proof(for: relay, signedBy: nil)

        relay.transport.handleIncoming(packet: forged, from: relay.towardResponder)

        XCTAssertEqual(relay.towardInitiator.sent.count, 0,
                       """
                       `else: … return packet.receiving_interface.protocol_violation(…)` \
                       (Transport.py:2668). Forwarding it makes this node carry an attacker's \
                       forgery to the initiator, which is the whole point of the check.
                       """)
    }

    func testAProofWithAnInvalidSignatureRaisesAProtocolViolation() throws {
        let relay = makeRelay()
        let before = relay.transport.interfaceCounts(for: relay.towardResponder).protocolViolations

        relay.transport.handleIncoming(packet: try proof(for: relay, signedBy: nil),
                                       from: relay.towardResponder)

        XCTAssertEqual(relay.transport.interfaceCounts(for: relay.towardResponder).protocolViolations,
                       before + 1,
                       """
                       Python counts the violation on the receiving interface, and `rnstatus` \
                       surfaces it. Dropping the proof silently loses the only signal an \
                       operator gets that someone is injecting forgeries.
                       """)
    }

    // MARK: - The genuine proof

    func testAValidlySignedProofIsForwardedToTheInitiator() throws {
        let relay = makeRelay()
        let genuine = try proof(for: relay, signedBy: relay.responder)

        relay.transport.handleIncoming(packet: genuine, from: relay.towardResponder)

        XCTAssertEqual(relay.towardInitiator.sent.count, 1,
                       "the gate must not break relaying: a real proof still has to reach the "
                       + "initiator, or no link through this node ever completes")
        XCTAssertEqual(relay.towardInitiator.sent.first?.data, genuine.data)
        XCTAssertEqual(relay.transport.interfaceCounts(for: relay.towardResponder).protocolViolations, 0)
    }

    func testAValidlySignedProofMarksTheLinkTableEntryValidated() throws {
        let relay = makeRelay()
        XCTAssertEqual(relay.transport.linkRoutes[relay.linkID]?.validated, false,
                       "an entry starts unvalidated—no proof has been checked yet")

        relay.transport.handleIncoming(packet: try proof(for: relay, signedBy: relay.responder),
                                       from: relay.towardResponder)

        XCTAssertEqual(relay.transport.linkRoutes[relay.linkID]?.validated, true,
                       "`link_table[…][IDX_LT_VALIDATED] = True` (Transport.py:2661)—the flag "
                       + "is set where the signature is checked, and nowhere else")
    }

    func testAForgedProofLeavesTheEntryUnvalidated() throws {
        let relay = makeRelay()
        relay.transport.handleIncoming(packet: try proof(for: relay, signedBy: nil),
                                       from: relay.towardResponder)
        XCTAssertEqual(relay.transport.linkRoutes[relay.linkID]?.validated, false,
                       "otherwise the flag records 'a proof arrived', not 'a proof verified', "
                       + "and anything counting validated entries counts forgeries")
    }

    // MARK: - Direction and recall

    func testAProofArrivingFromTheInitiatorSideIsNotForwarded() throws {
        let relay = makeRelay()
        let genuine = try proof(for: relay, signedBy: relay.responder)

        // Correctly signed, but arriving from the wrong side of the link. Python gates on
        // `packet.receiving_interface == link_entry[IDX_LT_NH_IF]` (Transport.py:2643); a proof
        // travels responder→initiator, so the initiator side is never a legitimate source.
        relay.transport.handleIncoming(packet: genuine, from: relay.towardInitiator)

        XCTAssertEqual(relay.towardResponder.sent.count, 0,
                       "a valid signature doesn't make a wrong-direction proof relayable—it "
                       + "would let anyone on the initiator side replay it back at the responder")
    }

    func testAProofForADestinationWhoseIdentityIsUnknownIsNotForwarded() throws {
        let t = Transport()
        let responder = Identity()
        let destinationHash = Data(repeating: 0x4D, count: Constants.truncatedHashLength)
        let linkID = Data(repeating: 0x71, count: Constants.truncatedHashLength)
        let towardInitiator = RecordingHop(name: "R←A")
        let towardResponder = RecordingHop(name: "R→B")
        t.register(interface: towardInitiator)
        t.register(interface: towardResponder)
        // Deliberately no `restore(identity:)`: this relay knows the route but never heard the
        // announce that would carry the responder's keys.
        t.restore(linkRoute: Transport.LinkRoute(
            linkID: linkID,
            initiatorSideInterface: towardInitiator,
            responderSideInterface: towardResponder,
            initiatorSideInterfaceName: towardInitiator.name,
            responderSideInterfaceName: towardResponder.name,
            destinationHash: destinationHash,
            lastHeard: Date()))
        let relay = Relay(transport: t, towardInitiator: towardInitiator, towardResponder: towardResponder,
                          responder: responder, linkID: linkID, destinationHash: destinationHash)

        t.handleIncoming(packet: try proof(for: relay, signedBy: responder), from: towardResponder)

        XCTAssertEqual(towardInitiator.sent.count, 0,
                       """
                       Python reaches `peer_identity.get_public_key()` on `None`, and the \
                       enclosing `except Exception` swallows it without transmitting \
                       (Transport.py:2671). A node that can't check the signature must not \
                       vouch for the proof by relaying it.
                       """)
        XCTAssertEqual(t.interfaceCounts(for: towardResponder).protocolViolations, 0,
                       "Python's exception path logs but raises no violation—the proof may be "
                       + "perfectly genuine, this node simply can't tell")
    }
}
