import XCTest
@testable import ReticulumSwift

/// Tests for Reticulum instance blackhole management API.
/// Mirrors Python's Reticulum.blackhole_identity(), unblackhole_identity(),
/// and get_blackholed_identities().
final class ReticulumBlackholeAPITests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-bh-api-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Reticulum.shared?.stop()
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func startReticulum() throws -> Reticulum {
        let cfg = Reticulum.Configuration(storagePath: tmpDir.appendingPathComponent("storage"))
        let rns = Reticulum(configuration: cfg)
        try rns.start()
        return rns
    }

    // MARK: - blackholeIdentity

    func testBlackholeIdentityReturnsTrue() throws {
        let rns = try startReticulum()
        let identity = Identity()
        let result = rns.blackholeIdentity(identity.hash)
        XCTAssertEqual(result, true)
    }

    func testBlackholeIdentityRejectsWrongHashLength() throws {
        let rns = try startReticulum()
        let result = rns.blackholeIdentity(Data(repeating: 0x01, count: 8))
        XCTAssertEqual(result, false, "Must reject hash of wrong length")
    }

    func testBlackholeIdentityReturnsNilIfAlreadyBlackholed() throws {
        let rns = try startReticulum()
        let identity = Identity()
        _ = rns.blackholeIdentity(identity.hash)
        let second = rns.blackholeIdentity(identity.hash)
        XCTAssertNil(second, "Second blackhole of same identity must return nil")
    }

    // MARK: - unblackholeIdentity

    func testUnblackholeIdentityReturnsTrue() throws {
        let rns = try startReticulum()
        let identity = Identity()
        _ = rns.blackholeIdentity(identity.hash)
        let result = rns.unblackholeIdentity(identity.hash)
        XCTAssertEqual(result, true)
        XCTAssertFalse(rns.transport.isBlackholed(identity.hash))
    }

    func testUnblackholeIdentityRejectsWrongHashLength() throws {
        let rns = try startReticulum()
        let result = rns.unblackholeIdentity(Data(repeating: 0x01, count: 5))
        XCTAssertEqual(result, false)
    }

    func testUnblackholeIdentityReturnsNilForUnknown() throws {
        let rns = try startReticulum()
        let identity = Identity()
        let result = rns.unblackholeIdentity(identity.hash)
        XCTAssertNil(result, "Unblackholing unknown identity must return nil")
    }

    // MARK: - getBlackholedIdentities

    func testGetBlackholedIdentitiesEmptyInitially() throws {
        let rns = try startReticulum()
        XCTAssertTrue(rns.getBlackholedIdentities().isEmpty)
    }

    func testGetBlackholedIdentitiesContainsBlackholed() throws {
        let rns = try startReticulum()
        let identity = Identity()
        _ = rns.blackholeIdentity(identity.hash)
        let list = rns.getBlackholedIdentities()
        XCTAssertTrue(list.keys.contains(identity.hash),
            "getBlackholedIdentities must include the blackholed identity hash")
    }

    func testGetBlackholedIdentitiesExcludesRemovedIdentity() throws {
        let rns = try startReticulum()
        let identity = Identity()
        _ = rns.blackholeIdentity(identity.hash)
        _ = rns.unblackholeIdentity(identity.hash)
        XCTAssertFalse(rns.getBlackholedIdentities().keys.contains(identity.hash))
    }
}
