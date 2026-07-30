import Foundation

/// Parsed representation of a Reticulum configuration file.
///
/// The format is the Python `configobj`-style INI used by RNS:
/// ```
/// [reticulum]
/// enable_transport = False
///
/// [logging]
/// loglevel = 4
///
/// [interfaces]
///   [[My TCP Interface]]
///     type = TCPClientInterface
///     target_host = example.com
///     target_port = 4242
///     enabled = Yes
/// ```
public struct ReticulumConfig {

    // MARK: - Top-level sections

    public var reticulum: ReticulumSection = .init()
    public var logging: LoggingSection = .init()
    public var interfaces: [InterfaceConfig] = []

    /// `"<section>.<key>"` for every key in a recognised top-level section that no branch
    /// matched — i.e. every key this parser silently discarded.
    ///
    /// `bugs/030`. The parser's `default: break` is invisible from the outside: a key it does
    /// not know is indistinguishable from a key it read and applied, which is how the port
    /// shipped an example config advertising four controls it ignores. Recording them makes
    /// "the parser reads this key" an assertable fact rather than an assumption, and gives a
    /// daemon something to warn about when an operator misspells a directive.
    ///
    /// Interface subsections are not included: they keep every key verbatim in
    /// ``InterfaceConfig/parameters``, so nothing is discarded at parse time there.
    public private(set) var unrecognisedKeys: [String] = []

    // MARK: - [reticulum] section

    public struct ReticulumSection {
        public var enableTransport: Bool = false
        /// When true, a non-transport node keeps using its persistent identity
        /// as the transport identity instead of a fresh ephemeral one.
        /// Mirrors Python's `static_transport_identity = No` (RNS 1.3.7).
        public var staticTransportIdentity: Bool = false
        /// When true, this instance obfuscates the hop count of packets that
        /// originate locally (its own traffic and directly-connected local
        /// clients) by replacing `hops == 0` with a random per-session delta
        /// when injecting them into the wider network. Privacy hardening for
        /// shared/transport instances. Mirrors Python's `local_hops_delta = No`.
        public var localHopsDelta: Bool = false
        public var shareInstance: Bool = true
        /// TCP port the shared instance serves local clients on.
        /// Mirrors Python's `shared_instance_port = 37428`.
        public var sharedInstancePort: UInt16 = 37428
        /// TCP port the shared instance answers management RPC on.
        /// Mirrors Python's `instance_control_port = 37429`.
        public var instanceControlPort: UInt16 = 37429
        public var panicOnInterfaceError: Bool = false
        /// Whether the probe destination is enabled.
        /// Mirrors Python's `allow_probes = True`.
        public var allowProbes: Bool = false
        /// Whether remote management is enabled.
        /// Mirrors Python's `enable_remote_management = True`.
        public var remoteManagementEnabled: Bool = false
        /// Identities allowed to access remote management.
        /// Mirrors Python's `remote_management_allowed = <hex>`.
        public var remoteManagementAllowed: [Identity] = []
        /// Whether to start listening for on-network interface discovery announces.
        /// Mirrors Python's `discover_interfaces = No`. Defaults to `false`.
        public var discoverInterfaces: Bool = false
        /// Trusted source identity hashes for the blackhole list updater.
        /// Mirrors Python's `blackhole_sources = <hex>, <hex>, ...`. Defaults to `[]`.
        public var blackholeSources: [Data] = []
        /// Blackhole list re-fetch interval, in seconds. Config value is in
        /// minutes (minimum 2 → 120 s). `nil` means use the default 3600 s.
        /// Mirrors Python's `blackhole_update_interval = <minutes>` config key
        /// (RNS commit 02924656).
        public var blackholeUpdateInterval: TimeInterval? = nil
        /// Minimum PoW stamp value required to accept a discovery announce.
        /// `nil` means use `Reticulum.requiredDiscoveryValue()` default (14).
        /// Mirrors Python's `required_discovery_value`. Positive → override; 0 or missing → nil.
        public var requiredDiscoveryValue: Int? = nil
        /// Whether to publish this node's blackhole list to the network.
        /// Mirrors Python's `publish_blackhole = No`. Defaults to `false`.
        public var publishBlackholeEnabled: Bool = false
        /// Trusted source identity hashes for interface discovery announce filtering.
        /// Mirrors Python's `interface_discovery_sources`. Defaults to `[]`.
        public var interfaceDiscoverySources: [Data] = []
        /// Maximum number of discovered interfaces to auto-connect.
        /// 0 (default) means auto-connect is disabled.
        /// Mirrors Python's `autoconnect_discovered_interfaces`. Positive → enabled.
        public var autoconnectDiscoveredInterfaces: Int = 0
        /// Gravity applied to interfaces that don't set `gravity` themselves.
        /// `nil` falls back to `InterfaceMode.defaultGravity` (0).
        /// Mirrors Python's `default_gravity` (RNS 1.4.1).
        public var defaultGravity: Int? = nil
        /// Interface mode assigned to auto-connected discovered interfaces.
        /// `nil` keeps Python's default of `.gateway` when transport is enabled,
        /// and no mode at all otherwise.
        /// Mirrors Python's `autoconnect_interface_mode` (RNS 1.4.1).
        public var autoconnectInterfaceMode: InterfaceMode? = nil
        /// Gravity assigned to auto-connected discovered interfaces. `nil` uses
        /// Python's `InterfaceDiscovery.AC_GRAVITY` (0).
        /// Mirrors Python's `autoconnect_interface_gravity` (RNS 1.4.1).
        public var autoconnectInterfaceGravity: Int? = nil
        /// `announces_to_internal` assigned to auto-connected discovered
        /// interfaces. `nil` means unset, matching Python's `None`.
        /// Mirrors Python's `autoconnect_announces_to_internal` (RNS 1.4.1).
        public var autoconnectAnnouncesToInternal: Bool? = nil

