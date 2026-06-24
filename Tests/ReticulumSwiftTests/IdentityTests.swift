import XCTest
@testable import ReticulumSwift

final class IdentityTests: XCTestCase {
    func testHashLength() {
        XCTAssertEqual(Identity().hash.count, Constants.truncatedHashLength)
    }

    func testPublicKeyBytesLength() {
        XCTAssertEqual(Identity().publicKeyBytes.count, Constants.keySize)
    }

    func testPrivateKeyBytesLength() {
        XCTAssertEqual(Identity().privateKeyBytes?.count, Constants.keySize)
    }

    func testRoundTripPrivateKey() throws {
        let original = Identity()
        let serialized = try XCTUnwrap(original.privateKeyBytes)
        let restored = try Identity(privateKeyBytes: serialized)
        XCTAssertEqual(original.publicKeyBytes, restored.publicKeyBytes)
        XCTAssertEqual(original.hash, restored.hash)
    }

    func testRoundTripPublicKey() throws {
        let original = Identity()
        let restored = try Identity(publicKeyBytes: original.publicKeyBytes)
        XCTAssertEqual(original.hash, restored.hash)
        XCTAssertFalse(restored.hasPrivateKey)
    }

    func testSignAndValidate() throws {
        let identity = Identity()
        let message = Data("hello reticulum".utf8)
        let signature = try identity.sign(message)
        XCTAssertEqual(signature.count, Constants.signatureLength)
        XCTAssertTrue(identity.validate(signature: signature, for: message))
        var tampered = message; tampered[0] ^= 1
        XCTAssertFalse(identity.validate(signature: signature, for: tampered))
    }

    func testEncryptDecryptRoundTrip() throws {
        let identity = Identity()
        let plaintext = Data("the network is the sum of its peers".utf8)
        let ciphertext = try identity.encrypt(plaintext)
        // Token = 32-byte ephemeral pub + IV(16) + AES-CBC(blocks of 16) + HMAC(32)
        XCTAssertGreaterThan(ciphertext.count, Constants.halfKeySize + Constants.tokenOverhead)
        let decrypted = try identity.decrypt(ciphertext)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testDecryptFailsWithoutPrivateKey() throws {
        let publicOnly = try Identity(publicKeyBytes: Identity().publicKeyBytes)
        XCTAssertThrowsError(try publicOnly.decrypt(Data(repeating: 0, count: 100)))
    }
}
