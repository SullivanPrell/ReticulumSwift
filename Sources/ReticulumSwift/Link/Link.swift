import Foundation
import CryptoKit

/// A Reticulum Link — an ephemeral, encrypted, end-to-end session between
/// two destinations.
///
/// Three packets establish a link:
///   1. LRR  — Link Request (initiator → destination)
///             `[X25519 pub 32][Ed25519 pub 32]`
///             packet_type = LINKREQUEST, dest_type = SINGLE,
///             destination_hash = destination.hash.
///   2. LRPR — Link Request Proof (responder → initiator)
///             `[Ed25519 signature 64][X25519 pub 32]`
///             packet_type = PROOF, context = LRPROOF, dest_type = LINK,
///             destination_hash = link_id.
///             The signature covers `link_id || responder_eph_x25519_pub
///             || responder_identity_ed25519_pub`. The responder's signing
///             public key is *not* on the wire — the initiator already has
///             it via `destination.identity`.
///   3. RTT  — measured round-trip-time, msgpack-encoded float, encrypted
///             with the link's derived key. dest_type = LINK,
///             context = LRRTT, destination_hash = link_id.
///
/// Once active, both sides hold a 32-byte HKDF-derived key (salt = link_id)
/// and use it through the same Token construction as `Identity.encrypt`.
public final class Link {

    public enum Status: Sendable {
        case pending    // LRR sent, awaiting proof
        case handshake  // proof received, awaiting RTT
        case active     // fully established
        case stale      // no inbound traffic for stale_time; about to tear down
        case closed     // cleanly closed
        case failed     // timed out or error
    }
    public enum Role: Sendable { case initiator, responder }

    /// Why the link was torn down. Mirrors Python `Link.TIMEOUT / INITIATOR_CLOSED / DESTINATION_CLOSED`.
    public enum TeardownReason: Sendable {
        case timeout            // watchdog: establishment or stale timeout
        case initiatorClosed    // local (initiator) or remote (responder) called teardown()
        case destinationClosed  // remote (initiator) received a close packet
    }
    /// Set when the link enters `.closed` or `.failed`. Nil while active.
    public private(set) var teardownReason: TeardownReason?

    /// Bytes exchanged during link establishment (LRR + LRPR).
    /// Mirrors Python's `Link.establishment_cost`.
    public private(set) var establishmentCost: Int = 0
    /// Data rate of the link establishment phase (bytes/sec). Set once link is active.
    /// Mirrors Python's `Link.establishment_rate`.
    public private(set) var establishmentRate: Double?

    // MARK: - Watchdog constants (mirrors Python Link class attributes)

    /// Elliptic curve used for key agreement. Mirrors Python `Link.CURVE = 'Curve25519'`.
    public static let curve: String = "Curve25519"

    // MARK: - Cipher mode constants (Python Link.MODE_*)

    /// Python: `Link.MODE_AES128_CBC = 0x00`
    public static let modeAes128Cbc:  UInt8 = 0x00
    /// Python: `Link.MODE_AES256_CBC = 0x01`
    public static let modeAes256Cbc:  UInt8 = 0x01
    /// Python: `Link.MODE_AES256_GCM = 0x02`
    public static let modeAes256Gcm:  UInt8 = 0x02
    /// Python: `Link.MODE_OTP_RESERVED = 0x03`
    public static let modeOtpReserved: UInt8 = 0x03
    /// Python: `Link.MODE_PQ_RESERVED_1 = 0x04`
    public static let modePqReserved1: UInt8 = 0x04
    /// Python: `Link.MODE_PQ_RESERVED_2 = 0x05`
    public static let modePqReserved2: UInt8 = 0x05
    /// Python: `Link.MODE_PQ_RESERVED_3 = 0x06`
    public static let modePqReserved3: UInt8 = 0x06
    /// Python: `Link.MODE_PQ_RESERVED_4 = 0x07`
    public static let modePqReserved4: UInt8 = 0x07

    /// Currently enabled cipher modes. Python: `ENABLED_MODES = [MODE_AES256_CBC]`.
    public static let enabledModes: Set<UInt8> = [modeAes256Cbc]

    /// Human-readable names for each mode. Python: `Link.MODE_DESCRIPTIONS`.
    public static let modeDescriptions: [UInt8: String] = [
        modeAes128Cbc:  "AES_128_CBC",
        modeAes256Cbc:  "AES_256_CBC",
        modeAes256Gcm:  "MODE_AES256_GCM",
        modeOtpReserved: "MODE_OTP_RESERVED",
        modePqReserved1: "MODE_PQ_RESERVED_1",
        modePqReserved2: "MODE_PQ_RESERVED_2",
        modePqReserved3: "MODE_PQ_RESERVED_3",
        modePqReserved4: "MODE_PQ_RESERVED_4",
    ]

    /// Default cipher mode. Python: `MODE_DEFAULT = MODE_AES256_CBC = 0x01`.
    public static let defaultMode: UInt8 = modeAes256Cbc

    /// Bit mask for 21-bit MTU field in signalling bytes. Python: `MTU_BYTEMASK = 0x1FFFFF`.
    public static let mtuByteMask: UInt32 = 0x1FFFFF
    /// Bit mask for 3-bit mode field in signalling bytes. Python: `MODE_BYTEMASK = 0xE0`.
    public static let modeByteMask: UInt8 = 0xE0

    /// Minimum traffic timeout in milliseconds. Python: `TRAFFIC_TIMEOUT_MIN_MS = 5`.
    public static let trafficTimeoutMinMs: Int = 5
    /// Max time watchdog sleeps per iteration in seconds. Python: `WATCHDOG_MAX_SLEEP = 5`.
    public static let watchdogMaxSleep: TimeInterval = 5

    /// Encrypted MDU for link packets (session key, no ephemeral pub key overhead).
    /// Mirrors Python `Link.MDU = 431`.
    /// Formula: floor((500 - 1 - 19 - 48) / 16) * 16 - 1 = 431.
    public static let encryptedMdu: Int = Constants.linkMdu

    /// Default link plain MDU. Mirrors Python `RNS.Link.MDU` (= 464 plain, but Python actually
    /// uses the encrypted version = 431 for payload limits).
    /// The actual MDU for an established link depends on negotiated MTU.
    public static let mtu: Int = Constants.mdu

    /// Minimum keepalive interval in seconds. Mirrors Python `Link.KEEPALIVE_MIN = 5`.
    public static let keepaliveMin: TimeInterval = 5
    /// Maximum keepalive interval in seconds. Mirrors Python `Link.KEEPALIVE_MAX = 360`.
    public static let keepaliveMax: TimeInterval = 360
    /// RTT (seconds) at which keepalive equals KEEPALIVE_MAX.
    /// Mirrors Python `Link.KEEPALIVE_MAX_RTT = 1.75`.
    public static let keepaliveMaxRTT: Double = 1.75

    /// Default keepalive interval before RTT is known.
    /// Matches Python `KEEPALIVE = KEEPALIVE_MAX = 360`.
    public static let keepaliveInterval: TimeInterval = keepaliveMax

    /// Factor by which to multiply keepalive for stale detection.
    /// Python: `STALE_FACTOR = 2`, so `STALE_TIME = STALE_FACTOR * KEEPALIVE = 720`.
    public static let staleFactor: Int = 2
    /// Time after last inbound before the link is considered stale and torn down.
    /// Python: `STALE_TIME = STALE_FACTOR * KEEPALIVE = 2 * 360 = 720`.
    public static let staleTime: TimeInterval = keepaliveInterval * TimeInterval(staleFactor)
    /// Grace period in seconds after STALE before actual teardown.
    /// Python: `STALE_GRACE = 5`.
    public static let staleGrace: TimeInterval = 5
    /// Maximum time to establish a link per hop.
    /// Python: `ESTABLISHMENT_TIMEOUT_PER_HOP = 6` seconds.
    public static let establishmentTimeoutPerHop: TimeInterval = 6
    /// Timeout factor: `rtt * keepaliveTimeoutFactor` used in timeout calculations.
    /// Python: `KEEPALIVE_TIMEOUT_FACTOR = 4`.
    public static let keepaliveTimeoutFactor: Double = 4.0
    /// Multiplier for RTT when computing default request timeout.
    /// Mirrors Python `Link.TRAFFIC_TIMEOUT_FACTOR = 6`.
    public static let trafficTimeoutFactor: Double = 6.0
    /// Addend for default request timeout (max response grace time × 1.125).
    /// Mirrors Python `Resource.RESPONSE_MAX_GRACE_TIME * 1.125 = 10 * 1.125 = 11.25`.
    public static let requestTimeoutGrace: TimeInterval = 11.25

