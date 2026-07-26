import XCTest
@testable import ReticulumSwift

/// Tests for the `multiprocessing.connection` authentication handshake used by the
/// RNS instance-control RPC channel (port 37429).
///
/// Python reference: CPython `Lib/multiprocessing/connection.py` —
///   • `_get_digest_name_and_payload(message)`
///   • `_create_response(authkey, message)`
///   • `_verify_challenge(authkey, message, response)`
///   • `deliver_challenge` / `answer_challenge`
///
/// Two protocol generations exist and both must be supported, because a Swift
/// `rnsd` may be driven by a Python ≤3.11 client and a Swift `rnstatus` may be
/// driven against a Python ≥3.12 daemon:
///   • **legacy** (≤3.11): challenge payload is 16 or 20 raw bytes, response is a
///     bare HMAC-MD5 digest with no prefix.
///   • **modern** (≥3.12): challenge payload is `{digest}` + 40 random bytes, and
///     the response is `{digest}` + HMAC over the *entire* prefixed message.
///
/// The golden vectors below were produced by CPython 3.14.5.
final class MultiprocessingAuthTests: XCTestCase {

    /// authkey = bytes(range(32))
    private let authkey = Data((0..<32).map { UInt8($0) })

    // MARK: - Protocol constants

    func testChallengePrefix() {
        // Python: _CHALLENGE = b'#CHALLENGE#'
        XCTAssertEqual(MultiprocessingAuth.challengePrefix, Data("#CHALLENGE#".utf8))
    }

    func testWelcomeMessage() {
        // Python: _WELCOME = b'#WELCOME#'
        XCTAssertEqual(MultiprocessingAuth.welcomeMessage, Data("#WELCOME#".utf8))
    }

    func testFailureMessage() {
        // Python: _FAILURE = b'#FAILURE#'
        XCTAssertEqual(MultiprocessingAuth.failureMessage, Data("#FAILURE#".utf8))
    }

    func testModernMessageLength() {
        // Python: MESSAGE_LENGTH = 40 (3.12+)
        XCTAssertEqual(MultiprocessingAuth.messageLength, 40)
    }

    func testLegacyMessageLength() {
        // Python ≤3.11: MESSAGE_LENGTH = 20
        XCTAssertEqual(MultiprocessingAuth.legacyMessageLength, 20)
    }

    // MARK: - digestNameAndPayload

    func testDigestNameAndPayload_20ByteMessage_isLegacy() throws {
        // Python: len(message) in _LEGACY_LENGTHS -> return '', message
        let msg = Data((0..<20).map { UInt8($0) })
        let (digest, payload) = try MultiprocessingAuth.digestNameAndPayload(msg)
        XCTAssertNil(digest)
        XCTAssertEqual(payload, msg)
    }

    func testDigestNameAndPayload_16ByteMessage_isLegacy() throws {
        // 16 is the other member of Python's _LEGACY_LENGTHS
        let msg = Data((0..<16).map { UInt8($0) })
        let (digest, payload) = try MultiprocessingAuth.digestNameAndPayload(msg)
        XCTAssertNil(digest)
        XCTAssertEqual(payload, msg)
    }

    func testDigestNameAndPayload_sha256Prefix() throws {
        let payloadBytes = Data((0..<40).map { UInt8($0) })
        let msg = Data("{sha256}".utf8) + payloadBytes
        let (digest, payload) = try MultiprocessingAuth.digestNameAndPayload(msg)
        XCTAssertEqual(digest, .sha256)
        XCTAssertEqual(payload, payloadBytes)
    }

    func testDigestNameAndPayload_sha384Prefix() throws {
        let payloadBytes = Data((0..<40).map { UInt8($0) })
        let msg = Data("{sha384}".utf8) + payloadBytes
        let (digest, payload) = try MultiprocessingAuth.digestNameAndPayload(msg)
        XCTAssertEqual(digest, .sha384)
        XCTAssertEqual(payload, payloadBytes)
    }

