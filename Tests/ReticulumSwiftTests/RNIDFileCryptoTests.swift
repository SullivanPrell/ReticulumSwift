import XCTest
@testable import ReticulumSwift

/// Tests for the `.rfe` chunked file format.
///
/// Python reference: RNS/Utilities/rnid.py — `encrypt` (:847-888), `decrypt` (:890-939),
/// and the `ENC_CHUNK`/`DEC_CHUNK` constants (:60-61).
final class RNIDFileCryptoTests: XCTestCase {

    // MARK: - The chunk-size identity

    /// The single most important invariant in the port: the `.rfe` format has no header, no
    /// length prefix and no framing, so decryption only re-aligns because a full `ENC_CHUNK`
    /// plaintext encrypts to exactly `DEC_CHUNK` bytes.
    func testChunkSizeIdentity() {
        // Python: ENC_CHUNK = CHUNK_BLOCKS * RNS.Identity.AES256_BLOCKSIZE
        XCTAssertEqual(RNIDApp.encChunk, 16_777_216)
        // Python: DEC_CHUNK = ENC_CHUNK + RNS.Cryptography.Token.TOKEN_OVERHEAD*2
        XCTAssertEqual(RNIDApp.decChunk, 16_777_312)
        XCTAssertEqual(RNIDApp.decChunk, RNIDApp.encChunk + 96)

        XCTAssertEqual(RNIDFileCrypto.encryptedChunkSize(plaintextChunk: RNIDApp.encChunk),
                       RNIDApp.decChunk)
    }

    func testEncryptedChunkSizeForShortTails() {
        for n in [0, 1, 15, 16, 17, 4095] {
            // 32 (ephemeral pub) + 16 (IV) + PKCS7-padded plaintext + 32 (HMAC).
            let expected = 80 + n + (16 - n % 16)
            XCTAssertEqual(RNIDFileCrypto.encryptedChunkSize(plaintextChunk: n), expected, "n = \(n)")
            XCTAssertLessThan(expected, RNIDApp.decChunk, "n = \(n)")
        }
    }

    /// Proves the `.rfe` format really is a bare token concatenation.
    func testNoFramingOverhead() throws {
        let identity = Identity()
        let reader = RNIDDataReader(Data(repeating: 0x5A, count: 40))
        let writer = RNIDDataWriter()
        try RNIDFileCrypto.encryptStream(identity: identity, reader: reader, writer: writer)
        // 32 ephemeral pub + 16 IV + 48 ciphertext (40 → 48 after PKCS7) + 32 HMAC.
        XCTAssertEqual(writer.data.count, 128)
        XCTAssertEqual(writer.data.count, RNIDFileCrypto.encryptedChunkSize(plaintextChunk: 40))
    }

    // MARK: - Round trips

    func testRoundTripsSmallPayloads() throws {
        let identity = Identity()
        for size in [0, 1, 15, 16, 17, 1000] {
            var payload = Data(capacity: size)
            for index in 0..<size { payload.append(UInt8(index % 251)) }

            let cipherWriter = RNIDDataWriter()
            try RNIDFileCrypto.encryptStream(identity: identity,
                                             reader: RNIDDataReader(payload),
                                             writer: cipherWriter)
            let plainWriter = RNIDDataWriter()
            try RNIDFileCrypto.decryptStream(identity: identity,
                                             reader: RNIDDataReader(cipherWriter.data),
                                             writer: plainWriter)
            XCTAssertEqual(plainWriter.data, payload, "size \(size)")
        }
    }