    // MARK: - MTU signalling (Python Link.LINK_MTU_SIZE = 3)

    /// 3-byte MTU+mode signalling appended to LRR and LRPR data.
    /// Encodes: bits[23:21] = mode (AES256_CBC=0x01 → 0x20 in top byte),
    ///          bits[20:0]  = mtu & 0x1FFFFF.
    /// Mirrors Python: `Link.signalling_bytes(mtu, mode)`.
    static func mtuSignallingBytes(mtu: Int = Constants.mtu) -> Data {
        let modeByte: UInt32 = 0x20 // (AES256_CBC=1) << 5 = 0x20
        let value = (UInt32(mtu) & 0x1FFFFF) | (modeByte << 16)
        return Data([
            UInt8((value >> 16) & 0xFF),
            UInt8((value >>  8) & 0xFF),
            UInt8( value        & 0xFF)
        ])
    }

    /// Decode the MTU from 3-byte signalling bytes (inverse of `mtuSignallingBytes`).
    /// Mirrors Python's `Link.mtu_from_lr_packet` / `mtu_from_lp_packet` masking
    /// (the mode bits in the top byte are discarded via `MTU_BYTEMASK`).
    /// Returns `nil` if `bytes` is not exactly 3 bytes.
    static func mtuFromSignalling(_ bytes: Data) -> Int? {
        guard bytes.count == 3 else { return nil }
        let b = Array(bytes)
        let value = (UInt32(b[0]) << 16) | (UInt32(b[1]) << 8) | UInt32(b[2])
        return Int(value & mtuByteMask)
    }

    /// Compute the hashable bytes for link ID derivation from a LINK_REQUEST packet.
    ///
    /// Mirrors Python `Link.link_id_from_lr_packet`:
    ///   ```python
    ///   hashable_part = packet.get_hashable_part()
    ///   if len(packet.data) > ECPUBSIZE:
    ///       hashable_part = hashable_part[:-diff]   # strip signalling bytes
    ///   ```
    /// Both Python and Swift must produce the same link_id to route LRPROOF packets.
    /// If we include the 3-byte MTU signalling in the hash, Python will compute a
    /// different ID, and LRPROOF delivery will fail (mismatch in link lookup table).
    static func linkIDHashable(for packet: Packet, dataLength: Int) throws -> Data {
        var hashable = try packet.hashablePart()
        let extraBytes = dataLength - Constants.keySize   // keySize = ECPUBSIZE = 64
        if extraBytes > 0 {
            hashable = Data(hashable.dropLast(extraBytes))
        }
        return hashable
    }

    public let role: Role
    public private(set) var status: Status = .pending

    /// Initiator: target destination. Responder: local registered destination
    /// the request landed on.
    public let destination: Destination

    /// Initiator's ephemeral X25519 (key agreement) and Ed25519 (signing,
    /// only used by responder side, where it's the owning identity's key).
    public let prv: Curve25519.KeyAgreement.PrivateKey
    public let sigPrv: Curve25519.Signing.PrivateKey

    public var pubBytes: Data { prv.publicKey.rawRepresentation }
    public var sigPubBytes: Data { sigPrv.publicKey.rawRepresentation }

    public private(set) var peerPub: Curve25519.KeyAgreement.PublicKey?
    public private(set) var peerPubBytes: Data?
    public private(set) var peerSigPub: Curve25519.Signing.PublicKey?
    public private(set) var peerSigPubBytes: Data?

    public private(set) var linkID: Data?
    public private(set) var derivedKey: Data?
    public private(set) var rtt: TimeInterval?

    /// Cipher mode used for this link. Always AES-256-CBC (0x01) since that is the
    /// only currently enabled mode. Mirrors Python `Link.mode = Link.MODE_AES256_CBC`.
    public let mode: UInt8 = 0x01  // MODE_AES256_CBC

    /// Negotiated link MTU in bytes. Mirrors Python's per-link `Link.mtu`.
    /// Defaults to `Constants.mtu` (500) and is updated during the handshake:
    /// the responder adopts the MTU signalled in the LINK_REQUEST and confirms
    /// it in the proof; the initiator adopts the confirmed value. When neither
    /// side signals a higher value (e.g. interfaces with no HW MTU), it stays
    /// at 500 and `mdu` equals `Constants.linkMdu` — identical to prior behavior.
    public internal(set) var establishedMtu: Int = Constants.mtu

    /// Maximum data unit for a single encrypted link packet payload, derived
    /// from the negotiated `establishedMtu`. With the default MTU this equals
    /// `Constants.linkMdu` (= 431). Mirrors Python's
    /// `mdu = floor((mtu - IFAC_MIN - HEADER_MIN - TOKEN_OVERHEAD)/16)*16 - 1`.
    public var mdu: Int {
        (establishedMtu - Constants.ifacMinSize - Constants.headerMinSize - Constants.tokenOverhead)
            / Constants.aes128BlockSize * Constants.aes128BlockSize - 1
    }

    public var requestTime: Date?
    public var establishedAt: Date?

    /// Establishment timeout. Defaults to `establishmentTimeoutPerHop`
    /// seconds; scaled up by hop count when the path is known.
    public var establishmentTimeout: TimeInterval = Link.establishmentTimeoutPerHop

    /// Fires when the link transitions to `.active`. If the link is already
    /// active when the callback is set (synchronous loopback), it replays.
    public var onEstablished: ((Link) -> Void)? {
        didSet { if status == .active { onEstablished?(self) } }
    }
    public var onClosed: ((Link) -> Void)?
    public var onDataReceived: ((Data, Link) -> Void)?
    /// Called when the link times out (establishment or stale).
    public var onTimeout: ((Link) -> Void)?
    /// Called when the remote peer reveals their identity via `identify`.
    /// Mirrors Python's `LinkCallbacks.remote_identified`.
    public var onRemoteIdentified: ((Link, Identity) -> Void)? {
        didSet {
            if let id = remoteIdentity { onRemoteIdentified?(self, id) }
        }
    }

    /// The identity the remote peer revealed via `identify()`, if any.
    /// Only populated on the responder side.
    public private(set) var remoteIdentity: Identity?

    /// Adaptive keepalive interval based on measured RTT.
    /// Mirrors Python's `Link.__update_keepalive`:
    ///   keepalive = max(KEEPALIVE_MIN, min(rtt * (KEEPALIVE_MAX / KEEPALIVE_MAX_RTT), KEEPALIVE_MAX))
    public var effectiveKeepalive: TimeInterval {
        guard let rtt, rtt > 0 else { return Link.keepaliveInterval }
        return max(Link.keepaliveMin, min(rtt * (Link.keepaliveMax / Link.keepaliveMaxRTT), Link.keepaliveMax))
    }

    /// Adaptive stale time based on measured RTT.
    /// Mirrors Python: `stale_time = keepalive * STALE_FACTOR`.
    public var effectiveStaleTime: TimeInterval {
        effectiveKeepalive * TimeInterval(Link.staleFactor)
    }

    /// Timestamp when the link transitioned to `.active`. Mirrors Python `Link.activated_at`.
    /// This is the same moment as `establishedAt`; exposed as `activatedAt` for API parity.
    public var activatedAt: Date? { establishedAt }

    /// Timestamp of the last non-keepalive DATA payload sent or received on
    /// this link. Mirrors Python `Link.last_data`.
    public private(set) var lastData: Date?

