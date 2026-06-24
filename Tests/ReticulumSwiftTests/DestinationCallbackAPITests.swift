import XCTest
@testable import ReticulumSwift

/// Tests for Destination callback/setter API methods mirroring Python's:
///   - `Destination.set_link_established_callback(callback)`
///   - `Destination.set_packet_callback(callback)`
///   - `Destination.set_proof_requested_callback(callback)`
///   - `Destination.set_proof_strategy(strategy)`
///   - `Destination.accepts_links(accepts=None)`
///   - `Destination.clear_default_app_data()`
///   - `Destination.set_default_app_data(app_data)`
final class DestinationCallbackAPITests: XCTestCase {

    // MARK: - accepts_links getter/setter

    func testAcceptsLinksDefaultTrue() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        XCTAssertTrue(dest.acceptsLinks)
    }

    func testAcceptsLinksSetter() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        dest.acceptsLinks = false
        XCTAssertFalse(dest.acceptsLinks)
        dest.acceptsLinks = true
        XCTAssertTrue(dest.acceptsLinks)
    }

    func testAcceptsLinksViaMethod() throws {
        // Python API: destination.accepts_links(False) sets, accepts_links() gets
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        dest.setAcceptsLinks(false)
        XCTAssertFalse(dest.acceptsLinks)
        XCTAssertFalse(dest.getAcceptsLinks())
        dest.setAcceptsLinks(true)
        XCTAssertTrue(dest.getAcceptsLinks())
    }

    // MARK: - clear_default_app_data

    func testClearDefaultAppData() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        dest.defaultAppData = Data("hello".utf8)
        XCTAssertNotNil(dest.defaultAppData)
        dest.clearDefaultAppData()
        XCTAssertNil(dest.defaultAppData)
        XCTAssertNil(dest.defaultAppDataProvider)
    }

    func testClearDefaultAppDataAlsoClearsProvider() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        dest.defaultAppDataProvider = { Data("dynamic".utf8) }
        dest.clearDefaultAppData()
        XCTAssertNil(dest.defaultAppDataProvider)
        XCTAssertNil(dest.effectiveAppData)
    }

    // MARK: - set_default_app_data

    func testSetDefaultAppDataBytes() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        let data = Data("fixed".utf8)
        dest.setDefaultAppData(data)
        XCTAssertEqual(dest.defaultAppData, data)
        XCTAssertEqual(dest.effectiveAppData, data)
    }

    func testSetDefaultAppDataCallable() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        var counter = 0
        dest.setDefaultAppData(provider: {
            counter += 1
            return Data("dynamic\(counter)".utf8)
        })
        XCTAssertNil(dest.defaultAppData)
        let result1 = dest.effectiveAppData
        let result2 = dest.effectiveAppData
        XCTAssertEqual(result1, Data("dynamic1".utf8))
        XCTAssertEqual(result2, Data("dynamic2".utf8))
    }

    // MARK: - set_proof_strategy as method

    func testSetProofStrategyMethod() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        XCTAssertEqual(dest.proofStrategy, .proveNone)
        dest.setProofStrategy(.proveAll)
        XCTAssertEqual(dest.proofStrategy, .proveAll)
        dest.setProofStrategy(.proveApp)
        XCTAssertEqual(dest.proofStrategy, .proveApp)
    }

    // MARK: - set_*_callback as methods

    func testSetLinkEstablishedCallback() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        var fired = false
        dest.setLinkEstablishedCallback { _ in fired = true }
        XCTAssertNotNil(dest.onLinkEstablished)
        _ = fired
    }

    func testSetPacketCallback() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        dest.setPacketCallback { _, _ in }
        XCTAssertNotNil(dest.onPacketReceived)
    }

    func testSetProofRequestedCallback() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        dest.setProofRequestedCallback { _ in true }
        XCTAssertNotNil(dest.onProofRequested)
    }
}
