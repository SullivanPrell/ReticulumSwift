import Foundation

/// The Reticulum stack. Owns the Transport, persistent identity storage,
/// and lifecycle of the registered interfaces.
public final class Reticulum {
    /// This library's own release version — the tag published to
    /// `github.com/SullivanPrell/ReticulumSwift` and pinned by consumers (RetiOS).
    /// Bump this on every release. This is the value surfaced in UI ("About")
    /// and by `rnsd --version`; it is informational only and never travels on
    /// the wire.
    ///
    /// Distinct from ``rnsProtocolVersion``: the two happen to share a lineage
    /// (releases are cut to mirror the RNS version they reach parity with) but
    /// advance independently — a patch release fixes the port without changing
    /// the protocol it targets.
    public static let version = "1.7.0"

    /// The Python RNS release whose wire protocol and behavior this port matches.
    /// Mirrors Python's `RNS.__version__` as a parity reference (Python RNS uses
    /// a single version string for both its library and its protocol). Bump only
    /// when parity is verified against a new RNS release. Informational only.
    ///
    /// 1.4.2 required no changes here, which is why this moved without a
    /// corresponding port. Its three core diffs against 1.4.1 are:
    ///
    ///  - `Transport.py:3126` — skip offline interfaces when fanning a recursive
    ///    path request out. Every fan-out loop in this port already filtered on
    ///    `isOnline`, so the port was ahead of Python here rather than behind.
    ///  - `Transport.py:1841` — a gravity-replacement log line moved from
    ///    `LOG_DEBUG` to `LOG_PATHING`. This port does not emit that line.
    ///  - `Discovery.py` — `list_discovered_interfaces` now caches the blackholed
    ///    identity set for 60s instead of asking per record. Python pays an RPC
    ///    round-trip to the shared instance for each `is_blackholed` call; here it
    ///    is a dictionary lookup under a lock (`Transport.isBlackholed`), so the
    ///    cache would buy nothing and only make a fresh blackhole take a minute
    ///    to apply.
    ///
    /// The rest of 1.4.2 is `RNS/Utilities/rnsh`, which is not ported.
    public static let rnsProtocolVersion = "1.4.2"

    public enum LogLevel: Int, Comparable, Sendable {
        case none = -1, critical = 0, error, warning, notice, info, verbose, debug, pathing, extreme
        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Log-level class constants (mirrors Python RNS.LOG_* module attributes)

    /// Python: `RNS.LOG_CRITICAL = 0`
    public static let logCritical: LogLevel = .critical
    /// Python: `RNS.LOG_ERROR = 1`
    public static let logError: LogLevel = .error
    /// Python: `RNS.LOG_WARNING = 2`
    public static let logWarning: LogLevel = .warning
    /// Python: `RNS.LOG_NOTICE = 3`
    public static let logNotice: LogLevel = .notice
    /// Python: `RNS.LOG_INFO = 4`
    public static let logInfo: LogLevel = .info
    /// Python: `RNS.LOG_VERBOSE = 5`
    public static let logVerbose: LogLevel = .verbose
    /// Python: `RNS.LOG_DEBUG = 6`
    public static let logDebug: LogLevel = .debug
    /// Python: `RNS.LOG_PATHING = 7`
    public static let logPathing: LogLevel = .pathing
    /// Python: `RNS.LOG_EXTREME = 8`
    public static let logExtreme: LogLevel = .extreme

    // MARK: - Logging

    /// Global log level threshold. Only messages at or above this level are emitted.
    /// Defaults to `.notice` (matches Python's default log level).
    public static var globalLogLevel: LogLevel = .notice

    /// Whether to prepend a timestamp to log lines. Mirrors Python's `RNS.logtimestamps`.
    public static var logTimestamps: Bool = true

    /// Optional custom log handler. When non-nil, all log messages are routed here
    /// instead of `print`. Allows apps to integrate with os.Logger or a custom sink.
    public static var logHandler: ((String, LogLevel) -> Void)?

    /// Emit a log message if `level >= globalLogLevel`.
    ///
    /// Mirrors Python's module-level `RNS.log(msg, level=LOG_NOTICE)`.
    ///
    /// - Parameters:
    ///   - message:  The message to log.
    ///   - level:    Severity level. Defaults to `.notice`.
    public static func log(_ message: String, level: LogLevel = .notice) {
        guard level <= globalLogLevel else { return }
        if let handler = logHandler {
            handler(message, level)
        } else {
            let prefix: String
            switch level {
            case .critical:  prefix = "[CRITICAL]"
            case .error:     prefix = "[ERROR]"
            case .warning:   prefix = "[WARNING]"
            case .notice:    prefix = "[NOTICE]"
            case .info:      prefix = "[INFO]"
            case .verbose:   prefix = "[VERBOSE]"
            case .debug:     prefix = "[DEBUG]"
            case .pathing:   prefix = "[PATHING]"
            case .extreme:   prefix = "[EXTREME]"
            case .none:      prefix = "[NONE]"
            }
            let ts = logTimestamps ? "[\(Date())] " : ""
            print("\(ts)\(prefix) \(message)")
            fflush(stdout)
        }
    }

    public struct Configuration {
        public var storagePath: URL
        /// Config file path. If nil and a file exists at the standard location
        /// (`storagePath/../config`), it is loaded automatically by `start()`.
        public var configPath: URL?
        public var shareInstance: Bool
        public var logLevel: LogLevel
        /// Optional stamp validator for interface discovery.
        ///
        /// When `discover_interfaces = Yes` is set in the config file and this
        /// property is non-nil, `start()` calls `transport.discoverInterfaces()`
        /// using this validator. Typically backed by `LXStamper` from LXMFSwift.
        /// Mirrors the dynamic LXMF import in Python's `InterfaceAnnounceHandler`.
        public var discoveryStampValidator: (any DiscoveryStampValidator)?

        public init(storagePath: URL, configPath: URL? = nil, shareInstance: Bool = true, logLevel: LogLevel = .notice) {
            self.storagePath = storagePath
            self.configPath = configPath
            self.shareInstance = shareInstance
            self.logLevel = logLevel
            self.discoveryStampValidator = nil
        }
    }

    /// The most recently started Reticulum instance. Mirrors Python's
    /// `RNS.Reticulum.get_instance()`. Set by `start()`.
    public private(set) static var shared: Reticulum?

    // MARK: - Wire-format constants (mirrors Python Reticulum class attributes)

    /// Maximum Transmission Unit in bytes. Python: `Reticulum.MTU = 500`.
    public static let mtu: Int = Constants.mtu                       // 500

