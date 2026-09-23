//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

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

  // Python's `PKCS7.unpad` reads only the last byte `n`, raises only when
  // `n > bs`, and returns `data[:len-n]`. Expected values below were captured
  // from `RNS/Cryptography/PKCS7.py` (RNS 1.5.4).

  func testPKCS7UnpadAcceptsZeroFilledPaddingLikePython() throws {
    // ANSI X.923 as microReticulum 0.5.0 pads: zeros, then one length byte.
    let body = Data((1...13).map { UInt8($0) })
    XCTAssertEqual(try PKCS7.unpad(body + Data([0x00, 0x00, 0x03])), body)
    XCTAssertEqual(try PKCS7.unpad(Data(repeating: 0, count: 15) + Data([0x10])), Data())
  }

  func testPKCS7UnpadIgnoresPadBytesOtherThanTheLast() throws {
    let body = Data((1...13).map { UInt8($0) })
    XCTAssertEqual(try PKCS7.unpad(body + Data([0xAA, 0xBB, 0x03])), body)
  }

  func testPKCS7UnpadOfZeroLengthPadReturnsDataUnchanged() throws {
    let data = Data((1...15).map { UInt8($0) }) + Data([0x00])
    XCTAssertEqual(try PKCS7.unpad(data), data)
  }

  func testPKCS7UnpadDoesNotRequireBlockAlignment() throws {
    let data = Data([0x09, 0x08, 0x07, 0x06, 0x05, 0x02, 0x02])
    XCTAssertEqual(try PKCS7.unpad(data), Data([0x09, 0x08, 0x07, 0x06, 0x05]))
  }

  func testPKCS7UnpadRejectsPadLengthAboveBlockSize() {
    XCTAssertThrowsError(try PKCS7.unpad(Data(repeating: 0xFF, count: 16)))
    XCTAssertThrowsError(try PKCS7.unpad(Data(repeating: 0, count: 15) + Data([0x11])))
  }

  // Python raises IndexError on empty input and slices from the end when
  // `n > len`; neither is reachable from `Token.decrypt`, which only hands
  // unpad a non-empty, block-aligned AES-CBC output. Swift throws for both.
  func testPKCS7UnpadRejectsEmptyInputAndPadLongerThanData() {
    XCTAssertThrowsError(try PKCS7.unpad(Data()))
    XCTAssertThrowsError(try PKCS7.unpad(Data([0x01, 0x02, 0x05])))
  }

  // MARK: AES-CBC

  func testAESCBCRoundTrip() throws {
    let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
    let iv = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    let plaintext = PKCS7.pad(Data("hello aes cbc".utf8))
    let ciphertext = try AESCBC.encrypt(plaintext: plaintext, key: key, iv: iv)
    let decrypted = try AESCBC.decrypt(ciphertext: ciphertext, key: key, iv: iv)
    XCTAssertEqual(try PKCS7.unpad(decrypted), Data("hello aes cbc".utf8))
  }

  // MARK: HKDF—RFC 5869 test vector A.1

  func testHKDFTestVectorA1() {
    let ikm = Data([
      0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b,
      0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b, 0x0b,
    ])
    let salt = Data([
      0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a,
      0x0b, 0x0c,
    ])
    let info = Data([
      0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9,
    ])
    let expected = Data([
      0x3c, 0xb2, 0x5f, 0x25, 0xfa, 0xac, 0xd5, 0x7a, 0x90, 0x43, 0x4f,
      0x64, 0xd0, 0x36, 0x2f, 0x2a, 0x2d, 0x2d, 0x0a, 0x90, 0xcf, 0x1a,
      0x5a, 0x4c, 0x5d, 0xb0, 0x2d, 0x56, 0xec, 0xc4, 0xc5, 0xbf, 0x34,
      0x00, 0x72, 0x08, 0xd5, 0xb8, 0x87, 0x18, 0x58, 0x65,
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
      0x3d, 0xa7, 0x26, 0xe9, 0x37, 0x6c, 0x2e, 0x32, 0xcf, 0xf7,
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

  // A token whose plaintext is padded ANSI X.923-style (zeros, then the length
  // byte), as microReticulum 0.5.0 sends it. Built and decrypted by the Python
  // reference (RNS 1.5.4): key 0x00…0x3F, IV 0xA0…0xAF, plaintext
  // "microReticulum" padded with [0x00, 0x02].
  func testTokenDecryptsZeroFilledPaddingLikePython() throws {
    let token = try Token(key: Data((0..<64).map { UInt8($0) }))
    let encrypted = try XCTUnwrap(
      Data(
        hex: "a0a1a2a3a4a5a6a7a8a9aaabacadaeaf7b4a5e7d061135f53fd9962badd785c9"
          + "dad3b1b76df655ec04796a02badeee50cd080eef561293c7dade87ab8a32c12a"))
    XCTAssertEqual(try token.decrypt(encrypted), Data("microReticulum".utf8))
  }
}
