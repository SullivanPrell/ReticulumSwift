import Foundation

/// A Reticulum Destination.
///
/// Naming convention (matches Python):
///   * Full name string is `app_name(.aspect)*(.identity_hex_hash)?`
///   * Name hash:        `SHA256(name_without_identity)[:10]` (80 bits)
///   * Destination hash: `SHA256(name_hash || identity_hash)[:16]` (128 bits)
///     For PLAIN destinations, only the name hash is used.
public final class Destination {
    public enum Kind: UInt8, Sendable { case single = 0x00, group = 0x01, plain = 0x02, link = 0x03 }
    public enum Direction: UInt8, Sendable { case `in` = 0x11, out = 0x12 }

    // MARK: - Class-level constants (mirrors Python Destination class attributes)

    /// Time window in seconds for path-request tag deduplication.
    /// Python: `Destination.PR_TAG_WINDOW = 30`.
    public static let prTagWindow: TimeInterval = 30

    /// Default number of ratchet keys a destination retains.
    /// Mirrors Python `Destination.RATCHET_COUNT = 512`.
    public static let ratchetCount: Int = 512

    /// Minimum interval between ratchet key rotations in seconds.
    /// Mirrors Python `Destination.RATCHET_INTERVAL = 30*60 = 1800`.
    public static let ratchetInterval: TimeInterval = 1800

    /// Proof strategy constants (mirrors Python's PROVE_NONE/PROVE_ALL/PROVE_APP).
    public static let proveNone: ProofStrategy = .proveNone
    public static let proveAll: ProofStrategy = .proveAll
    public static let proveApp: ProofStrategy = .proveApp

    /// Allow policy constants (mirrors Python's ALLOW_NONE/ALLOW_ALL/ALLOW_LIST).
    public static let allowNone: AllowPolicy = .none
    public static let allowAll: AllowPolicy = .all
    public static let allowList: AllowPolicy = .list

    public let identity: Identity?
    public let direction: Direction
    public let kind: Kind
    public let appName: String
    public let aspects: [String]

    public let nameHash: Data        // 10 bytes
    public let hash: Data            // 16 bytes
    public let fullName: String

    /// Optional default app data attached to outgoing announces.
    /// When set, overrides any `appData` passed to `Transport.announce`.
    public var defaultAppData: Data?

    /// Callable that produces app data for each announce (mirrors Python's
    /// `Destination.set_default_app_data` with a callable argument).
    public var defaultAppDataProvider: (() -> Data?)?

    /// Returns the effective app data for an outgoing announce:
    /// `defaultAppDataProvider()` if set, otherwise `defaultAppData`.
    public var effectiveAppData: Data? {
        defaultAppDataProvider?() ?? defaultAppData
    }

    /// Whether this destination accepts incoming link requests.
    /// Mirrors Python's `Destination.accepts_links()`.
    public var acceptsLinks: Bool = true

    /// Getter/setter for `acceptsLinks`. Mirrors Python's `Destination.accepts_links(accepts)`.
    public func getAcceptsLinks() -> Bool { acceptsLinks }
    public func setAcceptsLinks(_ accepts: Bool) { acceptsLinks = accepts }

    // MARK: - Ratchets (Python-parity API)
    //
    // Ratchet privates live on the underlying Identity (one identity
    // can back several Destinations). Destination is the Python-style
    // entry point: `enableRatchets(path:)`, `enforceRatchets()`,
    // `setRatchetInterval`, `setRetainedRatchets`, `latestRatchetID`.

    /// True after `enableRatchets(path:)`. While set, `Announce.make`
    /// will lazily call `identity.rotateRatchetIfNeeded()` and embed
    /// the active ratchet pub in outgoing announces.
    public private(set) var ratchetsEnabled: Bool = false

    /// Path to the destination-scoped ratchet sidecar file. The actual
    /// file (`Identity` ratchet privates) is written by Identity; this
    /// is just where it lives for *this* destination.
    public private(set) var ratchetsPath: URL?

    /// When true, `decrypt(_:)` refuses to fall back to the static
    /// identity key, matching `Destination.enforce_ratchets()` in
    /// Python.
    public private(set) var ratchetsEnforced: Bool = false

    /// 10-byte ID (`SHA256(ratchet_pub)[:10]`) of the most recent
    /// ratchet that successfully decrypted an inbound packet on this
    /// destination — or nil if the static identity key did. Mirrors
    /// Python's `Destination.latest_ratchet_id`.
    public private(set) var latestRatchetID: Data?

