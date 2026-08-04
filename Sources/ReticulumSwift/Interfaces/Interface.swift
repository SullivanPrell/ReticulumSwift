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

    /// Interface modes a *boundary*-mode interface is allowed to propagate
    /// recursive path requests onto. RNS 1.4.1 lets boundary interfaces search
    /// for unknown destinations, but only towards boundary and gateway peers —
    /// never back out over access-point/roaming/internal segments.
    /// Mirrors Python's `Interface.BOUNDARY_SEARCH_MODES`.
    public static let boundarySearchModes: Set<InterfaceMode> = [.boundary, .gateway]

    /// Gravity assigned to an interface that has no explicit configuration.
    /// Mirrors Python's `Interface.DEFAULT_GRAVITY = 0`.
    public static let defaultGravity: Int = 0

    /// Parse a config-file mode string, accepting every alias Python does
    /// (`Reticulum._config_interface_mode` / the `autoconnect_interface_mode`
    /// parser). Comparison is case-insensitive; returns `nil` for an
    /// unrecognised value so callers can leave their default in place, matching
    /// Python's `if v != None:` assignment guard.
    public init?(configName: String) {
        switch configName.trimmingCharacters(in: .whitespaces).lowercased() {
        case "full":                            self = .full
        case "access_point", "accesspoint", "ap": self = .accessPoint
        case "pointtopoint", "ptp":             self = .pointToPoint
        case "roaming":                         self = .roaming
        case "boundary":                        self = .boundary
        case "gateway", "gw":                   self = .gateway
        case "internal":                        self = .internal
        default:                                return nil
        }
    }
}

/// Base protocol every transport implementation conforms to.
///
/// Reticulum Interfaces speak in *whole packets*: the underlying medium
/// (TCP, UDP, BLE serial, RNode KISS) handles framing; the Interface
/// reports clean packet bytes upward via `inboundHandler`.
public protocol Interface: AnyObject {
    var name: String { get }

    /// Interface capacity in bits per second.
    ///
    /// Settable because Python assigns it per interface from config and copies it onto every
    /// spawned sub-interface (`Reticulum.py:1115`, `TCPInterface.py:594-641`). Each conformer
    /// stores its own so that types deriving a bitrate from radio parameters keep that
    /// derivation as their starting value. See `swift_devel/bugs/025-*.md`.
    var bitrate: Int { get set }

    var isOnline: Bool { get }

    /// Per-interface mutable configuration — mode, announce rate control, ingress/egress
    /// control and the `ic_*` tunables.
    ///
    /// One stored property is the entire requirement; `Interface`'s extension forwards each
    /// individual attribute to it. This exists because Python mutates all of these at runtime
    /// while this port declared them `{ get }`-only, leaving a parsed config value nowhere to
    /// be written (`swift_devel/bugs/025-*.md`). Declare it in a conformer as:
    ///
    /// ```swift
    /// public let interfaceState = InterfaceState()
    /// ```
    var interfaceState: InterfaceState { get }

    /// Human-readable display name matching Python's `str(interface)` format,
    /// e.g. `"AutoInterface[local]"`, `"TCPClientInterface[...]"`.
    /// Declared as a protocol requirement (rather than left to the extension)
    /// so that `hash`/`getHash()` dispatch dynamically to overrides — a plain
    /// extension member here would be statically dispatched and always resolve
    /// to the default, silently hashing `name` instead of the type-qualified string.
    /// Mirrors Python's `Interface.__str__`.
    var displayName: String { get }

    /// The class name a Python peer expects to see for this interface, as reported in the
    /// `type` field of the interface-stats payload (Python: `type(interface).__name__`).
    ///
    /// Declared here, rather than left to reflection over the Swift type, because a handful
    /// of Swift classes are named differently from their Python counterparts. `rnstatus -d`
    /// prints this string, and Reticulum's own config reconstruction branches on it, so a
    /// Swift-only name reaches Python consumers as an interface kind they do not recognise.
    var statsTypeName: String { get }

    /// The `short_name` reported in the interface-stats payload (Python:
    /// `str(interface.name)`). Overridden only where Python hardcodes a name that differs
    /// from the one Swift uses internally to identify the interface.
    var statsShortName: String { get }

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

    /// Fraction of interface capacity announces may consume (e.g. `0.02` for 2%).
    /// Mirrors Python's `Interface.announce_cap`, assigned from config at
    /// `Reticulum.py:834-837` / `:912` where the config value is a percentage in `(0, 100]`.
    var announceCap: Double { get set }

    /// Minimum time (seconds) between successive announces of the same destination.
    /// When nil, no rate limiting is applied. Mirrors Python's `Interface.announce_rate_target`.
    var announceRateTarget: TimeInterval? { get set }
    /// Number of rate violations allowed before a destination is blocked.
    /// Mirrors Python's `Interface.announce_rate_grace`.
    var announceRateGrace: Int { get set }
    /// Extra penalty (seconds) added to the block window on top of `announceRateTarget`.
    /// Mirrors Python's `Interface.announce_rate_penalty`.
    var announceRatePenalty: TimeInterval { get set }