    /// Maximum Data Unit (payload capacity) in bytes. Python: `Reticulum.MDU = 464`.
    public static let mdu: Int = Constants.mdu                       // 464

    /// Minimum header size for type-1 packets. Python: `Reticulum.HEADER_MINSIZE = 19`.
    public static let headerMinSize: Int = Constants.headerMinSize   // 19

    /// Maximum header size (type-2 packets with transport ID).
    /// Python: `Reticulum.HEADER_MAXSIZE = 35`.
    public static let headerMaxSize: Int = Constants.headerMaxSize   // 35

    /// Minimum IFAC (Interface Access Code) tail size.
    /// Python: `Reticulum.IFAC_MIN_SIZE = 1`.
    public static let ifacMinSize: Int = Constants.ifacMinSize       // 1

    // MARK: - Announce / persistence constants (mirrors Python Reticulum class attributes)

    /// Maximum percentage of interface bandwidth that announce traffic may consume.
    /// Used as: `announce_cap = Reticulum.ANNOUNCE_CAP / 100.0` (→ 0.02).
    /// Python: `Reticulum.ANNOUNCE_CAP = 2`.
    public static let announceCap: Int = 2

    /// Maximum number of queued announces per interface before older ones are dropped.
    /// Python: `Reticulum.MAX_QUEUED_ANNOUNCES = 16384`.
    public static let maxQueuedAnnounces: Int = 16384

    /// Interval at which data is persisted when the system is idle (quick save).
    /// Python: `Reticulum.GRACIOUS_PERSIST_INTERVAL = 60*5`.
    public static let graciousPersistInterval: TimeInterval = 60 * 5   // 300 s

    /// Full persistence interval (paths, known destinations, hashlist).
    /// Python: `Reticulum.PERSIST_INTERVAL = 60*60*12`.
    public static let persistInterval: TimeInterval = 60 * 60 * 12     // 43200 s

    /// Periodic cleanup interval for caches and stale entries.
    /// Python: `Reticulum.CLEAN_INTERVAL = 900`.
    public static let cleanInterval: TimeInterval = 900

    /// Job loop interval (same as persist check interval).
    /// Python: `Reticulum.JOB_INTERVAL = 300`.
    public static let jobInterval: TimeInterval = 300

    /// Minimum bitrate in bits/s below which an interface is considered unusable.
    /// Python: `Reticulum.MINIMUM_BITRATE = 5`.
    public static let minimumBitrate: Int = 5

    /// How long a queued announce is kept before being dropped (seconds).
    /// Python: `Reticulum.QUEUED_ANNOUNCE_LIFE = 60*60*24`.
    public static let queuedAnnounceLife: TimeInterval = 86400

    /// How long resource cache entries are kept (seconds).
    /// Python: `Reticulum.RESOURCE_CACHE = 60*60*24`.
    public static let resourceCacheLifetime: TimeInterval = 86400

    /// Hash length in bits for truncated hashes (destination hashes, identity hashes).
    /// Python: `Reticulum.TRUNCATED_HASHLENGTH = 128`.
    public static let truncatedHashLength: Int = Constants.truncatedHashLengthBits   // 128

    /// IFAC salt used for Interface Access Code derivation.
    /// Python: `Reticulum.IFAC_SALT = bytes.fromhex("adf54d882c9a…")`.
    public static let ifacSalt: Data = Constants.ifacSalt

    // MARK: - Log destination constants (Python: RNS.LOG_STDOUT / LOG_FILE / LOG_CALLBACK)

    /// Log to stdout. Mirrors Python `RNS.LOG_STDOUT = 0x91`.
    public static let logDestStdout:   Int = 0x91

    /// Log to a file. Mirrors Python `RNS.LOG_FILE = 0x92`.
    public static let logDestFile:     Int = 0x92

    /// Log via a callback. Mirrors Python `RNS.LOG_CALLBACK = 0x93`.
    public static let logDestCallback: Int = 0x93

    /// Maximum log file size in bytes (5 MiB). Mirrors Python `RNS.LOG_MAXSIZE = 5*1024*1024`.
    public static let logMaxSize:      Int = 5 * 1024 * 1024

    /// When `true`, log lines omit the log-level label (compact format).
    /// Mirrors Python `RNS.compact_log_fmt = False`.
    public static var compactLogFmt: Bool = false

    // MARK: - Example configuration

    /// A complete example Reticulum configuration file as a string.
    ///
    /// Python: `rnsd.py:90-583`, `__example_rns_config__` — the blob that
    /// `rnsd --exampleconfig` prints. The byte-exact transcription lives in
    /// ``RNSConfigTemplates/exampleConfig``, next to its SHA-256 regression test.
    public static let exampleConfig: String = RNSConfigTemplates.exampleConfig

    // MARK: - Static API (mirrors Python class-level static methods)

    /// Returns the shared Reticulum instance.
    /// Mirrors Python's `RNS.Reticulum.get_instance()`.
    public static func getInstance() -> Reticulum? { shared }

    /// Returns the Transport instance from the running shared Reticulum instance, or nil.
    /// Mirrors Python's `RNS.Reticulum.get_transport_instance()`.
    public static func getTransportInstance() -> Transport? { shared?.transport }

    /// Returns whether this process is connected to a shared Reticulum instance
    /// (i.e. whether `Reticulum.shared` has been initialised).
    /// Mirrors Python's `Reticulum.is_connected_to_shared_instance()`.
    public static func isConnectedToSharedInstance() -> Bool { shared != nil }

    /// Whether proofs sent are implicit (signature only, 64 bytes) or explicit
    /// (full hash + Ed25519 signature, 96 bytes). Defaults to `true` (implicit), matching
    /// Python's `Reticulum.__use_implicit_proof = True`.
    /// Mirrors `RNS.Reticulum.should_use_implicit_proof()`.
    public static var useImplicitProof: Bool = true

    /// Returns whether implicit proofs are in use.
    /// Mirrors Python's `Reticulum.should_use_implicit_proof()`.
    public static func shouldUseImplicitProof() -> Bool { useImplicitProof }

    // MARK: - Module-level utility functions (mirrors Python RNS module-level functions)

    /// Returns a cryptographically-random `Double` in `[0, 1)`.
    /// Mirrors Python's `RNS.rand()`.
    public static func rand() -> Double {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, 8, &bytes)
        // Construct a value in [0, 1) by filling the mantissa of a 64-bit float.
        let bits = bytes.withUnsafeBytes { $0.load(as: UInt64.self) }
        // IEEE-754: exponent = 1023 (value 1.0..2.0), then subtract 1.0 → [0, 1)
        let mantissa = (bits & 0x000FFFFFFFFFFFFF) | 0x3FF0000000000000
        return Double(bitPattern: mantissa) - 1.0
    }