    /// Expected in-flight data rate in bits per second, updated after each
    /// completed Resource transfer. Mirrors Python `Link.expected_rate`.
    public private(set) var expectedRate: Double?

    // MARK: - Traffic statistics (mirrors Python Link.tx/rx/txbytes/rxbytes)

    /// Total outbound packet count. Mirrors Python `Link.tx`.
    public private(set) var tx: Int = 0
    /// Total inbound packet count. Mirrors Python `Link.rx`.
    public private(set) var rx: Int = 0
    /// Total bytes transmitted (encrypted payload). Mirrors Python `Link.txbytes`.
    public private(set) var txBytes: Int = 0
    /// Total bytes received (encrypted payload). Mirrors Python `Link.rxbytes`.
    public private(set) var rxBytes: Int = 0

    /// Wall-clock of the most recent inbound encrypted packet (any
    /// context). Used by the keepalive watchdog. `nil` until the first
    /// inbound packet arrives.
    public private(set) var lastInbound: Date?
    /// Wall-clock of the most recent outbound encrypted packet.
    public private(set) var lastOutbound: Date?
    /// Wall-clock of the most recent keepalive we sent (initiator only).
    public private(set) var lastKeepalive: Date?
    /// Full SHA-256 hash (32 bytes) of the last received link DATA packet (context == .none).
    /// Set in `receive(_:from:)` just before `onDataReceived` fires so callers can
    /// compute a `prove_packet` acknowledgment (mirrors Python `Link.prove_packet`).
    /// Python uses the FULL hash (Identity.full_hash, 32 bytes) for proof matching.
    public private(set) var lastReceivedDataPacketHash: Data?
    /// Fires for every decrypted inbound packet, with its packetType and
    /// context. Higher-level layers (resources, requests, channels) hook
    /// here to dispatch on context.
    public var onPacketReceived: ((Data, Packet.PacketType, Packet.Context, Link) -> Void)?

    // MARK: - PHY stats (mirrors Python Link.track_phy_stats / Link.rssi / Link.snr / Link.q)

    /// Enable PHY stats tracking. When true, RSSI/SNR/quality are pulled from
    /// the receiving interface on each inbound packet.
    public var trackPhyStats: Bool = false
    /// Last received signal strength indicator (dBm). Updated from the receiving interface
    /// when `trackPhyStats` is true. Mirrors Python `Link.rssi`.
    public private(set) var rssi: Float?
    /// Last received signal-to-noise ratio (dB). Mirrors Python `Link.snr`.
    public private(set) var snr: Float?
    /// Link quality 0–100 derived from SNR. Mirrors Python `Link.q`.
    public private(set) var quality: Float?

    /// Enable or disable physical layer statistics tracking.
    ///
    /// Explicit method form of the `trackPhyStats` property, matching Python's
    /// `Link.track_phy_stats(track: bool)` method signature.
    public func trackPhyStats(_ track: Bool) {
        trackPhyStats = track
    }

    /// Returns the RSSI if PHY stat tracking is enabled, otherwise nil.
    /// Mirrors Python's `Link.get_rssi()`.
    public func getRssi() -> Float? { trackPhyStats ? rssi : nil }
    /// Returns the SNR if PHY stat tracking is enabled, otherwise nil.
    /// Mirrors Python's `Link.get_snr()`.
    public func getSnr() -> Float? { trackPhyStats ? snr : nil }
    /// Returns the link quality if PHY stat tracking is enabled, otherwise nil.
    /// Mirrors Python's `Link.get_q()`.
    public func getQ() -> Float? { trackPhyStats ? quality : nil }

    private weak var transport: Transport?
    private var token: Token?
    private var watchdogTimer: DispatchSourceTimer?

    // Request/response dispatch — populated by Link.request.
    var pendingRequests: [Data: RequestReceipt] = [:]

    /// Channel attached to this link (lazy; created by `getChannel()`).
    private var _channel: Channel?

    // MARK: - Resource strategy (mirrors Python Link.resource_strategy)

    public enum ResourceStrategy: UInt8 { case acceptNone = 0, acceptApp = 1, acceptAll = 2 }

    /// Controls how incoming (non-request, non-response) resources are handled.
    public var resourceStrategy: ResourceStrategy = .acceptNone

    /// Called when a resource advertisement arrives and `resourceStrategy == .acceptApp`.
    /// Return `true` to accept (start receiving), `false` to reject.
    public var onResourceAdvertised: ((ResourceAdvertisement, Link) -> Bool)?

    /// Called when an incoming resource transfer starts (ADV accepted, receiving begins).
    /// Mirrors Python's `Link.set_resource_started_callback`.
    public var onResourceStarted: ((ResourceTransfer) -> Void)?

    /// Called when an incoming resource transfer completes (whether accepted via
    /// `acceptAll` or `acceptApp`). The first argument is the reassembled payload.
    public var onResourceConcluded: ((Data, ResourceAdvertisement, Link) -> Void)?

    // MARK: - Python-style setter methods (mirrors Python Link.set_*_callback / set_resource_strategy)

    /// Mirrors Python's `Link.set_link_established_callback(callback)`.
    public func setLinkEstablishedCallback(_ callback: @escaping (Link) -> Void) { onEstablished = callback }

    /// Mirrors Python's `Link.set_link_closed_callback(callback)`.
    public func setLinkClosedCallback(_ callback: @escaping (Link) -> Void) { onClosed = callback }

    /// Mirrors Python's `Link.set_packet_callback(callback)`.
    public func setPacketCallback(_ callback: @escaping (Data, Link) -> Void) { onDataReceived = callback }

    /// Mirrors Python's `Link.set_resource_callback(callback)`.
    public func setResourceCallback(_ callback: @escaping (ResourceAdvertisement, Link) -> Bool) {
        onResourceAdvertised = callback
    }

    /// Mirrors Python's `Link.set_resource_started_callback(callback)`.
    public func setResourceStartedCallback(_ callback: @escaping (ResourceTransfer) -> Void) {
        onResourceStarted = callback
    }

    /// Mirrors Python's `Link.set_resource_concluded_callback(callback)`.
    public func setResourceConcludedCallback(_ callback: @escaping (Data, ResourceAdvertisement, Link) -> Void) {
        onResourceConcluded = callback
    }

    /// Mirrors Python's `Link.set_remote_identified_callback(callback)`.
    public func setRemoteIdentifiedCallback(_ callback: @escaping (Link, Identity) -> Void) {
        onRemoteIdentified = callback
    }

    /// Mirrors Python's `Link.set_resource_strategy(resource_strategy)`.
    public func setResourceStrategy(_ strategy: ResourceStrategy) { resourceStrategy = strategy }

    // Resource transfer state — managed by ResourceTransfer.
    var outgoingResources: [ResourceTransfer] = []
    var incomingResources: [ResourceTransfer] = []

    /// Called by ResourceTransfer when a transfer concludes. Updates `expectedRate`.
    /// Mirrors Python `Link.resource_concluded(resource)`.
    func resourceConcluded(dataSize: Int, duration: TimeInterval) {
        let elapsed = max(duration, 0.0001)
        expectedRate = Double(dataSize * 8) / elapsed
    }

    func registerOutgoingResource(_ rt: ResourceTransfer) {
        outgoingResources.append(rt)
    }
    func unregisterOutgoingResource(_ rt: ResourceTransfer) {
        outgoingResources.removeAll { $0 === rt }
    }
    func registerIncomingResource(_ rt: ResourceTransfer) {
        incomingResources.append(rt)
    }
    func unregisterIncomingResource(_ rt: ResourceTransfer) {
        incomingResources.removeAll { $0 === rt }
    }

    private var lastResourceWindow_: Int? = nil
    private var lastResourceEifr_: Double? = nil

    /// Returns whether the given resource is in the incoming queue. Mirrors Python `Link.has_incoming_resource()`.
    public func hasIncomingResource(_ rt: ResourceTransfer) -> Bool {
        incomingResources.contains { $0 === rt }
    }