    /// Mirrors Python's `Destination.set_ratchet_interval`. Forwarded
    /// to the underlying Identity.
    public func setRatchetInterval(_ interval: TimeInterval) {
        identity?.ratchetInterval = interval
    }

    /// Mirrors Python's `Destination.set_retained_ratchets`. Forwarded
    /// to the underlying Identity's history depth.
    public func setRetainedRatchets(_ count: Int) {
        guard count > 0 else { return }
        identity?.ratchetHistoryDepth = count
        identity?.sweepExpiredRatchets()
    }

    /// Enable ratchets on this destination, persisting their privates
    /// to `path`. If the file exists, ratchet privates are loaded;
    /// otherwise the file is written when ratchets rotate. Mirrors
    /// `Destination.enable_ratchets(ratchets_path)`.
    @discardableResult
    public func enableRatchets(path: URL) throws -> Bool {
        guard let identity else { return false }
        ratchetsPath = path
        if FileManager.default.fileExists(atPath: path.path) {
            try? identity.loadRatchets(fromFile: path)
        }
        ratchetsEnabled = true
        return true
    }

    /// Mirrors `Destination.enforce_ratchets()`. Returns true if
    /// ratchets are enabled and enforcement was applied.
    @discardableResult
    public func enforceRatchets() -> Bool {
        guard ratchetsEnabled else { return false }
        ratchetsEnforced = true
        return true
    }

    /// Persist the underlying identity's ratchet privates to the
    /// destination's configured path, if any. Called automatically
    /// after rotation in `Announce.make`.
    public func persistRatchets() {
        guard let identity, let url = ratchetsPath else { return }
        try? identity.writeRatchets(toFile: url)
    }

    /// Force a ratchet rotation for this destination if the ratchet interval has elapsed.
    /// Mirrors Python's `Destination.rotate_ratchets()`.
    /// Returns `true` whether or not a rotation was needed (ratchets are healthy).
    /// Throws `DestinationError.ratchetsNotEnabled` if ratchets have not been enabled.
    @discardableResult
    public func rotateRatchets() throws -> Bool {
        guard ratchetsEnabled, let identity else {
            throw DestinationError.ratchetsNotEnabled
        }
        // If no ratchet exists yet, seed the first one unconditionally
        // (mirrors Python where latest_ratchet_time starts at 0, so the
        // very first call always generates a ratchet).
        if identity.activeRatchetPrivateKey == nil {
            identity.rotateRatchet()
        } else {
            identity.rotateRatchetIfNeeded()
        }
        persistRatchets()
        return true
    }

    // MARK: - Application callbacks

    /// Called when a Link is established to this destination.
    /// Mirrors Python's `Destination.set_link_established_callback`.
    public var onLinkEstablished: ((Link) -> Void)?

    /// Called when a DATA packet is delivered to this destination (no link).
    /// Mirrors Python's `Destination.set_packet_callback`.
    public var onPacketReceived: ((Data, Packet) -> Void)?

    /// Called when this destination is asked to generate a proof.
    /// Return `true` to allow the proof, `false` to refuse.
    /// Mirrors Python's `set_proof_strategy` / `PROVE_APP`.
    public var onProofRequested: ((Packet) -> Bool)?

    // MARK: - Proof strategy

    public enum ProofStrategy { case proveNone, proveAll, proveApp }

    /// Proof strategy for inbound DATA packets.
    /// Default is `.proveNone`, matching Python's `PROVE_NONE` default.
    public var proofStrategy: ProofStrategy = .proveNone

    // MARK: - Request handlers

    /// Controls which remote peers are allowed to invoke a request handler.
    /// Mirrors Python's `Destination.ALLOW_NONE / ALLOW_ALL / ALLOW_LIST`.
    public enum AllowPolicy {
        case none   // never answer (default — must opt in explicitly)
        case all    // answer requests from any peer
        case list   // answer only from identities in allowedList
    }

    /// Synchronous request handler. Returns the response bytes, or nil
    /// to send no response. `requestData` may be nil if the request
    /// carried no payload.
    public typealias RequestHandler = (
        _ pathHash: Data,
        _ requestData: Data?,
        _ requestID: Data,
        _ link: Link,
        _ requestedAt: Double
    ) -> Data?

