import XCTest
@testable import ReticulumSwift

/// Tests for Identity static hash utilities mirroring Python's
/// `RNS.Identity.full_hash()`, `RNS.Identity.truncated_hash()`, `RNS.Identity.get_random_hash()`.
final class IdentityHashUtilsTests: XCTestCase {

    func testFullHashIsSHA256() {
        let data = Data("hello".utf8)
        let hash = Identity.fullHash(data)
        XCTAssertEqual(hash.count, 32)
        // Known SHA-256 of "hello"
        let expected = Data([
            0x2c,0xf2,0x4d,0xba,0x5f,0xb0,0xa3,0x0e,0x26,0xe8,0x3b,0x2a,0xc5,0xb9,0xe2,0x9e,
            0x1b,0x16,0x1e,0x5c,0x1f,0xa7,0x42,0x5e,0x73,0x04,0x33,0x62,0x93,0x8b,0x98,0x24
        ])
        XCTAssertEqual(hash, expected)
    }

    func testTruncatedHashIs16Bytes() {
        let hash = Identity.truncatedHash(Data("test".utf8))
        XCTAssertEqual(hash.count, Constants.truncatedHashLength)
    }

    func testTruncatedHashIsPrefixOfFullHash() {
        let data = Data("prefix test".utf8)
        let full = Identity.fullHash(data)
        let trunc = Identity.truncatedHash(data)
        XCTAssertEqual(trunc, Data(full.prefix(Constants.truncatedHashLength)))
    }

    func testRandomHashIs16Bytes() {
        let h = Identity.randomHash()
        XCTAssertEqual(h.count, Constants.truncatedHashLength)
    }

    func testRandomHashIsRandom() {
        let h1 = Identity.randomHash()
        let h2 = Identity.randomHash()
        XCTAssertNotEqual(h1, h2, "two random hashes should differ")
    }

    // Mirror Python constant: Identity.TRUNCATED_HASHLENGTH = 128 bits = 16 bytes
    func testTruncatedHashLengthConstant() {
        XCTAssertEqual(Constants.truncatedHashLengthBits, 128)
        XCTAssertEqual(Constants.truncatedHashLength, 16)
    }

    // Mirror Python constant: Identity.KEYSIZE = 512 bits = 64 bytes
    func testKeySizeConstant() {
        XCTAssertEqual(Constants.keySize, 64)
    }

    // Mirror Python constant: Identity.SIGLENGTH = 512 bits = 64 bytes
    func testSignatureLengthConstant() {
        XCTAssertEqual(Constants.signatureLength, 64)
    }
}