    /// Whether ingress burst limiting is enabled on this interface.
    /// Mirrors Python's `Interface.ingress_control` (default True).
    var ingressControl: Bool { get set }

    /// Whether egress path-request limiting is enabled on this interface.
    /// Mirrors Python's `Interface.egress_control` (default False).
    var egressControl: Bool { get set }

    /// Egress path-request frequency cap in Hz.
    /// Mirrors Python's `Interface.EC_PR_FREQ = 5`.
    var ecPrFreq: Double { get set }

    /// Operating mode of this interface.
    /// Mirrors Python's `Interface.mode` (default `.full`), assigned at `Reticulum.py:910`.
    var mode: InterfaceMode { get set }

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

    /// The IFAC segment this interface is on, from the block's `networkname` / `network_name`.
    /// Mirrors Python's `Interface.ifac_netname` (`Reticulum.py:955`); `rnstatus` reports it.
    var ifacNetname: String? { get set }

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

    /// When `true`, announces whose next hop toward the source is *this*
    /// interface are always allowed onto `internal`-mode interfaces, even when
    /// this interface is in `boundary` mode (which would otherwise block them).
    /// `nil` means "not configured" and behaves like `false`.
    /// Mirrors Python's RNS 1.4.1 `Interface.announces_to_internal` (default `None`).
    var announcesToInternal: Bool? { get set }

    /// Routing preference weight for this interface. When two announces for the
    /// same destination carry the *same* emission timebase, the one received on
    /// the interface with the higher gravity wins the path-table entry. Higher
    /// pulls harder. Mirrors Python's RNS 1.4.1 `Interface.gravity` (default 0).
    var gravity: Int { get set }

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

/// An interface whose hardware MTU follows its bitrate — Python's `AUTOCONFIGURE_MTU = True`
/// classes, where `optimise_mtu()` writes `HW_MTU` at runtime (`Interface.py:205-217`).
///
/// Adopted by exactly the types whose Python counterparts set the flag (TCP client/server and
/// their spawned clients, Backbone, both Local classes). The base protocol keeps `hwMtu` as
/// `{ get }` because the radio and datagram families genuinely never mutate it; the audit's
/// structural lesson is that a runtime-*written* Python attribute must not be ported `{ get }`-
/// only, and this conformance is where the setter lives. `OptimiseMtuTests`' structural guard
/// fails any type that claims `autoconfigureMtu` without adopting it.
public protocol MtuAutoconfiguringInterface: Interface {
    var hwMtu: Int? { get set }
}

/// The `optimise_mtu()` bitrate → `HW_MTU` ladder, verbatim from `Interface.py:207-217`.
/// One implementation shared by every caller, so no interface can carry its own drifted copy.
public enum RNSInterfaceMtu {
    public static func optimised(forBitrate bitrate: Int) -> Int? {
        if bitrate >= 1_000_000_000 { return 524_288 }   // the one inclusive rung (`:207`)
        else if bitrate > 750_000_000 { return 262_144 }
        else if bitrate > 400_000_000 { return 131_072 }
        else if bitrate > 200_000_000 { return 65_536 }
        else if bitrate > 100_000_000 { return 32_768 }
        else if bitrate > 10_000_000 { return 16_384 }
        else if bitrate > 5_000_000 { return 8_192 }
        else if bitrate > 2_000_000 { return 4_096 }
        else if bitrate > 1_000_000 { return 2_048 }
        else if bitrate > 62_500 { return 1_024 }
        else { return nil }                              // `else: self.HW_MTU = None`
    }
}

/// Default implementations so existing interfaces don't need to add these.
public extension Interface {

    /// Python `Interface.optimise_mtu()`. Called unconditionally after the configured bitrate
    /// lands (`Reticulum.py:914-915`) and on spawned server-side clients after the bitrate copy
    /// (`TCPInterface.py:612-613`); the write is gated on `AUTOCONFIGURE_MTU`, so fixed-MTU
    /// interfaces keep their class value and this is safe to call on every interface.
    func optimiseMtu() {
        guard autoconfigureMtu else { return }
        guard let mutable = self as? MtuAutoconfiguringInterface else {
            // A type-level contradiction, not a runtime condition: the claim is inert without
            // the setter, which is the `{ get }`-only freeze this seam exists to prevent.
            Reticulum.log("\(displayName) claims autoconfigureMtu but has no settable hwMtu — "
                          + "its MTU cannot follow its bitrate", level: .error)
            return
        }
        mutable.hwMtu = RNSInterfaceMtu.optimised(forBitrate: bitrate)
        // Python logs the outcome for every interface at LOG_PATHING (`Interface.py:219`).
        Reticulum.log("\(displayName) hardware MTU set to \(String(describing: mutable.hwMtu))",
                      level: .pathing)
    }
    /// Default `displayName`: the class-qualified form `"Class[name]"`, which is what Python's
    /// `__str__` returns for every interface whose reference string carries no peer address —
    /// `SerialInterface[…]` (`SerialInterface.py:226-227`), `KISSInterface[…]` (`:387-388`),
    /// `AX25KISSInterface[…]` (`:400-401`), `RNodeInterface[…]` (`:1247-1248`),
    /// `RNodeMultiInterface[…]` (`:923-924`), `I2PInterface[…]` (`:890`),
    /// `I2PInterfacePeer[…]` (`:713-714`), `AutoInterface[…]` (`:609`),
    /// `WeaveInterface[…]` (`:1005-1006`).
    ///
    /// It composes `statsTypeName`, which is already the RNS class name, so a new interface type
    /// gets the correct shape by declaring nothing. **The previous default was the bare `name`**,
    /// and that is why `bugs/022` exists: 1.7.0 fixed the nine wrong publishers by adding
    /// overrides to the TCP and UDP families only, and every type it did not touch kept silently
    /// inheriting a name that is neither the identity Python computes
    /// (`hash` is `fullHash(displayName)`) nor a string `rnstatus`' class-prefix filters match.
    /// Composing here rather than overriding per file is the seam: the tenth interface type
    /// cannot repeat it.
    ///
    /// Override only where the reference string is genuinely a different shape — a peer address
    /// in the tail (`TCPInterface[name/ip:port]`), a form that ignores `name`
    /// (`LocalInterface[port]`, `Shared Instance[port]`), or one derived from a parent or peer
    /// address (`RNodeSubInterface`, `WeaveInterfacePeer`). `InterfaceDisplayNameTests` asserts
    /// the resulting string for every conformer against the reference form.
    var displayName: String { "\(statsTypeName)[\(name)]" }

