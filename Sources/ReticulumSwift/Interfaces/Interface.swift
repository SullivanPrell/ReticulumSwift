import Foundation

/// Operating mode of a Reticulum interface.
///
/// Mirrors Python's `Interface.MODE_*` constants (0x01–0x07).
/// The mode controls how a transport node interacts with the interface,
/// e.g. whether unknown-path requests are propagated outward.
public enum InterfaceMode: UInt8, Sendable, Equatable {
    case full         = 0x01
    case pointToPoint = 0x02
    case accessPoint  = 0x03
    case roaming      = 0x04
    case boundary     = 0x05
    case gateway      = 0x06
    /// Internal interface between co-located instances (RNS 1.3.6).
    /// Behaves like a roaming-aware relay for announce suppression but is
    /// included in path discovery. Mirrors Python's `Interface.MODE_INTERNAL`.
    case `internal`   = 0x07

    /// Modes for which a transport node should attempt to discover paths
    /// for unknown destinations on behalf of a path request.
    /// Mirrors Python's `Interface.DISCOVER_PATHS_FOR`.
    public static let discoverPathsFor: Set<InterfaceMode> = [.accessPoint, .gateway, .roaming, .internal]
}

/// Base protocol every transport implementation conforms to.
///
/// Reticulum Interfaces speak in *whole packets*: the underlying medium
/// (TCP, UDP, BLE serial, RNode KISS) handles framing; the Interface
/// reports clean packet bytes upward via `inboundHandler`.
public protocol Interface: AnyObject {
    var name: String { get }
    var bitrate: Int { get }
    var isOnline: Bool { get }

    /// Human-readable display name matching Python's `str(interface)` format,
    /// e.g. `"AutoInterface[local]"`, `"TCPClientInterface[...]"`.
    /// Declared as a protocol requirement (rather than left to the extension)
    /// so that `hash`/`getHash()` dispatch dynamically to overrides — a plain
    /// extension member here would be statically dispatched and always resolve
    /// to the default, silently hashing `name` instead of the type-qualified string.
    /// Mirrors Python's `Interface.__str__`.
    var displayName: String { get }

    /// Cumulative bytes received (inbound). Mirrors Python Interface.rxb.
    var rxBytes: Int { get }
    /// Cumulative bytes transmitted (outbound). Mirrors Python Interface.txb.
    var txBytes: Int { get }
    /// Cumulative packets received. Mirrors Python Interface.rxp.
    var rxPackets: Int { get }
    /// Cumulative packets transmitted. Mirrors Python Interface.txp.
    var txPackets: Int { get }

    /// Last received signal strength indicator in dBm, if available. Mirrors Python Interface.r_stat_rssi.
    var rssi: Float? { get }
    /// Last received signal-to-noise ratio in dB, if available. Mirrors Python Interface.r_stat_snr.
    var snr: Float? { get }
    /// Link quality 0–100 derived from SNR, if available. Mirrors Python Interface.r_stat_q.
    var quality: Float? { get }

    /// Physical (hardware) MTU of this interface in bytes, or nil if unknown.
    /// Mirrors Python's `Interface.HW_MTU`.
    var hwMtu: Int? { get }

    /// True when this interface can automatically negotiate a higher link MTU.
    /// Mirrors Python's `Interface.AUTOCONFIGURE_MTU`.
    var autoconfigureMtu: Bool { get }

    /// True when this interface has a fixed hardware MTU that cannot be exceeded.
    /// Mirrors Python's `Interface.FIXED_MTU`.
    var fixedMtu: Bool { get }

    /// Minimum time (seconds) between successive announces of the same destination.
    /// When nil, no rate limiting is applied. Mirrors Python's `Interface.announce_rate_target`.
    var announceRateTarget: TimeInterval? { get }
    /// Number of rate violations allowed before a destination is blocked.
    /// Mirrors Python's `Interface.announce_rate_grace`.
    var announceRateGrace: Int { get }
    /// Extra penalty (seconds) added to the block window on top of `announceRateTarget`.
    /// Mirrors Python's `Interface.announce_rate_penalty`.
    var announceRatePenalty: TimeInterval { get }

    /// Whether ingress burst limiting is enabled on this interface.
    /// Mirrors Python's `Interface.ingress_control` (default True).
    var ingressControl: Bool { get }

    /// Whether egress path-request limiting is enabled on this interface.
    /// Mirrors Python's `Interface.egress_control` (default False).
    var egressControl: Bool { get }

    /// Egress path-request frequency cap in Hz.
    /// Mirrors Python's `Interface.EC_PR_FREQ = 5`.
    var ecPrFreq: Double { get }

    /// Operating mode of this interface.
    /// Mirrors Python's `Interface.mode` (default `.full`).
    var mode: InterfaceMode { get }

    /// When this interface was created. Used to determine "new interface" vs established.
    /// Mirrors Python's `Interface.age()` computation.
    var createdAt: Date { get }