    /// Returns `true` if the current global log level is at or above `level`.
    /// Mirrors Python's `RNS.sl(level=LOG_NOTICE)`.
    ///
    /// - Parameter level: The threshold level to check. Defaults to `.notice` (matching Python's default of 3).
    public static func sl(level: LogLevel = .notice) -> Bool {
        globalLogLevel != .none && globalLogLevel >= level
    }

    /// Returns a dictionary of physical-layer parameters for this stack.
    /// Mirrors Python's `RNS.phyparams()` which prints the same values.
    ///
    /// Keys: `"mtu"`, `"linkMdu"`, `"linkCurve"`, `"ecPubKeySize"`, `"keySize"`.
    public static func phyparams() -> [String: Any] {
        [
            "mtu":          Reticulum.mtu,
            "linkMdu":      Constants.linkMdu,
            "linkCurve":    Identity.curve,
            "ecPubKeySize": Identity.ecPubSize,
            "keySize":      Identity.keySize,
        ]
    }

    /// Returns the human-readable name string for a log level.
    /// Mirrors Python's `RNS.loglevelname(level)` — note Python uses fixed-width
    /// padded strings to align log output.
    public static func loglevelname(_ level: LogLevel) -> String {
        switch level {
        case .critical: return "[Critical]"
        case .error:    return "[Error]   "
        case .warning:  return "[Warning] "
        case .notice:   return "[Notice]  "
        case .info:     return "[Info]    "
        case .verbose:  return "[Verbose] "
        case .debug:    return "[Debug]   "
        case .pathing:  return "[Pathing] "   // Python LOG_PATHING = 7
        case .extreme:  return "[Extra]   "   // Python uses "[Extra]" for LOG_EXTREME (now 8)
        case .none:     return "[None]    "
        }
    }

    /// Whether link MTU discovery is enabled globally.
    /// Mirrors Python's `Reticulum.link_mtu_discovery()`.
    /// Default: true (Python `LINK_MTU_DISCOVERY = True`).
    ///
    /// Settable because Python reads `link_mtu_discovery` from the `[reticulum]` config section
    /// (`Reticulum.py:537-539`). It was `private(set)` with no writer anywhere, so the option had
    /// nowhere to be applied — the same shape as the get-only interface attributes, and the reason
    /// adding the config parser alone would not have been enough. See `swift_devel/bugs/025-*.md`
    /// and `bugs/030-*.md`.
    public static var linkMtuDiscoveryEnabled: Bool = true

    public static func linkMtuDiscovery() -> Bool { linkMtuDiscoveryEnabled }

    /// Returns whether Transport is enabled for the running shared instance.
    /// Mirrors Python's `Reticulum.transport_enabled()`.
    public static func transportEnabled() -> Bool { shared?.transport.transportEnabled ?? false }

    /// Whether the probe destination is enabled.
    /// Mirrors Python's `Reticulum.probe_destination_enabled()`.
    /// Settable so tests can control the flag without a full config file.
    public static var allowProbes_: Bool = false
    public static func probeDestinationEnabled() -> Bool { allowProbes_ }

    /// Whether remote management is enabled. Defaults to false.
    /// Mirrors Python's `Reticulum.remote_management_enabled()`.
    /// Settable so tests can control the flag without a full config file.
    public static var remoteManagementEnabled_: Bool = false
    public static func remoteManagementEnabled() -> Bool { remoteManagementEnabled_ }

    /// Returns the required stamp value for interface discovery validation.
    /// Mirrors Python's `Reticulum.required_discovery_value()`.
    public private(set) static var requiredDiscoveryValue_: Int = 16
    public static func requiredDiscoveryValue() -> Int { requiredDiscoveryValue_ }

    /// Returns whether blackhole list publishing is enabled.
    /// Mirrors Python's `Reticulum.publish_blackhole_enabled()`.
    public private(set) static var publishBlackholeEnabled_: Bool = false
    public static func publishBlackholeEnabled() -> Bool { publishBlackholeEnabled_ }

    /// Returns the list of transport identity hashes from which blackhole lists are sourced.
    /// Mirrors Python's `Reticulum.blackhole_sources()`.
    public private(set) static var blackholeSources_: [Data] = []
    public static func blackholeSources() -> [Data] { blackholeSources_ }

    /// Interval (seconds) between blackhole list re-fetches from each source.
    /// Default 3600 (1 hour). Minimum 120s. Configurable via the
    /// `blackhole_update_interval` config key (value in minutes).
    /// Mirrors Python's `Reticulum.blackhole_update_interval()` accessor +
    /// `BlackholeUpdater.UPDATE_INTERVAL` default (RNS commit 02924656).
    public private(set) static var blackholeUpdateInterval_: TimeInterval = 3600
    public static func blackholeUpdateInterval() -> TimeInterval { blackholeUpdateInterval_ }

    /// Returns a list of interfaces discovered over the network.
    /// Mirrors Python's `Reticulum.discovered_interfaces()`.
    public private(set) static var discoveredInterfaces_: [String] = []
    public static func discoveredInterfaces() -> [String] { discoveredInterfaces_ }

    /// Returns the list of network identity hashes from which interfaces are discovered.
    /// Mirrors Python's `Reticulum.interface_discovery_sources()`.
    /// `internal(set)`, not `private(set)`: the announce-time allowlist check in
    /// `InterfaceAnnounceHandler` needs to be testable, and config loading (the
    /// only production writer) already lives in this module.
    public internal(set) static var interfaceDiscoverySources_: [Data] = []
    public static func interfaceDiscoverySources() -> [Data] { interfaceDiscoverySources_ }

    /// Maximum number of discovered interfaces to auto-connect to.
    /// 0 means auto-connect is disabled. Mirrors Python's `Reticulum.__autoconnect_discovered_interfaces`.
    public static var maxAutoconnectedInterfaces_: Int = 0

    /// Returns true if discovered interfaces should be automatically connected.
    /// Mirrors Python's `Reticulum.should_autoconnect_discovered_interfaces()`.
    public static func shouldAutoconnectDiscoveredInterfaces() -> Bool { maxAutoconnectedInterfaces_ > 0 }

    /// Returns the maximum number of auto-connected discovered interfaces.
    /// Mirrors Python's `Reticulum.max_autoconnected_interfaces()`.
    public static func maxAutoconnectedInterfaces() -> Int { maxAutoconnectedInterfaces_ }

    // MARK: - RNS 1.4.1 gravity / autoconnect policy

    /// Configured `default_gravity`, or `nil` when unset.
    public static var defaultGravity_: Int? = nil