    /// Default: the Swift type's own name, which is what most interfaces are called in
    /// Python too (`UDPInterface`, `TCPClientInterface`, `RNodeInterface`, …).
    var statsTypeName: String { String(describing: type(of: self)) }

    /// Default: the interface's own `name`, matching Python's `str(interface.name)`.
    var statsShortName: String { name }

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

    /// Default `interfaceState` for conformers that do not declare their own.
    ///
    /// Every interface this library ships declares `public let interfaceState = InterfaceState()`,
    /// which is the intended form. This default keeps the protocol adoptable by conformers defined
    /// elsewhere, and still yields genuine per-instance state — see
    /// `InterfaceState.FallbackStorage`.
    var interfaceState: InterfaceState {
        InterfaceState.fallbackStorage.state(for: self)
    }

    // MARK: - Mutable configuration, forwarded to `interfaceState`
    //
    // These were `{ get }`-only requirements with blanket defaults (announce rates, ingress and
    // egress control, mode) or `{ get set }` requirements with `set { }` no-op defaults that
    // silently discarded the write (the tunnel and announce-propagation flags below). Both shapes
    // meant a parsed config value had nowhere to go. Every one now forwards to the per-interface
    // state box, so a conformer needs one stored property and gets the whole set. Defaults live in
    // `InterfaceState` and match Python's. See `swift_devel/bugs/025-*.md`.

    var announceCap: Double {
        get { interfaceState.announceCap }
        set { interfaceState.announceCap = newValue }
    }
    var announceRateTarget: TimeInterval? {
        get { interfaceState.announceRateTarget }
        set { interfaceState.announceRateTarget = newValue }
    }
    var announceRateGrace: Int {
        get { interfaceState.announceRateGrace }
        set { interfaceState.announceRateGrace = newValue }
    }
    var announceRatePenalty: TimeInterval {
        get { interfaceState.announceRatePenalty }
        set { interfaceState.announceRatePenalty = newValue }
    }

    var ingressControl: Bool {
        get { interfaceState.ingressControl }
        set { interfaceState.ingressControl = newValue }
    }
    var egressControl: Bool {
        get { interfaceState.egressControl }
        set { interfaceState.egressControl = newValue }
    }
    var ecPrFreq: Double {
        get { interfaceState.ecPrFreq }
        set { interfaceState.ecPrFreq = newValue }
    }

    var mode: InterfaceMode {
        get { interfaceState.mode }
        set { interfaceState.mode = newValue }
    }

    var createdAt: Date { Date() }

    var wantsTunnel: Bool {
        get { interfaceState.wantsTunnel }
        set { interfaceState.wantsTunnel = newValue }
    }
    var tunnelID: Data? {
        get { interfaceState.tunnelID }
        set { interfaceState.tunnelID = newValue }
    }
    var bootstrapOnly: Bool {
        get { interfaceState.bootstrapOnly }
        set { interfaceState.bootstrapOnly = newValue }
    }
    var ifacNetname: String? {
        get { interfaceState.ifacNetname }
        set { interfaceState.ifacNetname = newValue }
    }
    var recursivePrs: Bool {
        get { interfaceState.recursivePrs }
        set { interfaceState.recursivePrs = newValue }
    }
    var announcesFromInternal: Bool {
        get { interfaceState.announcesFromInternal }
        set { interfaceState.announcesFromInternal = newValue }
    }
    var announcesToInternal: Bool? {
        get { interfaceState.announcesToInternal }
        set { interfaceState.announcesToInternal = newValue }
    }
    /// Mirrors Python's `Interface.gravity` (`DEFAULT_GRAVITY = 0`).
    var gravity: Int {
        get { interfaceState.gravity }
        set { interfaceState.gravity = newValue }
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
