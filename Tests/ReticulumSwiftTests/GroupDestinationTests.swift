import XCTest
@testable import ReticulumSwift

/// Tests for GROUP destination type key management.
/// Mirrors Python's `Destination.create_keys()`, `Destination.get_private_key()`,
/// `Destination.load_private_key()`.
final class GroupDestinationTests: XCTestCase {

    func testGroupDestinationCanBeCreated() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["group"])
        XCTAssertEqual(dest.kind, .group)
    }

    func testCreateKeysGeneratesSymmetricKey() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["keys"])
        XCTAssertNil(dest.getGroupKey(), "no key before createKeys")
        dest.createKeys()
        XCTAssertNotNil(dest.getGroupKey(), "key should exist after createKeys")
    }

    func testGroupKeyLength() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["len"])
        dest.createKeys()
        let key = dest.getGroupKey()
        XCTAssertEqual(key?.count, Constants.derivedKeyLength, "group key must be 64 bytes (AES-256 token key)")
    }

    func testLoadPrivateKey() throws {
        let dest1 = try Destination(identity: nil, direction: .in, kind: .group,
                                    appName: "test", aspects: ["load"])
        dest1.createKeys()
        let key = try XCTUnwrap(dest1.getGroupKey())

        let dest2 = try Destination(identity: nil, direction: .in, kind: .group,
                                    appName: "test", aspects: ["load"])
        dest2.loadGroupKey(key)
        XCTAssertEqual(dest2.getGroupKey(), key)
    }

    func testEncryptDecryptWithGroupKey() throws {
        let dest = try Destination(identity: nil, direction: .in, kind: .group,
                                   appName: "test", aspects: ["encrypt"])
        dest.createKeys()

        let plaintext = Data("secret group message".utf8)
        let ciphertext = try dest.encrypt(plaintext)
        XCTAssertNotEqual(ciphertext, plaintext)

        let decrypted = try dest.decrypt(ciphertext)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testTwoGroupDestinationsWithSharedKey() throws {
        let sender = try Destination(identity: nil, direction: .in, kind: .group,
                                     appName: "test", aspects: ["shared"])
        sender.createKeys()
        let key = try XCTUnwrap(sender.getGroupKey())

        let receiver = try Destination(identity: nil, direction: .in, kind: .group,
                                       appName: "test", aspects: ["shared"])
        receiver.loadGroupKey(key)

        let plaintext = Data("broadcast message".utf8)
        let encrypted = try sender.encrypt(plaintext)
        let decrypted = try receiver.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testCreateKeysThrowsForSingleDestination() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: [])
        // Should be a no-op (returns false) for non-GROUP types
        let result = dest.createKeys()
        XCTAssertFalse(result, "createKeys should fail for SINGLE destinations")
    }
}
