import XCTest
@testable import ReticulumSwift

final class LinkGetterTests: XCTestCase {

    func testGetModeReturnsAES256CBC() throws {
        let link = try makeInitiatedLink()
        XCTAssertEqual(link.getMode(), 0x01, "getMode returns AES256_CBC (0x01)")
    }

    func testGetModeMatchesModeConstant() throws {
        let link = try makeInitiatedLink()
        XCTAssertEqual(link.getMode(), link.mode)
    }

    func testGetModeIsConsistentWithLinkModeConstants() throws {
        let link = try makeInitiatedLink()
        XCTAssertEqual(link.getMode(), Link.modeAes256Cbc)
    }

    func testGetExpectedRateNilOnPendingLink() throws {
        let link = try makeInitiatedLink()
        // Link is pending (not yet established) — expected rate should be nil.
        XCTAssertNil(link.getExpectedRate())
    }

    func testGetExpectedRateNilBeforeTransferOnEstablishedLink() throws {
        let (initiator, _) = try makeEstablishedPair()
        // Link is established but no Resource transfer has happened.
        XCTAssertNil(initiator.getExpectedRate())
    }

    // MARK: - getStatus

    func testGetStatusPendingOnNewLink() throws {
        let link = try makeInitiatedLink()
        XCTAssertEqual(link.getStatus(), .pending,
                       "getStatus() must be .pending immediately after initiation")
    }

    func testGetStatusMatchesStatusProperty() throws {
        let link = try makeInitiatedLink()
        XCTAssertEqual(link.getStatus(), link.status,
                       "getStatus() must return the same value as the status property")
    }

    func testGetStatusActiveAfterEstablishment() throws {
        let (initiator, _) = try makeEstablishedPair()
        XCTAssertEqual(initiator.getStatus(), .active)
        XCTAssertEqual(initiator.getStatus(), initiator.status)
    }

    // MARK: - getLinkID

    func testGetLinkIDNonNilAfterHandshake() throws {
        let (initiator, _) = try makeEstablishedPair()
        XCTAssertNotNil(initiator.getLinkID(),
                        "getLinkID() must be non-nil after the handshake")
    }

    func testGetLinkIDMatchesLinkIDProperty() throws {
        let (initiator, _) = try makeEstablishedPair()
        XCTAssertEqual(initiator.getLinkID(), initiator.linkID,
                       "getLinkID() must return the same data as the linkID property")
    }

    func testGetLinkIDIs16Bytes() throws {
        let (initiator, _) = try makeEstablishedPair()
        XCTAssertEqual(initiator.getLinkID()?.count, 16,
                       "Reticulum link IDs are always 16 bytes (truncated hash)")
    }

    func testGetLinkIDSameOnBothSides() throws {
        let (initiator, responder) = try makeEstablishedPair()
        XCTAssertEqual(initiator.getLinkID(), responder.getLinkID(),
                       "Both sides derive the same link ID during handshake")
    }

    // MARK: - getRtt

    func testGetRttNilOnPendingLink() throws {
        let link = try makeInitiatedLink()
        XCTAssertNil(link.getRtt(),
                     "getRtt() must be nil before RTT is measured")
    }

    func testGetRttNonNilAfterEstablishment() throws {
        let (initiator, _) = try makeEstablishedPair()
        XCTAssertNotNil(initiator.getRtt(),
                        "getRtt() must be non-nil after the handshake")
    }

    func testGetRttMatchesRttProperty() throws {
        let (initiator, _) = try makeEstablishedPair()
        XCTAssertEqual(initiator.getRtt(), initiator.rtt,
                       "getRtt() must return the same value as the rtt property")
    }

    func testGetRttIsPositive() throws {
        let (initiator, _) = try makeEstablishedPair()
        let rtt = try XCTUnwrap(initiator.getRtt())
        XCTAssertGreaterThan(rtt, 0, "RTT must be positive after establishment")
    }

    // MARK: - getRemoteIdentity

    func testGetRemoteIdentityNilByDefault() throws {
        let link = try makeInitiatedLink()
        XCTAssertNil(link.getRemoteIdentity(),
                     "getRemoteIdentity() must be nil before identify() is called")
    }

    func testGetRemoteIdentityMatchesRemoteIdentityProperty() throws {
        // Remote identity is only populated on the responder side after
        // the initiator calls identify(). Without a full identify exchange
        // we verify structural parity: both getters return the same value.
        let (initiator, responder) = try makeEstablishedPair()
        XCTAssertEqual(initiator.getRemoteIdentity() == nil, initiator.remoteIdentity == nil)
        XCTAssertEqual(responder.getRemoteIdentity() == nil, responder.remoteIdentity == nil)
    }

    // MARK: - getTeardownReason

    func testGetTeardownReasonNilWhileActive() throws {
        let (initiator, _) = try makeEstablishedPair()
        XCTAssertNil(initiator.getTeardownReason(),
                     "getTeardownReason() must be nil on an active link")
    }

    func testGetTeardownReasonNilOnPendingLink() throws {
        let link = try makeInitiatedLink()
        XCTAssertNil(link.getTeardownReason(),
                     "getTeardownReason() must be nil on a fresh (pending) link")
    }

    func testGetTeardownReasonMatchesTeardownReasonProperty() throws {
        let (initiator, _) = try makeEstablishedPair()
        // Before teardown, both should agree (both nil).
        XCTAssertEqual(initiator.getTeardownReason() == nil, initiator.teardownReason == nil)
        // After explicit teardown, getTeardownReason should match the property.
        try? initiator.teardown()
        XCTAssertEqual(initiator.getTeardownReason(), initiator.teardownReason)
    }

    func testGetTeardownReasonSetAfterTeardown() throws {
        let (initiator, _) = try makeEstablishedPair()
        try? initiator.teardown()
        XCTAssertNotNil(initiator.getTeardownReason(),
                        "getTeardownReason() must be non-nil after teardown()")
    }

    // MARK: - Helpers

    private func makeInitiatedLink() throws -> Link {
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["getter"])
        let transport = Transport()
        let loopback = LoopbackInterface(name: "GetterTest")
        transport.register(interface: loopback)
        return try Link.initiate(destination: dest, transport: transport)
    }

    private func makeEstablishedPair() throws -> (Link, Link) {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                     appName: "test", aspects: ["getter"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)

        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)

        let established = expectation(description: "established")
        bT.onLinkEstablished = { _ in established.fulfill() }
        let initiator = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [established], timeout: 2.0)

        let bLink = try XCTUnwrap(bT.links[initiator.linkID!])
        return (initiator, bLink)
    }
}
