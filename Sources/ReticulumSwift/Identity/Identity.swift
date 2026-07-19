import Foundation
import CryptoKit

/// A Reticulum Identity. Combines an X25519 key pair (for ECDH-derived
/// encryption) with an Ed25519 key pair (for signatures).
///
/// Wire serialization, identical to the Python reference implementation:
///   * Public key bytes:  [32 X25519 pub] [32 Ed25519 pub]      (64 bytes)
///   * Private key bytes: [32 X25519 priv] [32 Ed25519 priv]    (64 bytes)
///   * Identity hash:     SHA256(pub bytes)[:16]                (16 bytes)
public final class Identity: Equatable, Hashable, @unchecked Sendable {
    public let signingPrivateKey: Curve25519.Signing.PrivateKey?
    public let encryptionPrivateKey: Curve25519.KeyAgreement.PrivateKey?

    public let signingPublicKey: Curve25519.Signing.PublicKey
    public let encryptionPublicKey: Curve25519.KeyAgreement.PublicKey

    /// Application-supplied bytes attached to the most recent announce, if any.
    public var appData: Data?

    /// Guards the mutable ratchet state (`_activeRatchetPrivateKey`,
    /// `_previousRatchets`, `_activeRatchetTime`). `Identity` is `@unchecked
    /// Sendable`, and the same identity is used by the send path (which rotates
    /// the ratchet) and the receive path (which reads the key pool to decrypt)
    /// concurrently — an unsynchronized read of the `Data?`/array while rotation
    /// writes it can tear. Self-contained leaf lock: the guarded regions make no
    /// callouts, so it never nests with any other lock. Internal helpers suffixed
    /// `Locked` assume the caller already holds it (the lock is non-recursive).
    private let ratchetLock = NSLock()

    /// Currently-active ratchet private key (32 bytes). Set by
    /// `rotateRatchet()`; the public part is what we publish in our
    /// next announce so peers will encrypt to it (forward secrecy).
    private var _activeRatchetPrivateKey: Data?
    public private(set) var activeRatchetPrivateKey: Data? {
        get { ratchetLock.lock(); defer { ratchetLock.unlock() }; return _activeRatchetPrivateKey }
        set { ratchetLock.lock(); _activeRatchetPrivateKey = newValue; ratchetLock.unlock() }
    }

    /// Recently-rotated ratchet privates. Inbound encrypted messages
    /// may still be addressed to a previous ratchet for a short window
    /// after rotation, so we keep a few around for decrypt fallback.
    /// Bounded by `ratchetHistoryDepth` and aged out per
    /// `ratchetExpiry`.
    private var _previousRatchets: [HistoricalRatchet] = []
    public private(set) var previousRatchets: [HistoricalRatchet] {
        get { ratchetLock.lock(); defer { ratchetLock.unlock() }; return _previousRatchets }
        set { ratchetLock.lock(); _previousRatchets = newValue; ratchetLock.unlock() }
    }
    public var ratchetHistoryDepth: Int = 8

    /// Mirrors Python's `RNS.Identity.RATCHET_EXPIRY` (30 days). Historical
    /// ratchet privates older than this are dropped on rotation/sweep.
    public var ratchetExpiry: TimeInterval = 60 * 60 * 24 * 30

    /// Mirrors Python's `RNS.Destination.RATCHET_INTERVAL` (30 minutes).
    /// `rotateRatchetIfNeeded()` only rotates if at least this much time
    /// has elapsed since the active ratchet was generated.
    public var ratchetInterval: TimeInterval = 30 * 60

    /// Wall-clock time the active ratchet was generated. Nil until the
    /// first rotation.
    private var _activeRatchetTime: Date?
    public private(set) var activeRatchetTime: Date? {
        get { ratchetLock.lock(); defer { ratchetLock.unlock() }; return _activeRatchetTime }
        set { ratchetLock.lock(); _activeRatchetTime = newValue; ratchetLock.unlock() }
    }

    public struct HistoricalRatchet: Equatable {
        public let privateKey: Data
        public let retiredAt: Date
    }

