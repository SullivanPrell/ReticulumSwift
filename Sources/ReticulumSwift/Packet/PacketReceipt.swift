import Foundation

/// Tracks delivery of a sent DATA packet and optionally validates an
/// explicit proof from the recipient.
///
/// Created automatically by `Transport.send(_:generateReceipt:)` for
/// DATA packets addressed to SINGLE destinations. Matches Python's
/// `RNS.PacketReceipt`.
public final class PacketReceipt {

    public enum Status: Sendable { case sent, delivered, failed, culled }

    // MARK: - Wire sizes

    /// Implicit proof: Ed25519 signature only (64 bytes). Python default.
    /// Mirrors Python `PacketReceipt.IMPL_LENGTH`.
    public static let implicitProofLength = Constants.signatureLength

    /// Explicit proof: full hash (32 bytes) + Ed25519 signature (64 bytes).
    /// Mirrors Python `PacketReceipt.EXPL_LENGTH`.
    public static let explicitProofLength = Constants.fullHashLength + Constants.signatureLength

    // MARK: - Properties

    /// Full 32-byte SHA-256 of the hashable packet bytes.
    public let packetHash: Data
    /// Truncated 16-byte hash used as the packet's identity on wire.
    public let truncatedHash: Data

    public let sentAt: Date
    public private(set) var concludedAt: Date?
    public private(set) var status: Status = .sent
    public private(set) var proved: Bool = false

    /// Timeout interval in seconds. When `sentAt + timeout < now` the
    /// receipt transitions to `.failed` (or `.culled` when `timeout == -1`).
    public var timeout: TimeInterval

    /// The identity whose public key validates the proof signature.
    /// For outbound packets this is the remote destination's identity
    /// (public key only), looked up from `Transport.knownIdentities`.
    public var peerIdentity: Identity?

    /// Guards `status`, `proved`, `concludedAt`, and the two callbacks so that
    /// the terminal-state transition is check-and-set atomic. Without this,
    /// `checkTimeout()` (jobs thread, under Transport.receiptsLock) races
    /// `validateExplicit/ImplicitProof` (receive thread) over `status`, allowing
    /// both a delivery and a timeout callback to fire. Self-contained: callbacks
    /// are always invoked OUTSIDE this lock, so it never nests with any other.
    private let stateLock = NSLock()

