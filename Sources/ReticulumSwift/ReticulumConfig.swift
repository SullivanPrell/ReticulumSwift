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

    // MARK: - [reticulum] section

    public struct ReticulumSection {
        public var enableTransport: Bool = false
        public var shareInstance: Bool = true
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

        public subscript(_ key: String) -> String? { parameters[key] }
        public func int(_ key: String) -> Int? { parameters[key].flatMap(Int.init) }
        public func bool(_ key: String) -> Bool? { parameters[key].flatMap(parseBool) }
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
                case "share_instance":
                    cfg.reticulum.shareInstance = parseBool(value) ?? true
                case "panic_on_interface_error":
                    cfg.reticulum.panicOnInterfaceError = parseBool(value) ?? false
                case "allow_probes":
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
                default: break
                }
            case "logging":
                if key == "loglevel", let n = Int(value) { cfg.logging.logLevel = n }
                if key == "logtimestamps", let b = parseBool(value) { cfg.logging.logTimestamps = b }
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
    /// Mirrors Python's `__default_rns_config__`.
    public static let defaultConfigText = """
# This is the default Reticulum config file.
# You should probably edit it to include any additional
# interfaces and settings you might need.

[reticulum]
enable_transport = False
share_instance = Yes

[logging]
loglevel = 4

[interfaces]

  [[Default Interface]]
    type = AutoInterface
    enabled = Yes
"""
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
