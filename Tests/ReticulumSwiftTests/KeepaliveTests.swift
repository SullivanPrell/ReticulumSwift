import XCTest
@testable import ReticulumSwift

final class KeepaliveTests: XCTestCase {

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

    var aTransport: Transport!
    var bTransport: Transport!

    private func establishLink() throws -> (Link, Link) {
        aTransport = Transport()
        bTransport = Transport()
        let bIdentity = Identity()
        let bDest = try Destination(
            identity: bIdentity, direction: .in, kind: .single, appName: "x"
        )
        bTransport.ownerIdentity = bIdentity
        bTransport.register(destination: bDest)
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aTransport.register(interface: aI); bTransport.register(interface: bI)

        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aTransport.onLinkEstablished = { _ in aE.fulfill() }
        bTransport.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aTransport)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bTransport.links[aLink.linkID!])
        return (aLink, bLink)
    }

    func testKeepaliveProbeIsEchoedBack() throws {
        let (aLink, bLink) = try establishLink()

        let beforeAOut = aLink.lastOutbound
        let beforeAIn = aLink.lastInbound
        let beforeBIn = bLink.lastInbound

        try aLink.sendKeepalive()

        // Initiator recorded an outbound and (synchronously) the
        // responder's reply landed inbound.
        XCTAssertNotNil(aLink.lastKeepalive)
        XCTAssertNotEqual(aLink.lastOutbound, beforeAOut)
        XCTAssertNotEqual(aLink.lastInbound, beforeAIn)
        XCTAssertNotEqual(bLink.lastInbound, beforeBIn)
    }

    func testResponderIgnoresKeepaliveSendOnly() throws {
        let (_, bLink) = try establishLink()
        // Calling sendKeepalive on the responder side is a no-op
        // (Python only the initiator initiates).
        try bLink.sendKeepalive()
        XCTAssertNil(bLink.lastKeepalive)
    }
}
