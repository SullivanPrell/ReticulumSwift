import XCTest
@testable import ReticulumSwift

/// Tests for proof forwarding through relay/transport nodes.
/// In Python, Transport maintains a `reverse_table` so that when a DATA packet
/// is forwarded through a relay, the resulting proof travels back the same path.
///
/// Topology: Sender (A) <-> Relay (R) <-> Destination (B)
final class ProofForwardingTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        weak var paired: LoopbackInterface?
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

    /// Tests that a proof sent from B propagates back through relay R to A,
    /// where it can validate an outstanding PacketReceipt.
    func testProofForwardedThroughRelay() throws {
        // Topology: A <-> R <-> B
        // A sends DATA to B via R; B generates proof; R forwards proof back to A.

        let aT = Transport()
        let rT = Transport()
        let bT = Transport()

        rT.transportEnabled = true  // R is a transport node

        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["relay"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)
        bDest.proofStrategy = .proveAll

        // Wire: A <-> R (interfaces A→R and R←A)
        let aToR = LoopbackInterface(name: "A→R")
        let rFromA = LoopbackInterface(name: "R←A")
        aToR.paired = rFromA; rFromA.paired = aToR
        aT.register(interface: aToR)
        rT.register(interface: rFromA)

        // Wire: R <-> B (interfaces R→B and B←R)
        let rToB = LoopbackInterface(name: "R→B")
        let bFromR = LoopbackInterface(name: "B←R")
        rToB.paired = bFromR; bFromR.paired = rToB
        rT.register(interface: rToB)
        bT.register(interface: bFromR)

        // Seed R's path table. B is directly reachable on the R→B interface,
        // so hops = 0 (Python remaining_hops == 1). Per the relay rules this
        // means R must strip the transport header and deliver to B as HEADER_1
        // — B filters on transport_id, so a HEADER_2 packet bearing R's id
        // would (correctly) be dropped.
        rT.restore(
            path: Transport.PathEntry(
                destinationHash: bDest.hash,
                nextHopInterfaceName: rToB.name,
                hops: 0,
                lastHeard: Date(),
                identityHash: bId.hash
            ),
            forDestination: bDest.hash
        )

        // A needs B's identity to encrypt
        aT.restore(identity: bId, forDestination: bDest.hash)

        // Send DATA from A to B; the packet must be forwarded by R.
        let packet = Packet(
            destinationType: .single, packetType: .data,
            destinationHash: bDest.hash,
            data: try bId.encrypt(Data("multi-hop proof test".utf8))
        )

        let delivered = expectation(description: "proof delivered back to A")
        let receipt = try aT.send(packet)
        receipt?.onDelivery = { _ in delivered.fulfill() }

        wait(for: [delivered], timeout: 2.0)
        XCTAssertEqual(receipt?.status, .delivered)
        XCTAssertTrue(receipt?.proved ?? false)
    }
}
