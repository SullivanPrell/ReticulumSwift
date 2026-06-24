import XCTest
@testable import ReticulumSwift

final class ProbeDestinationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset static flags after each test.
        Reticulum.allowProbes_ = false
        Reticulum.remoteManagementEnabled_ = false
    }

    override func tearDown() {
        Reticulum.allowProbes_ = false
        Reticulum.remoteManagementEnabled_ = false
        super.tearDown()
    }

    func testProbeDestinationNotCreatedByDefault() {
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()
        XCTAssertNil(transport.probeDestination,
                     "Probe destination should not be created when allowProbes is false")
    }

    func testProbeDestinationCreatedWhenEnabled() {
        Reticulum.allowProbes_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()
        XCTAssertNotNil(transport.probeDestination,
                        "Probe destination should be created when allowProbes is true")
    }

    func testProbeDestinationHasProveAllStrategy() {
        Reticulum.allowProbes_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()
        XCTAssertEqual(transport.probeDestination?.proofStrategy, .proveAll)
    }

    func testProbeDestinationDoesNotAcceptLinks() {
        Reticulum.allowProbes_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()
        XCTAssertFalse(transport.probeDestination?.acceptsLinks ?? true)
    }

    func testProbeDestinationIsSingleType() {
        Reticulum.allowProbes_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()
        XCTAssertEqual(transport.probeDestination?.kind, .single)
    }

    func testProbeDestinationUsesTransportIdentity() {
        Reticulum.allowProbes_ = true
        let identity = Identity()
        let transport = Transport()
        transport.transportIdentity = identity
        try? transport.start()
        XCTAssertEqual(transport.probeDestination?.identity?.hash, identity.hash)
    }

    func testProbeDestinationHashMatchesExpected() throws {
        Reticulum.allowProbes_ = true
        let identity = Identity()
        let transport = Transport()
        transport.transportIdentity = identity
        try? transport.start()

        // Expected hash: same as constructing the destination directly.
        let expected = try Destination(identity: identity, direction: .in, kind: .single,
                                        appName: "rnstransport", aspects: ["probe"])
        XCTAssertEqual(transport.probeDestination?.hash, expected.hash)
    }

    func testProbeDestinationRegisteredInTransport() {
        Reticulum.allowProbes_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()

        guard let probe = transport.probeDestination else {
            XCTFail("Probe destination not created"); return
        }
        XCTAssertNotNil(transport.registeredDestinations[probe.hash],
                        "Probe destination should be registered in transport.registeredDestinations")
    }
}