    func testDigestNameAndPayload_md5Prefix() throws {
        let payloadBytes = Data((0..<40).map { UInt8($0) })
        let msg = Data("{md5}".utf8) + payloadBytes
        let (digest, payload) = try MultiprocessingAuth.digestNameAndPayload(msg)
        XCTAssertEqual(digest, .md5)
        XCTAssertEqual(payload, payloadBytes)
    }

    func testDigestNameAndPayload_unknownDigest_throws() {
        // Python raises AuthenticationError for a digest not in _ALLOWED_DIGESTS
        let msg = Data("{blake2b}".utf8) + Data((0..<40).map { UInt8($0) })
        XCTAssertThrowsError(try MultiprocessingAuth.digestNameAndPayload(msg))
    }

    func testDigestNameAndPayload_sha3_isAllowedButUnsupported() {
        // Python allows sha3_256 / sha3_384, but CryptoKit has no SHA-3.
        // We must reject rather than silently mis-compute.
        let msg = Data("{sha3_256}".utf8) + Data((0..<40).map { UInt8($0) })
        XCTAssertThrowsError(try MultiprocessingAuth.digestNameAndPayload(msg)) { error in
            XCTAssertEqual(error as? MultiprocessingAuth.AuthError, .unsupportedDigest("sha3_256"))
        }
    }

    func testDigestNameAndPayload_noPrefixAndNonLegacyLength_throws() {
        // Python: raises AuthenticationError ("unsupported message length,
        // missing digest prefix, or unsupported digest")
        let msg = Data((0..<40).map { UInt8($0) })
        XCTAssertThrowsError(try MultiprocessingAuth.digestNameAndPayload(msg))
    }

    func testDigestNameAndPayload_closingBraceTooFarAway_throws() {
        // Python bounds the search: message.find(b'}', 1, _MAX_DIGEST_LEN+2)
        // _MAX_DIGEST_LEN == 8 (len("sha3_256")), so '}' must appear before index 10.
        let msg = Data("{aaaaaaaaaaaa}".utf8) + Data((0..<40).map { UInt8($0) })
        XCTAssertThrowsError(try MultiprocessingAuth.digestNameAndPayload(msg))
    }

    // MARK: - createResponse (golden vectors from CPython 3.14.5)

