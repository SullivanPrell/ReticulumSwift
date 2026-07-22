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
    public static let version = "1.4.3"

    /// The Python RNS release whose wire protocol and behavior this port matches.
    /// Mirrors Python's `RNS.__version__` as a parity reference (Python RNS uses
    /// a single version string for both its library and its protocol). Bump only
    /// when parity is verified against a new RNS release. Informational only.
    public static let rnsProtocolVersion = "1.4.0"

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
    /// Mirrors the `__example_rns_config__` constant embedded in `rnsd.py`.
    public static let exampleConfig: String = """
# This is an example Reticulum config file.
# You should probably edit it to include any additional,
# interfaces and settings you might need.

[reticulum]

# If you enable Transport, your system will route traffic
# for other peers, pass announces and serve path requests.
# This should be done for systems that are suited to act
# as transport nodes, ie. if they are stationary and
# always-on. This directive is optional and can be removed
# for brevity.

enable_transport = No


# By default, the first program to launch the Reticulum
# Network Stack will create a shared instance, that other
# programs can communicate with. Only the shared instance
# opens all the configured interfaces directly, and other
# local programs communicate with the shared instance over
# a local socket. This is completely transparent to the
# user, and should generally be turned on. This directive
# is optional and can be removed for brevity.

share_instance = Yes


# If you want to run multiple *different* shared instances
# on the same system, you will need to specify different
# instance names for each. On platforms supporting domain
# sockets, this can be done with the instance_name option:

instance_name = default

# Some platforms don't support domain sockets, and if that
# is the case, you can isolate different instances by
# specifying a unique set of ports for each:

# shared_instance_port = 37428
# instance_control_port = 37429


# You can configure Reticulum to panic and forcibly close
# if an unrecoverable interface error occurs, such as the
# hardware device for an interface disappearing. This is
# an optional directive, and can be left out for brevity.
# This behaviour is disabled by default.

# panic_on_interface_error = No


# When Transport is enabled, it is possible to allow the
# Transport Instance to respond to probe requests from
# the rnprobe utility. This can be a useful tool to test
# connectivity. When this option is enabled, the probe
# destination will be generated from the Identity of the
# Transport Instance, and printed to the log at startup.
# Optional, and disabled by default.

# respond_to_probes = No


[logging]
# Valid log levels are 0 through 7:
#   0: Log only critical information
#   1: Log errors and lower log levels
#   2: Log warnings and lower log levels
#   3: Log notices and lower log levels
#   4: Log info and lower (this is the default)
#   5: Verbose logging
#   6: Debug logging
#   7: Extreme logging

loglevel = 4


# The interfaces section defines the physical and virtual
# interfaces Reticulum will use to communicate on. This
# section will contain examples for a variety of interface
# types. You can modify these or use them as a basis for
# your own config, or simply remove the unused ones.

[interfaces]

  # This interface enables communication with other
  # link-local Reticulum nodes over UDP. It does not
  # need any functional IP infrastructure like routers
  # or DHCP servers, but will require that at least link-
  # local IPv6 is enabled in your operating system, which
  # should be enabled by default in almost any OS. See
  # the Reticulum Manual for more configuration options.

  [[Default Interface]]
    type = AutoInterface
    enabled = yes


  # The following example enables communication with other
  # local Reticulum peers using UDP broadcasts.

  [[UDP Interface]]
    type = UDPInterface
    enabled = no
    listen_ip = 0.0.0.0
    listen_port = 4242
    forward_ip = 255.255.255.255
    forward_port = 4242


  # This example demonstrates a TCP server interface.
  # It will listen for incoming connections on the
  # specified IP address and port number.

  [[TCP Server Interface]]
    type = TCPServerInterface
    enabled = no
    listen_ip = 0.0.0.0
    listen_port = 4242


  # To connect to a TCP server interface, you would
  # naturally use the TCP client interface. Here's
  # an example. The target_host can either be an IP
  # address or a hostname

  [[TCP Client Interface]]
    type = TCPClientInterface
    enabled = no
    target_host = 127.0.0.1
    target_port = 4242


  # Here's an example of how to add a LoRa interface
  # using the RNode LoRa transceiver.

  [[RNode LoRa Interface]]
    type = RNodeInterface
    enabled = no
    port = /dev/ttyUSB0
    frequency = 867200000
    bandwidth = 125000
    txpower = 7
    spreadingfactor = 8
    codingrate = 5


  # An example KISS modem interface. Useful for running
  # Reticulum over packet radio hardware.

  [[Packet Radio KISS Interface]]
    type = KISSInterface
    enabled = no
    port = /dev/ttyUSB1
    speed = 115200
    databits = 8
    parity = none
    stopbits = 1
    preamble = 150
    txtail = 10
    persistence = 200
    slottime = 20
    flow_control = false
"""

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

    /// Returns whether link MTU discovery is enabled globally.
    /// Mirrors Python's `Reticulum.link_mtu_discovery()`.
    /// Default: true (Python `LINK_MTU_DISCOVERY = True`).
    public private(set) static var linkMtuDiscoveryEnabled: Bool = true

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
    public private(set) static var interfaceDiscoverySources_: [Data] = []
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

            case "BackboneInterface":
                guard let host = ifCfg["target_host"],
                      let port = ifCfg.int("target_port") else { continue }
                let bb = BackboneInterface(name: ifCfg.name, host: host, port: UInt16(port))
                iface = bb

            case "TCPClientInterface":
                guard let host = ifCfg["target_host"],
                      let port = ifCfg.int("target_port") else { continue }
                let tcpClient = TCPClientInterface(name: ifCfg.name, host: host, port: UInt16(port))
                if ifCfg.bool("bootstrap_only") == true { tcpClient.bootstrapOnly = true }
                iface = tcpClient

            case "TCPServerInterface":
                let listenPort = ifCfg.int("listen_port") ?? ifCfg.int("port") ?? 4242
                iface = TCPServerInterface(name: ifCfg.name, port: UInt16(listenPort))

            case "UDPInterface":
                let listenPort = ifCfg.int("listen_port")
                let forwardHost = ifCfg["forward_ip"] ?? ifCfg["forward_host"]
                let forwardPort = ifCfg.int("forward_port")
                iface = UDPInterface(
                    name: ifCfg.name,
                    listenPort: listenPort.map(UInt16.init),
                    forwardHost: forwardHost,
                    forwardPort: forwardPort.map(UInt16.init)
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
        // Log level mapping: Python 0=critical, 4=info, 7=extreme.
        if let level = LogLevel(rawValue: cfg.logging.logLevel) {
            Reticulum.globalLogLevel = level
        }
        Reticulum.logTimestamps = cfg.logging.logTimestamps
    }
}