    /// Set to true before registering with Transport to request that a tunnel be synthesized
    /// for this interface. Transport will call `synthesizeTunnel` and then clear this flag.
    /// Mirrors Python's `Interface.wants_tunnel`.
    var wantsTunnel: Bool { get set }

    /// Set by Transport after a tunnel has been established for this interface.
    /// Mirrors Python's `Interface.tunnel_id`.
    var tunnelID: Data? { get set }

    /// When true, this interface is used only to bootstrap the path table on startup.
    /// Mirrors Python's `Interface.bootstrap_only`.
    var bootstrapOnly: Bool { get set }

    /// When true, a transport node searches for unknown paths on path requests
    /// received here regardless of this interface's `mode` (i.e. even when the
    /// mode isn't in `discoverPathsFor`). Mirrors Python's RNS 1.3.6
    /// `Interface.recursive_prs`. Defaults to `false`.
    var recursivePrs: Bool { get set }

    /// When false, a relayed announce whose next hop toward the source is an
    /// `internal`-mode interface is blocked from being broadcast on this
    /// interface. Mirrors Python's RNS 1.3.7 `Interface.announces_from_internal`.
    /// Defaults to `true`.
    var announcesFromInternal: Bool { get set }

    /// Called by Transport when an outbound packet is ready for the wire.
    func send(_ packet: Packet) throws

    /// Set by Transport when the interface is registered. The interface
    /// invokes this for every successfully-decoded inbound packet.
    var inboundHandler: ((Packet, any Interface) -> Void)? { get set }

    /// Set by Transport when IFAC is needed. When non-nil the interface
    /// delivers raw frame bytes here instead of parsing a Packet itself.
    /// Transport verifies the IFAC code and parses the packet internally.
    var rawInboundHandler: ((Data, any Interface) -> Void)? { get set }

    // MARK: - IFAC properties (optional — nil means no IFAC on this interface)

    /// Ed25519 identity derived from the network name / access key.
    var ifacIdentity: Identity? { get set }
    /// 64-byte HKDF-derived key used as the HKDF salt when generating masks.
    var ifacKey: Data? { get set }
    /// Number of bytes to take from the tail of an Ed25519 signature.
    var ifacSize: Int { get set }

    /// Whether Transport should route packets and forward announces through this interface.
    /// False for server/factory interfaces whose spawned clients are the real routing endpoints.
    /// Mirrors Python's per-spawned-client TCPServerInterfaceClient model.
    var isRoutingEndpoint: Bool { get }

    func start() throws
    func stop()
}

/// An interface that can front multiple locally-connected shared-instance
/// clients (rnstatus, nomadnet, MeshChatX, …). Mirrors Python's
/// `Transport.local_client_interfaces` — a list of one per-connection
/// `LocalClientInterface` spawned per accepted socket — collapsed here into
/// a single object per listening server (e.g. `PosixTCPServer`) since Swift
/// fans a whole accept-loop out from one `Interface`. `clientCount` is the
/// number of currently attached local clients; `Transport` only treats the
/// interface as "serving local clients" while this is greater than zero.
public protocol LocalClientServingInterface: Interface {
    var clientCount: Int { get }
}

/// Default implementations so existing interfaces don't need to add these.
public extension Interface {
    /// Default `displayName`: just `name`. Sufficient for interfaces that don't
    /// appear in rnstatus-style output; others override to match Python's `__str__`.
    var displayName: String { name }

    /// SHA-256 hash of the display name (as UTF-8 bytes).
    /// Mirrors Python's `Interface.get_hash()` = `SHA256(str(self).encode("utf-8"))`.
    var hash: Data { Hashes.fullHash(Data(displayName.utf8)) }

    /// Returns the SHA-256 hash of the display name.
    /// Explicit method form of the `hash` property.
    /// Mirrors Python's `Interface.get_hash()`.
    func getHash() -> Data { hash }

    /// Returns the interface bitrate in bits per second.
    /// Mirrors Python's `Interface.bitrate` direct attribute access.
    func getBitrate() -> Int { bitrate }

    /// Returns the interface mode (full, access-point, roaming, etc.).
    /// Mirrors Python's `Interface.mode` direct attribute access.
    func getMode() -> InterfaceMode { mode }

    var rxBytes: Int { 0 }
    var txBytes: Int { 0 }
    var rxPackets: Int { 0 }
    var txPackets: Int { 0 }

    // HW MTU — unknown by default
    var hwMtu: Int? { nil }
    var autoconfigureMtu: Bool { false }
    var fixedMtu: Bool { false }

    // Announce rate limiting — disabled by default (matches Python's None defaults).
    var announceRateTarget: TimeInterval? { nil }
    var announceRateGrace: Int { 0 }
    var announceRatePenalty: TimeInterval { 0 }

    // Ingress burst control — enabled by default, creation time = now.
    var ingressControl: Bool { true }
    // Egress PR control — disabled by default (matches Python's None/False defaults).
    var egressControl: Bool { false }
    var ecPrFreq: Double { 5.0 }
    // Interface mode — full by default.
    var mode: InterfaceMode { .full }
    var createdAt: Date { Date() }