    /// Read-only view that flattens history into `[Data]` for callers
    /// that don't care about timestamps (decrypt path, persistence).
    public var previousRatchetPrivateKeys: [Data] {
        ratchetLock.lock(); defer { ratchetLock.unlock() }
        return _previousRatchets.map { $0.privateKey }
    }

    /// Rotate the active ratchet. Generates a fresh X25519 keypair,
    /// stores the private locally, returns the 32-byte public bytes
    /// to embed in the next announce.
    @discardableResult
    public func rotateRatchet() -> Data {
        let prv = Curve25519.KeyAgreement.PrivateKey()
        ratchetLock.lock()
        rotateRatchetLocked(to: prv.rawRepresentation)
        ratchetLock.unlock()
        return prv.publicKey.rawRepresentation
    }

    /// Perform the rotation bookkeeping. Caller must hold `ratchetLock`.
    private func rotateRatchetLocked(to newPrivate: Data) {
        if let existing = _activeRatchetPrivateKey {
            _previousRatchets.insert(
                HistoricalRatchet(privateKey: existing, retiredAt: Date()),
                at: 0
            )
        }
        _activeRatchetPrivateKey = newPrivate
        _activeRatchetTime = Date()
        sweepExpiredRatchetsLocked()
    }

    /// Rotate only if `ratchetInterval` has elapsed since the last
    /// rotation. Mirrors `Destination.rotate_ratchets` in Python, which
    /// runs lazily on every announce. Returns the active public bytes
    /// (rotated or not), or nil if the ratchet was never initialized.
    @discardableResult
    public func rotateRatchetIfNeeded(now: Date = Date()) -> Data? {
        // Whole decision + rotation under one lock hold so the check and the
        // rotate can't interleave with another thread's rotation.
        let publicBytes: Data?
        ratchetLock.lock()
        if _activeRatchetPrivateKey == nil {
            publicBytes = nil
        } else if let last = _activeRatchetTime, now.timeIntervalSince(last) < ratchetInterval {
            publicBytes = activeRatchetPublicKeyLocked()
        } else {
            let prv = Curve25519.KeyAgreement.PrivateKey()
            rotateRatchetLocked(to: prv.rawRepresentation)
            publicBytes = prv.publicKey.rawRepresentation
        }
        ratchetLock.unlock()
        return publicBytes
    }

    /// Drop historical ratchets older than `ratchetExpiry`, then trim
    /// the remainder to `ratchetHistoryDepth`.
    public func sweepExpiredRatchets(now: Date = Date()) {
        ratchetLock.lock(); defer { ratchetLock.unlock() }
        sweepExpiredRatchetsLocked(now: now)
    }

    /// Sweep body. Caller must hold `ratchetLock`.
    private func sweepExpiredRatchetsLocked(now: Date = Date()) {
        _previousRatchets.removeAll {
            now.timeIntervalSince($0.retiredAt) > ratchetExpiry
        }
        if _previousRatchets.count > ratchetHistoryDepth {
            _previousRatchets.removeLast(_previousRatchets.count - ratchetHistoryDepth)
        }
    }

    /// Public bytes of the active ratchet, or nil if `rotateRatchet`
    /// has never been called.
    public var activeRatchetPublicKey: Data? {
        ratchetLock.lock(); defer { ratchetLock.unlock() }
        return activeRatchetPublicKeyLocked()
    }

