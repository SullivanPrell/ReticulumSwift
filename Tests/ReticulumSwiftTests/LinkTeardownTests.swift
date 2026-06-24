import XCTest
@testable import ReticulumSwift

/// Tests for Link.teardownReason and related close semantics.
final class LinkTeardownTests: XCTestCase {

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

    func makeLinkedPair() throws -> (aT: Transport, bT: Transport, aLink: Link, bLink: Link) {
        let aT = Transport()
        let bT = Transport()
        let bIdentity = Identity()
        let bDest = try Destination(
            identity: bIdentity, direction: .in, kind: .single, appName: "test"
        )
        bT.ownerIdentity = bIdentity
        bT.register(destination: bDest)

        let aIface = LoopbackInterface(name: "A")
        let bIface = LoopbackInterface(name: "B")
        aIface.paired = bIface; bIface.paired = aIface
        aT.register(interface: aIface)
        bT.register(interface: bIface)

        let aE = expectation(description: "A established")
        let bE = expectation(description: "B established")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }

        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aT, bT, aLink, bLink)
    }

    // MARK: - Tests

    func testTeardownReasonInitiatorClosedWhenInitiatorCalls() throws {
        let (aT, bT, aLink, _) = try makeLinkedPair()
        _ = (aT, bT)
        XCTAssertNil(aLink.teardownReason, "no reason before teardown")
        try aLink.teardown()
        XCTAssertEqual(aLink.teardownReason, .initiatorClosed)
    }

    func testTeardownReasonInitiatorClosedWhenResponderReceivesClose() throws {
        // Keep transports alive so Link's weak transport reference stays valid.
        let (aT, bT, aLink, bLink) = try makeLinkedPair()
        _ = (aT, bT)
        XCTAssertNil(bLink.teardownReason, "no reason before teardown")

        let aClosed = expectation(description: "A link closed")
        aLink.onClosed = { _ in aClosed.fulfill() }

        // Initiator closes first.
        try aLink.teardown()
        wait(for: [aClosed], timeout: 1.0)

        // Initiator called teardown → .initiatorClosed
        XCTAssertEqual(aLink.teardownReason, .initiatorClosed)
        // Responder received the close packet → .initiatorClosed (initiator closed)
        XCTAssertEqual(bLink.teardownReason, .initiatorClosed)
    }

    func testTeardownReasonDestinationClosedWhenResponderCalls() throws {
        let (aT, bT, aLink, bLink) = try makeLinkedPair()
        _ = (aT, bT)
        XCTAssertNil(bLink.teardownReason, "no reason before teardown")

        let aClosed = expectation(description: "A link closed")
        aLink.onClosed = { _ in aClosed.fulfill() }

        try bLink.teardown()
        wait(for: [aClosed], timeout: 1.0)

        // Responder called teardown → its reason is .destinationClosed
        XCTAssertEqual(bLink.teardownReason, .destinationClosed)
        // Initiator receives the close packet → its reason is .destinationClosed
        XCTAssertEqual(aLink.teardownReason, .destinationClosed)
    }

    func testTeardownReasonTimeoutWhenEstablishmentExpires() throws {
        let aT = Transport()
        let bIdentity = Identity()
        let bDest = try Destination(
            identity: bIdentity, direction: .in, kind: .single, appName: "test"
        )

        let iface = LoopbackInterface(name: "A")
        let dead = LoopbackInterface(name: "dead") // no transport on this side
        iface.paired = dead; dead.paired = iface
        aT.register(interface: iface)

        let timedOut = expectation(description: "link timed out")
        let aLink = try Link.initiate(destination: bDest, transport: aT)
        aLink.establishmentTimeout = 0.1 // very short for test
        aLink.onTimeout = { _ in timedOut.fulfill() }

        wait(for: [timedOut], timeout: 2.0)
        XCTAssertEqual(aLink.teardownReason, .timeout)
        XCTAssertEqual(aLink.status, .failed)
    }
}
