import XCTest
@testable import ReticulumSwift

/// Tests for link establishment rate, destination deregistration, and
/// request handler deregistration — parity with Python Link/Transport/Destination.
final class LinkEstablishmentRateTests: XCTestCase {

    final class Loopback: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: Loopback?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    func makeEstablishedLink() throws -> (initiator: Link, responder: Link) {
        let aT = Transport()
        let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "test")
        bT.ownerIdentity = bId; bT.register(destination: bDest)

        let a = Loopback(name: "a"); let b = Loopback(name: "b")
        a.paired = b; b.paired = a
        aT.register(interface: a); bT.register(interface: b)

        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        aT.onLinkEstablished = { _ in aE.fulfill() }
        bT.onLinkEstablished = { _ in bE.fulfill() }

        let aLink = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bT.links[aLink.linkID!])
        return (aLink, bLink)
    }

    // MARK: - establishmentRate

    func testEstablishmentRateSetAfterLinkActive() throws {
        let (aLink, _) = try makeEstablishedLink()
        XCTAssertEqual(aLink.status, .active)
        XCTAssertNotNil(aLink.establishmentRate, "establishment rate must be set once link is active")
        XCTAssertGreaterThan(aLink.establishmentRate!, 0)
    }

    func testEstablishmentCostMatchesPythonFormula() throws {
        let (aLink, _) = try makeEstablishedLink()
        // Python: KEYSIZE/8*2 + SIGLENGTH/8 + ECPUBSIZE/2 + ECPUBSIZE
        // = 64*2 + 64 + 32 + 64 = 288
        let expected = Constants.keySize * 2 + Constants.keySize + Constants.halfKeySize + Constants.keySize
        XCTAssertEqual(aLink.establishmentCost, expected)
    }

    func testEstablishmentRateEqualsEstablishmentCostDividedByRTT() throws {
        let (aLink, _) = try makeEstablishedLink()
        guard let rate = aLink.establishmentRate, let rtt = aLink.rtt, rtt > 0 else {
            XCTFail("establishment rate and rtt must be set")
            return
        }
        let expected = Double(aLink.establishmentCost) / rtt
        XCTAssertEqual(rate, expected, accuracy: 1e-6)
    }

    // MARK: - Destination.deregisterRequestHandler

    func testDeregisterRequestHandlerRemovesHandler() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single, appName: "rh")
        dest.registerRequestHandler(path: "/ping", allow: .all) { _, _, _, _, _ in Data("pong".utf8) }

        let key = Hashes.truncatedHash(Data("/ping".utf8))
        XCTAssertNotNil(dest.requestHandlers[key])

        dest.deregisterRequestHandler(path: "/ping")
        XCTAssertNil(dest.requestHandlers[key])
    }

    func testDeregisterRequestHandlerUnknownPathIsNoop() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single, appName: "rh")
        dest.registerRequestHandler(path: "/ping", allow: .all) { _, _, _, _, _ in nil }

        // Deregistering a non-existent path must not throw or remove other handlers.
        dest.deregisterRequestHandler(path: "/nonexistent")
        let key = Hashes.truncatedHash(Data("/ping".utf8))
        XCTAssertNotNil(dest.requestHandlers[key])
    }

    // MARK: - Transport.deregister(destination:)

    func testDeregisterDestinationRemovesFromTransport() throws {
        let transport = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single, appName: "dereg")
        transport.register(destination: dest)
        XCTAssertNotNil(transport.registeredDestinations[dest.hash])

        transport.deregister(destination: dest)
        XCTAssertNil(transport.registeredDestinations[dest.hash])
    }

    func testDeregisterDestinationMakesItIgnoreLinkRequests() throws {
        let aT = Transport()
        let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "dereg2")
        bT.ownerIdentity = bId; bT.register(destination: bDest)

        let a = Loopback(name: "a2"); let b = Loopback(name: "b2")
        a.paired = b; b.paired = a
        aT.register(interface: a); bT.register(interface: b)

        // Deregister before initiating — link should not be answered.
        bT.deregister(destination: bDest)

        let established = expectation(description: "established")
        established.isInverted = true
        bT.onLinkEstablished = { _ in established.fulfill() }

        _ = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [established], timeout: 0.2)
    }
}
