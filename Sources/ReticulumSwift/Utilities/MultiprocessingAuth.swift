import Foundation
import CryptoKit

/// The `multiprocessing.connection` mutual-authentication handshake, as used by the
/// RNS instance-control RPC channel.
///
/// Python reference: CPython `Lib/multiprocessing/connection.py`. RNS itself never
/// implements this — it hands the socket to `multiprocessing.connection.Listener` /
/// `Client` with `authkey = RNS.Identity.full_hash(internal_identity.get_private_key())`
/// (`RNS/Reticulum.py`, `rpc_key`), so the Swift side must speak CPython's protocol
/// byte-for-byte to interoperate with `rnstatus`, `rnpath` and friends.
///
/// ## Two protocol generations
///
/// CPython changed this handshake in 3.12 while keeping backwards compatibility, and
/// both generations are live in the wild:
///
/// - **Legacy** (CPython ≤ 3.11): the challenge payload is 16 or 20 raw random bytes
///   and the response is a bare HMAC-MD5 digest with no prefix.
/// - **Modern** (CPython ≥ 3.12): the challenge payload is `{digest}` followed by 40
///   random bytes, and the response is `{digest}` followed by an HMAC taken over the
///   *entire* message — the `{digest}` prefix included, which is what prevents a
///   downgrade attack.
///
/// A peer that sends a legacy challenge may still receive a modern (prefixed) response:
/// CPython deliberately allows the answering side to upgrade to a stronger digest when
/// the challenger did not pin one.
///
/// ## Digest support
///
/// CPython allows `md5`, `sha256`, `sha384`, `sha3_256` and `sha3_384`. CryptoKit has no
/// SHA-3, so the two SHA-3 names are recognised and then explicitly rejected rather than
/// silently mis-computed. This is not a practical limitation: `deliver_challenge` defaults
/// to `sha256` and nothing in RNS overrides it.
public enum MultiprocessingAuth {

    // MARK: - Protocol constants

    /// Python: `_CHALLENGE = b'#CHALLENGE#'`.
    public static let challengePrefix = Data("#CHALLENGE#".utf8)

    /// Python: `_WELCOME = b'#WELCOME#'`.
    public static let welcomeMessage = Data("#WELCOME#".utf8)

    /// Python: `_FAILURE = b'#FAILURE#'`.
    public static let failureMessage = Data("#FAILURE#".utf8)

    /// Random-payload length used when *issuing* a challenge.
    /// Python ≥ 3.12: `MESSAGE_LENGTH = 40`.
    public static let messageLength = 40

    /// Random-payload length used by CPython ≤ 3.11 when issuing a challenge.
    /// Python ≤ 3.11: `MESSAGE_LENGTH = 20`.
    public static let legacyMessageLength = 20

    /// Payload lengths that identify an unprefixed, legacy-format message.
    /// Python: `_LEGACY_LENGTHS = frozenset({16, 20})`.
    static let legacyLengths: Set<Int> = [16, 20]

    /// Longest allowed digest name — `len("sha3_256")`.
    /// Python: `_MAX_DIGEST_LEN = max(len(_) for _ in _ALLOWED_DIGESTS)`.
    static let maxDigestNameLength = 8

    /// Digest names CPython permits but CryptoKit cannot compute.
    static let unsupportedDigestNames: Set<String> = ["sha3_256", "sha3_384"]

    // MARK: - Digest

    /// A digest algorithm usable in the handshake.
    public enum Digest: String, CaseIterable, Equatable {
        case md5
        case sha256
        case sha384

        /// Digest output size in bytes.
        public var outputLength: Int {
            switch self {
            case .md5:    return 16
            case .sha256: return 32
            case .sha384: return 48
            }
        }
    }

    // MARK: - Errors

    public enum AuthError: Error, Equatable {
        /// The message was neither a legacy-length payload nor a validly prefixed one.
        /// Python raises `AuthenticationError` with the same meaning.
        case malformedMessage
        /// The digest name is one CPython allows but CryptoKit cannot compute (SHA-3).
        case unsupportedDigest(String)
        /// The peer did not prefix its challenge with `#CHALLENGE#`.
        case missingChallengePrefix
        /// The peer rejected our digest, or sent something other than `#WELCOME#`.
        case rejected
    }

    // MARK: - Message parsing

