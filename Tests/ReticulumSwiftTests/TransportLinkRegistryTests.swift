import XCTest
@testable import ReticulumSwift

/// Tests for Transport link registry management.
final class TransportLinkRegistryTests: XCTestCase {

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

    func testLinkRegisteredAfterEstablishment() throws {
        let aT = Transport(); let bT = Transport()
        defer { _ = (aT, bT) }
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["reg"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)

        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }; bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)

        XCTAssertEqual(aT.getLinkCount(), 1)
        XCTAssertEqual(bT.getLinkCount(), 1)
        XCTAssertNotNil(aLink.linkID)
        XCTAssertNotNil(aT.links[aLink.linkID!])
    }

    func testLinkDeregisteredAfterTeardown() throws {
        let aT = Transport(); let bT = Transport()
        defer { _ = (aT, bT) }
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["dereg"])
        bT.ownerIdentity = bId; bT.register(destination: bDest)
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)

        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }; bT.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)

        let linkID = try XCTUnwrap(aLink.linkID)
        XCTAssertEqual(aT.getLinkCount(), 1)

        // Teardown the link
        let closed = expectation(description: "closed")
        aLink.onClosed = { _ in closed.fulfill() }
        try aLink.teardown()
        wait(for: [closed], timeout: 1.0)

        XCTAssertNil(aT.links[linkID], "link should be removed from registry after teardown")
        XCTAssertEqual(aT.getLinkCount(), 0)
    }
}
