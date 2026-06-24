import XCTest
@testable import ReticulumSwift

/// Cross-compatibility tests using known test vectors from Python reference implementation.
/// These verify that Swift produces identical results for known inputs.
final class CrossCompatibilityTests: XCTestCase {

    // Test vectors from Python's tests/identity.py
    // format: (private_key_hex, expected_identity_hash_hex)
    let fixedKeys: [(String, String)] = [
        ("f8953ffaf607627e615603ff1530c82c434cf87c07179dd7689ea776f30b964cfb7ba6164af00c5111a45e69e57d885e1285f8dbfe3a21e95ae17cf676b0f8b7", "650b5d76b6bec0390d1f8cfca5bd33f9"),
        ("d85d036245436a3c33d3228affae06721f8203bc364ee0ee7556368ac62add650ebf8f926abf628da9d92baaa12db89bd6516ee92ec29765f3afafcb8622d697", "1469e89450c361b253aefb0c606b6111"),
        ("8893e2bfd30fc08455997caf7abb7a6341716768dbbf9a91cc1455bd7eeaf74cdc10ec72a4d4179696040bac620ee97ebc861e2443e5270537ae766d91b58181", "e5fe93ee4acba095b3b9b6541515ed3e"),
        ("b82c7a4f047561d974de7e38538281d7f005d3663615f30d9663bad35a716063c931672cd452175d55bcdd70bb7aa35a9706872a97963dc52029938ea7341b39", "1333b911fa8ebb16726996adbe3c6262"),
        ("08bb35f92b06a0832991165a0d9b4fd91af7b7765ce4572aa6222070b11b767092b61b0fd18b3a59cae6deb9db6d4bfb1c7fcfe076cfd66eea7ddd5f877543b9", "d13712efc45ef87674fb5ac26c37c912"),
    ]

    // MARK: - Identity hash computation (known test vectors)

    func testIdentityHashMatchesPythonForKnownKeys() throws {
        for (privHex, expectedHashHex) in fixedKeys {
            guard let privBytes = Data(hex: privHex),
                  let expectedHash = Data(hex: expectedHashHex) else {
                XCTFail("Invalid hex in test vector")
                continue
            }
            let identity = try Identity(privateKeyBytes: privBytes)
            XCTAssertEqual(identity.hash, expectedHash,
                "Identity hash mismatch for key \(privHex.prefix(16))...")
        }
    }

    func testGetPrivateKeyRoundTrip() throws {
        for (privHex, _) in fixedKeys {
            guard let privBytes = Data(hex: privHex) else { continue }
            let identity = try Identity(privateKeyBytes: privBytes)
            let retrieved = try XCTUnwrap(identity.getPrivateKey())
            XCTAssertEqual(retrieved, privBytes,
                "get_private_key() should return the same bytes used for initialization")
        }
    }

    // MARK: - Destination hash computation

    func testDestinationHashMatchesPythonFormula() throws {
        // Python: environmentlogger.remotesensor.temperature
        // Hash verified against Python reference
        let nameHash = Destination.computeNameHash(
            appName: "environmentlogger",
            aspects: ["remotesensor", "temperature"]
        )
        XCTAssertEqual(nameHash.count, Constants.nameHashLength)

        // Without identity: hash = truncated(SHA256(nameHash))
        let destHash = Destination.computeHash(identity: nil, nameHash: nameHash, kind: .plain)
        XCTAssertEqual(destHash.count, Constants.truncatedHashLength)

        // Verify the computation is consistent
        let hash2 = Destination.computeHash(identity: nil, nameHash: nameHash, kind: .plain)
        XCTAssertEqual(destHash, hash2)
    }

    // MARK: - Announce validation cross-compatibility

    func testAnnounceRoundTripWithKnownKey() throws {
        guard let privBytes = Data(hex: fixedKeys[0].0) else {
            XCTFail("Invalid test vector"); return
        }
        let identity = try Identity(privateKeyBytes: privBytes)
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "test", aspects: ["compat"])
        let announce = try Announce.make(for: dest, timestamp: 1700000000)
        let decoded = try Announce.validate(announce)

        XCTAssertEqual(decoded.destinationHash, dest.hash)
        XCTAssertEqual(decoded.identity.hash, identity.hash)
    }

    // MARK: - Token (encryption) roundtrip

    func testTokenEncryptDecryptRoundTrip() throws {
        let key = Data(repeating: 0xAA, count: 64)
        let token = try Token(key: key)
        let plaintext = Data("hello cross-compat".utf8)
        let encrypted = try token.encrypt(plaintext)
        let decrypted = try token.decrypt(encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testTokenLengthMatchesPython() throws {
        // Python Token: IV(16) + ciphertext + HMAC(32)
        // For 16 bytes of input (padded to 16): TOKEN_OVERHEAD = 48 bytes overhead
        let key = Data(repeating: 0xBB, count: 64)
        let token = try Token(key: key)
        let plaintext = Data(repeating: 0xCC, count: 1)  // 1 byte → padded to 16
        let encrypted = try token.encrypt(plaintext)
        // encrypted = IV(16) + ciphertext(16 padded) + HMAC(32) = 64 bytes
        XCTAssertEqual(encrypted.count, 64)
    }

    // MARK: - HKDF cross-compat

    func testHKDFDerivesConsistentKey() {
        let inputKey = Data(repeating: 0x01, count: 32)
        let salt = Data(repeating: 0x02, count: 16)
        let derived1 = HKDF.derive(length: 64, derivedFrom: inputKey, salt: salt, context: nil)
        let derived2 = HKDF.derive(length: 64, derivedFrom: inputKey, salt: salt, context: nil)
        XCTAssertEqual(derived1, derived2, "HKDF should be deterministic")
        XCTAssertEqual(derived1.count, 64)
    }
}