    /// Returns the window size of the last completed incoming resource. Mirrors Python `Link.get_last_resource_window()`.
    public func getLastResourceWindow() -> Int? { lastResourceWindow_ }

    /// Returns the EIFR of the last completed incoming resource. Mirrors Python `Link.get_last_resource_eifr()`.
    public func getLastResourceEifr() -> Double? { lastResourceEifr_ }

    /// Removes the resource from the outgoing queue. Mirrors Python `Link.cancel_outgoing_resource()`.
    public func cancelOutgoingResource(_ rt: ResourceTransfer) {
        outgoingResources.removeAll { $0 === rt }
    }

    /// Removes the resource from the incoming queue. Mirrors Python `Link.cancel_incoming_resource()`.
    public func cancelIncomingResource(_ rt: ResourceTransfer) {
        incomingResources.removeAll { $0 === rt }
    }

    /// Returns true if there are no outgoing resources pending. Mirrors Python `Link.ready_for_new_resource()`.
    public func readyForNewResource() -> Bool { outgoingResources.isEmpty }

    /// Called by ResourceTransfer when an incoming resource concludes — records window and EIFR.
    func recordIncomingResourceConclusion(window: Int, eifr: Double?) {
        lastResourceWindow_ = window
        lastResourceEifr_ = eifr
    }

    func testSetLastResourceWindow(_ w: Int) { lastResourceWindow_ = w }
    func testSetLastResourceEifr(_ e: Double) { lastResourceEifr_ = e }

    /// Send pre-encrypted resource segment data without applying link-level
    /// encryption (matches Python: "A resource takes care of encryption by itself").
    func sendResourcePart(_ encryptedData: Data) throws {
        guard status == .active else { throw LinkError.notActive }
        guard let linkID, let transport else { throw LinkError.invalidState }
        let packet = Packet(
            destinationType: .link,
            packetType: .data,
            destinationHash: linkID,
            context: .resource,
            data: encryptedData
        )
        try transport.send(packet, generateReceipt: false)
        lastOutbound = Date()
    }

    /// Send resource proof packet (PROOF type, not link-encrypted, matches Python).
    func sendResourceProof(_ proofData: Data) throws {
        guard status == .active else { throw LinkError.notActive }
        guard let linkID, let transport else { throw LinkError.invalidState }
        let packet = Packet(
            destinationType: .link,
            packetType: .proof,
            destinationHash: linkID,
            context: .resourceProof,
            data: proofData
        )
        try transport.send(packet, generateReceipt: false)
        lastOutbound = Date()
    }

    /// Returns the Channel for this link, creating one if needed.
    /// Matches Python's `Link.get_channel()`.
    public func getChannel() -> Channel {
        if let ch = _channel { return ch }
        let outlet = LinkChannelOutlet(link: self)
        let ch = Channel(outlet: outlet)
        _channel = ch
        return ch
    }

    public enum LinkError: Swift.Error, Equatable {
        case malformedRequest
        case malformedProof
        case missingResponderIdentity
        case invalidSignature
        case invalidState
        case notActive
    }

    // MARK: - Initiator

    /// Create an initiator-side link bound to `destination` and send the
    /// link request on `transport`. Caller must `transport.register(link:)`
    /// before sending if it wants `Transport` to deliver the proof.
    public static func initiate(
        destination: Destination,
        transport: Transport
    ) throws -> Link {
        let link = Link(role: .initiator, destination: destination)
        link.transport = transport

        // Use next-hop HW MTU if available (link MTU discovery).
        // Mirrors Python: Transport.next_hop_interface_hw_mtu → Link.signalling_bytes.
        let signaledMtu = transport.nextHopInterfaceHwMtu(for: destination.hash) ?? Constants.mtu
        let body = link.pubBytes + link.sigPubBytes + mtuSignallingBytes(mtu: signaledMtu)
        let packet = Packet(
            destinationType: .single,
            packetType: .linkRequest,
            destinationHash: destination.hash,
            data: body
        )

        // Python strips any signalling bytes beyond ECPUBSIZE from the hashable part
        // before computing the link ID. Mirrors `Link.link_id_from_lr_packet`:
        //   if len(packet.data) > ECPUBSIZE: hashable_part = hashable_part[:-diff]
        // This ensures Swift and Python agree on the link_id regardless of whether
        // MTU signalling is present in the LINK_REQUEST payload.
        link.linkID = Hashes.truncatedHash(try Link.linkIDHashable(for: packet, dataLength: body.count))
        link.requestTime = Date()
        // Scale establishment timeout by hop count and add first-hop propagation time.
        // Mirrors Python Link.__init__ lines 283–284:
        //   self.establishment_timeout  = RNS.Reticulum.get_instance().get_first_hop_timeout(destination.hash)
        //   self.establishment_timeout += Link.ESTABLISHMENT_TIMEOUT_PER_HOP * max(1, hops_to(destination.hash))
        let hops = transport.hopsTo(destination.hash) ?? 1
        let fht  = transport.firstHopTimeout(for: destination.hash)
        link.establishmentTimeout = fht + Link.establishmentTimeoutPerHop * TimeInterval(max(1, hops))
        transport.register(link: link)

        try transport.send(packet, generateReceipt: false)
        link.startWatchdog()
        return link
    }

    // MARK: - Responder

    /// Build a responder-side link from a received LRR packet. Computes
    /// link id, derives the shared key, sends the proof packet.
    public static func answer(
        request packet: Packet,
        destination: Destination,
        owner: Identity,
        transport: Transport
    ) throws -> Link {
        // Accept 64-byte (no signalling) or 67-byte (with MTU signalling) requests.
        guard packet.data.count == Constants.keySize
                || packet.data.count == Constants.keySize + 3 else {
            throw LinkError.malformedRequest
        }
        guard let signingPrivateKey = owner.signingPrivateKey,
              let _ = owner.encryptionPrivateKey else {
            throw LinkError.missingResponderIdentity
        }

        let initiatorEncRaw = packet.data.prefix(Constants.halfKeySize)
        let initiatorSigRaw = packet.data[Constants.halfKeySize ..< Constants.keySize]
        let initiatorEnc = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: initiatorEncRaw)
        let initiatorSig = try Curve25519.Signing.PublicKey(rawRepresentation: initiatorSigRaw)

        // Responder's ephemeral X25519 is fresh. Its signing key is the
        // owning identity's Ed25519 key — that's what the initiator already
        // knows, so we sign the link id with it.
        let link = Link(
            role: .responder,
            destination: destination,
            prv: Curve25519.KeyAgreement.PrivateKey(),
            sigPrv: signingPrivateKey
        )
        link.transport = transport
        link.peerPub = initiatorEnc
        link.peerPubBytes = Data(initiatorEncRaw)
        link.peerSigPub = initiatorSig
        link.peerSigPubBytes = Data(initiatorSigRaw)

        // Mirror Python's link_id_from_lr_packet: strip any signalling bytes (beyond ECPUBSIZE)
        // from the hashable part so both sides agree on the link_id regardless of signalling.
        link.linkID = Hashes.truncatedHash(try Link.linkIDHashable(for: packet, dataLength: packet.data.count))
        try link.deriveSharedKey()

        // Mirror Python validate_request (lines 207–208 in Link.py):
        //   link.establishment_timeout = ESTABLISHMENT_TIMEOUT_PER_HOP * max(1, packet.hops) + KEEPALIVE
        //   link.request_time = time.time()
        // The KEEPALIVE constant (360 s) gives the responder ample time to receive the RTT
        // packet on slow radio links or across many hops.
        link.requestTime = Date()
        link.establishmentTimeout =
            Link.establishmentTimeoutPerHop * TimeInterval(max(1, Int(packet.hops))) + Link.keepaliveInterval

        // Adopt the MTU signalled in the LINK_REQUEST (RNS link MTU discovery).
        // Mirrors Python `validate_request`: `link.mtu = mtu_from_lr_packet(packet) or MTU`.
        // The confirmed value is echoed back in the proof (see sendProof). We never
        // shrink below the default 500 even if a peer signals a smaller value.
        if packet.data.count == Constants.keySize + 3 {
            let signalling = Data(packet.data[Constants.keySize ..< Constants.keySize + 3])
            if let requestedMtu = Link.mtuFromSignalling(signalling), requestedMtu >= Constants.mtu {
                link.establishedMtu = requestedMtu
            }
        }