    /// The boundary that matters: exactly one full `ENC_CHUNK`, plus one byte over, which is
    /// what proves fixed-size `DEC_CHUNK` reads re-align.
    func testRoundTripsAcrossTheChunkBoundary() throws {
        let identity = Identity()
        for size in [RNIDApp.encChunk - 1, RNIDApp.encChunk, RNIDApp.encChunk + 1] {
            let payload = Data(repeating: 0x42, count: size)

            let cipherWriter = RNIDDataWriter()
            try RNIDFileCrypto.encryptStream(identity: identity,
                                             reader: RNIDDataReader(payload),
                                             writer: cipherWriter)

            // Predicted ciphertext length = sum of encryptedChunkSize over the chunking.
            var expected = 0
            var remaining = size
            repeat {
                let take = min(remaining, RNIDApp.encChunk)
                expected += RNIDFileCrypto.encryptedChunkSize(plaintextChunk: take)
                remaining -= take
            } while remaining > 0
            XCTAssertEqual(cipherWriter.data.count, expected, "size \(size)")

            let plainWriter = RNIDDataWriter()
            try RNIDFileCrypto.decryptStream(identity: identity,
                                             reader: RNIDDataReader(cipherWriter.data),
                                             writer: plainWriter)
            XCTAssertEqual(plainWriter.data.count, size, "size \(size)")
            XCTAssertEqual(plainWriter.data, payload, "size \(size)")
        }
    }

    // MARK: - Failure modes

    func testDecryptWithTheWrongIdentityFails() throws {
        let alice = Identity()
        let bob = Identity()
        let cipherWriter = RNIDDataWriter()
        try RNIDFileCrypto.encryptStream(identity: alice,
                                         reader: RNIDDataReader(Data("secret".utf8)),
                                         writer: cipherWriter)

        XCTAssertThrowsError(try RNIDFileCrypto.decryptStream(
            identity: bob,
            reader: RNIDDataReader(cipherWriter.data),
            writer: RNIDDataWriter())) { error in
            // Python's `if not decrypted:` cannot distinguish causes → exit 12.
            XCTAssertEqual(error as? RNIDFileCrypto.CryptoError, .decryptFailed)
        }
    }

    func testShortCiphertextAlsoMapsToDecryptFailed() {
        let identity = Identity()
        // Swift rejects any token with count <= 32 via IdentityError.ciphertextTooShort;
        // that must still surface as .decryptFailed, not .unknownError.
        XCTAssertThrowsError(try RNIDFileCrypto.decryptStream(
            identity: identity,
            reader: RNIDDataReader(Data(count: 20)),
            writer: RNIDDataWriter())) { error in
            XCTAssertEqual(error as? RNIDFileCrypto.CryptoError, .decryptFailed)
        }
    }

    func testPublicOnlyIdentityCanEncryptButNotDecrypt() throws {
        let publicOnly = try Identity(publicKeyBytes: Identity().getPublicKey())

        // Python only requires get_public_key() for encryption.
        let writer = RNIDDataWriter()
        XCTAssertNoThrow(try RNIDFileCrypto.encryptStream(identity: publicOnly,
                                                          reader: RNIDDataReader(Data("x".utf8)),
                                                          writer: writer))
        XCTAssertFalse(writer.data.isEmpty)

        XCTAssertThrowsError(try RNIDFileCrypto.decryptStream(identity: publicOnly,
                                                              reader: RNIDDataReader(writer.data),
                                                              writer: RNIDDataWriter())) { error in
            XCTAssertEqual(error as? RNIDFileCrypto.CryptoError, .missingPrivateKey)
        }
    }

    // MARK: - Progress-callback placement

    /// Python's encrypt progress `print` sits OUTSIDE the `if chunk` block, so it also fires
    /// on the terminating iteration; decrypt's sits INSIDE it. The asymmetry is observable.
    func testProgressCallbackPlacementDiffersBetweenEncryptAndDecrypt() throws {
        let identity = Identity()

        var encryptCalls: [Int] = []
        try RNIDFileCrypto.encryptStream(identity: identity,
                                         reader: RNIDDataReader(Data()),
                                         writer: RNIDDataWriter()) { encryptCalls.append($0) }
        XCTAssertEqual(encryptCalls, [0], "an empty input still reports one \"Wrote 0 B\"")

        var decryptCalls: [Int] = []
        try RNIDFileCrypto.decryptStream(identity: identity,
                                         reader: RNIDDataReader(Data()),
                                         writer: RNIDDataWriter()) { decryptCalls.append($0) }
        XCTAssertEqual(decryptCalls, [], "an empty .rfe reports nothing at all")
    }
}