        // MARK: - `bugs/030` — the rest of the section
        //
        // Everything below was emitted by this port's own config templates, or read by the
        // reference, and parsed by nothing. Each is `nil` when the key is absent, so an
        // unconfigured option keeps the built-in default rather than overwriting it with a zero
        // — which is how Python's `if option ==` chain behaves.

        /// Shared-instance RPC authentication key, as raw bytes.
        /// Mirrors Python's `rpc_key` (`Reticulum.py:494-499`), specified in hexadecimal.
        /// `nil` when absent **or malformed**: Python logs and falls back to the derived key.
        public var rpcKey: Data? = nil
        /// Whether an `rpc_key` was present at all, so a malformed value stays distinguishable
        /// from an absent one. Both fall back to the derived key, but only one of them is an
        /// operator mistake worth reporting.
        public var rpcKeySpecified: Bool = false
        /// Distinguishes multiple shared instances on one host.
        /// Mirrors Python's `instance_name` (`Reticulum.py:475-478`), which uses it as the
        /// domain-socket path component. `nil` means Python's `"default"`.
        public var instanceName: String? = nil
        /// `"tcp"` or `"unix"`; anything else is ignored, as in Python
        /// (`Reticulum.py:479-484`). `nil` means unset, letting the platform decide.
        public var sharedInstanceType: String? = nil
        /// Path to the shared network identity file, created if absent.
        /// Mirrors Python's `network_identity` (`Reticulum.py:513-534`).
        public var networkIdentityPath: String? = nil
        /// Mirrors Python's `use_implicit_proof` (`Reticulum.py:568-571`), which assigns both
        /// directions. `nil` keeps the default of `true`.
        public var useImplicitProof: Bool? = nil
        /// Mirrors Python's `link_mtu_discovery` (`Reticulum.py:537-539`). `nil` keeps the
        /// default of `true`.
        public var linkMtuDiscovery: Bool? = nil
        /// Overrides the bitrate reported by the shared-instance interface.
        /// Mirrors Python's `force_shared_instance_bitrate` (`Reticulum.py:560-562`).
        public var forceSharedInstanceBitrate: Int? = nil