        transport.register(link: link)
        return link
    }

    /// Build and send the LRPR proof packet for a responder-side link that
    /// has just been registered. Split from `answer` so the caller can hook
    /// `onEstablished` before any reply travels (matters under synchronous
    /// loopback transports).
    public func sendProof() throws {
        guard role == .responder, let linkID, let transport else {
            throw LinkError.invalidState
        }
        // Include 3-byte MTU signalling in both the signed data and the proof packet.
        // Confirm the MTU we adopted from the request so the initiator can adopt
        // the same value (Python `prove`: `signalling_bytes(self.mtu, self.mode)`).
        let sig = Link.mtuSignallingBytes(mtu: establishedMtu)
        let signedData = linkID + pubBytes + sigPubBytes + sig
        let signature = try sigPrv.signature(for: signedData)
        let proof = Packet(
            destinationType: .link,
            packetType: .proof,
            destinationHash: linkID,
            context: .lrproof,
            data: signature + pubBytes + sig
        )
        try transport.send(proof, generateReceipt: false)
    }

    // MARK: - Data-packet proof (mirrors Python Link.prove_packet)

    /// Send an explicit proof for the most-recently-received link DATA packet.
    ///
    /// Mirrors Python's `link.prove_packet(packet)`:
    /// ```python
    /// signature = self.sign(packet.packet_hash)
    /// proof_data = packet.packet_hash + signature
    /// proof = RNS.Packet(self, proof_data, RNS.Packet.PROOF)
    /// proof.send()
    /// ```
    /// Must be called immediately after `onDataReceived` fires so that
    /// `lastReceivedDataPacketHash` holds the correct hash.
    ///
    /// Called by LXMRouter.delivery_packet (via link.onDataReceived) to prove
    /// every inbound LXMF link packet — matching Python LXMF's explicit
    /// `packet.prove()` at the top of `delivery_packet`.
    public func proveInboundData() {
        guard status == .active,
              let linkID,
              let transport,
              let packetHash = lastReceivedDataPacketHash else { return }
        guard let signature = try? sigPrv.signature(for: packetHash) else { return }
        let proofData = packetHash + signature
        let proof = Packet(
            destinationType: .link,
            packetType: .proof,
            destinationHash: linkID,
            context: .none,
            data: proofData
        )
        try? transport.send(proof, generateReceipt: false)
        lastOutbound = Date()
    }

    // MARK: - Init

    private init(role: Role, destination: Destination) {
        self.role = role
        self.destination = destination
        self.prv = Curve25519.KeyAgreement.PrivateKey()
        self.sigPrv = Curve25519.Signing.PrivateKey()
    }

    private init(
        role: Role,
        destination: Destination,
        prv: Curve25519.KeyAgreement.PrivateKey,
        sigPrv: Curve25519.Signing.PrivateKey
    ) {
        self.role = role
        self.destination = destination
        self.prv = prv
        self.sigPrv = sigPrv
    }

    // MARK: - Initiator: validate proof

    /// Process an incoming LRPR packet. On success, the link transitions to
    /// `.active`, sends the encrypted RTT packet, and fires `onEstablished`.
    public func validateProof(_ packet: Packet) throws {
        guard role == .initiator else { throw LinkError.invalidState }
        guard status == .pending else { throw LinkError.invalidState }
        let baseLen = Constants.signatureLength + Constants.halfKeySize
        // Accept 96-byte (no signalling) or 99-byte (with MTU signalling) proofs.
        guard packet.data.count == baseLen || packet.data.count == baseLen + 3 else {
            throw LinkError.malformedProof
        }

        let signature = packet.data.prefix(Constants.signatureLength)
        let responderPubBytes = packet.data[Constants.signatureLength ..< baseLen]
        // If present, extract the 3-byte signalling and include it in signature
        // verification (Python always signs linkID+pub+sigPub+signalling).
        let signallingBytes: Data = packet.data.count == baseLen + 3
            ? Data(packet.data[baseLen...])
            : Data()

        let responderPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: responderPubBytes)
        guard let destinationIdentity = destination.identity else {
            throw LinkError.missingResponderIdentity
        }
        let responderSigPubBytes = destinationIdentity.signingPublicKey.rawRepresentation
        let responderSigPub = destinationIdentity.signingPublicKey

        guard let linkID else { throw LinkError.invalidState }
        let signedData = linkID + responderPubBytes + responderSigPubBytes + signallingBytes
        guard responderSigPub.isValidSignature(signature, for: signedData) else {
            throw LinkError.invalidSignature
        }

        self.peerPub = responderPub
        self.peerPubBytes = Data(responderPubBytes)
        self.peerSigPub = responderSigPub
        self.peerSigPubBytes = responderSigPubBytes

        // Adopt the MTU the responder confirmed in the proof (RNS link MTU
        // discovery). Mirrors Python `validate_proof`:
        //   `confirmed_mtu = mtu_from_lp_packet(packet); self.mtu = confirmed_mtu or MTU`.
        if let confirmedMtu = Link.mtuFromSignalling(signallingBytes), confirmedMtu >= Constants.mtu {
            self.establishedMtu = confirmedMtu
        }

        try deriveSharedKey()

        if let requestTime { self.rtt = Date().timeIntervalSince(requestTime) }
        self.status = .active
        self.establishedAt = Date()

        // establishment_cost = KEYSIZE/8*2 + SIGLENGTH/8 + ECPUBSIZE/2 + ECPUBSIZE
        // Matches Python's formula: 64*2 + 64 + 32 + 64 = 288 bytes.
        let cost = Constants.keySize * 2 + Constants.keySize + Constants.halfKeySize + Constants.keySize
        self.establishmentCost = cost
        if let rtt, rtt > 0 { self.establishmentRate = Double(cost) / rtt }

        // Send LRRTT (msgpack float, encrypted) to acknowledge.
        let rttPlain = MsgPack.encodeDouble(self.rtt ?? 0)
        let rttCiphertext = try encrypt(rttPlain)
        let rttPacket = Packet(
            destinationType: .link,
            packetType: .data,
            destinationHash: linkID,
            context: .lrrtt,
            data: rttCiphertext
        )
        try transport?.send(rttPacket)

        // Mark path responsive on successful link establishment.
        // Mirrors Python: Transport.mark_path_responsive(self.destination.hash)
        transport?.markPathResponsive(for: destination.hash)
        onEstablished?(self)
    }

    // MARK: - Responder: receive RTT

    /// Process the LRRTT packet on the responder side. Marks the link
    /// active and fires `onEstablished`.
    ///
    /// Mirrors Python's `Link.rtt_packet` (lines 534–551 in Link.py):
    ///   measured_rtt = time.time() - self.request_time
    ///   rtt = umsgpack.unpackb(plaintext)
    ///   self.rtt = max(measured_rtt, rtt)
    ///   self.establishment_rate = self.establishment_cost / self.rtt
    public func receiveRTT(_ packet: Packet) throws {
        guard role == .responder else { throw LinkError.invalidState }
        guard status == .handshake else { throw LinkError.invalidState }

        let plaintext = try decrypt(packet.data)
        let reportedRTT = (try? MsgPack.decodeDouble(plaintext)) ?? 0
        // Take the maximum of our own measured round-trip time and the initiator's
        // reported value — whichever is larger is the more conservative estimate.
        let measuredRTT = requestTime.map { Date().timeIntervalSince($0) } ?? reportedRTT
        self.rtt = max(measuredRTT, reportedRTT)
        // Compute establishment rate if we have cost data.
        if let rtt, rtt > 0, establishmentCost > 0 {
            self.establishmentRate = Double(establishmentCost) / rtt
        }
        self.status = .active
        self.establishedAt = Date()
        onEstablished?(self)
    }

    // MARK: - Crypto plumbing

    private func deriveSharedKey() throws {
        guard let peerPub, let linkID else { throw LinkError.invalidState }
        let shared = try prv.sharedSecretFromKeyAgreement(with: peerPub)
        let sharedData = shared.withUnsafeBytes { Data($0) }
        // Mirrors RNS.Link.handshake: salt = link_id, no context.
        // MODE_AES256_CBC (default) → 64-byte derived key → Token AES-256-CBC mode.
        // Python: HKDF(length=64) when mode == MODE_AES256_CBC.
        let derived = HKDF.derive(
            length: Constants.derivedKeyLength,
            derivedFrom: sharedData,
            salt: linkID,
            context: nil
        )
        self.derivedKey = derived
        self.token = try Token(key: derived)
        self.status = .handshake
    }

    public func encrypt(_ plaintext: Data) throws -> Data {
        guard let token else { throw LinkError.notActive }
        return try token.encrypt(plaintext)
    }

    public func decrypt(_ ciphertext: Data) throws -> Data {
        guard let token else { throw LinkError.notActive }
        return try token.decrypt(ciphertext)
    }

    public func close() {
        stopWatchdog()
        // Preserve .failed/.stale status set by the watchdog; only override to .closed
        // for explicit clean closes.
        let wasTimeout = (teardownReason == .timeout)
        if status != .failed && status != .stale { status = .closed }
        // Mark path unresponsive on timeout teardown.
        // Mirrors Python: link_closed() → if teardown_reason == TIMEOUT: mark_path_unresponsive
        if wasTimeout { transport?.markPathUnresponsive(for: destination.hash) }
        token = nil
        derivedKey = nil
        onClosed?(self)
    }

    // MARK: - Inactivity helpers

    /// Seconds since the last inbound packet (including keepalives).
    /// Mirrors Python's `Link.no_inbound_for()`.
    /// Time in seconds since the link was established. Returns `nil` if the
    /// link has not yet become active. Mirrors Python `Link.get_age()`.
    /// Returns the link ID (used as HKDF salt during handshake).
    /// Mirrors Python's `Link.get_salt()` which returns `self.link_id`.
    public func getSalt() -> Data? { linkID }

    /// Returns the link context (always nil in current implementation).
    /// Mirrors Python's `Link.get_context()`.
    public func getContext() -> Data? { nil }

    /// Returns the expected in-flight data rate (bits/second) of an established link.
    /// Nil if the link is not active or no transfer has concluded.
    /// Mirrors Python's `Link.get_expected_rate()`.
    public func getExpectedRate() -> Double? {
        guard status == .active else { return nil }
        return expectedRate
    }

    /// Returns the link MTU for an established link, nil if not active.
    /// Mirrors Python's `Link.get_mtu()`.
    public func getMtu() -> Int? {
        guard status == .active else { return nil }
        return establishedMtu
    }

    /// Returns the packet MDU for an established link, nil if not active.
    /// Mirrors Python's `Link.get_mdu()`.
    public func getMdu() -> Int? {
        guard status == .active else { return nil }
        return mdu
    }

    /// Returns the data transfer rate at link establishment in bits/second, or nil.
    /// Mirrors Python's `Link.get_establishment_rate()` which returns
    /// `self.establishment_rate * 8` (converts bytes/s to bits/s).
    public func getEstablishmentRate() -> Double? {
        guard let rate = establishmentRate else { return nil }
        return rate * 8.0
    }

    /// Returns the cipher mode byte for this link.
    /// Mirrors Python's `Link.get_mode()`.
    public func getMode() -> UInt8 { mode }

    /// Returns the current link status.
    /// Mirrors Python's `Link.status` (direct attribute access).
    public func getStatus() -> Status { status }

    /// Returns the 16-byte link ID (HKDF salt), or nil before establishment.
    /// Mirrors Python's `Link.link_id` (direct attribute access).
    public func getLinkID() -> Data? { linkID }

    /// Returns the measured round-trip time in seconds, or nil before establishment.
    /// Mirrors Python's `Link.rtt` (direct attribute access).
    public func getRtt() -> TimeInterval? { rtt }

    /// Returns the identity revealed by the remote peer via `identify()`, or nil.
    /// Mirrors Python's `Link.remote_identity` (direct attribute access).
    public func getRemoteIdentity() -> Identity? { remoteIdentity }

    /// Returns the reason the link was torn down, or nil while the link is active.
    /// Mirrors Python's `Link.teardown_reason` (direct attribute access).
    public func getTeardownReason() -> TeardownReason? { teardownReason }

    public func getAge() -> TimeInterval? {
        guard let at = establishedAt else { return nil }
        return Date().timeIntervalSince(at)
    }

    /// Time in seconds since the last non-keepalive data traversed the link.
    /// Excludes keepalive packets (mirrors Python `Link.no_data_for()`).
    /// Returns a large value if no data has been sent or received yet.
    public func noDataFor() -> TimeInterval {
        guard let last = lastData else { return Date().timeIntervalSinceReferenceDate }
        return Date().timeIntervalSince(last)
    }

    public func noInboundFor() -> TimeInterval {
        // Use establishedAt as the baseline when available (matches Python's
        // `last_inbound = max(self.last_inbound, activated_at)`). Fall back
        // to requestTime so the value stays bounded before establishment.
        let baseline = (establishedAt ?? requestTime ?? Date()).timeIntervalSinceReferenceDate
        let last = max(lastInbound?.timeIntervalSinceReferenceDate ?? 0, baseline)
        return Date().timeIntervalSinceReferenceDate - last
    }

    /// Seconds since the last outbound packet (including keepalives).
    public func noOutboundFor() -> TimeInterval {
        guard let last = lastOutbound else { return Date().timeIntervalSince(requestTime ?? Date()) }
        return Date().timeIntervalSince(last)
    }

    /// Seconds since any activity on the link (min of inbound/outbound).
    /// Mirrors Python's `Link.inactive_for()`.
    public func inactiveFor() -> TimeInterval { min(noInboundFor(), noOutboundFor()) }

    /// Update the last-outbound timestamp (and last-data if not a keepalive).
    /// Mirrors Python's `Link.had_outbound(is_keepalive=False)`.
    public func hadOutbound(isKeepalive: Bool = false) {
        lastOutbound = Date()
        if isKeepalive {
            lastKeepalive = lastOutbound
        } else {
            lastData = lastOutbound
        }
    }

    // MARK: - Watchdog

    /// Start the background watchdog. Called automatically after the link
    /// reaches `.handshake` (initiator) or `.pending` (responder).
    /// Mirrors Python's `Link.start_watchdog()`.
    public func startWatchdog() {
        stopWatchdog()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 0.1, repeating: .never)
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        timer.resume()
        watchdogTimer = timer
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private func watchdogTick() {
        guard status != .closed && status != .failed else { return }
        let now = Date()
        var nextTick: TimeInterval = 30

        switch status {
        case .pending, .handshake:
            let requestedAt = requestTime ?? now
            let deadline = requestedAt.addingTimeInterval(establishmentTimeout)
            if now >= deadline {
                teardownReason = .timeout
                status = .failed
                stopWatchdog()
                // Mark path unresponsive on timeout.
                // Mirrors Python: Transport.mark_path_unresponsive(destination.hash)
                transport?.markPathUnresponsive(for: destination.hash)
                let cb = onTimeout; onTimeout = nil
                DispatchQueue.global(qos: .utility).async { cb?(self) }
                close()
                return
            }
            nextTick = max(0.5, deadline.timeIntervalSince(now))

        case .active:
            // Use adaptive keepalive/stale times based on measured RTT.
            // Mirrors Python's Link.__update_keepalive().
            let inboundAge = noInboundFor()
            let ka = effectiveKeepalive
            let st = effectiveStaleTime
            if inboundAge >= st {
                // No traffic for stale_time — tear down.
                teardownReason = .timeout
                status = .stale
                // Mark path unresponsive on timeout.
                transport?.markPathUnresponsive(for: destination.hash)
                try? teardown()
                return
            }
            if inboundAge >= ka {
                // Send a keepalive if we're the initiator and haven't sent one recently.
                if role == .initiator,
                   now.timeIntervalSince(lastKeepalive ?? .distantPast) >= ka {
                    try? sendKeepalive()
                }
                nextTick = ka
            } else {
                nextTick = max(0.5, ka - inboundAge)
            }

        default:
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + nextTick, repeating: .never)
        timer.setEventHandler { [weak self] in self?.watchdogTick() }
        timer.resume()
        watchdogTimer = timer
    }

    // MARK: - Data send / receive

    /// Encrypt and send a data packet over the link. `context` defaults to
    /// `.none` (a plain user-data packet); pass `.request`, `.response`,
    /// `.channel`, etc., for higher-level framing.
    public func send(_ plaintext: Data, context: Packet.Context = .none) throws {
        guard status == .active else { throw LinkError.notActive }
        guard let linkID, let transport else { throw LinkError.invalidState }
        let ciphertext = try encrypt(plaintext)
        let packet = Packet(
            destinationType: .link,
            packetType: .data,
            destinationHash: linkID,
            context: context,
            data: ciphertext
        )
        try transport.send(packet, generateReceipt: false)
        lastOutbound = Date()
        tx += 1
        txBytes += ciphertext.count
        if context != .keepalive { lastData = lastOutbound }
    }

    // MARK: - Request helpers (called from LinkRequest.swift extension)

    /// Encrypt `body` and build a link REQUEST Packet.
    /// Returns `(packet, requestID)` where `requestID` is the wire-format
    /// truncated packet hash — mirrors Python's `packet.getTruncatedHash()`.
    ///
    /// The caller must store the receipt in `pendingRequests[requestID]`
    /// **before** calling `sendPrebuiltPacket(_:)` so that a synchronous
    /// loopback transport can deliver the response without missing the lookup.
    func buildRequestPacket(_ body: Data) throws -> (Packet, Data) {
        guard let linkID else { throw LinkError.invalidState }
        let ciphertext = try encrypt(body)
        let packet = Packet(
            destinationType: .link,
            packetType: .data,
            destinationHash: linkID,
            context: .request,
            data: ciphertext
        )
        let requestID = (try? packet.truncatedPacketHash()) ?? Hashes.truncatedHash(body)
        return (packet, requestID)
    }

    /// Send a pre-built link DATA packet and update outbound traffic stats.
    func sendPrebuiltPacket(_ packet: Packet) throws {
        guard let transport else { throw LinkError.invalidState }
        try transport.send(packet, generateReceipt: false)
        let now = Date()
        lastOutbound = now
        tx += 1
        txBytes += packet.data.count
        lastData = now   // only keepalive packets skip lastData; REQUEST is not keepalive
    }

    /// Process an inbound packet. Routes resource contexts without link-level
    /// decryption (resource handles its own encryption); decrypts all others.
    /// The optional `receivingInterface` is used to update PHY stats when `trackPhyStats` is true.
    public func receive(_ packet: Packet, from receivingInterface: (any Interface)? = nil) throws {
        guard status == .active else { throw LinkError.notActive }
        updatePhyStats(from: receivingInterface)

        // RESOURCE data parts — pre-encrypted by the resource layer; pass raw.
        if packet.context == .resource {
            lastInbound = Date()
            rx += 1; rxBytes += packet.data.count
            let data = packet.data
            for rt in incomingResources { rt.receivePart(data) }
            return
        }

        // RESOURCE_PRF proof — sent unencrypted (Python: "not encrypted").
        if packet.packetType == .proof, packet.context == .resourceProof {
            lastInbound = Date()
            let proofData = packet.data
            guard proofData.count >= Constants.hashLength else { return }
            let resourceHash = proofData.prefix(Constants.hashLength)
            for rt in outgoingResources where rt.resourceHash == Data(resourceHash) {
                rt.validateProof(proofData)
            }
            return
        }

        // All other packets use link-level encryption.
        let plaintext = try decrypt(packet.data)
        let now = Date()
        lastInbound = now
        rx += 1
        rxBytes += packet.data.count

        switch packet.context {
        case .keepalive:
            handleKeepalive(plaintext)
            // Keepalives do NOT update lastData (matches Python had_outbound(is_keepalive=True))
        case .channel:
            _channel?.receive(plaintext)
        case .linkIdentify:
            handleRemoteIdentify(plaintext)
        case .resourceAdvertisement:
            if let adv = try? ResourceAdvertisement.unpack(plaintext) {
                if adv.isRequest {
                    // Incoming request via Resource — create a dedicated receiver.
                    handleIncomingRequestResource(adv: adv, rawAdv: plaintext)
                } else if adv.isResponse, let reqID = adv.requestID {
                    // Incoming response via Resource — route to pending request.
                    handleIncomingResponseResource(adv: adv, rawAdv: plaintext, requestID: reqID)
                } else if !incomingResources.isEmpty {
                    // Pre-registered receivers (via bindAsReceiver) take priority.
                    for rt in incomingResources { rt.receiveAdvertisement(plaintext) }
                } else {
                    // No pre-registered receiver — apply resource strategy.
                    switch resourceStrategy {
                    case .acceptNone:
                        try? send(adv.resourceHash, context: .resourceReceiverCancel)
                    case .acceptAll:
                        acceptIncomingResource(adv: adv, rawAdv: plaintext)
                    case .acceptApp:
                        if onResourceAdvertised?(adv, self) ?? false {
                            acceptIncomingResource(adv: adv, rawAdv: plaintext)
                        } else {
                            try? send(adv.resourceHash, context: .resourceReceiverCancel)
                        }
                    }
                }
            } else {
                for rt in incomingResources { rt.receiveAdvertisement(plaintext) }
            }
        case .resourceRequest:
            let reqData = plaintext
            let hashStart = reqData.count > 1 && reqData[0] == ResourceTransfer.hashmapIsExhausted
                ? 1 + ResourceTransfer.mapHashLength
                : 1
            guard reqData.count > hashStart + Constants.hashLength else { break }
            let resourceHash = reqData[hashStart ..< hashStart + Constants.hashLength]
            for rt in outgoingResources where rt.resourceHash == Data(resourceHash) {
                rt.handleRequest(reqData)
            }
        case .resourceHashmapUpdate:
            guard plaintext.count >= Constants.hashLength else { break }
            let resourceHash = plaintext.prefix(Constants.hashLength)
            for rt in incomingResources where rt.resourceHash == Data(resourceHash) {
                rt.handleHashmapUpdate(plaintext)
            }
        case .resourceInitiatorCancel:
            guard plaintext.count >= Constants.hashLength else { break }
            let resourceHash = plaintext.prefix(Constants.hashLength)
            for rt in incomingResources where rt.resourceHash == Data(resourceHash) {
                rt.cancel(reason: "initiator cancelled")
            }
        case .resourceReceiverCancel:
            guard plaintext.count >= Constants.hashLength else { break }
            let resourceHash = plaintext.prefix(Constants.hashLength)
            for rt in outgoingResources where rt.resourceHash == Data(resourceHash) {
                rt.reject()
            }
        case .request:
            // REQUEST packet: dispatch to registered handler using the wire-format
            // packet hash as request_id — mirrors Python's packet.getTruncatedHash().
            // The hash is computed from the raw packet bytes (header nibble + dest hash +
            // context + ciphertext), not from the plaintext, so the id matches what the
            // initiator stored regardless of implementation language.
            lastData = now
            let reqID = (try? packet.truncatedPacketHash()) ?? Hashes.truncatedHash(plaintext)
            handleIncomingRequest(plaintext, requestID: reqID)
            onPacketReceived?(plaintext, packet.packetType, packet.context, self)
        case .response:
            // RESPONSE packet: deliver to the pending RequestReceipt that sent the
            // matching request. request_id is embedded in the msgpack response body.
            lastData = now
            handleIncomingResponse(plaintext)
            onPacketReceived?(plaintext, packet.packetType, packet.context, self)
        default:
            // Non-keepalive DATA: update lastData (mirrors Python last_data = last_inbound)
            lastData = now
            onPacketReceived?(plaintext, packet.packetType, packet.context, self)
            // Only fire the data callback for actual DATA packets with no special
            // context — not for PROOF packets that happen to have context .none
            // (e.g. the explicit link data-proof sent by proveInboundData()).
            if packet.context == .none && packet.packetType == .data {
                // Capture full SHA-256 hash before callback so callers can prove receipt
                // (mirrors Python's PacketReceipt.hash = full_hash = 32 bytes).
                lastReceivedDataPacketHash = try? packet.packetHash()
                onDataReceived?(plaintext, self)
            }
        }
    }

    private func acceptIncomingResource(adv: ResourceAdvertisement, rawAdv: Data) {
        let rt = ResourceTransfer(link: self)
        rt.onAssembledInternal = { [weak self] payload, _ in
            guard let self else { return }
            self.onResourceConcluded?(payload, adv, self)
        }
        registerIncomingResource(rt)
        onResourceStarted?(rt)
        rt.receiveAdvertisement(rawAdv)
    }

    private func handleIncomingRequestResource(adv: ResourceAdvertisement, rawAdv: Data) {
        let rt = ResourceTransfer(link: self)
        rt.onAssembledInternal = { [weak self] payload, _ in
            guard let self else { return }
            // Unpack the request and dispatch to the registered handler.
            guard case .array(let parts) = (try? MsgPack.decode(payload)) ?? .nil,
                  parts.count >= 3 else { return }
            let requestedAt: Double = {
                if case .double(let t) = parts[0] { return t }
                if case .uint(let n) = parts[0] { return Double(n) }
                if case .int(let n) = parts[0] { return Double(n) }
                return 0
            }()
            guard case .bytes(let pathHash) = parts[1] else { return }
            let reqPayload: Data? = { if case .bytes(let b) = parts[2] { return b }; return nil }()
            let requestID = adv.requestID ?? Hashes.truncatedHash(payload)
            self.dispatchRequest(pathHash: pathHash, payload: reqPayload,
                                 requestID: requestID, requestedAt: requestedAt)
        }
        registerIncomingResource(rt)
        rt.receiveAdvertisement(rawAdv)
    }

    private func handleIncomingResponseResource(adv: ResourceAdvertisement, rawAdv: Data, requestID: Data) {
        guard let receipt = pendingRequests[requestID] else { return }
        let rt = ResourceTransfer(link: self)
        rt.onAssembledInternal = { [weak self, weak receipt] payload, _ in
            guard let self, let receipt else { return }
            self.pendingRequests.removeValue(forKey: requestID)
            receipt.deliverReady(payload)
        }
        registerIncomingResource(rt)
        rt.receiveAdvertisement(rawAdv)
    }

    private func handleRemoteIdentify(_ plaintext: Data) {
        // Only the responder processes this; initiators don't receive it.
        guard role == .responder else { return }
        let keySize = Constants.keySize
        let sigLen  = Constants.signatureLength
        guard plaintext.count == keySize + sigLen else { return }
        let pubKeyBytes = plaintext.prefix(keySize)
        let signature   = plaintext.suffix(sigLen)
        guard let linkID else { return }
        guard let identity = try? Identity(publicKeyBytes: Data(pubKeyBytes)) else { return }
        let signedData = linkID + Data(pubKeyBytes)
        guard identity.validate(signature: signature, for: signedData) else { return }
        // Terminate the link if the remote identifies as a blackholed identity.
        // Mirrors Python commit d3fcc2a3: extended blackhole functionality
        // immediately tears down inbound links from blackholed identities.
        if let transport = Reticulum.shared?.transport,
           transport.isBlackholed(identity.hash) {
            try? teardown()
            return
        }
        remoteIdentity = identity
        onRemoteIdentified?(self, identity)
    }

    // MARK: - Keepalive

    /// Initiator-side: send a keepalive probe. Body is the single byte
    /// `0xFF`, encrypted with the link key. The responder echoes back a
    /// `0xFE` keepalive on receipt. Matches Python's
    /// `RNS.Link.send_keepalive`.
    public func sendKeepalive() throws {
        guard role == .initiator else { return }
        try send(Data([0xFF]), context: .keepalive)
        lastKeepalive = Date()
    }

    private func updatePhyStats(from interface: (any Interface)?) {
        guard trackPhyStats, let interface else { return }
        if let r = interface.rssi    { rssi    = r }
        if let s = interface.snr     { snr     = s }
        if let q = interface.quality { quality = q }
    }

    /// Test helper: directly inject PHY stats without a real interface.
    func testSetPhyStats(rssi: Float, snr: Float, quality: Float) {
        self.rssi    = rssi
        self.snr     = snr
        self.quality = quality
    }

    private func handleKeepalive(_ plaintext: Data) {
        // Initiator gets `0xFE` from the responder — nothing to do; the
        // updated `lastInbound` already reset the watchdog.
        // Responder gets `0xFF` from the initiator and replies `0xFE`.
        if role == .responder, plaintext == Data([0xFF]) {
            try? send(Data([0xFE]), context: .keepalive)
        }
    }

    /// Encrypted send with a non-default packet type (e.g. `.proof` for
    /// RESOURCE_PRF). Used by the Resource transfer layer.
    public func send(_ plaintext: Data, packetType: Packet.PacketType, context: Packet.Context) throws {
        guard status == .active else { throw LinkError.notActive }
        guard let linkID, let transport else { throw LinkError.invalidState }
        let ciphertext = try encrypt(plaintext)
        let packet = Packet(
            destinationType: .link,
            packetType: packetType,
            destinationHash: linkID,
            context: context,
            data: ciphertext
        )
        try transport.send(packet, generateReceipt: false)
        lastOutbound = Date()
        tx += 1
        txBytes += ciphertext.count
        if context != .keepalive { lastData = lastOutbound }
    }

    // MARK: - Identify

    /// Reveal the initiator's identity to the responder over the encrypted
    /// link. Can only be called by the initiator once the link is active.
    ///
    /// Wire format (encrypted):  `[pubkey 64][ed25519_sig 64]`
    /// `signed_data = link_id + pubkey`
    ///
    /// Mirrors Python's `Link.identify(identity)`.
    public func identify(as identity: Identity) throws {
        guard role == .initiator, status == .active else { throw LinkError.notActive }
        guard identity.hasPrivateKey else { throw LinkError.missingResponderIdentity }
        guard let linkID else { throw LinkError.invalidState }
        let pubKey = identity.publicKeyBytes
        let signedData = linkID + pubKey
        let signature = try identity.sign(signedData)
        try send(pubKey + signature, context: .linkIdentify)
    }

    // MARK: - Teardown

    /// Send a LINKCLOSE packet to the peer and mark this side closed.
    /// The packet body is `encrypt(link_id)` — the peer verifies the
    /// plaintext matches its own link id before honoring the close.
    public func teardown() throws {
        guard let linkID, let transport else {
            if teardownReason == nil { teardownReason = .initiatorClosed }
            close()
            return
        }
        if teardownReason == nil {
            teardownReason = (role == .initiator) ? .initiatorClosed : .destinationClosed
        }
        if status == .active {
            let ciphertext = try encrypt(linkID)
            let packet = Packet(
                destinationType: .link,
                packetType: .data,
                destinationHash: linkID,
                context: .linkClose,
                data: ciphertext
            )
            try? transport.send(packet, generateReceipt: false)
        }
        close()
        transport.unregister(link: self)
    }

    /// Process an inbound LINKCLOSE packet. Closes the link if the
    /// decrypted plaintext matches our link id (proof of session
    /// possession).
    public func receiveTeardown(_ packet: Packet) {
        guard let linkID else { return }
        guard let plaintext = try? decrypt(packet.data), plaintext == linkID else { return }
        if teardownReason == nil {
            teardownReason = (role == .initiator) ? .destinationClosed : .initiatorClosed
        }
        close()
        transport?.unregister(link: self)
    }
}

