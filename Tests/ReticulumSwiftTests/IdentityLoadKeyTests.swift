import XCTest
@testable import ReticulumSwift

/// Tests for Identity.load_private_key() and Identity.load_public_key() Python API parity.
/// Note: In Swift, Identity is immutable. These methods return a NEW Identity.
final class IdentityLoadKeyTests: XCTestCase {

    // MARK: - loadPrivateKey (mirrors Python Identity.load_private_key)

    func testLoadPrivateKeyCreatesIdentityWithCorrectHash() throws {
        let original = Identity()
        let privBytes = try XCTUnwrap(original.getPrivateKey())

        let loaded = try XCTUnwrap(Identity().loadPrivateKey(privBytes))
        XCTAssertEqual(loaded.hash, original.hash)
    }

    func testLoadPrivateKeyReturnsFalseForInvalidBytes() {
        let id = Identity()
        let result = id.loadPrivateKey(Data(repeating: 0, count: 10))
        XCTAssertNil(result, "invalid bytes should return nil")
    }

    func testLoadPrivateKeyResultHasPrivateKey() throws {
        let original = Identity()
        let privBytes = try XCTUnwrap(original.getPrivateKey())
        let loaded = try XCTUnwrap(Identity().loadPrivateKey(privBytes))
        XCTAssertTrue(loaded.hasPrivateKey)
    }

    // MARK: - loadPublicKey (mirrors Python Identity.load_public_key)

    func testLoadPublicKeyCreatesPublicOnlyIdentity() {
        let id = Identity()
        let pubBytes = id.getPublicKey()
        let pubOnly = try? Identity().loadPublicKey(pubBytes)
        XCTAssertNotNil(pubOnly)
        XCTAssertFalse(pubOnly?.hasPrivateKey ?? true)
    }

    func testLoadPublicKeyPreservesHash() {
        let id = Identity()
        let pubBytes = id.getPublicKey()
        let pubOnly = try? Identity().loadPublicKey(pubBytes)
        XCTAssertEqual(pubOnly?.hash, id.hash)
    }

    func testLoadPublicKeyReturnsFalseForInvalidBytes() {
        let id = Identity()
        let result = try? id.loadPublicKey(Data(repeating: 0, count: 10))
        XCTAssertNil(result)
    }
}