    /// Compute the active ratchet public key. Caller must hold `ratchetLock`.
    private func activeRatchetPublicKeyLocked() -> Data? {
        guard let prvBytes = _activeRatchetPrivateKey,
              let prv = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: prvBytes)
        else { return nil }
        return prv.publicKey.rawRepresentation
    }

    /// Combined private-key pool used during decrypt: the active
    /// ratchet first (most likely match), then the history.
    public var ratchetPrivateKeyPool: [Data] {
        ratchetLock.lock(); defer { ratchetLock.unlock() }
        var pool: [Data] = []
        if let active = _activeRatchetPrivateKey { pool.append(active) }
        pool.append(contentsOf: _previousRatchets.map { $0.privateKey })
        return pool
    }

    public var hasPrivateKey: Bool { signingPrivateKey != nil && encryptionPrivateKey != nil }

    public var publicKeyBytes: Data {
        encryptionPublicKey.rawRepresentation + signingPublicKey.rawRepresentation
    }

    public var privateKeyBytes: Data? {
        guard let enc = encryptionPrivateKey, let sig = signingPrivateKey else { return nil }
        return enc.rawRepresentation + sig.rawRepresentation
    }

    public var hash: Data { Hashes.truncatedHash(publicKeyBytes) }
    public var hexHash: String { hash.map { String(format: "%02x", $0) }.joined() }

    /// Create a fresh identity with both key pairs randomly generated.
    public init() {
        let enc = Curve25519.KeyAgreement.PrivateKey()
        let sig = Curve25519.Signing.PrivateKey()
        self.encryptionPrivateKey = enc
        self.signingPrivateKey = sig
        self.encryptionPublicKey = enc.publicKey
        self.signingPublicKey = sig.publicKey
    }

    /// Reconstruct from the 64-byte concatenated private-key blob produced
    /// by `privateKeyBytes`.
    public init(privateKeyBytes: Data) throws {
        guard privateKeyBytes.count == Constants.keySize else {
            throw IdentityError.invalidKeyLength
        }
        let encRaw = privateKeyBytes.prefix(Constants.halfKeySize)
        let sigRaw = privateKeyBytes.suffix(Constants.halfKeySize)
        let enc = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: encRaw)
        let sig = try Curve25519.Signing.PrivateKey(rawRepresentation: sigRaw)
        self.encryptionPrivateKey = enc
        self.signingPrivateKey = sig
        self.encryptionPublicKey = enc.publicKey
        self.signingPublicKey = sig.publicKey
    }

    /// Reconstruct a public-only identity from the 64-byte public-key blob.
    public init(publicKeyBytes: Data) throws {
        guard publicKeyBytes.count == Constants.keySize else {
            throw IdentityError.invalidKeyLength
        }
        let encRaw = publicKeyBytes.prefix(Constants.halfKeySize)
        let sigRaw = publicKeyBytes.suffix(Constants.halfKeySize)
        self.encryptionPrivateKey = nil
        self.signingPrivateKey = nil
        self.encryptionPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: encRaw)
        self.signingPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: sigRaw)
    }

    // MARK: - Class-level constants (mirrors Python RNS.Identity class attributes)

    /// Elliptic curve used. Mirrors Python `Identity.CURVE = 'Curve25519'`.
    public static let curve: String = "Curve25519"

    /// Key size in bits (512). Mirrors Python `Identity.KEYSIZE = 256*2`.
    public static let keySize: Int = Constants.keySize * 8          // 512 bits
    /// X.25519 key size in bits (256). Mirrors Python `Identity.ECPUBSIZE//2 = 32*8`.
    public static let ecPubSize: Int = Constants.halfKeySize * 8    // 256 bits
    /// Signature length in bits (512). Mirrors Python `Identity.SIGLENGTH = KEYSIZE`.
    public static let sigLength: Int = Constants.signatureLength * 8 // 512 bits
    /// Ratchet key size in bits (256). Mirrors Python `Identity.RATCHETSIZE = 256`.
    public static let ratchetSize: Int = 256                         // bits (32 bytes)
    /// Full SHA-256 hash length in bits (256). Mirrors Python `Identity.HASHLENGTH = 256`.
    public static let hashLength: Int = 256                          // bits (32 bytes)
    /// Token overhead in bytes (48). Mirrors Python `Identity.TOKEN_OVERHEAD = Token.TOKEN_OVERHEAD`.
    public static let tokenOverhead: Int = Constants.tokenOverhead   // 48 bytes
    /// AES-128 block size in bytes (16). Mirrors Python `Identity.AES128_BLOCKSIZE = 16`.
    public static let aes128BlockSize: Int = Constants.aes128BlockSize  // 16 bytes
    /// HKDF derived key length in bytes (64). Mirrors Python `Identity.DERIVED_KEY_LENGTH = 512//8`.
    public static let derivedKeyLength: Int = Constants.derivedKeyLength  // 64 bytes
    /// Truncated hash length in bits (128). Mirrors Python `Identity.TRUNCATED_HASHLENGTH = 128`.
    public static let truncatedHashLength: Int = Constants.truncatedHashLengthBits  // 128 bits
    /// Name hash length in bits (80). Mirrors Python `Identity.NAME_HASH_LENGTH = 80`.
    public static let nameHashLength: Int = Constants.nameHashLengthBits            // 80 bits
    /// AES-256 block size in bytes (16). Mirrors Python `Identity.AES256_BLOCKSIZE = 16`.
    public static let aes256BlockSize: Int = 16
    /// Legacy HKDF derived key length in bytes (32, AES-128).
    /// Python: `Identity.DERIVED_KEY_LENGTH_LEGACY = 256//8`.
    public static let derivedKeyLengthLegacy: Int = 32
    /// Default ratchet expiry in seconds (30 days).
    /// Python: `Identity.RATCHET_EXPIRY = 60*60*24*30`.
    public static let defaultRatchetExpiry: TimeInterval = 60 * 60 * 24 * 30

    // MARK: - Static hash utilities (mirrors Python RNS.Identity class-level static methods)

    /// Compute the full SHA-256 hash of data.
    /// Mirrors Python's `RNS.Identity.full_hash(data)`.
    public static func fullHash(_ data: Data) -> Data { Hashes.fullHash(data) }

    /// Compute a truncated (128-bit) SHA-256 hash of data.
    /// Mirrors Python's `RNS.Identity.truncated_hash(data)`.
    public static func truncatedHash(_ data: Data) -> Data { Hashes.truncatedHash(data) }

    /// Generate a random truncated hash.
    /// Mirrors Python's `RNS.Identity.get_random_hash()`.
    public static func randomHash() -> Data { Hashes.randomHash() }

    // MARK: - Announce validation (mirrors Python Identity.validate_announce)

    /// Validate an announce packet.
    /// Returns true if the announce's signature is valid (and optionally the destination hash matches).
    /// Mirrors Python's `RNS.Identity.validate_announce(packet, only_validate_signature=False)`.
    public static func validateAnnounce(_ packet: Packet, onlyValidateSignature: Bool = false) -> Bool {
        do {
            if onlyValidateSignature {
                // Only check signature, skip destination hash verification
                let keysize = Constants.keySize
                let nameHashLen = Constants.nameHashLength
                let randLen = Constants.randomHashLength
                let sigLen = Constants.signatureLength
                let body = packet.data
                guard body.count >= keysize + nameHashLen + randLen + sigLen else { return false }
                let publicKey = body.prefix(keysize)
                let nameHash = body[keysize..<(keysize + nameHashLen)]
                let randomHash = body[(keysize + nameHashLen)..<(keysize + nameHashLen + randLen)]
                var cursor = keysize + nameHashLen + randLen
                var ratchet: Data? = nil
                if packet.contextFlag == .set && body.count >= cursor + Constants.ratchetSize + sigLen {
                    ratchet = Data(body[cursor..<(cursor + Constants.ratchetSize)])
                    cursor += Constants.ratchetSize
                }
                let signature = Data(body[cursor..<(cursor + sigLen)])
                let appData: Data? = cursor + sigLen < body.count ? Data(body[(cursor + sigLen)...]) : nil
                let identity = try Identity(publicKeyBytes: Data(publicKey))
                var signedData = Data(packet.destinationHash)
                signedData.append(publicKey)
                signedData.append(nameHash)
                signedData.append(randomHash)
                if let r = ratchet { signedData.append(r) }
                if let a = appData { signedData.append(a) }
                return identity.validate(signature: signature, for: signedData)
            } else {
                // Full validation (signature + destination hash)
                _ = try Announce.validate(packet)
                return true
            }
        } catch {
            return false
        }
    }

    // MARK: - Static ratchet ID utilities

    /// Get the 10-byte ID of the currently known ratchet key for a destination.
    /// Delegates to `Reticulum.shared?.transport.currentRatchetID(forDestination:)`.
    /// Mirrors Python's `RNS.Identity.current_ratchet_id(destination_hash)`.
    public static func currentRatchetID(for destinationHash: Data) -> Data? {
        Reticulum.shared?.transport.currentRatchetID(forDestination: destinationHash)
    }

    // MARK: - Static remember / recall (mirrors Python RNS.Identity class-level cache API)

    /// Store a remote identity in the shared transport's known-identities cache.
    ///
    /// Mirrors Python's `RNS.Identity.remember(packet_hash, destination_hash, public_key, app_data)`.
    /// The `packetHash` argument is accepted for API parity but is not stored (Swift's transport
    /// tracks known identities by destination hash only).
    ///
    /// - Returns: The newly created `Identity` on success, or `nil` if `publicKeyBytes` is invalid.
    @discardableResult
    public static func remember(
        packetHash: Data? = nil,
        destinationHash: Data,
        publicKeyBytes: Data,
        appData: Data? = nil
    ) -> Identity? {
        guard let identity = try? Identity(publicKeyBytes: publicKeyBytes) else { return nil }
        identity.appData = appData
        Reticulum.shared?.transport.restore(identity: identity, forDestination: destinationHash)
        return identity
    }

    // MARK: - Static recall (mirrors Python RNS.Identity.recall / recall_app_data)

    /// Recall the identity associated with a destination hash from the shared
    /// Reticulum instance. Delegates to `Reticulum.shared?.transport.recall(identity:)`.
    ///
    /// Mirrors Python's `RNS.Identity.recall(target_hash)`.
    public static func recall(destinationHash: Data) -> Identity? {
        Reticulum.shared?.transport.recall(identity: destinationHash)
    }

    /// Recall the last heard `appData` for a destination hash from the shared
    /// Reticulum instance.
    ///
    /// Mirrors Python's `RNS.Identity.recall_app_data(destination_hash)`.
    public static func recallAppData(forDestination destinationHash: Data) -> Data? {
        Reticulum.shared?.transport.recallAppData(forDestination: destinationHash)
    }

    public enum IdentityError: Error {
        case invalidKeyLength
        case missingPrivateKey
        case decryptionFailed
        case ciphertextTooShort
    }

    // MARK: - Sign / verify

    public func sign(_ message: Data) throws -> Data {
        guard let signingPrivateKey else { throw IdentityError.missingPrivateKey }
        return try signingPrivateKey.signature(for: message)
    }

    public func validate(signature: Data, for message: Data) -> Bool {
        signingPublicKey.isValidSignature(signature, for: message)
    }

    // MARK: - Encrypt / decrypt
    //
    // Reticulum encrypts to a single destination by:
    //   1. Generating a fresh ephemeral X25519 key pair.
    //   2. Performing ECDH against the recipient's static (or ratchet) X25519 key.
    //   3. Deriving a 64-byte AES-256 token key via HKDF with the recipient's
    //      identity hash as salt.
    //   4. Wrapping the plaintext in a Token (AES-256-CBC + HMAC-SHA256).
    //   5. Prepending the ephemeral public key to the token.
    //
    // The token therefore is: [32-byte ephemeral pub] [Token bytes]

    public func encrypt(_ plaintext: Data, ratchetPublicKey: Data? = nil) throws -> Data {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let targetPub: Curve25519.KeyAgreement.PublicKey
        if let ratchetPublicKey {
            targetPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ratchetPublicKey)
        } else {
            targetPub = encryptionPublicKey
        }
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: targetPub)
        let sharedData = shared.withUnsafeBytes { Data($0) }

        let derived = HKDF.derive(
            length: Constants.derivedKeyLength,
            derivedFrom: sharedData,
            salt: hash,
            context: nil
        )

        let token = try Token(key: derived)
        let ciphertext = try token.encrypt(plaintext)
        return ephemeral.publicKey.rawRepresentation + ciphertext
    }

    public func decrypt(_ token: Data, ratchetPrivateKeys: [Data] = []) throws -> Data {
        try decrypt(token, ratchetPrivateKeys: ratchetPrivateKeys, enforceRatchets: false).plaintext
    }

    /// Decrypt result. `ratchetID` is the 10-byte name-hash ID of the
    /// ratchet public key whose private successfully decrypted the
    /// token (mirrors Python's `latest_ratchet_id`). Nil if the
    /// destination's static identity key did the work.
    public struct DecryptResult: Equatable {
        public var plaintext: Data
        public var ratchetID: Data?
    }

    /// Full Python-parity decrypt:
    ///   * Tries each provided ratchet private in order.
    ///   * If `enforceRatchets` is set and no ratchet matched, fails
    ///     rather than falling back to the static identity key
    ///     (matches `Destination.enforce_ratchets`).
    ///   * On success via a ratchet, populates `ratchetID` with
    ///     `ratchetID(forPublicKey:)` of the matching ratchet's pub.
    public func decrypt(
        _ token: Data,
        ratchetPrivateKeys: [Data],
        enforceRatchets: Bool
    ) throws -> DecryptResult {
        guard let encryptionPrivateKey else { throw IdentityError.missingPrivateKey }
        guard token.count > Constants.halfKeySize else { throw IdentityError.ciphertextTooShort }

        let peerPubRaw = token.prefix(Constants.halfKeySize)
        let ciphertext = token.suffix(token.count - Constants.halfKeySize)
        let peerPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPubRaw)

        for ratchetRaw in ratchetPrivateKeys {
            guard let prv = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ratchetRaw)
            else { continue }
            if let plaintext = try? decryptWithKey(
                privateKey: prv, peerPub: peerPub, ciphertext: ciphertext
            ) {
                let pub = prv.publicKey.rawRepresentation
                return DecryptResult(plaintext: plaintext, ratchetID: Identity.ratchetID(forPublicKey: pub))
            }
        }

        if enforceRatchets {
            throw IdentityError.decryptionFailed
        }

        let plaintext = try decryptWithKey(
            privateKey: encryptionPrivateKey, peerPub: peerPub, ciphertext: ciphertext
        )
        return DecryptResult(plaintext: plaintext, ratchetID: nil)
    }

    /// Mirrors Python's `Identity._get_ratchet_id`: SHA256(pub)[:10].
    public static func ratchetID(forPublicKey pub: Data) -> Data {
        Hashes.fullHash(pub).prefix(Constants.nameHashLength)
    }

    private func decryptWithKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPub: Curve25519.KeyAgreement.PublicKey,
        ciphertext: Data
    ) throws -> Data {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peerPub)
        let sharedData = shared.withUnsafeBytes { Data($0) }
        let derived = HKDF.derive(
            length: Constants.derivedKeyLength,
            derivedFrom: sharedData,
            salt: hash,
            context: nil
        )
        let token = try Token(key: derived)
        return try token.decrypt(ciphertext)
    }

    // MARK: - Python-style key loading (mirrors Python Identity.load_private_key / load_public_key)
    // Note: Swift Identity is immutable; these methods return NEW Identity instances.

    /// Load a private key, returning a new Identity. Returns nil on failure.
    /// Mirrors Python's `Identity.load_private_key(prv_bytes)`.
    public func loadPrivateKey(_ bytes: Data) -> Identity? {
        try? Identity(privateKeyBytes: bytes)
    }

    /// Load a public key, returning a new public-only Identity. Returns nil on failure.
    /// Mirrors Python's `Identity.load_public_key(pub_bytes)`.
    public func loadPublicKey(_ bytes: Data) throws -> Identity? {
        try Identity(publicKeyBytes: bytes)
    }

    // MARK: - Python-style factory methods (mirrors Python Identity.from_bytes / from_file)

    /// Create an Identity from private key bytes.
    /// Returns nil if the bytes are invalid.
    /// Mirrors Python's `Identity.from_bytes(prv_bytes)`.
    public static func fromBytes(_ bytes: Data) -> Identity? {
        try? Identity(privateKeyBytes: bytes)
    }

    /// Load an Identity from a file.
    /// Returns nil if the file doesn't exist or is invalid.
    /// Mirrors Python's `Identity.from_file(path)`.
    public static func fromFile(_ url: URL) -> Identity? {
        try? read(fromFile: url)
    }

    /// Save this Identity's private key to a file.
    /// Returns true on success. Mirrors Python's `Identity.to_file(path)`.
    @discardableResult
    public func toFile(_ url: URL) throws -> Bool {
        guard let bytes = privateKeyBytes else { return false }
        try bytes.write(to: url, options: .atomic)
        return true
    }

    /// Save this Identity's public key to a file.
    /// Returns true on success. Mirrors Python's `Identity.pub_to_file(path)`.
    @discardableResult
    public func pubToFile(_ url: URL) -> Bool {
        guard (try? publicKeyBytes.write(to: url, options: .atomic)) != nil else { return false }
        return true
    }

    // MARK: - Python-style key accessors (mirrors Python Identity.get_private_key / get_public_key)

    /// Returns the private key bytes, or nil if this is a public-only identity.
    /// Mirrors Python's `Identity.get_private_key()`.
    public func getPrivateKey() -> Data? { privateKeyBytes }

    /// Returns the public key bytes (64 bytes: X25519 + Ed25519).
    /// Mirrors Python's `Identity.get_public_key()`.
    public func getPublicKey() -> Data { publicKeyBytes }

    /// Returns the identity hash (truncated 16-byte SHA-256 of public key).
    /// Mirrors Python's `Identity.get_salt()`.
    public func getSalt() -> Data { hash }

    /// Returns nil (no context defined for Identity). Mirrors Python's `Identity.get_context()`.
    public func getContext() -> Data? { nil }

    // MARK: - Persistence

    public func write(toFile url: URL) throws {
        guard let bytes = privateKeyBytes else { throw IdentityError.missingPrivateKey }
        try bytes.write(to: url, options: .atomic)
    }

    public static func read(fromFile url: URL) throws -> Identity {
        try Identity(privateKeyBytes: try Data(contentsOf: url))
    }

    // MARK: - Ratchet persistence
    //
    // Ratchet privates live in a sidecar file alongside the static
    // identity blob, so the on-disk identity wire format stays a flat
    // 64-byte blob (matching Python). The sidecar is JSON of:
    //   { "active": "<hex>", "history": ["<hex>", ...] }
    // Either field may be absent.

    private struct RatchetSidecar: Codable {
        struct HistoryEntry: Codable {
            var key: String
            var retiredAt: Date
        }
        var active: String?
        var activeAt: Date?
        var history: [HistoryEntry]
        // Older snapshots wrote `history: [String]`; tolerate that on read.
        var legacyHistory: [String]?

        enum CodingKeys: String, CodingKey { case active, activeAt, history }

        init(active: String?, activeAt: Date?, history: [HistoryEntry]) {
            self.active = active; self.activeAt = activeAt; self.history = history
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.active = try c.decodeIfPresent(String.self, forKey: .active)
            self.activeAt = try c.decodeIfPresent(Date.self, forKey: .activeAt)
            if let entries = try? c.decode([HistoryEntry].self, forKey: .history) {
                self.history = entries
                self.legacyHistory = nil
            } else {
                self.history = []
                self.legacyHistory = (try? c.decode([String].self, forKey: .history)) ?? []
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(active, forKey: .active)
            try c.encodeIfPresent(activeAt, forKey: .activeAt)
            try c.encode(history, forKey: .history)
        }
    }

    public func writeRatchets(toFile url: URL) throws {
        let entries = previousRatchets.map {
            RatchetSidecar.HistoryEntry(
                key: $0.privateKey.hexString,
                retiredAt: $0.retiredAt
            )
        }
        let sidecar = RatchetSidecar(
            active: activeRatchetPrivateKey?.hexString,
            activeAt: activeRatchetTime,
            history: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sidecar).write(to: url, options: .atomic)
    }

    public func loadRatchets(fromFile url: URL) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(RatchetSidecar.self, from: try Data(contentsOf: url))
        if let activeHex = sidecar.active, let active = Data(hex: activeHex) {
            activeRatchetPrivateKey = active
        }
        activeRatchetTime = sidecar.activeAt
        if let legacy = sidecar.legacyHistory, !legacy.isEmpty {
            let now = Date()
            previousRatchets = legacy.compactMap(Data.init(hex:)).map {
                HistoricalRatchet(privateKey: $0, retiredAt: now)
            }
        } else {
            previousRatchets = sidecar.history.compactMap { entry in
                Data(hex: entry.key).map {
                    HistoricalRatchet(privateKey: $0, retiredAt: entry.retiredAt)
                }
            }
        }
        sweepExpiredRatchets()
    }

    // MARK: - Equatable / Hashable

    public static func == (lhs: Identity, rhs: Identity) -> Bool {
        lhs.publicKeyBytes == rhs.publicKeyBytes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(publicKeyBytes)
    }
}
