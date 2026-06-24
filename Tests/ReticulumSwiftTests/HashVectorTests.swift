import XCTest
@testable import ReticulumSwift

/// Tests using known SHA-256 hash vectors from Python's tests/hashes.py.
final class HashVectorTests: XCTestCase {

    func testSHA256EmptyString() {
        let result = Hashes.fullHash(Data())
        let expected = Data(hex: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")!
        XCTAssertEqual(result, expected)
    }

    func testSHA256ABC() {
        let result = Hashes.fullHash(Data("abc".utf8))
        let expected = Data(hex: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")!
        XCTAssertEqual(result, expected)
    }

    func testSHA25664xA() {
        let result = Hashes.fullHash(Data(String(repeating: "a", count: 64).utf8))
        let expected = Data(hex: "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb")!
        XCTAssertEqual(result, expected)
    }

    // Note: 1 million 'a's test would be too slow for unit tests
    // func testSHA2561MillionA() { ... }

    // MARK: - Truncated hash

    func testTruncatedHashIs16Bytes() {
        let result = Hashes.truncatedHash(Data("test".utf8))
        XCTAssertEqual(result.count, 16)
    }

    func testTruncatedHashIsPrefixOfFull() {
        let data = Data("hello world".utf8)
        let full = Hashes.fullHash(data)
        let trunc = Hashes.truncatedHash(data)
        XCTAssertEqual(trunc, Data(full.prefix(16)))
    }

    // MARK: - Known Identity hash vectors

    func testIdentityHashes() throws {
        let vectors: [(String, String)] = [
            ("f8953ffaf607627e615603ff1530c82c434cf87c07179dd7689ea776f30b964cfb7ba6164af00c5111a45e69e57d885e1285f8dbfe3a21e95ae17cf676b0f8b7", "650b5d76b6bec0390d1f8cfca5bd33f9"),
            ("d85d036245436a3c33d3228affae06721f8203bc364ee0ee7556368ac62add650ebf8f926abf628da9d92baaa12db89bd6516ee92ec29765f3afafcb8622d697", "1469e89450c361b253aefb0c606b6111"),
        ]
        for (privHex, expectedHash) in vectors {
            guard let privBytes = Data(hex: privHex),
                  let expected = Data(hex: expectedHash) else { continue }
            let id = try Identity(privateKeyBytes: privBytes)
            XCTAssertEqual(id.hash, expected,
                "Identity hash must match Python reference for key \(privHex.prefix(16))...")
        }
    }
}
