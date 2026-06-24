import XCTest
@testable import ReticulumSwift

final class MultiHopLinkTests: XCTestCase {

    /// Loopback interface paired in-memory to one peer.
    final class HopInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        weak var paired: HopInterface?
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

    /// Pair two interfaces (one on each Transport) so packets sent on one
    /// land on the other side's inbound handler.
    func wire(_ a: HopInterface, _ b: HopInterface) {
        a.paired = b; b.paired = a
    }

    func testLinkEstablishesAndExchangesDataThroughRelay() throws {
        // A (initiator) <-> R (relay) <-> B (responder)
        let aTransport = Transport()
        let rTransport = Transport()
        let bTransport = Transport()

        // Responder identity + destination, registered on B.
        let bIdentity = Identity()
        let bDestination = try Destination(
            identity: bIdentity, direction: .in, kind: .single,
            appName: "lxmf", aspects: ["delivery"]
        )
        bTransport.ownerIdentity = bIdentity
        bTransport.register(destination: bDestination)

        // Wire A <-> R
        let aToR = HopInterface(name: "A→R")
        let rFromA = HopInterface(name: "R←A")
        wire(aToR, rFromA)
        aTransport.register(interface: aToR)
        rTransport.register(interface: rFromA)

        // Wire R <-> B
        let rToB = HopInterface(name: "R→B")
        let bFromR = HopInterface(name: "B←R")
        wire(rToB, bFromR)
        rTransport.register(interface: rToB)
        bTransport.register(interface: bFromR)

        // Seed R's path table so it knows B's destination is reachable
        // through the rToB interface. (In a real network this would come
        // from B announcing.)
        rTransport.restore(
            path: Transport.PathEntry(
                destinationHash: bDestination.hash,
                nextHopInterfaceName: rToB.name,
                hops: 1,
                lastHeard: Date(),
                identityHash: bIdentity.hash
            ),
            forDestination: bDestination.hash
        )

        // Watch for both sides reaching ACTIVE.
        let initiatorEstablished = expectation(description: "initiator established")
        let responderEstablished = expectation(description: "responder established")
        aTransport.onLinkEstablished = { _ in initiatorEstablished.fulfill() }
        bTransport.onLinkEstablished = { _ in responderEstablished.fulfill() }

        // Initiator opens a link to the responder destination.
        let aLink = try Link.initiate(destination: bDestination, transport: aTransport)
        wait(for: [initiatorEstablished, responderEstablished], timeout: 1.0)
        XCTAssertEqual(aLink.status, .active)

        // R should have learned a route for the link id.
        let route = rTransport.linkRoutes[aLink.linkID!]
        XCTAssertEqual(route?.initiatorSideInterfaceName, rFromA.name)
        XCTAssertEqual(route?.responderSideInterfaceName, rToB.name)

        // Encrypted user data round-trips through the relay.
        let bLink = try XCTUnwrap(bTransport.links[aLink.linkID!])
        let received = expectation(description: "responder got data")
        var got: Data?
        bLink.onDataReceived = { data, _ in got = data; received.fulfill() }

        try aLink.send(Data("over three hops".utf8))
        wait(for: [received], timeout: 1.0)
        XCTAssertEqual(got, Data("over three hops".utf8))

        // Teardown propagates back.
        let closed = expectation(description: "responder side closed")
        bLink.onClosed = { _ in closed.fulfill() }
        try aLink.teardown()
        wait(for: [closed], timeout: 1.0)
        XCTAssertEqual(bLink.status, .closed)
    }
}