    func testCreateResponse_legacy20Byte_isBareMD5() throws {
        // python: hmac.new(authkey, bytes(range(20)), 'md5').digest()
        let msg = Data((0..<20).map { UInt8($0) })
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: msg)
        XCTAssertEqual(response.hexString, "7e57151ba744ee63c52e1497fbef19d0")
    }

    func testCreateResponse_legacy16Byte_isBareMD5() throws {
        let msg = Data((0..<16).map { UInt8($0) })
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: msg)
        XCTAssertEqual(response.hexString, "80424d3e343a7428bcfc6103ab345a99")
    }

    func testCreateResponse_modernSHA256_isPrefixedAndCoversWholeMessage() throws {
        // The MAC protects the ENTIRE message, digest prefix included.
        let msg = Data("{sha256}".utf8) + Data((0..<40).map { UInt8($0) })
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: msg)
        XCTAssertEqual(
            response.hexString,
            "7b7368613235367d0988643d19a1da3f98648ba4eec9b8b09b61d95da64bc38ba809c6b7e7bcaf3c"
        )
    }

    func testCreateResponse_modernSHA384() throws {
        let msg = Data("{sha384}".utf8) + Data((0..<40).map { UInt8($0) })
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: msg)
        XCTAssertEqual(
            response.hexString,
            "7b7368613338347d258efc885620a24ad71c5d7dd232b7064c369203e7960dfa"
            + "8c2a5588d69d6ded3fc5e41c4e861722b0e415c8f7852874"
        )
    }

    func testCreateResponse_modernResponseCarriesDigestPrefix() throws {
        let msg = Data("{sha256}".utf8) + Data((0..<40).map { UInt8($0) })
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: msg)
        XCTAssertEqual(response.prefix(8), Data("{sha256}".utf8))
        XCTAssertEqual(response.count, 8 + 32)
    }

    // MARK: - verifyChallenge

    func testVerifyChallenge_legacyRoundTrip() throws {
        let msg = Data((0..<20).map { UInt8($0) })
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: msg)
        XCTAssertTrue(MultiprocessingAuth.verifyChallenge(authkey: authkey, message: msg, response: response))
    }

    func testVerifyChallenge_modernRoundTrip() throws {
        let msg = Data("{sha256}".utf8) + Data((0..<40).map { UInt8($0) })
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: msg)
        XCTAssertTrue(MultiprocessingAuth.verifyChallenge(authkey: authkey, message: msg, response: response))
    }

    func testVerifyChallenge_wrongAuthkey_fails() throws {
        let msg = Data("{sha256}".utf8) + Data((0..<40).map { UInt8($0) })
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: msg)
        let otherKey = Data(repeating: 0xAB, count: 32)
        XCTAssertFalse(MultiprocessingAuth.verifyChallenge(authkey: otherKey, message: msg, response: response))
    }

    func testVerifyChallenge_truncatedResponse_fails() throws {
        // Python raises on a length mismatch before comparing.
        let msg = Data("{sha256}".utf8) + Data((0..<40).map { UInt8($0) })
        var response = try MultiprocessingAuth.createResponse(authkey: authkey, message: msg)
        response = response.dropLast(4)
        XCTAssertFalse(MultiprocessingAuth.verifyChallenge(authkey: authkey, message: msg, response: response))
    }

    func testVerifyChallenge_clientMayUpgradeDigestOnLegacyChallenge() throws {
        // Python: "If our message did not include a digest_name prefix, the client
        // is allowed to select a stronger digest_name from _ALLOWED_DIGESTS."
        // The MAC is still taken over the (unprefixed) challenge message.
        let msg = Data((0..<20).map { UInt8($0) })
        let mac = MultiprocessingAuth.hmac(.sha256, key: authkey, data: msg)
        let response = Data("{sha256}".utf8) + mac
        XCTAssertTrue(MultiprocessingAuth.verifyChallenge(authkey: authkey, message: msg, response: response))
    }

    func testVerifyChallenge_garbageResponse_failsWithoutThrowing() {
        let msg = Data("{sha256}".utf8) + Data((0..<40).map { UInt8($0) })
        let response = Data(repeating: 0x00, count: 7) // neither legacy length nor prefixed
        XCTAssertFalse(MultiprocessingAuth.verifyChallenge(authkey: authkey, message: msg, response: response))
    }

    // MARK: - Challenge generation

    func testMakeChallenge_isModernAndCorrectlyShaped() {
        // Python deliver_challenge: b'{%s}%s' % (digest_name, os.urandom(MESSAGE_LENGTH))
        let message = MultiprocessingAuth.makeChallengeMessage(digest: .sha256)
        XCTAssertEqual(message.prefix(8), Data("{sha256}".utf8))
        XCTAssertEqual(message.count, 8 + MultiprocessingAuth.messageLength)
    }

    func testMakeChallenge_isRandomPerCall() {
        let a = MultiprocessingAuth.makeChallengeMessage(digest: .sha256)
        let b = MultiprocessingAuth.makeChallengeMessage(digest: .sha256)
        XCTAssertNotEqual(a, b)
    }

    func testMakeChallenge_roundTripsThroughCreateResponseAndVerify() throws {
        let message = MultiprocessingAuth.makeChallengeMessage(digest: .sha256)
        let response = try MultiprocessingAuth.createResponse(authkey: authkey, message: message)
        XCTAssertTrue(MultiprocessingAuth.verifyChallenge(authkey: authkey, message: message, response: response))
    }

    // MARK: - Digest metadata

    func testDigestOutputLengths() {
        XCTAssertEqual(MultiprocessingAuth.Digest.md5.outputLength, 16)
        XCTAssertEqual(MultiprocessingAuth.Digest.sha256.outputLength, 32)
        XCTAssertEqual(MultiprocessingAuth.Digest.sha384.outputLength, 48)
    }

    func testDigestWireNames() {
        XCTAssertEqual(MultiprocessingAuth.Digest.md5.rawValue, "md5")
        XCTAssertEqual(MultiprocessingAuth.Digest.sha256.rawValue, "sha256")
        XCTAssertEqual(MultiprocessingAuth.Digest.sha384.rawValue, "sha384")
    }
}