    /// Native-value request handler. Returns a MsgPack value embedded directly
    /// in the response array (Python-wire-compatible). Use for handlers that serve
    /// Python clients (e.g., LXMF propagation node). `requestData` is the raw
    /// MsgPack.Value from the incoming request — no double-encoding round-trip.
    public typealias NativeRequestHandler = (
        _ pathHash: Data,
        _ requestData: MsgPack.Value,
        _ requestID: Data,
        _ link: Link,
        _ requestedAt: Double
    ) -> MsgPack.Value?

    /// A registered request handler together with its allow policy.
    public struct RequestHandlerEntry {
        public let path: String
        let handler: RequestHandler
        /// Non-nil for Python-compatible native-value handlers registered via
        /// `registerNativeRequestHandler`. When set, `handler` is a no-op stub.
        let nativeHandler: NativeRequestHandler?
        public let allow: AllowPolicy
        /// Identity hashes (16 bytes each) that are explicitly allowed when
        /// `allow == .list`.
        let allowedHashes: Set<Data>
        /// Whether Resource responses should be auto-compressed.
        /// Mirrors Python's `auto_compress` parameter (default `True`).
        public let autoCompress: Bool
    }

    /// Path-hash → handler entry. Path hash is `truncatedHash(path.utf8)`.
    public var requestHandlers: [Data: RequestHandlerEntry] = [:]

    /// Register a handler keyed by `path` (UTF-8 hashed to 16 bytes).
    ///
    /// - Parameters:
    ///   - allow: Access policy. Defaults to `.none` (matches Python's
    ///     `ALLOW_NONE` default — you must opt in to serving requests).
    ///   - allowedList: Identities permitted when `allow == .list`.
    ///   - autoCompress: Whether Resource responses should be auto-compressed (default `true`).
    public func registerRequestHandler(
        path: String,
        allow: AllowPolicy = .none,
        allowedList: [Identity] = [],
        autoCompress: Bool = true,
        handler: @escaping RequestHandler
    ) {
        let key = Hashes.truncatedHash(Data(path.utf8))
        let hashes = Set(allowedList.map { $0.hash })
        requestHandlers[key] = RequestHandlerEntry(
            path: path, handler: handler, nativeHandler: nil,
            allow: allow, allowedHashes: hashes,
            autoCompress: autoCompress
        )
    }

    /// Register a Python-compatible native-value handler keyed by `path`.
    ///
    /// The handler receives the raw `MsgPack.Value` from the incoming request
    /// (not re-encoded bytes) and returns a `MsgPack.Value` embedded directly in
    /// the response envelope — matching Python's `packb([request_id, response])`.
    ///
    /// Use this for handlers that must interoperate with Python RNS clients
    /// (e.g., LXMF propagation node `message_get_request`).
    public func registerNativeRequestHandler(
        path: String,
        allow: AllowPolicy = .none,
        allowedList: [Identity] = [],
        autoCompress: Bool = true,
        handler: @escaping NativeRequestHandler
    ) {
        let key = Hashes.truncatedHash(Data(path.utf8))
        let hashes = Set(allowedList.map { $0.hash })
        requestHandlers[key] = RequestHandlerEntry(
            path: path, handler: { _, _, _, _, _ in nil }, nativeHandler: handler,
            allow: allow, allowedHashes: hashes,
            autoCompress: autoCompress
        )
    }

    /// Remove the request handler registered for `path`, if any.
    /// Mirrors Python's `Destination.deregister_request_handler`.
    public func deregisterRequestHandler(path: String) {
        let key = Hashes.truncatedHash(Data(path.utf8))
        requestHandlers.removeValue(forKey: key)
    }

    public init(
        identity: Identity?,
        direction: Direction,
        kind: Kind,
        appName: String,
        aspects: [String] = []
    ) throws {
        if appName.contains(".") { throw DestinationError.dotsForbidden }
        for aspect in aspects where aspect.contains(".") {
            throw DestinationError.dotsForbidden
        }
        // GROUP destinations don't need an identity (they use symmetric keys).
        // SINGLE destinations require an identity for outbound (to encrypt to).
        if identity == nil && direction == .out && kind == .single {
            throw DestinationError.outboundRequiresIdentity
        }
        if identity != nil && kind == .plain {
            throw DestinationError.plainCannotHoldIdentity
        }
        if identity != nil && kind == .group {
            // GROUP destinations use symmetric keys, not asymmetric identity keys.
            // Passing an identity alongside a group destination is unusual; ignore it.
        }

        self.identity = identity
        self.direction = direction
        self.kind = kind
        self.appName = appName
        self.aspects = aspects

        self.fullName = Destination.expandName(identity: identity, appName: appName, aspects: aspects)
        self.nameHash = Destination.computeNameHash(appName: appName, aspects: aspects)
        self.hash = Destination.computeHash(identity: identity, nameHash: self.nameHash, kind: kind)
    }

