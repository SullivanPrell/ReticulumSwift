import XCTest
@testable import ReticulumSwift

final class LinkResourceManagementTests: XCTestCase {

    private func makeLink() throws -> Link {
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "test", aspects: ["lrm"])
        let transport = Transport()
        let iface = LoopbackInterface(name: "LRMTest")
        transport.register(interface: iface)
        let link = try Link.initiate(destination: dest, transport: transport)
        return link
    }

    // MARK: - readyForNewResource

    func testReadyForNewResourceWhenEmpty() throws {
        let link = try makeLink()
        XCTAssertTrue(link.readyForNewResource())
    }

    func testReadyForNewResourceFalseWhenOutgoing() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        link.registerOutgoingResource(rt)
        XCTAssertFalse(link.readyForNewResource())
    }

    // MARK: - hasIncomingResource

    func testHasIncomingResourceFalseWhenNone() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertFalse(link.hasIncomingResource(rt))
    }

    func testHasIncomingResourceTrueAfterRegister() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        link.registerIncomingResource(rt)
        XCTAssertTrue(link.hasIncomingResource(rt))
    }

    func testHasIncomingResourceFalseAfterUnregister() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        link.registerIncomingResource(rt)
        link.unregisterIncomingResource(rt)
        XCTAssertFalse(link.hasIncomingResource(rt))
    }

    // MARK: - cancelOutgoingResource / cancelIncomingResource

    func testCancelOutgoingResource() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        link.registerOutgoingResource(rt)
        XCTAssertFalse(link.readyForNewResource())
        link.cancelOutgoingResource(rt)
        XCTAssertTrue(link.readyForNewResource())
    }

    func testCancelIncomingResource() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        link.registerIncomingResource(rt)
        XCTAssertTrue(link.hasIncomingResource(rt))
        link.cancelIncomingResource(rt)
        XCTAssertFalse(link.hasIncomingResource(rt))
    }

    func testCancelOutgoingResourceLeavesOtherResourcesIntact() throws {
        let link = try makeLink()
        let rt1 = ResourceTransfer(link: link)
        let rt2 = ResourceTransfer(link: link)
        link.registerOutgoingResource(rt1)
        link.registerOutgoingResource(rt2)
        link.cancelOutgoingResource(rt1)
        XCTAssertFalse(link.readyForNewResource(), "rt2 still pending")
        link.cancelOutgoingResource(rt2)
        XCTAssertTrue(link.readyForNewResource())
    }

    // MARK: - getLastResourceWindow / getLastResourceEifr

    func testGetLastResourceWindowNilInitially() throws {
        let link = try makeLink()
        XCTAssertNil(link.getLastResourceWindow())
    }

    func testGetLastResourceEifrNilInitially() throws {
        let link = try makeLink()
        XCTAssertNil(link.getLastResourceEifr())
    }

    func testGetLastResourceWindowSetViaTestHelper() throws {
        let link = try makeLink()
        link.testSetLastResourceWindow(7)
        XCTAssertEqual(link.getLastResourceWindow(), 7)
    }

    func testGetLastResourceEifrSetViaTestHelper() throws {
        let link = try makeLink()
        link.testSetLastResourceEifr(1_000_000.0)
        XCTAssertEqual(link.getLastResourceEifr(), 1_000_000.0)
    }

    func testRecordIncomingResourceConclusionUpdatesWindowAndEifr() throws {
        let link = try makeLink()
        link.recordIncomingResourceConclusion(window: 5, eifr: 500_000.0)
        XCTAssertEqual(link.getLastResourceWindow(), 5)
        XCTAssertEqual(link.getLastResourceEifr(), 500_000.0)
    }

    func testRecordIncomingResourceConclusionNilEifr() throws {
        let link = try makeLink()
        link.recordIncomingResourceConclusion(window: 3, eifr: nil)
        XCTAssertEqual(link.getLastResourceWindow(), 3)
        XCTAssertNil(link.getLastResourceEifr())
    }
}