        /// Announce-rate defaults applied to any interface that does not set its own, and only
        /// when transport is enabled (`Reticulum.py:854-857`, accessors at `:1146-1152`).
        /// Python maps a configured `0` target to "no target" (`:643-645`).
        public var defaultArTarget: Int? = nil
        public var defaultArPenalty: Int? = nil
        public var defaultArGrace: Int? = nil

        /// Egress-control defaults every interface starts from
        /// (`Interface.py:135-136`, accessors at `Reticulum.py:1173-1176`).
        public var egressControl: Bool? = nil
        public var ecPrFreq: Double? = nil

        /// Ingress-control defaults every interface starts from (`Interface.py:126-134`,
        /// accessors at `Reticulum.py:1154-1185`). A per-interface block still overrides them.
        public var icMaxHeldAnnounces: Int? = nil
        public var icBurstHold: Double? = nil
        public var icBurstFreqNew: Double? = nil
        public var icBurstFreq: Double? = nil
        public var icPrBurstFreqNew: Double? = nil
        public var icPrBurstFreq: Double? = nil
        public var icNewTime: Double? = nil
        public var icBurstPenalty: Double? = nil
        public var icHeldReleaseInterval: Double? = nil
    }

    // MARK: - [logging] section

    public struct LoggingSection {
        /// 0=critical … 7=extreme. Matches Python's `loglevel`.
        public var logLevel: Int = 4
        /// Whether to prepend timestamps to log lines. Mirrors Python's `logtimestamps`.
        public var logTimestamps: Bool = true
    }

    // MARK: - [[Interface]] subsections

    public struct InterfaceConfig {
        public var name: String
        public var type: String
        public var enabled: Bool
        /// All raw key-value pairs from the subsection (for type-specific
        /// parameters like `target_host`, `target_port`, etc.).
        public var parameters: [String: String]

        /// Explicit rather than relying on the memberwise initialiser, which a `public struct`
        /// only exposes internally.
        ///
        /// A caller outside this module needs to build one: `Reticulum
        /// .applyInterfaceConfiguration(to:from:)` and `applyIfacConfiguration(to:from:)` take a
        /// block, and the interfaces RetiOS constructs in code have no config file to come from —
        /// so without this they could not reach the parser at all, which is the shape of
        /// `bugs/015` (the API exists; nothing outside can call it).
        public init(name: String, type: String, enabled: Bool, parameters: [String: String]) {
            self.name = name
            self.type = type
            self.enabled = enabled
            self.parameters = parameters
        }

        public subscript(_ key: String) -> String? { parameters[key] }
        public func int(_ key: String) -> Int? { parameters[key].flatMap(Int.init) }
        public func bool(_ key: String) -> Bool? { parameters[key].flatMap(parseBool) }
        /// Python's `c.as_float(key)`. Used by the `ic_*` / `ec_pr_freq` family, all of which
        /// Python reads as floats (`Reticulum.py:791-813`).
        public func double(_ key: String) -> Double? { parameters[key].flatMap(Double.init) }
    }

    // MARK: - Parsing

    /// Parse a config file at `url`. Returns `nil` if the file cannot be read.
    public static func load(from url: URL) -> ReticulumConfig? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Parse a config string. Returns a config with defaults if `text` is empty.
    public static func parse(_ text: String) -> ReticulumConfig {
        var cfg = ReticulumConfig()
        var currentSection: String? = nil
        var currentInterface: [String: String] = [:]
        var currentIfaceName: String? = nil

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine
                .components(separatedBy: "#").first!   // strip inline comments
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // [[Interface subsection]]
            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                // Flush previous interface.
                if let name = currentIfaceName {
                    let enabled = resolveEnabled(currentInterface)
                    let type_ = currentInterface["type"] ?? "Unknown"
                    var params = currentInterface
                    params.removeValue(forKey: "type")
                    params.removeValue(forKey: "enabled")
                    params.removeValue(forKey: "interface_enabled")
                    cfg.interfaces.append(InterfaceConfig(
                        name: name, type: type_, enabled: enabled, parameters: params
                    ))
                }
                currentIfaceName = String(line.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: .whitespaces)
                currentInterface = [:]
                continue
            }

