import XCTest
@testable import ReticulumSwift

final class CryptoTests: XCTestCase {

    // MARK: PKCS7

    func testPKCS7PadAndUnpadRoundTrip() throws {
        for length in [0, 1, 15, 16, 17, 31, 32, 100] {
            let original = Data(repeating: 0xAB, count: length)
            let padded = PKCS7.pad(original)
            XCTAssertEqual(padded.count % 16, 0)
            let unpadded = try PKCS7.unpad(padded)
            XCTAssertEqual(unpadded, original)
        }
    }

    func testPKCS7RejectsBadPadding() {
        let bogus = Data(repeating: 0xFF, count: 16) // pad byte 0xFF > blockSize
        XCTAssertThrowsError(try PKCS7.unpad(bogus))
    }

    // MARK: AES-CBC

    func testAESCBCRoundTrip() throws {
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let iv  = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let plaintext = PKCS7.pad(Data("hello aes cbc".utf8))
        let ciphertext = try AESCBC.encrypt(plaintext: plaintext, key: key, iv: iv)
        let decrypted = try AESCBC.decrypt(ciphertext: ciphertext, key: key, iv: iv)
        XCTAssertEqual(try PKCS7.unpad(decrypted), Data("hello aes cbc".utf8))
    }

    // MARK: HKDF — RFC 5869 test vector A.1

    func testHKDFTestVectorA1() {
        let ikm = Data([
            0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b,
            0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b
        ])
        let salt = Data([
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a,
            0x0b, 0x0c
        ])
        let info = Data([
            0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9
        ])
        let expected = Data([
            0x3c, 0xb2, 0x5f, 0x25, 0xfa, 0xac, 0xd5, 0x7a, 0x90, 0x43, 0x4f,
            0x64, 0xd0, 0x36, 0x2f, 0x2a, 0x2d, 0x2d, 0x0a, 0x90, 0xcf, 0x1a,
            0x5a, 0x4c, 0x5d, 0xb0, 0x2d, 0x56, 0xec, 0xc4, 0xc5, 0xbf, 0x34,
            0x00, 0x72, 0x08, 0xd5, 0xb8, 0x87, 0x18, 0x58, 0x65
        ])
        let derived = HKDF.derive(length: 42, derivedFrom: ikm, salt: salt, context: info)
        XCTAssertEqual(derived, expected)
    }

    // MARK: HMAC

    func testHMACSHA256TestVector() {
        // RFC 4231 test case 1
        let key = Data(repeating: 0x0b, count: 20)
        let data = Data("Hi There".utf8)
        let expected = Data([
            0xb0, 0x34, 0x4c, 0x61, 0xd8, 0xdb, 0x38, 0x53, 0x5c, 0xa8, 0xaf,
            0xce, 0xaf, 0x0b, 0xf1, 0x2b, 0x88, 0x1d, 0xc2, 0x00, 0xc9, 0x83,
            0x3d, 0xa7, 0x26, 0xe9, 0x37, 0x6c, 0x2e, 0x32, 0xcf, 0xf7
        ])
        XCTAssertEqual(HMACSHA256.authenticate(data, key: key), expected)
    }

    // MARK: Token

    func testTokenRoundTrip128() throws {
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let token = try Token(key: key)
        XCTAssertEqual(token.mode, .aes128cbc)
        let plaintext = Data("token round trip".utf8)
        let encrypted = try token.encrypt(plaintext)
        XCTAssertGreaterThan(encrypted.count, Constants.tokenOverhead)
        XCTAssertEqual(try token.decrypt(encrypted), plaintext)
    }

    func testTokenRoundTrip256() throws {
        let key = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
        let token = try Token(key: key)
        XCTAssertEqual(token.mode, .aes256cbc)
        let plaintext = Data("aes256 token".utf8)
        let encrypted = try token.encrypt(plaintext)
        XCTAssertEqual(try token.decrypt(encrypted), plaintext)
    }

    func testTokenRejectsBadHMAC() throws {
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let token = try Token(key: key)
        var encrypted = try token.encrypt(Data("ok".utf8))
        encrypted[encrypted.count - 1] ^= 0xFF
        XCTAssertThrowsError(try token.decrypt(encrypted))
    }
}
