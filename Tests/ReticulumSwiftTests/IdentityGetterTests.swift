import XCTest
@testable import ReticulumSwift

final class IdentityGetterTests: XCTestCase {

    func testGetSaltReturnsHash() {
        let identity = Identity()
        XCTAssertEqual(identity.getSalt(), identity.hash)
        XCTAssertEqual(identity.getSalt().count, 16)
    }

    func testGetContextReturnsNil() {
        let identity = Identity()
        XCTAssertNil(identity.getContext())
    }

    func testGetSaltDiffersPerIdentity() {
        let id1 = Identity()
        let id2 = Identity()
        XCTAssertNotEqual(id1.getSalt(), id2.getSalt())
    }

    func testGetSaltPublicOnlyIdentity() throws {
        let full = Identity()
        let pubOnly = try Identity(publicKeyBytes: full.publicKeyBytes)
        XCTAssertEqual(pubOnly.getSalt(), full.hash)
    }
}

final class LinkHadOutboundTests: XCTestCase {

    private func makeLink() throws -> Link {
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "test", aspects: ["hob"])
        let transport = Transport()
        transport.register(interface: LoopbackInterface(name: "HOBTest"))
        return try Link.initiate(destination: dest, transport: transport)
    }

    func testHadOutboundUpdatesLastOutbound() throws {
        let link = try makeLink()
        let before = Date()
        link.hadOutbound()
        XCTAssertNotNil(link.lastOutbound)
        XCTAssertGreaterThanOrEqual(link.lastOutbound!, before)
    }

    func testHadOutboundNotKeepaliveUpdatesLastData() throws {
        let link = try makeLink()
        link.hadOutbound(isKeepalive: false)
        XCTAssertNotNil(link.lastData)
        XCTAssertEqual(link.lastData, link.lastOutbound)
    }

    func testHadOutboundKeepaliveUpdatesLastKeepalive() throws {
        let link = try makeLink()
        link.hadOutbound(isKeepalive: true)
        XCTAssertNotNil(link.lastKeepalive)
        XCTAssertEqual(link.lastKeepalive, link.lastOutbound)
    }

    func testHadOutboundKeepaliveDoesNotUpdateLastData() throws {
        let link = try makeLink()
        let beforeData = link.lastData
        link.hadOutbound(isKeepalive: true)
        XCTAssertEqual(link.lastData, beforeData)
    }
}
