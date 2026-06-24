import XCTest
@testable import ReticulumSwift

/// Tests verifying that Destination.acceptsLinks controls whether link requests are answered.
/// Python: `if self.accept_link_requests: link = Link.validate_request(self, data, packet)`
final class DestinationAcceptsLinksTests: XCTestCase {

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    func testDestinationAcceptsLinksByDefault() {
        let dest = try! Destination(
            identity: Identity(), direction: .in, kind: .single,
            appName: "test", aspects: []
        )
        XCTAssertTrue(dest.acceptsLinks, "destinations should accept links by default")
    }

    func testLinkEstablishesWhenAcceptsLinksTrue() throws {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["accept"])
        bDest.acceptsLinks = true
        bT.ownerIdentity = bId; bT.register(destination: bDest)

        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)

        let established = expectation(description: "established")
        aT.onLinkEstablished = { _ in established.fulfill() }
        _ = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [established], timeout: 1.0)
    }

    func testLinkNotEstablishedWhenAcceptsLinksFalse() throws {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["reject"])
        bDest.acceptsLinks = false  // reject incoming link requests
        bT.ownerIdentity = bId; bT.register(destination: bDest)

        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)

        let notEstablished = expectation(description: "not-established")
        notEstablished.isInverted = true
        aT.onLinkEstablished = { _ in notEstablished.fulfill() }
        _ = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [notEstablished], timeout: 0.3)
    }
}