    /// Gravity for an interface that does not configure its own.
    /// Mirrors Python's `Reticulum._default_gravity()`.
    public static func defaultGravity() -> Int {
        defaultGravity_ ?? InterfaceMode.defaultGravity
    }

    /// Configured `autoconnect_interface_mode`, or `nil` when unset.
    /// Mirrors Python's `Reticulum.autoconnect_interface_mode()`.
    public static var autoconnectInterfaceMode_: InterfaceMode? = nil
    public static func autoconnectInterfaceMode() -> InterfaceMode? { autoconnectInterfaceMode_ }

    /// Configured `autoconnect_interface_gravity`, or `nil` when unset.
    /// Mirrors Python's `Reticulum.autoconnect_interface_gravity()`.
    public static var autoconnectInterfaceGravity_: Int? = nil
    public static func autoconnectInterfaceGravity() -> Int? { autoconnectInterfaceGravity_ }

    /// Configured `autoconnect_announces_to_internal`, or `nil` when unset.
    /// Mirrors Python's `Reticulum.autoconnect_announces_to_internal()`.
    public static var autoconnectAnnouncesToInternal_: Bool? = nil
    public static func autoconnectAnnouncesToInternal() -> Bool? { autoconnectAnnouncesToInternal_ }

    public let configuration: Configuration
    public let transport: Transport
    public private(set) var rpcServer: RPCServer?

    /// Parsed config file, if one was loaded.
    public private(set) var config: ReticulumConfig?