    public enum DestinationError: Error {
        case dotsForbidden
        case outboundRequiresIdentity
        case plainCannotHoldIdentity
        case missingIdentity
        case ratchetsNotEnabled
    }

    // MARK: - Static helpers

    public static func expandName(identity: Identity?, appName: String, aspects: [String]) -> String {
        var name = appName
        for aspect in aspects { name += "." + aspect }
        if let identity { name += "." + identity.hexHash }
        return name
    }

    public static func computeNameHash(appName: String, aspects: [String]) -> Data {
        var name = appName
        for aspect in aspects { name += "." + aspect }
        let bytes = Data(name.utf8)
        return Hashes.fullHash(bytes).prefix(Constants.nameHashLength)
    }

    public static func computeHash(identity: Identity?, nameHash: Data, kind: Kind) -> Data {
        var material = Data()
        material.append(nameHash)
        if let identity, kind != .plain {
            material.append(identity.hash)
        }
        return Hashes.truncatedHash(material)
    }

    public var hexHash: String { hash.map { String(format: "%02x", $0) }.joined() }

    /// Compute destination hash for an identity, app name, and aspects.
    /// Mirrors Python's `Destination.hash(identity, app_name, *aspects)`.
    public static func hash(identity: Identity?, appName: String, aspects: [String] = []) -> Data {
        let nameHash = computeNameHash(appName: appName, aspects: aspects)
        return computeHash(identity: identity, nameHash: nameHash, kind: identity == nil ? .plain : .single)
    }

    /// Compute destination hash from a full dotted name string and identity.
    /// Mirrors Python's `Destination.hash_from_name_and_identity(full_name, identity)`.
    public static func hash(fromFullName fullName: String, identity: Identity?) -> Data {
        let (appName, aspects) = appAndAspects(fromFullName: fullName)
        return hash(identity: identity, appName: appName, aspects: aspects)
    }

    /// Split a full dotted destination name into app name and aspects.
    /// Mirrors Python's `Destination.app_and_aspects_from_name(full_name)`.
    public static func appAndAspects(fromFullName fullName: String) -> (appName: String, aspects: [String]) {
        let components = fullName.split(separator: ".").map(String.init)
        guard !components.isEmpty else { return ("", []) }
        return (components[0], Array(components.dropFirst()))
    }

    // MARK: - App data management (mirrors Python Destination.set_default_app_data / clear_default_app_data)

    /// Set default app data as bytes or clear it.
    /// Mirrors Python's `Destination.set_default_app_data(app_data)` when passed bytes.
    public func setDefaultAppData(_ data: Data?) {
        defaultAppData = data
        defaultAppDataProvider = nil
    }

    /// Set a callable that produces app data for each announce.
    /// Mirrors Python's `Destination.set_default_app_data(app_data)` when passed a callable.
    public func setDefaultAppData(provider: @escaping () -> Data?) {
        defaultAppData = nil
        defaultAppDataProvider = provider
    }

    /// Clear the default app data and any callable provider.
    /// Mirrors Python's `Destination.clear_default_app_data()`.
    public func clearDefaultAppData() {
        defaultAppData = nil
        defaultAppDataProvider = nil
    }

    // MARK: - Proof strategy setter (mirrors Python Destination.set_proof_strategy)

    /// Set the proof strategy.
    /// Mirrors Python's `Destination.set_proof_strategy(proof_strategy)`.
    public func setProofStrategy(_ strategy: ProofStrategy) {
        proofStrategy = strategy
    }

    // MARK: - Manual proof (mirrors Python Destination.prove_for_packet)

    /// Generate and send a delivery proof for a received packet.
    ///
    /// Intended for use in conjunction with the `.proveApp` proof strategy,
    /// where the application decides on a per-packet basis whether to prove.
    /// Call this from the packet callback (or later, as long as
    /// `packet.receivingInterface` is still set).
    ///
    /// Mirrors Python's `Destination.prove_for_packet(packet)`.
    public func proveForPacket(_ packet: Packet) {
        packet.prove(destination: self)
    }

