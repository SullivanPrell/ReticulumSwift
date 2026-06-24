import XCTest
@testable import ReticulumSwift

final class RemoteManagementDestinationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Reticulum.allowProbes_ = false
        Reticulum.remoteManagementEnabled_ = false
    }

    override func tearDown() {
        Reticulum.allowProbes_ = false
        Reticulum.remoteManagementEnabled_ = false
        super.tearDown()
    }

    func testRemoteManagementDestinationNotCreatedByDefault() {
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()
        XCTAssertNil(transport.remoteManagementDestination)
    }

    func testRemoteManagementDestinationCreatedWhenEnabled() {
        Reticulum.remoteManagementEnabled_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()
        XCTAssertNotNil(transport.remoteManagementDestination)
    }

    func testRemoteManagementDestinationIsSingleType() {
        Reticulum.remoteManagementEnabled_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()
        XCTAssertEqual(transport.remoteManagementDestination?.kind, .single)
    }

    func testRemoteManagementDestinationHashMatchesExpected() throws {
        Reticulum.remoteManagementEnabled_ = true
        let identity = Identity()
        let transport = Transport()
        transport.transportIdentity = identity
        try? transport.start()

        let expected = try Destination(identity: identity, direction: .in, kind: .single,
                                        appName: "rnstransport", aspects: ["remote", "management"])
        XCTAssertEqual(transport.remoteManagementDestination?.hash, expected.hash)
    }

    func testRemoteManagementDestinationRegistersStatusHandler() {
        Reticulum.remoteManagementEnabled_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()

        guard let mgmt = transport.remoteManagementDestination else {
            XCTFail("Management destination not created"); return
        }
        let pathHash = Hashes.truncatedHash(Data("/status".utf8))
        XCTAssertNotNil(mgmt.requestHandlers[pathHash],
                        "Management destination should have /status handler")
    }

    func testRemoteManagementDestinationRegistersPathHandler() {
        Reticulum.remoteManagementEnabled_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()

        guard let mgmt = transport.remoteManagementDestination else {
            XCTFail("Management destination not created"); return
        }
        let pathHash = Hashes.truncatedHash(Data("/path".utf8))
        XCTAssertNotNil(mgmt.requestHandlers[pathHash],
                        "Management destination should have /path handler")
    }

    func testStatusHandlerAllowListPolicy() {
        Reticulum.remoteManagementEnabled_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()

        guard let mgmt = transport.remoteManagementDestination else {
            XCTFail("Management destination not created"); return
        }
        let pathHash = Hashes.truncatedHash(Data("/status".utf8))
        XCTAssertEqual(mgmt.requestHandlers[pathHash]?.allow, .list,
                       "/status handler should require ALLOW_LIST")
    }

    func testPathHandlerAllowListPolicy() {
        Reticulum.remoteManagementEnabled_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()

        guard let mgmt = transport.remoteManagementDestination else {
            XCTFail("Management destination not created"); return
        }
        let pathHash = Hashes.truncatedHash(Data("/path".utf8))
        XCTAssertEqual(mgmt.requestHandlers[pathHash]?.allow, .list,
                       "/path handler should require ALLOW_LIST")
    }

    func testStatusHandlerReturnsNilForNilData() {
        Reticulum.remoteManagementEnabled_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()

        guard let mgmt = transport.remoteManagementDestination else {
            XCTFail("Management destination not created"); return
        }
        let pathHash = Hashes.truncatedHash(Data("/status".utf8))
        guard let entry = mgmt.requestHandlers[pathHash] else {
            XCTFail("No /status handler"); return
        }
        // Nil data → handler returns nil (can't parse request)
        let result = entry.handler(pathHash, nil, Data(), makeMinimalLink(), 0)
        XCTAssertNil(result)
    }

    func testPathHandlerReturnsNilForNilData() {
        Reticulum.remoteManagementEnabled_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()

        guard let mgmt = transport.remoteManagementDestination else {
            XCTFail("Management destination not created"); return
        }
        let pathHash = Hashes.truncatedHash(Data("/path".utf8))
        guard let entry = mgmt.requestHandlers[pathHash] else {
            XCTFail("No /path handler"); return
        }
        let result = entry.handler(pathHash, nil, Data(), makeMinimalLink(), 0)
        XCTAssertNil(result)
    }

    func testRemoteManagementDestinationRegisteredInTransport() {
        Reticulum.remoteManagementEnabled_ = true
        let transport = Transport()
        transport.transportIdentity = Identity()
        try? transport.start()

        guard let mgmt = transport.remoteManagementDestination else {
            XCTFail("Management destination not created"); return
        }
        XCTAssertNotNil(transport.registeredDestinations[mgmt.hash],
                        "Management destination should be in transport.registeredDestinations")
    }

    // MARK: - Helpers

    private func makeMinimalLink() -> Link {
        // Uses LoopbackInterface (defined in LinkTests.swift, same test target).
        let identity = Identity()
        let dest = try! Destination(identity: identity, direction: .in, kind: .single,
                                     appName: "dummy", aspects: ["link"])
        let transport = Transport()
        let loopback = LoopbackInterface(name: "MgmtTest")
        transport.register(interface: loopback)
        return try! Link.initiate(destination: dest, transport: transport)
    }
}