    // Tunnel defaults — not a tunneled interface by default
    var wantsTunnel: Bool {
        get { false }
        set { }
    }
    var tunnelID: Data? {
        get { nil }
        set { }
    }
    var bootstrapOnly: Bool {
        get { false }
        set { }
    }
    var recursivePrs: Bool {
        get { false }
        set { }
    }
    var announcesFromInternal: Bool {
        get { true }
        set { }
    }

    var isRoutingEndpoint: Bool { true }

    // PHY stats — no radio hardware by default
    var rssi: Float? { nil }
    var snr: Float? { nil }
    var quality: Float? { nil }

    // IFAC defaults — no IFAC enabled (no-op storage for types that don't override)
    var rawInboundHandler: ((Data, any Interface) -> Void)? {
        get { nil }
        set { }
    }
    var ifacIdentity: Identity? {
        get { nil }
        set { }
    }
    var ifacKey: Data? {
        get { nil }
        set { }
    }
    var ifacSize: Int {
        get { Constants.defaultIfacSize }
        set { }
    }

    // MARK: - IFAC wrap / unwrap

    /// Wrap `raw` with an IFAC code and mask. Returns `raw` unchanged if
    /// this interface has no IFAC identity configured.
    ///
    /// Wire layout of the returned bytes (matches Python `Transport.transmit`):
    ///   [0]        header[0] ^ mask[0] | 0x80   (IFAC flag always set)
    ///   [1]        header[1] ^ mask[1]
    ///   [2..S+1]   IFAC code (S = ifacSize, not masked)
    ///   [S+2..]    raw[2..] ^ mask[S+2..]
    func wrapIfac(_ raw: Data) -> Data {
        guard let key = ifacKey, raw.count >= 2 else { return raw }

        // Python RNS verifies IFAC by re-signing and comparing, which requires
        // deterministic Ed25519 (the seed = last 32 bytes of the 64-byte ifacKey).
        // DeterministicEd25519 is wire-compatible with Python's pure25519 library.
        let sig  = DeterministicEd25519.sign(raw, seed: Data(key.suffix(32)))
        let ifac = sig.suffix(ifacSize)

        // mask length = len(new_raw) = len(raw) + ifacSize
        let maskLen = raw.count + ifacSize
        let mask = HKDF.derive(length: maskLen, derivedFrom: Data(ifac), salt: key)

        var out = Data(capacity: maskLen)
        // Header byte 0: set IFAC flag, then XOR with mask, then ensure flag stays set
        out.append((raw[0] | 0x80) ^ mask[0] | 0x80)
        // Header byte 1: XOR with mask
        out.append(raw[1] ^ mask[1])
        // IFAC code (positions 2 .. ifacSize+1): not masked
        out.append(contentsOf: ifac)
        // Payload (raw[2..]) at mask positions ifacSize+2..
        for i in 2 ..< raw.count {
            out.append(raw[i] ^ mask[ifacSize + i])
        }
        return out
    }

    /// Verify and strip the IFAC code from `raw`. Returns the original
    /// (pre-IFAC) packet bytes on success, or `nil` if verification fails
    /// or the IFAC flag state is inconsistent with this interface's config.
    func unwrapIfac(_ raw: Data) -> Data? {
        let hasIfacFlag = raw.count >= 1 && (raw[0] & 0x80) == 0x80

        guard let key = ifacKey else {
            // No IFAC on this interface — drop if IFAC flag is set.
            return hasIfacFlag ? nil : raw
        }

        guard hasIfacFlag else { return nil }
        guard raw.count > 2 + ifacSize else { return nil }

        let extractedIfac = Data(raw[2 ..< 2 + ifacSize])

        // mask length = len(raw) (the received bytes already include the IFAC code)
        let mask = HKDF.derive(length: raw.count, derivedFrom: extractedIfac, salt: key)

        var unmasked = Data(capacity: raw.count)
        for i in 0 ..< raw.count {
            if i <= 1 || i > ifacSize + 1 {
                unmasked.append(raw[i] ^ mask[i])
            } else {
                unmasked.append(raw[i])   // IFAC bytes — not unmasked
            }
        }

        // Unset IFAC flag in first header byte
        let h0: UInt8 = unmasked[0] & 0x7F
        // Reconstruct original packet: header + payload after IFAC
        var verified = Data(capacity: raw.count - ifacSize)
        verified.append(h0)
        verified.append(unmasked[1])
        verified.append(contentsOf: unmasked[(2 + ifacSize)...])

        // Recompute expected IFAC from the verified (IFAC-stripped) bytes.
        // Uses the same deterministic Ed25519 as wrapIfac.
        let expectedSig  = DeterministicEd25519.sign(verified, seed: Data(key.suffix(32)))
        let expectedIfac = Data(expectedSig.suffix(ifacSize))

        guard extractedIfac == expectedIfac else { return nil }
        return verified
    }
}