    // MARK: - Callback setters (mirrors Python Destination.set_*_callback)

    /// Mirrors Python's `Destination.set_link_established_callback(callback)`.
    public func setLinkEstablishedCallback(_ callback: @escaping (Link) -> Void) {
        onLinkEstablished = callback
    }

    /// Mirrors Python's `Destination.set_packet_callback(callback)`.
    public func setPacketCallback(_ callback: @escaping (Data, Packet) -> Void) {
        onPacketReceived = callback
    }

    /// Mirrors Python's `Destination.set_proof_requested_callback(callback)`.
    public func setProofRequestedCallback(_ callback: @escaping (Packet) -> Bool) {
        onProofRequested = callback
    }

    // MARK: - Announce convenience (mirrors Python Destination.announce)

    /// Broadcast an announce for this destination using the shared Reticulum transport.
    ///
    /// This is a convenience wrapper around `transport.announce(destination:appData:ratchet:)`.
    /// It requires `Reticulum.shared` to be set (i.e., `Reticulum.start()` must have been called).
    ///
    /// For more control (e.g., specifying a specific transport), use `Transport.announce(destination:appData:)` directly.
    ///
    /// Mirrors Python's `Destination.announce(app_data=None)`.
    @discardableResult
    /// Block until a path to this destination is known or `timeout` elapses.
    /// Mirrors Python's `Transport.await_path(destination_hash, timeout)`.
    ///
    /// - Returns: `true` if a path is available, `false` if timeout elapsed first.
    public func awaitPath(using transport: Transport,
                          timeout: TimeInterval = Transport.pathRequestTimeout) -> Bool {
        transport.awaitPath(to: hash, timeout: timeout)
    }

    /// Announce this destination on the shared Reticulum transport.
    ///
    /// - Parameters:
    ///   - appData: Optional app data to attach to the announce.
    ///   - attachedInterface: If specified, the announce is sent only on this
    ///     interface. Mirrors Python's `Destination.announce(attached_interface=...)`.
    ///   - isPathResponse: If `true`, the announce is tagged as a path response
    ///     and will not be re-forwarded by other transport nodes.
    ///     Mirrors Python's `Destination.announce(path_response=True)`.
    /// - Returns: A `PacketReceipt` if the announce was sent via the full
    ///   transport broadcast, or `nil` when sent on a specific interface.
    @discardableResult
    public func announce(
        appData: Data? = nil,
        attachedInterface: (any Interface)? = nil,
        isPathResponse: Bool = false
    ) throws -> PacketReceipt? {
        guard let transport = Reticulum.shared?.transport else { return nil }
        return try transport.announce(
            destination: self,
            appData: appData,
            isPathResponse: isPathResponse,
            onInterface: attachedInterface
        )
    }

    // MARK: - GROUP symmetric key management

    /// Symmetric key bytes for GROUP destinations. Nil until `createKeys()` or
    /// `loadGroupKey(_:)` is called.
    public private(set) var groupKeyBytes: Data?

    // MARK: - Python-compatible attribute getters

    /// Returns the 16-byte destination hash.
    /// Mirrors Python's `Destination.hash` (direct attribute access via `get_hash()`).
    public func getHash() -> Data { hash }

    /// Returns the full expanded destination name (e.g. `"appName.aspect.identity_hexhash"`).
    /// Mirrors Python's `Destination.name` direct attribute.
    public func getName() -> String { fullName }

    /// Returns the destination type (`.single`, `.group`, `.plain`, `.link`).
    /// Mirrors Python's `Destination.type` direct attribute.
    public func getType() -> Kind { kind }

    /// Returns the destination direction (`.in` or `.out`).
    /// Mirrors Python's `Destination.direction` direct attribute.
    public func getDirection() -> Direction { direction }

    /// Returns the destination's identity, or nil for PLAIN/GROUP destinations without one.
    /// Mirrors Python's `Destination.identity` direct attribute.
    public func getIdentity() -> Identity? { identity }

    /// Returns the current symmetric key for GROUP destinations, or nil.
    /// Mirrors Python's `Destination.get_private_key()` for GROUP type.
    public func getGroupKey() -> Data? {
        guard kind == .group else { return nil }
        return groupKeyBytes
    }