            // [Top-level section]
            if line.hasPrefix("[") && line.hasSuffix("]") {
                // Flush pending interface if we're leaving [interfaces].
                if currentSection == "interfaces", let name = currentIfaceName {
                    let enabled = resolveEnabled(currentInterface)
                    let type_ = currentInterface["type"] ?? "Unknown"
                    var params = currentInterface
                    params.removeValue(forKey: "type")
                    params.removeValue(forKey: "enabled")
                    params.removeValue(forKey: "interface_enabled")
                    cfg.interfaces.append(InterfaceConfig(
                        name: name, type: type_, enabled: enabled, parameters: params
                    ))
                    currentIfaceName = nil
                    currentInterface = [:]
                }
                currentSection = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            // key = value
            guard let eqRange = line.range(of: "=") else { continue }
            let key = String(line[line.startIndex..<eqRange.lowerBound])
                .trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[eqRange.upperBound...])
                .trimmingCharacters(in: .whitespaces)

            switch currentSection {
            case "reticulum":
                switch key {
                case "enable_transport":
                    cfg.reticulum.enableTransport = parseBool(value) ?? false
                case "static_transport_identity":
                    cfg.reticulum.staticTransportIdentity = parseBool(value) ?? false
                case "local_hops_delta":
                    cfg.reticulum.localHopsDelta = parseBool(value) ?? false
                case "share_instance":
                    cfg.reticulum.shareInstance = parseBool(value) ?? true
                case "shared_instance_port":
                    if let port = UInt16(value.trimmingCharacters(in: .whitespaces)) {
                        cfg.reticulum.sharedInstancePort = port
                    }
                case "instance_control_port":
                    if let port = UInt16(value.trimmingCharacters(in: .whitespaces)) {
                        cfg.reticulum.instanceControlPort = port
                    }
                case "panic_on_interface_error":
                    cfg.reticulum.panicOnInterfaceError = parseBool(value) ?? false
                // Python's spelling is `respond_to_probes` (Reticulum.py:550-552), which is
                // also the key documented in the example config; `allow_probes` is this
                // port's older name. Both are accepted.
                case "allow_probes", "respond_to_probes":
                    cfg.reticulum.allowProbes = parseBool(value) ?? false
                case "enable_remote_management":
                    cfg.reticulum.remoteManagementEnabled = parseBool(value) ?? false
                case "remote_management_allowed":
                    // Comma-separated list of hex identity hashes.
                    for hexHash in value.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                        if hexHash.count == 32,
                           let hashData = Data(hex: hexHash),
                           let identity = Identity.recall(destinationHash: hashData) {
                            cfg.reticulum.remoteManagementAllowed.append(identity)
                        }
                    }
                case "discover_interfaces":
                    cfg.reticulum.discoverInterfaces = parseBool(value) ?? false
                case "blackhole_sources":
                    // Comma-separated list of 32-hex-char (16-byte) truncated identity hashes.
                    for hexHash in value.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                        guard hexHash.count == 32, let hashData = Data(hex: hexHash) else { continue }
                        cfg.reticulum.blackholeSources.append(hashData)
                    }
                case "required_discovery_value":
                    // Python: if v > 0: set; else set to None.
                    if let n = Int(value), n > 0 { cfg.reticulum.requiredDiscoveryValue = n }
                    else { cfg.reticulum.requiredDiscoveryValue = nil }
                case "publish_blackhole":
                    cfg.reticulum.publishBlackholeEnabled = parseBool(value) ?? false
                case "blackhole_update_interval":
                    // Python: value is in minutes; minimum 2; stored as seconds.
                    if let mins = Double(value) {
                        let m = mins < 2 ? 2 : mins
                        cfg.reticulum.blackholeUpdateInterval = m * 60
                    }
                case "interface_discovery_sources":
                    for hexHash in value.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                        guard hexHash.count == 32, let hashData = Data(hex: hexHash) else { continue }
                        cfg.reticulum.interfaceDiscoverySources.append(hashData)
                    }
                case "autoconnect_discovered_interfaces":
                    // Python: if v > 0: set (so 0 is a no-op, preserving default of 0)
                    if let n = Int(value), n > 0 { cfg.reticulum.autoconnectDiscoveredInterfaces = n }
                case "default_gravity":
                    // Python assigns unconditionally (`as_int`), so 0 and
                    // negatives are honoured, not treated as "unset".
                    if let n = Int(value) { cfg.reticulum.defaultGravity = n }
                case "autoconnect_interface_mode":
                    // Python only assigns when the string matched a known mode,
                    // so an unrecognised value leaves the default in place.
                    if let m = InterfaceMode(configName: value) {
                        cfg.reticulum.autoconnectInterfaceMode = m
                    }
                case "autoconnect_interface_gravity":
                    if let n = Int(value) { cfg.reticulum.autoconnectInterfaceGravity = n }
                case "autoconnect_announces_to_internal":
                    if let b = parseBool(value), b { cfg.reticulum.autoconnectAnnouncesToInternal = true }

                // MARK: `bugs/030` — keys the templates advertised and nothing read

                case "rpc_key":
                    // Python logs and falls back to the derived key on a malformed value
                    // (`Reticulum.py:494-499`); `nil` here is that fallback.
                    cfg.reticulum.rpcKeySpecified = true
                    cfg.reticulum.rpcKey = Data(hex: value)
                case "instance_name":
                    if !value.isEmpty { cfg.reticulum.instanceName = value }
                case "shared_instance_type":
                    // Python accepts only these two and ignores anything else (`:479-484`).
                    let lowered = value.lowercased()
                    if lowered == "tcp" || lowered == "unix" {
                        cfg.reticulum.sharedInstanceType = lowered
                    }
                case "network_identity":
                    if !value.isEmpty { cfg.reticulum.networkIdentityPath = value }
                case "use_implicit_proof":
                    if let b = parseBool(value) { cfg.reticulum.useImplicitProof = b }
                case "link_mtu_discovery":
                    // Divergence from the reference, recorded rather than replicated: Python
                    // assigns only on `True` (`Reticulum.py:537-539`) against a class default of
                    // `LINK_MTU_DISCOVERY = True` (`:105`), so `link_mtu_discovery = no` cannot
                    // disable anything there. Every neighbouring option in the same chain
                    // (`use_implicit_proof`, `discover_interfaces`, `publish_blackhole`) assigns
                    // both directions, so this reads as a slip rather than a decision — and the
                    // `interface-configuration` spec requires the key to be able to disable
                    // discovery. Honoured both ways here. Purely local policy: declining to raise
                    // a link's MTU is a case the negotiation already handles, so no peer can tell
                    // this apart from a node that simply did not offer a larger MTU.
                    if let b = parseBool(value) { cfg.reticulum.linkMtuDiscovery = b }
                case "force_shared_instance_bitrate":
                    if let n = Int(value) { cfg.reticulum.forceSharedInstanceBitrate = n }

                // Announce-rate defaults. Python: target `0` means "none", `> 0` sets;
                // penalty and grace accept `>= 0` (`Reticulum.py:642-653`).
                case "default_ar_target":
                    if let n = Int(value) { cfg.reticulum.defaultArTarget = n > 0 ? n : nil }
                case "default_ar_penalty":
                    if let n = Int(value), n >= 0 { cfg.reticulum.defaultArPenalty = n }
                case "default_ar_grace":
                    if let n = Int(value), n >= 0 { cfg.reticulum.defaultArGrace = n }

                // Egress and ingress control defaults (`Reticulum.py:655-697`). Each guards on
                // `>= 0`, so a negative value leaves the class constant in place.
                case "egress_control":
                    if let b = parseBool(value) { cfg.reticulum.egressControl = b }
                case "ec_pr_freq":
                    if let v = Double(value), v >= 0 { cfg.reticulum.ecPrFreq = v }
                case "ic_max_held_announces":
                    if let n = Int(value), n >= 0 { cfg.reticulum.icMaxHeldAnnounces = n }
                case "ic_burst_hold":
                    if let v = Double(value), v >= 0 { cfg.reticulum.icBurstHold = v }
                case "ic_burst_freq_new":
                    if let v = Double(value), v >= 0 { cfg.reticulum.icBurstFreqNew = v }
                case "ic_burst_freq":
                    if let v = Double(value), v >= 0 { cfg.reticulum.icBurstFreq = v }
                case "ic_pr_burst_freq_new":
                    if let v = Double(value), v >= 0 { cfg.reticulum.icPrBurstFreqNew = v }
                case "ic_pr_burst_freq":
                    if let v = Double(value), v >= 0 { cfg.reticulum.icPrBurstFreq = v }
                case "ic_new_time":
                    if let v = Double(value), v >= 0 { cfg.reticulum.icNewTime = v }
                case "ic_burst_penalty":
                    if let v = Double(value), v >= 0 { cfg.reticulum.icBurstPenalty = v }
                case "ic_held_release_interval":
                    if let v = Double(value), v >= 0 { cfg.reticulum.icHeldReleaseInterval = v }

                default:
                    cfg.unrecognisedKeys.append("reticulum.\(key)")
                }
            case "logging":
                switch key {
                case "loglevel":      if let n = Int(value) { cfg.logging.logLevel = n }
                case "logtimestamps": if let b = parseBool(value) { cfg.logging.logTimestamps = b }
                default:
                    cfg.unrecognisedKeys.append("logging.\(key)")
                }
            case "interfaces":
                if currentIfaceName != nil { currentInterface[key] = value }
            default: break
            }
        }

        // Flush last interface.
        if let name = currentIfaceName {
            let enabled = resolveEnabled(currentInterface)
            let type_ = currentInterface["type"] ?? "Unknown"
            var params = currentInterface
            params.removeValue(forKey: "type")
            params.removeValue(forKey: "enabled")
            params.removeValue(forKey: "interface_enabled")
            cfg.interfaces.append(InterfaceConfig(
                name: name, type: type_, enabled: enabled, parameters: params
            ))
        }
        return cfg
    }

    // MARK: - Default config text

    /// The default configuration file content, written when no config exists.
    ///
    /// Python: `RNS/Reticulum.py:1818+`, `__default_rns_config__` — written by
    /// `__create_default_config()` on a first run. The byte-exact transcription lives in
    /// ``RNSConfigTemplates/defaultConfig``, next to its SHA-256 regression test.
    /// Previously this was a 17-line abridgement, so a config directory created by
    /// ReticulumSwift looked nothing like one created by Python RNS.
    public static let defaultConfigText = RNSConfigTemplates.defaultConfig
}

// MARK: - Helpers

/// Mirrors Python Reticulum line 928:
/// enabled if `interface_enabled == true` OR `enabled == true`; defaults to true if neither key present.
private func resolveEnabled(_ kv: [String: String]) -> Bool {
    if let v = kv["interface_enabled"], let b = parseBool(v) { return b }
    if let v = kv["enabled"],           let b = parseBool(v) { return b }
    return true
}

private func parseBool(_ s: String) -> Bool? {
    switch s.trimmingCharacters(in: .whitespaces).lowercased() {
    case "yes", "true", "1", "on":  return true
    case "no", "false", "0", "off": return false
    default: return nil
    }
}