    /// Identity returned by `loadOrCreateIdentity`. Held weakly so the
    /// stack can re-save its ratchets at checkpoint/stop time without
    /// keeping it alive past the host's own lifetime.
    private weak var trackedIdentity: Identity?

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.transport = Transport()
    }

    /// Convenience: init from a config directory path (mirrors Python's
    /// `RNS.Reticulum(configdir=...)` pattern).
    public static func fromConfigDir(_ configDir: URL) -> Reticulum {
        let storagePath = configDir.appendingPathComponent("storage")
        let configPath = configDir.appendingPathComponent("config")
        return Reticulum(configuration: Configuration(
            storagePath: storagePath,
            configPath: configPath
        ))
    }

    /// Start the RPC server on the specified port.
    /// Python: `self.rpc_listener = multiprocessing.connection.Listener(...)`
    public func startRPC(port: UInt16) throws {
        // Derive the auth key from the persistent (internal) identity so it stays
        // stable across runs even when an ephemeral transport identity is in use.
        // Mirrors Python's `rpc_key = full_hash(Transport.internal_identity().get_private_key())`.
        guard let identity = transport.internalIdentity ?? transport.transportIdentity,
              let privBytes = identity.getPrivateKey() else {
            throw ReticulumError.missingIdentity
        }

        let authkey = Identity.fullHash(privBytes)
        let server = RPCServer(port: port, authkey: authkey)
        server.transport = transport
        try server.start()
        self.rpcServer = server
    }

    public enum ReticulumError: Error {
        case missingIdentity
    }

    private var identityURL: URL {
        configuration.storagePath.appendingPathComponent("identity")
    }
    private var ratchetsURL: URL {
        configuration.storagePath.appendingPathComponent("identity.ratchets")
    }
    private var transportIDURL: URL {
        configuration.storagePath.appendingPathComponent("transport_identity")
    }
    private var knownDestinationsURL: URL {
        configuration.storagePath.appendingPathComponent("known_destinations.json")
    }

    public func start() throws {
        // Create storage directories.
        try FileManager.default.createDirectory(
            at: configuration.storagePath,
            withIntermediateDirectories: true
        )

        // Load and apply config file if available.
        if let cfgURL = resolvedConfigPath() {
            if !FileManager.default.fileExists(atPath: cfgURL.path) {
                try ReticulumConfig.defaultConfigText.write(to: cfgURL, atomically: true, encoding: .utf8)
            }
            if let parsed = ReticulumConfig.load(from: cfgURL) {
                config = parsed
                applyConfig(parsed)
            }
        }

        // Load or create the persistent transport identity (full 64-byte private key).
        // Mirrors Python's Transport.identity loaded from `transport_identity`.
        let persistentIdentity: Identity
        if let loaded = try? Identity.read(fromFile: transportIDURL) {
            persistentIdentity = loaded
        } else {
            persistentIdentity = Identity()
            try? persistentIdentity.write(toFile: transportIDURL)
        }
        // Keep the persistent identity as `internalIdentity` (Python's
        // `Transport._identity`). Non-transport nodes then run behind a fresh
        // ephemeral transport identity for privacy, unless
        // `static_transport_identity` is configured. Mirrors RNS 1.3.7
        // `Transport.start()`.
        transport.internalIdentity = persistentIdentity
        let transportIdentity: Identity
        if !transport.transportEnabled && !(config?.reticulum.staticTransportIdentity ?? false) {
            transportIdentity = Identity()
        } else {
            transportIdentity = persistentIdentity
        }
        transport.transportIdentity = transportIdentity
        transport.transportInstanceID = transportIdentity.hash

        // When local hop-count obfuscation is enabled, pick a random per-session
        // delta in 2...7. Mirrors Python: `if RNS.Reticulum.local_hops_delta():
        // Transport.local_hops_delta = (ord(os.urandom(1))%6)+2`.
        if config?.reticulum.localHopsDelta ?? false {
            transport.localHopsDelta = UInt8.random(in: 2...7)
        }

        transport.ratchetsDirectory = configuration.storagePath
            .appendingPathComponent("ratchets")

        // Set cache directory for disk-based packet (announce) cache.
        // Mirrors Python's `RNS.Reticulum.cachepath`.
        transport.cacheDirectory = configuration.storagePath.appendingPathComponent("cache")

        // Restore path table, dropping any expired entries.
        let pathStoreURL = configuration.storagePath.appendingPathComponent("paths.json")
        if FileManager.default.fileExists(atPath: pathStoreURL.path),
           let store = try? PathStore.read(from: pathStoreURL) {
            store.apply(to: transport)
        }

        transport.loadKnownRatchets()
        transport.sweepKnownRatchets()

        // Load persisted known destinations (mirrors Python's Identity.load_known_destinations).
        if FileManager.default.fileExists(atPath: knownDestinationsURL.path) {
            try? transport.loadKnownDestinations(from: knownDestinationsURL)
        }

        // Restore packet hashlist for replay prevention across restarts.
        // Mirrors Python's hashlist loading in Transport.__init__.
        let hashlistURL = configuration.storagePath.appendingPathComponent("packet_hashlist")
        try? transport.loadPacketHashlist(from: hashlistURL)

        // Load blackhole list from directory (mirrors Python's Transport.reload_blackhole()).
        // Allows external sources listed in Reticulum.blackhole_sources().
        let blackholePath = configuration.storagePath.appendingPathComponent("blackhole")
        try? transport.reloadBlacklist(fromDirectory: blackholePath,
                                       allowedSources: Reticulum.blackholeSources())

        try transport.start()

        // Start interface discovery listener when configured.
        // Mirrors Python: if Reticulum.__discover_interfaces: RNS.Transport.discover_interfaces()
        // A DiscoveryStampValidator must be injected (production: LXStamper from LXMFSwift).
        if let parsedCfg = config, parsedCfg.reticulum.discoverInterfaces,
           let validator = configuration.discoveryStampValidator {
            let discoveryPath = configuration.storagePath
                .appendingPathComponent("discovery")
                .appendingPathComponent("interfaces")
                .path
            transport.discoverInterfaces(
                storagePath: discoveryPath,
                requiredValue: Reticulum.requiredDiscoveryValue(),
                stampValidator: validator
            )
        }

        // Start blackhole-list updater when sources are configured.
        // Mirrors Python: if Reticulum.__blackhole_sources: RNS.Transport.enable_blackhole_updater()
        if let parsedCfg = config, !parsedCfg.reticulum.blackholeSources.isEmpty {
            Reticulum.blackholeSources_ = parsedCfg.reticulum.blackholeSources
            transport.enableBlackholeUpdater()
        }

        Reticulum.shared = self
    }

    public func stop() {
        transport.stop()
        let pathStoreURL = configuration.storagePath.appendingPathComponent("paths.json")
        try? PathStore.snapshot(of: transport).write(to: pathStoreURL)
        try? trackedIdentity?.writeRatchets(toFile: ratchetsURL)
        // Persist known destinations (mirrors Python's Identity.save_known_destinations).
        try? transport.saveKnownDestinations(to: knownDestinationsURL)
        // Persist packet hashlist for replay prevention across restarts.
        let hashlistURL = configuration.storagePath.appendingPathComponent("packet_hashlist")
        try? transport.savePacketHashlist(to: hashlistURL)
        // Persist blackhole list (own entries only, mirrors Python's Transport.persist_blackhole()).
        let blackholePath = configuration.storagePath.appendingPathComponent("blackhole")
        try? transport.persistBlacklist(toDirectory: blackholePath)
    }

    // MARK: - Management API (mirrors Python Reticulum instance methods)

    /// Drop a known path, forcing re-discovery on next attempt.
    /// Mirrors Python's `RNS.Reticulum.get_instance().drop_path(hash)`.
    @discardableResult
    public func dropPath(for destinationHash: Data) -> Bool {
        transport.dropPath(for: destinationHash)
    }

    /// Clear all per-interface announce queues, dropping any pending relayed announces.
    /// Returns `true` on success.
    /// Mirrors Python's `Reticulum.drop_announce_queues()` → `Transport.drop_announce_queues()`.
    @discardableResult
    public func dropAnnounceQueues() -> Bool {
        transport.dropAnnounceQueues()
        return true
    }

    /// Returns the current number of active links.
    /// Mirrors Python's `Reticulum.get_link_count()`.
    public func getLinkCount() -> Int { transport.getLinkCount() }

    /// Returns statistics for all registered interfaces.
    /// Mirrors Python's `Reticulum.get_interface_stats()`.
    public func getInterfaceStats() -> [Transport.InterfaceStats] { transport.getInterfaceStats() }

    /// Returns a snapshot of the path table, optionally filtered by max hops.
    /// Mirrors Python's `Reticulum.get_path_table(max_hops=None)`.
    public func getPathTable(maxHops: UInt8? = nil) -> [Transport.PathTableEntry] {
        transport.getPathTable(maxHops: maxHops)
    }

    /// Drop all path table entries that route via a specific transport instance.
    /// Returns the number of dropped paths.
    /// Mirrors Python's `Reticulum.drop_all_via(transport_hash)`.
    @discardableResult
    public func dropAllVia(transportHash: Data) -> Int {
        transport.dropAllPaths(via: transportHash)
    }

    /// Blackhole an identity hash, preventing its announces from being forwarded.
    /// Returns `true` on success, `nil` if already blackholed, `false` if hash length is wrong.
    /// Mirrors Python's `Reticulum.blackhole_identity(identity_hash, until, reason)`.
    @discardableResult
    public func blackholeIdentity(_ identityHash: Data, until: Date? = nil, reason: String? = nil) -> Bool? {
        guard identityHash.count == Constants.truncatedHashLength else { return false }
        return transport.blackholeIdentity(identityHash, until: until?.timeIntervalSince1970, reason: reason)
    }

    /// Remove an identity from the blackhole list.
    /// Returns `true` on success, `nil` if not blackholed, `false` if hash length is wrong.
    /// Mirrors Python's `Reticulum.unblackhole_identity(identity_hash)`.
    @discardableResult
    public func unblackholeIdentity(_ identityHash: Data) -> Bool? {
        guard identityHash.count == Constants.truncatedHashLength else { return false }
        return transport.unblackholeIdentity(identityHash)
    }

    /// Returns all currently blackholed identity hashes with their entries.
    /// Mirrors Python's `Reticulum.get_blackholed_identities()`.
    public func getBlackholedIdentities() -> [Data: Transport.BlackholeEntry] {
        transport.blackholeLock.lock(); defer { transport.blackholeLock.unlock() }
        return transport.blackholedIdentities
    }

    /// Returns a snapshot of the current announce rate table.
    /// Mirrors Python's `Reticulum.get_rate_table()`.
    public func getRateTable() -> [Transport.RateTableEntry] {
        transport.getRateTable()
    }

    /// Returns the cached RSSI for a received packet, or nil if not cached.
    /// Mirrors Python's `Reticulum.get_packet_rssi(packet_hash)`.
    public func getPacketRssi(packetHash: Data) -> Float? {
        transport.getPacketRssi(packetHash: packetHash)
    }

    /// Returns the cached SNR for a received packet, or nil if not cached.
    /// Mirrors Python's `Reticulum.get_packet_snr(packet_hash)`.
    public func getPacketSnr(packetHash: Data) -> Float? {
        transport.getPacketSnr(packetHash: packetHash)
    }

    /// Returns the cached signal quality for a received packet, or nil if not cached.
    /// Mirrors Python's `Reticulum.get_packet_q(packet_hash)`.
    public func getPacketQ(packetHash: Data) -> Float? {
        transport.getPacketQ(packetHash: packetHash)
    }

    /// Force-checkpoint the path table without stopping the stack — useful
    /// from `applicationWillResignActive` on iOS.
    public func checkpoint() throws {
        let pathStoreURL = configuration.storagePath.appendingPathComponent("paths.json")
        try PathStore.snapshot(of: transport).write(to: pathStoreURL)
        try trackedIdentity?.writeRatchets(toFile: ratchetsURL)
    }

    /// Load a persistent identity from disk, creating it if it doesn't
    /// exist. The 64-byte private-key blob lives at
    /// `<storagePath>/identity` with `0o600` semantics where the platform
    /// supports it. Ratchet privates, if present, live in a sidecar at
    /// `<storagePath>/identity.ratchets` and are reloaded here.
    public func loadOrCreateIdentity() throws -> Identity {
        let identity: Identity
        if FileManager.default.fileExists(atPath: identityURL.path) {
            identity = try Identity.read(fromFile: identityURL)
        } else {
            identity = Identity()
            try identity.write(toFile: identityURL)
        }
        if FileManager.default.fileExists(atPath: ratchetsURL.path) {
            try? identity.loadRatchets(fromFile: ratchetsURL)
        }
        trackedIdentity = identity
        return identity
    }

    // MARK: - Per-interface configuration

    /// Apply everything one interface block configures, then its IFAC keys.
    ///
    /// The other half of `bugs/025`. §1 of this change made `mode`, the three `announce_rate_*`
    /// values, `announce_cap`, `bitrate`, `ingress_control`, `egress_control`/`ec_pr_freq` and the
    /// nine `ic_*` tunables settable, because Python mutates all of them at runtime and this port
    /// had declared them get-only. That removed the compile-time blocker and left the values with
    /// nowhere to come *from*: this function did not exist, and `synthesizeInterfaces` applied
    /// exactly two attributes — `gravity` and `announces_to_internal`. Which is the same defect one
    /// step earlier, in the spec's words: "a configuration value with nowhere to be written is
    /// indistinguishable from a configuration value that is never read, and both are failures of
    /// this requirement."
    ///
    /// Mirrors `Reticulum.py:735-857` (extraction) and `:906-953` (application). Python applies the
    /// first group unconditionally, from resolved defaults, and the `egress_control` / `ic_*`
    /// group only where the key is present — so an absent key leaves the class default rather than
    /// overwriting it with a zero.
    ///
    /// Called before `Transport.register` and `Interface.start`, matching `Reticulum.py:975`.
    public static func applyInterfaceConfiguration(to interface: any Interface,
                                                   from block: ReticulumConfig.InterfaceConfig) {
        // `interface_mode` first, then `mode` (`Reticulum.py:736-768`). Case-insensitive, and an
        // unrecognised value falls through leaving the default — Python's if/elif chain has no
        // else branch, so `interface_mode` stays MODE_FULL.
        //
        // Divergence worth recording: Python's `interface_mode` branch reads `c["mode"]` for its
        // `gateway` and `internal` cases (`Reticulum.py:748-751`) — a typo in the reference. With
        // `interface_mode = gateway` and no `mode` key, configobj raises `KeyError` there. This
        // port resolves both aliases from whichever key was given, which is what the branch plainly
        // intends and what the spec table describes.
        let modeString = block["interface_mode"] ?? block["mode"]
        if let modeString, let mode = InterfaceMode(configName: modeString) {
            interface.mode = mode
        }

        // An explicit `gravity` wins, else `default_gravity`, else 0 (`Reticulum.py:771-772`).
        interface.gravity = block.int("gravity") ?? Reticulum.defaultGravity()

        // A percentage in `(0, 100]`, divided by 100 (`Reticulum.py:834-837`). Out of range leaves
        // the class default.
        if let cap = block.double("announce_cap"), cap > 0, cap <= 100 {
            interface.announceCap = cap / 100.0
        }

        interface.bootstrapOnly = block.bool("bootstrap_only") ?? false
        interface.recursivePrs = block.bool("recursive_prs") ?? false
        interface.announcesFromInternal = block.bool("announces_from_internal") ?? true
        // No default: absent means Python's `None`, distinct from an explicit `False`.
        interface.announcesToInternal = block.bool("announces_to_internal")

        // `announce_rate_target` must be `> 0`; grace and penalty `>= 0` (`Reticulum.py:820-829`).
        // A target with neither companion gets both defaulted to 0 (`:831-832`), so a config that
        // sets only the target is complete rather than half-configured.
        let target = block.int("announce_rate_target").flatMap { $0 > 0 ? $0 : nil }
        let grace = block.int("announce_rate_grace").flatMap { $0 >= 0 ? $0 : nil }
        let penalty = block.int("announce_rate_penalty").flatMap { $0 >= 0 ? $0 : nil }
        interface.announceRateTarget = target.map(TimeInterval.init)
        interface.announceRateGrace = grace ?? 0
        interface.announceRatePenalty = TimeInterval(penalty ?? 0)

        // A configured bitrate replaces the class guess when it is at least `MINIMUM_BITRATE`
        // (`Reticulum.py:815-816`, applied at `:914`). It is not merely reported: announce capacity
        // and resource timings derive from it.
        if let bitrate = block.int("bitrate"), bitrate >= Reticulum.minimumBitrate {
            interface.bitrate = bitrate
        }

        interface.ingressControl = block.bool("ingress_control") ?? true

        // Present-only, so an absent key leaves the class default (`Reticulum.py:942-953`).
        let state = interface.interfaceState
        if let value = block.bool("egress_control")            { interface.egressControl = value }
        if let value = block.double("ec_pr_freq")              { interface.ecPrFreq = value }
        if let value = block.int("ic_max_held_announces")      { state.icMaxHeldAnnounces = value }
        if let value = block.double("ic_burst_hold")           { state.icBurstHold = value }
        if let value = block.double("ic_burst_freq_new")       { state.icBurstFreqNew = value }
        if let value = block.double("ic_burst_freq")           { state.icBurstFreq = value }
        if let value = block.double("ic_pr_burst_freq_new")    { state.icPrBurstFreqNew = value }
        if let value = block.double("ic_pr_burst_freq")        { state.icPrBurstFreq = value }
        if let value = block.double("ic_new_time")             { state.icNewTime = value }
        if let value = block.double("ic_burst_penalty")        { state.icBurstPenalty = value }
        if let value = block.double("ic_held_release_interval") { state.icHeldReleaseInterval = value }

        // IFAC last, as Python does (`Reticulum.py:955` follows the attribute block).
        applyIfacConfiguration(to: interface, from: block)
    }

    // MARK: - Per-interface IFAC configuration

    /// Read the IFAC keys out of one interface block and install the derived key on the interface.
    ///
    /// `bugs/015`. `Transport.configureIfac` was correct and thoroughly tested, and **nothing
    /// called it**. An operator who set `network_name` and `passphrase` got an interface that came
    /// up, reported Up and passed nothing: every frame it sent went out unflagged and was dropped
    /// by the peer, every frame it received arrived flagged and was dropped locally. Silent in
    /// both directions, and invisible from the Python side, which saw a peer that simply never
    /// spoke.
    ///
    /// Python does this inline in `__apply_config` (`Reticulum.py:770-788` for the extraction,
    /// `:955-973` for the derivation). Factored out here so the one call site cannot be the thing
    /// that is missing again, and so `RetiOS` — which builds interfaces without a config file —
    /// can reach the same code.
    ///
    /// Must be called **before** `Transport.register` and `Interface.start`, matching
    /// `Reticulum.py:975`: the key has to be installed before the first frame moves, or the
    /// interface's opening announce goes out unprotected.
    public static func applyIfacConfiguration(to interface: any Interface,
                                              from block: ReticulumConfig.InterfaceConfig) {
        // Python reads both spellings and lets the later one win (`Reticulum.py:778-788`), and
        // treats an empty string as absent.
        func nonEmpty(_ keys: String...) -> String? {
            var found: String?
            for key in keys {
                if let value = block[key], !value.isEmpty { found = value }
            }
            return found
        }

        let netname = nonEmpty("networkname", "network_name")
        let netkey = nonEmpty("passphrase", "pass_phrase")

        // `ifac_size` in the config is in **bits** (`Reticulum.py:776`). A value below
        // `IFAC_MIN_SIZE * 8` is *ignored* — the assignment sits inside the `>=` guard — so the
        // class default stays in place rather than being clamped to the minimum.
        var size = interface.ifacSize
        if let bits = block.int("ifac_size"), bits >= Constants.ifacMinSize * 8 {
            size = bits / 8
        }
        interface.ifacSize = size

        // Python assigns both unconditionally, then derives only if either is present
        // (`Reticulum.py:955-958`).
        interface.ifacNetname = netname
        guard netname != nil || netkey != nil else { return }

        Transport.configureIfac(on: interface, netname: netname, netkey: netkey, size: size)
    }

    // MARK: - Interface synthesis from config

    /// Create and register interfaces described in `cfg.interfaces`.
    /// Supports: TCPClientInterface, TCPServerInterface, UDPInterface, AutoInterface,
    ///           BackboneInterface, LocalInterface.
    public func synthesizeInterfaces(from cfg: ReticulumConfig) throws {
        for ifCfg in cfg.interfaces where ifCfg.enabled {
            let iface: (any Interface)?
            switch ifCfg.type {
            case "LocalInterface":
                let host = ifCfg["connect_ip"] ?? ifCfg["host"] ?? "127.0.0.1"
                let port = UInt16(ifCfg.int("port") ?? 37428)
                let li = LocalInterface(name: ifCfg.name, host: host, port: port)
                if let w = ifCfg.int("reconnect_wait") { li.reconnectWait = TimeInterval(w) }
                if let t = ifCfg.int("max_reconnect_tries") { li.maxReconnectTries = t }
                iface = li

            case "BackboneInterface", "BackboneClientInterface":
                // Python accepts a set of aliases for this interface family before
                // constructing it (Reticulum.py:988-992): `remote` → `target_host`,
                // `port` → both `listen_port` and `target_port`. Written configs —
                // including the one RNS's own discovery emits for a backbone peer —
                // use `remote`/`port`, so without the aliases the entry parsed to
                // nothing and the interface was silently skipped.
                guard let host = ifCfg["target_host"] ?? ifCfg["remote"],
                      let port = ifCfg.int("target_port") ?? ifCfg.int("port") else { continue }
                let bb = BackboneInterface(name: ifCfg.name, host: host, port: UInt16(port))
                iface = bb

            case "TCPClientInterface":
                guard let host = ifCfg["target_host"],
                      let port = ifCfg.int("target_port") else { continue }
                let tcpClient = TCPClientInterface(name: ifCfg.name, host: host, port: UInt16(port))
                if ifCfg.bool("bootstrap_only") == true { tcpClient.bootstrapOnly = true }
                // Python: `max_reconnect_tries` from the interface block, else the class
                // default of None/unlimited (TCPInterface.py:109, 135).
                if let tries = ifCfg.int("max_reconnect_tries") { tcpClient.maxReconnectTries = tries }
                iface = tcpClient

            case "TCPServerInterface":
                let listenPort = ifCfg.int("listen_port") ?? ifCfg.int("port") ?? 4242
                // Python resolves `listen_ip` into `bind_ip` and renders it in `__str__`
                // (Reticulum.py / TCPInterface.py:518). Ignoring it made every Swift
                // listener report 0.0.0.0 regardless of configuration.
                let bindIP = ifCfg["listen_ip"] ?? "0.0.0.0"
                iface = TCPServerInterface(name: ifCfg.name, port: UInt16(listenPort), bindIP: bindIP)

            case "UDPInterface":
                let listenPort = ifCfg.int("listen_port")
                let forwardHost = ifCfg["forward_ip"] ?? ifCfg["forward_host"]
                let forwardPort = ifCfg.int("forward_port")
                iface = UDPInterface(
                    name: ifCfg.name,
                    listenPort: listenPort.map(UInt16.init),
                    forwardHost: forwardHost,
                    forwardPort: forwardPort.map(UInt16.init),
                    // Python's `bind_ip`, which its `__str__` reports (UDPInterface.py:63).
                    bindIP: ifCfg["listen_ip"] ?? "0.0.0.0"
                )

            case "AutoInterface":
                #if canImport(Darwin)
                let groupID = ifCfg["group_id"].flatMap { Data($0.utf8) }
                    ?? AutoInterface.defaultGroupID
                let discoveryPort = ifCfg.int("discovery_port").map(UInt16.init)
                    ?? AutoInterface.defaultDiscoveryPort
                let dataPort = ifCfg.int("data_port").map(UInt16.init)
                    ?? AutoInterface.defaultDataPort
                let allowed = ifCfg["allowed_interfaces"]?
                    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
                let ignored = ifCfg["ignored_interfaces"]?
                    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
                iface = AutoInterface(
                    name: ifCfg.name,
                    groupID: groupID,
                    discoveryPort: discoveryPort,
                    dataPort: dataPort,
                    allowedInterfaces: allowed,
                    ignoredInterfaces: ignored
                )
                #else
                iface = nil
                #endif

            default:
                iface = nil
            }
            if let iface {
                // Everything the block configures, applied before registration so Transport never
                // sees an unconfigured interface, and before `start()` so the IFAC key is installed
                // before the first frame moves — matching `Reticulum.py:975`. Spawned
                // sub-interfaces pick it all up through `InterfaceState.inherit(from:)`.
                //
                // This used to apply `gravity` and `announces_to_internal` and nothing else, which
                // is what `bugs/025`'s second half is: §1 made the rest settable and no parser
                // wrote to them.
                Reticulum.applyInterfaceConfiguration(to: iface, from: ifCfg)
                transport.register(interface: iface)
                try? iface.start()
            }
        }
    }

    // MARK: - Path and interface queries

    /// Returns the next-hop hash for a destination. Mirrors Python `Reticulum.get_next_hop(destination)`.
    public func getNextHop(for destinationHash: Data) -> Data? {
        transport.nextHop(to: destinationHash)
    }

    /// Returns the name of the interface toward the next hop. Mirrors Python `Reticulum.get_next_hop_if_name(destination)`.
    public func getNextHopIfName(for destinationHash: Data) -> String? {
        transport.nextHopInterfaceName(for: destinationHash)
    }

    /// Returns the per-hop timeout for a destination. Mirrors Python `Reticulum.get_first_hop_timeout(destination)`.
    public func getFirstHopTimeout(for destinationHash: Data) -> TimeInterval {
        transport.firstHopTimeout(for: destinationHash)
    }

    // MARK: - Destination retention

    /// Mark a destination as recently used. Mirrors Python `Reticulum._used_destination_data(destination_hash)`.
    @discardableResult
    public func usedDestinationData(_ destinationHash: Data) -> Bool {
        transport.markDestinationUsed(destinationHash)
        return transport.recall(identity: destinationHash) != nil
    }

    /// Pin a destination so `cleanKnownDestinations` never removes it.
    /// Mirrors Python `Reticulum._retain_destination_data(destination_hash)`.
    @discardableResult
    public func retainDestinationData(_ destinationHash: Data) -> Bool {
        transport.retainDestinationData(destinationHash)
    }

    /// Unpin a previously retained destination.
    /// Mirrors Python `Reticulum._unretain_destination_data(destination_hash)`.
    @discardableResult
    public func unretainDestinationData(_ destinationHash: Data) -> Bool {
        transport.unretainDestinationData(destinationHash)
    }

    /// Pin all destinations associated with the given identity hash.
    /// Mirrors Python `Reticulum._retain_identity(identity_hash)`.
    @discardableResult
    public func retainIdentity(_ identityHash: Data) -> Bool {
        transport.retainIdentity(identityHash)
    }

    // MARK: - Interface management

    /// No-op stub. Mirrors Python `Reticulum.halt_interface(interface)`.
    public func haltInterface(_ interface: any Interface) {}

    /// No-op stub. Mirrors Python `Reticulum.resume_interface(interface)`.
    public func resumeInterface(_ interface: any Interface) {}

    /// Stop and restart the named interface, re-applying its stored configuration.
    /// Returns `true` if the interface was found and reloaded; `false` if not found.
    /// Python parity: `Reticulum.reload_interface(name)`
    @discardableResult
    public func reloadInterface(named name: String) -> Bool {
        // 1. Check if the interface is currently registered.
        guard transport.interfaces.first(where: { $0.name == name }) != nil else {
            return false
        }
        // 2. Halt (stop) it.
        transport.halt(interfaceName: name)
        // 3. Resume it (restart).
        transport.resume(interfaceName: name)
        return true
    }

    // MARK: - Helpers

    private func resolvedConfigPath() -> URL? {
        if let explicit = configuration.configPath { return explicit }
        // Default: one level above storagePath, matching Python's layout
        // (<configdir>/storage ↔ <configdir>/config).
        let parent = configuration.storagePath.deletingLastPathComponent()
        let candidate = parent.appendingPathComponent("config")
        return candidate
    }

    private func applyConfig(_ cfg: ReticulumConfig) {
        transport.transportEnabled = cfg.reticulum.enableTransport
        Reticulum.allowProbes_ = cfg.reticulum.allowProbes
        Reticulum.remoteManagementEnabled_ = cfg.reticulum.remoteManagementEnabled
        for identity in cfg.reticulum.remoteManagementAllowed {
            transport.remoteManagementAllowed.append(identity)
        }
        // Discovery-related static properties.
        // Mirrors Python Reticulum.__init__ config application block.
        if let rdv = cfg.reticulum.requiredDiscoveryValue {
            Reticulum.requiredDiscoveryValue_ = rdv
        }
        Reticulum.publishBlackholeEnabled_ = cfg.reticulum.publishBlackholeEnabled
        if let bui = cfg.reticulum.blackholeUpdateInterval {
            Reticulum.blackholeUpdateInterval_ = bui
        }
        if !cfg.reticulum.interfaceDiscoverySources.isEmpty {
            Reticulum.interfaceDiscoverySources_ = cfg.reticulum.interfaceDiscoverySources
        }
        if cfg.reticulum.autoconnectDiscoveredInterfaces > 0 {
            Reticulum.maxAutoconnectedInterfaces_ = cfg.reticulum.autoconnectDiscoveredInterfaces
        }
        // RNS 1.4.1 gravity / autoconnect policy. Each is assigned only when the
        // key was present, so an absent option keeps the built-in default.
        if let dg = cfg.reticulum.defaultGravity { Reticulum.defaultGravity_ = dg }
        if let m  = cfg.reticulum.autoconnectInterfaceMode { Reticulum.autoconnectInterfaceMode_ = m }
        if let g  = cfg.reticulum.autoconnectInterfaceGravity { Reticulum.autoconnectInterfaceGravity_ = g }
        if let a  = cfg.reticulum.autoconnectAnnouncesToInternal { Reticulum.autoconnectAnnouncesToInternal_ = a }
        // Log level mapping: Python 0=critical, 4=info, 8=extreme.
        // Python saturates rather than ignoring an out-of-range value
        // (`if loglevel > 8: loglevel = 8`, raised from 7 in RNS 1.4.1 so
        // LOG_EXTREME is reachable from a config file at all); clamp to match,
        // instead of silently leaving the level at its default.
        let clamped = min(max(cfg.logging.logLevel, 0), LogLevel.extreme.rawValue)
        if let level = LogLevel(rawValue: clamped) {
            Reticulum.globalLogLevel = level
        }
        Reticulum.logTimestamps = cfg.logging.logTimestamps
    }
}