    /// Returns the private key material for this destination.
    ///
    /// For GROUP destinations: the symmetric 32-byte AES key (same as `getGroupKey()`).
    /// For SINGLE destinations: the 64-byte Ed25519+X25519 private key bytes,
    ///   or nil if the identity does not have a private key (outbound-only).
    /// For PLAIN/LINK: nil.
    ///
    /// Mirrors Python's `Destination.get_private_key()`.
    public func getPrivateKey() -> Data? {
        switch kind {
        case .group:
            return groupKeyBytes
        case .single:
            return identity?.privateKeyBytes
        default:
            return nil
        }
    }

    /// Load private key material into this destination.
    ///
    /// For GROUP destinations, loads a 32-byte symmetric key (same as `loadGroupKey(_:)`).
    /// For SINGLE destinations, loads Ed25519+X25519 private key bytes into the identity.
    ///
    /// Mirrors Python's `Destination.load_private_key(key)`.
    @discardableResult
    public func loadPrivateKey(_ key: Data) -> Bool {
        switch kind {
        case .group:
            groupKeyBytes = key
            return true
        case .single:
            guard let id = identity else { return false }
            return id.loadPrivateKey(key) != nil
        default:
            return false
        }
    }

    /// Load a public key into this destination.
    ///
    /// In Python, `Destination.load_public_key(key)` always raises `TypeError`:
    /// SINGLE destinations hold keys through an `Identity` instance, and PLAIN
    /// destinations hold no keys at all. For GROUP destinations it behaves the same
    /// as `loadGroupKey(_:)` (the symmetric key is the "public" key for Token).
    ///
    /// Swift mapping:
    ///   - `.single` / `.plain` / `.link` → returns `false` (no-op)
    ///   - `.group`                        → loads key bytes and returns `true`
    ///
    /// Mirrors Python's `Destination.load_public_key(key)`.
    @discardableResult
    public func loadPublicKey(_ key: Data) -> Bool {
        guard kind == .group else { return false }
        groupKeyBytes = key
        return true
    }

    /// Generate a new random symmetric key for this GROUP destination.
    /// Mirrors Python's `Destination.create_keys()`.
    /// Returns true on success, false if called on a non-GROUP destination.
    @discardableResult
    public func createKeys() -> Bool {
        guard kind == .group else { return false }
        groupKeyBytes = Token.generateKey()
        return true
    }

    /// Load a symmetric key into this GROUP destination.
    /// Mirrors Python's `Destination.load_private_key(key)` for GROUP type.
    public func loadGroupKey(_ key: Data) {
        guard kind == .group else { return }
        groupKeyBytes = key
    }

    // MARK: - Sign

    /// Sign a message using this destination's identity.
    /// Only works for `.single` destinations with a private key.
    /// Returns nil if the destination cannot sign.
    /// Mirrors Python's `Destination.sign(message)`.
    public func sign(_ message: Data) -> Data? {
        guard kind == .single, let identity, identity.hasPrivateKey else { return nil }
        return try? identity.sign(message)
    }

    // MARK: - Encryption

    public enum EncryptionError: Error { case missingGroupKey }

    public func encrypt(_ plaintext: Data) throws -> Data {
        switch kind {
        case .plain:
            return plaintext
        case .group:
            // GROUP uses symmetric AES key
            guard let key = groupKeyBytes else { throw EncryptionError.missingGroupKey }
            let token = try Token(key: key)
            return try token.encrypt(plaintext)
        case .single, .link:
            guard let identity else { throw DestinationError.missingIdentity }
            return try identity.encrypt(plaintext)
        }
    }

    public func decrypt(_ ciphertext: Data) throws -> Data {
        switch kind {
        case .plain:
            return ciphertext
        case .group:
            guard let key = groupKeyBytes else { throw EncryptionError.missingGroupKey }
            let token = try Token(key: key)
            return try token.decrypt(ciphertext)
        case .single, .link:
            guard let identity else { throw DestinationError.missingIdentity }
            let pool = ratchetsEnabled ? identity.ratchetPrivateKeyPool : []
            let result = try identity.decrypt(
                ciphertext,
                ratchetPrivateKeys: pool,
                enforceRatchets: ratchetsEnforced
            )
            latestRatchetID = result.ratchetID
            return result.plaintext
        }
    }
}