    /// Fires when the receipt is proved/delivered. If the proof already
    /// arrived before this callback was set (synchronous loopback), it
    /// is replayed immediately on assignment.
    private var _onDelivery: ((PacketReceipt) -> Void)?
    public var onDelivery: ((PacketReceipt) -> Void)? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _onDelivery }
        set {
            // Set the callback and decide whether to replay atomically, then
            // fire outside the lock. This closes the window where a concurrent
            // markDelivered() and this assignment could each miss the other and
            // drop the callback entirely.
            stateLock.lock()
            _onDelivery = newValue
            let replay = (status == .delivered)
            stateLock.unlock()
            if replay { newValue?(self) }
        }
    }
    private var _onTimeout: ((PacketReceipt) -> Void)?
    public var onTimeout: ((PacketReceipt) -> Void)? {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _onTimeout }
        set { stateLock.lock(); _onTimeout = newValue; stateLock.unlock() }
    }

    // MARK: - Init

    /// Test-only convenience init for injecting a receipt without a full packet.
    init(testHash: Data) {
        self.packetHash = testHash
        self.truncatedHash = testHash.prefix(Constants.truncatedHashLength)
        self.sentAt = Date()
        self.peerIdentity = nil
        self.timeout = 60
    }

    init(packetHash: Data, peerIdentity: Identity?, timeout: TimeInterval) {
        self.packetHash = packetHash
        self.truncatedHash = packetHash.prefix(Constants.truncatedHashLength)
        self.sentAt = Date()
        self.peerIdentity = peerIdentity
        self.timeout = timeout
    }

    // MARK: - Timeout

    public var isTimedOut: Bool { sentAt.addingTimeInterval(timeout) < Date() }

    /// Check whether the receipt has timed out. Called periodically by
    /// the Transport jobs loop. Matches Python's `PacketReceipt.check_timeout`.
    func checkTimeout() {
        stateLock.lock()
        guard status == .sent, isTimedOut else { stateLock.unlock(); return }
        concludedAt = Date()
        status = timeout < 0 ? .culled : .failed
        let cb = _onTimeout
        _onTimeout = nil
        stateLock.unlock()
        DispatchQueue.global(qos: .utility).async { cb?(self) }
    }

    func cull() {
        stateLock.lock(); defer { stateLock.unlock() }
        guard status == .sent else { return }
        concludedAt = Date()
        status = .culled
    }

    // MARK: - Proof validation

    /// Validate an explicit proof: `[32-byte packet hash][64-byte sig]`.
    /// If the signature over the packet hash verifies against the
    /// destination's identity, marks the receipt delivered.
    /// Mirrors Python's `PacketReceipt.validate_proof` (EXPL_LENGTH branch).
    @discardableResult
    func validateExplicitProof(_ proof: Data) -> Bool {
        guard status == .sent else { return false }
        guard proof.count == PacketReceipt.explicitProofLength else { return false }
        let proofHash = proof.prefix(Constants.fullHashLength)
        let signature = proof.suffix(Constants.signatureLength)
        guard proofHash == packetHash else { return false }
        guard let identity = peerIdentity else { return false }
        guard identity.validate(signature: signature, for: packetHash) else { return false }
        return markDelivered()
    }

    /// Validate an implicit proof: just a 64-byte Ed25519 signature over the
    /// packet hash. Mirrors Python's `PacketReceipt.validate_proof` (IMPL_LENGTH branch).
    ///
    /// Unlike explicit proofs, implicit proofs cannot be pre-filtered by hash,
    /// so the caller must try this against every outstanding receipt.
    @discardableResult
    func validateImplicitProof(_ proof: Data) -> Bool {
        guard status == .sent else { return false }
        guard proof.count == PacketReceipt.implicitProofLength else { return false }
        guard let identity = peerIdentity else { return false }
        guard identity.validate(signature: proof, for: packetHash) else { return false }
        return markDelivered()
    }

    /// Atomic terminal-state commit. Returns `true` iff this call won the race
    /// (transitioned from `.sent` to `.delivered`); a loser returns `false`
    /// without firing a callback. The delivery callback fires outside the lock.
    @discardableResult
    private func markDelivered() -> Bool {
        stateLock.lock()
        guard status == .sent else { stateLock.unlock(); return false }
        status = .delivered
        proved = true
        concludedAt = Date()
        let cb = _onDelivery
        _onDelivery = nil
        stateLock.unlock()
        DispatchQueue.global(qos: .utility).async { cb?(self) }
        return true
    }

    // MARK: - RTT

    /// Round-trip time from send to proof, or nil if not yet delivered.
    public var rtt: TimeInterval? {
        guard let concluded = concludedAt else { return nil }
        return concluded.timeIntervalSince(sentAt)
    }

    // MARK: - Python-compatible getter/setter methods

    /// Returns the RTT in seconds. Mirrors Python `PacketReceipt.get_rtt()`.
    public func getRtt() -> TimeInterval? { rtt }

    /// Returns whether the receipt has timed out. Mirrors Python `PacketReceipt.is_timed_out()`.
    public func isTimedOutMethod() -> Bool { isTimedOut }

    /// Sets the timeout. Mirrors Python `PacketReceipt.set_timeout(timeout)`.
    public func setTimeout(_ t: TimeInterval) { timeout = t }

    /// Sets the delivery callback. Mirrors Python `PacketReceipt.set_delivery_callback(callback)`.
    public func setDeliveryCallback(_ cb: @escaping (PacketReceipt) -> Void) { onDelivery = cb }

    /// Sets the timeout callback. Mirrors Python `PacketReceipt.set_timeout_callback(callback)`.
    public func setTimeoutCallback(_ cb: @escaping (PacketReceipt) -> Void) { onTimeout = cb }

    /// Returns the receipt status. Mirrors Python `PacketReceipt.get_status()`.
    public func getStatus() -> Status { status }

    /// Returns the full 32-byte SHA-256 packet hash.
    /// Mirrors Python `PacketReceipt.get_hash()`.
    public func getHash() -> Data { packetHash }

    /// Returns whether the receipt was proved by the remote destination.
    /// Mirrors Python `PacketReceipt.get_proved()`.
    public func getProved() -> Bool { proved }

    /// Returns the time the packet was sent.
    /// Mirrors Python `PacketReceipt.sent_at` (direct attribute access in Python).
    public func getSentAt() -> Date { sentAt }

    /// Returns the time the receipt was concluded (delivered or timed out), or nil.
    /// Mirrors Python `PacketReceipt.concluded_at`.
    public func getConcludedAt() -> Date? { concludedAt }
}