    /// Split a challenge (or response) message into its digest name and payload.
    ///
    /// Python: `_get_digest_name_and_payload(message)`. A `nil` digest means legacy
    /// mode, where the caller must fall back to unprefixed HMAC-MD5.
    ///
    /// - Parameter message: the message *without* the `#CHALLENGE#` prefix.
    /// - Returns: the pinned digest (or `nil` for legacy) and the payload bytes.
    public static func digestNameAndPayload(_ message: Data) throws -> (Digest?, Data) {
        // Python: if len(message) in _LEGACY_LENGTHS: return '', message
        if legacyLengths.contains(message.count) { return (nil, message) }

        // Python: message.startswith(b'{') and (curly := message.find(b'}', 1, _MAX_DIGEST_LEN+2)) > 0
        guard message.first == UInt8(ascii: "{") else { throw AuthError.malformedMessage }

        let searchEnd = min(message.count, maxDigestNameLength + 2)
        var closingIndex: Int? = nil
        var i = 1
        while i < searchEnd {
            if message[message.startIndex + i] == UInt8(ascii: "}") { closingIndex = i; break }
            i += 1
        }
        guard let curly = closingIndex else { throw AuthError.malformedMessage }

        let nameBytes = message[(message.startIndex + 1)..<(message.startIndex + curly)]
        guard let name = String(data: Data(nameBytes), encoding: .ascii) else {
            throw AuthError.malformedMessage
        }

        // Recognised by CPython but not computable here — reject loudly.
        if unsupportedDigestNames.contains(name) { throw AuthError.unsupportedDigest(name) }

        guard let digest = Digest(rawValue: name) else { throw AuthError.malformedMessage }

        let payload = Data(message[(message.startIndex + curly + 1)...])
        return (digest, payload)
    }

    // MARK: - Response creation

    /// Compute the response to a peer's challenge.
    ///
    /// Python: `_create_response(authkey, message)`. Note that the MAC covers the whole
    /// message including any `{digest}` prefix — not just the payload.
    ///
    /// - Parameters:
    ///   - authkey: the shared secret (RNS uses `full_hash(internal_identity_private_key)`).
    ///   - message: the challenge message *without* the `#CHALLENGE#` prefix.
    /// - Returns: a bare MD5 MAC in legacy mode, or `{digest}` + MAC in modern mode.
    public static func createResponse(authkey: Data, message: Data) throws -> Data {
        let (digest, _) = try digestNameAndPayload(message)
        guard let digest else {
            // Legacy peer: bare HMAC-MD5 over the whole message.
            return hmac(.md5, key: authkey, data: message)
        }
        return Data("{\(digest.rawValue)}".utf8) + hmac(digest, key: authkey, data: message)
    }

    // MARK: - Response verification

    /// Verify a peer's response to a challenge we issued.
    ///
    /// Python: `_verify_challenge(authkey, message, response)`, which raises on failure;
    /// this returns `false` instead, since every caller here treats a failure the same way.
    ///
    /// - Parameters:
    ///   - authkey: the shared secret.
    ///   - message: the challenge message we sent, *without* the `#CHALLENGE#` prefix.
    ///   - response: the peer's reply.
    public static func verifyChallenge(authkey: Data, message: Data, response: Data) -> Bool {
        // Python reads the digest from the RESPONSE, not from our challenge, so that a
        // peer answering an unprefixed challenge may upgrade to a stronger digest.
        guard let (responseDigest, responseMAC) = try? digestNameAndPayload(response) else {
            return false
        }
        let digest = responseDigest ?? .md5
        let expected = hmac(digest, key: authkey, data: message)
        guard expected.count == responseMAC.count else { return false }
        return constantTimeEquals(expected, responseMAC)
    }

    // MARK: - Challenge generation

    /// Build a fresh challenge message (without the `#CHALLENGE#` prefix).
    ///
    /// Python `deliver_challenge`: `b'{%s}%s' % (digest_name, os.urandom(MESSAGE_LENGTH))`.
    public static func makeChallengeMessage(digest: Digest = .sha256) -> Data {
        var payload = Data(count: messageLength)
        _ = payload.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, messageLength, $0.baseAddress!)
        }
        return Data("{\(digest.rawValue)}".utf8) + payload
    }

    // MARK: - Primitives

    /// HMAC using the named digest.
    static func hmac(_ digest: Digest, key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        switch digest {
        case .md5:    return Data(CryptoKit.HMAC<Insecure.MD5>.authenticationCode(for: data, using: symmetricKey))
        case .sha256: return Data(CryptoKit.HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey))
        case .sha384: return Data(CryptoKit.HMAC<SHA384>.authenticationCode(for: data, using: symmetricKey))
        }
    }

    /// Length-independent, early-exit-free comparison.
    /// Python uses `hmac.compare_digest` for the same reason.
    static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(lhs, rhs) { difference |= a ^ b }
        return difference == 0
    }
}
