import Foundation

/// The Transport system. Owns interfaces, registered destinations, and a
/// path table populated from received announces. Announces are validated
/// and forwarded; non-announce packets are delivered to any local
/// destination matching the destination hash.
public final class Transport {

    // MARK: - Constants (mirrors Python Transport class attributes)

    /// Maximum percentage of interface bandwidth used for announce propagation.
    /// Mirrors Python's `Reticulum.ANNOUNCE_CAP = 2`.
    public static let announceCap: Int = 2

    /// Maximum number of queued announces across all interfaces.
    /// Mirrors Python's `Reticulum.MAX_QUEUED_ANNOUNCES = 16384`.
    public static let maxQueuedAnnounces: Int = 16384

    /// Lifetime of a queued announce in seconds.
    /// Mirrors Python's `Reticulum.QUEUED_ANNOUNCE_LIFE = 86400`.
    public static let queuedAnnounceLife: TimeInterval = 86400

    /// Grace period before persist at shutdown (seconds).
    /// Mirrors Python's `Reticulum.GRACIOUS_PERSIST_INTERVAL = 300`.
    public static let graciousPersistInterval: TimeInterval = 300

    /// Minimum bitrate (bits/second) required for Reticulum to function.
    /// Mirrors Python's `Reticulum.MINIMUM_BITRATE = 5`.
    public static let minimumBitrate: Int = 5

    /// Resource cache lifetime in seconds.
    /// Mirrors Python's `Reticulum.RESOURCE_CACHE = 24*60*60`.
    public static let resourceCacheTimeout: TimeInterval = 86400

    /// Background maintenance job interval in seconds.
    /// Python's global `Reticulum.JOB_INTERVAL = 5*60 = 300`, but Swift's
    /// jobs loop runs every 5 seconds for more responsive sweeps.
    public static let cleanInterval: TimeInterval = 900   // Python: 15*60

    /// Interval between persistent data saves in seconds.
    /// Mirrors Python's `Reticulum.PERSIST_INTERVAL = 60*60*12`.
    public static let persistInterval: TimeInterval = 43200

    /// Default path expiry: 7 days. Python: `Transport.PATHFINDER_E = 60*60*24*7`.
    public static let pathExpiry: TimeInterval = 60 * 60 * 24 * 7
    /// Roaming-mode path expiry: 6 hours. Python: `Transport.ROAMING_PATH_TIME = 60*60*6`.
    public static let roamingPathExpiry: TimeInterval = 60 * 60 * 6
    /// Access-point path expiry: 1 day. Python: `Transport.AP_PATH_TIME = 60*60*24`.
    public static let apPathExpiry: TimeInterval = 60 * 60 * 24
    /// How often the jobs loop runs (seconds).
    public static let jobInterval: TimeInterval = 5
    /// How often `cleanKnownDestinations` is invoked from the jobs loop.
    /// Mirrors Python's periodic clean-jobs scheduler in `Reticulum.__clean_caches`
    /// (RNS commit b408699e). Defaults to 1 hour to amortise the table walk.
    public static let knownDestinationsCleanInterval: TimeInterval = 60 * 60
    /// Maximum receipts tracked simultaneously.
    public static let maxReceipts: Int = 1024
    /// Maximum number of hops Reticulum will transport a packet.
    /// Python: `Transport.PATHFINDER_M = 128`.
    public static let pathfinderM: Int = 128
    /// Announce retransmit retries. Python: `Transport.PATHFINDER_R = 1`.
    public static let pathRequestRetries: Int = 1
    /// Retry grace period in seconds. Python: `Transport.PATHFINDER_G = 5`.
    public static let pathfinderG: TimeInterval = 5
    /// Random window for announce rebroadcast jitter. Python: `Transport.PATHFINDER_RW = 0.5`.
    public static let pathfinderRW: TimeInterval = 0.5
    /// Timeout for `awaitPath` (seconds). Python: `Transport.PATH_REQUEST_TIMEOUT = 15`.
    public static let pathRequestTimeout: TimeInterval = 15
    /// Grace time before a path announcement is made, allows directly reachable
    /// peers to respond first. Python: `Transport.PATH_REQUEST_GRACE = 0.4`.
    public static let pathRequestGrace: TimeInterval = 0.4
    /// Extra grace time for roaming-mode interfaces. Python: `Transport.PATH_REQUEST_RG = 1.5`.
    public static let pathRequestRG: TimeInterval = 1.5
    /// Gate control timeout for path requests. Python: `Transport.PATH_REQUEST_GATE_TIMEOUT = 120`.
    public static let pathRequestGateTimeout: TimeInterval = 120
    /// Minimum interval between automated path requests. Python: `Transport.PATH_REQUEST_MI = 20`.
    public static let pathRequestMinInterval: TimeInterval = 20
    /// Maximum local rebroadcasts of an announce. Python: `Transport.LOCAL_REBROADCASTS_MAX = 2`.
    public static let localRebroadcastsMax: Int = 2

    /// Stale threshold for known destinations that have been used (7 days).
    /// Mirrors Python's `Transport.DESTINATION_TIMEOUT`.
    public static let destinationTimeout: TimeInterval = 60 * 60 * 24 * 7
    /// Linger time for never-used, pathless known destinations (6 minutes).
    /// Mirrors Python's `Transport.UNUSED_DESTINATION_LINGER`.
    public static let unusedDestinationLinger: TimeInterval = 6 * 60

    // Path responsiveness state values.
    public static let stateUnknown: UInt8 = 0x00
    public static let stateUnresponsive: UInt8 = 0x01
    public static let stateResponsive: UInt8 = 0x02

    public struct PathEntry: Equatable {
        public let destinationHash: Data
        public let nextHopInterfaceName: String
        public var hops: UInt8
        public var lastHeard: Date
        public let identityHash: Data
        /// Wall-clock time this path expires. Paths older than this are
        /// dropped by `sweepExpiredPaths()`. Matches Python's per-entry
        /// `expires` field (`PATHFINDER_E` = 7 days from announce time).
        public var expires: Date
        /// Transport ID of the next hop along this path. Learned from
        /// HEADER_2 announces; used to address forwarded outbound
        /// traffic. `nil` means "we'll use our own transport ID".
        public var nextHopTransportID: Data?
        /// Unix timestamp (seconds) extracted from the announce's random hash.
        /// Used to determine if a newer announce should override a worse-hop path.
        /// Mirrors Python's timebase logic in Transport.announce_emitted().
        public var announceEmittedAt: TimeInterval = 0
        /// Full 32-byte SHA-256 hash of the announce packet that established this path.
        /// Used to retrieve the cached announce from disk when restoring the path table.
        /// Mirrors Python's `path_table[dst][IDX_PT_PACKET]` = packet_hash field.
        public var cachedAnnounceHash: Data?
        /// Recently-heard 10-byte announce random blobs for this destination,
        /// newest last and capped at `Transport.maxRandomBlobs`. Mirrors Python's
        /// `path_table[dst][IDX_PT_RANDBLOBS]`. An announce whose random blob is
        /// already present is a replay and is rejected (prevents path forging /
        /// network loops via captured announces).
        public var randomBlobs: [Data] = []

        public init(
            destinationHash: Data,
            nextHopInterfaceName: String,
            hops: UInt8,
            lastHeard: Date,
            identityHash: Data,
            expires: Date? = nil,
            nextHopTransportID: Data? = nil,
            announceEmittedAt: TimeInterval = 0,
            cachedAnnounceHash: Data? = nil,
            randomBlobs: [Data] = []
        ) {
            self.destinationHash = destinationHash
            self.nextHopInterfaceName = nextHopInterfaceName
            self.hops = hops
            self.lastHeard = lastHeard
            self.identityHash = identityHash
            self.expires = expires ?? lastHeard.addingTimeInterval(Transport.pathExpiry)
            self.nextHopTransportID = nextHopTransportID
            self.announceEmittedAt = announceEmittedAt
            self.cachedAnnounceHash = cachedAnnounceHash
            self.randomBlobs = randomBlobs
        }

        public var isExpired: Bool { Date() >= expires }
    }

    /// Learned routing for an in-flight or active multi-hop link. The relay
    /// records which interface saw the LRR (initiator side) and which it
    /// forwarded the LRR onto (responder side); subsequent traffic for the
    /// link is forwarded through whichever interface didn't deliver it.
    public struct LinkRoute: Equatable {
        public let linkID: Data
        public let initiatorSideInterfaceName: String
        public let responderSideInterfaceName: String
        /// Original destination hash from the LINKREQUEST packet.
        /// Mirrors Python's `link_table[link_id][IDX_LT_DSTHASH]`.
        /// Used by `handleLinkRequestProof` to call `markDestinationUsed`
        /// after a relay node successfully forwards the LRPROOF.
        public let destinationHash: Data
        public var lastHeard: Date
    }

    /// A tunnel entry: tracks an interface that was synthesized as a tunnel endpoint
    /// and the paths that have been learned through it.
    /// Mirrors Python's `Transport.tunnels` table entries.
    public struct TunnelEntry {
        public let tunnelID: Data
        public weak var iface: (any Interface)?
        public var paths: [Data: PathEntry]
        public var expires: Date
    }

    /// Timeout for tunnel table entries. Matches Python `TUNNEL_TIMEOUT` (8 hours).
    public static let tunnelTimeout: TimeInterval = 60 * 60 * 8

    /// Per-destination entry in the announce rate table.
    /// Mirrors Python's rate_entry dict in `Transport.announce_rate_table`.
    struct AnnounceRateEntry {
        var last: TimeInterval       // timestamp of last accepted announce
        var violations: Int          // cumulative violation count
        var blockedUntil: TimeInterval  // if > now, announces are blocked
        var timestamps: [TimeInterval]  // recent announce timestamps (capped at MAX_RATE_TIMESTAMPS)
    }

    /// Snapshot of an interface's byte counts used for speed computation.
    /// Mirrors Python's `transport_traffic_counter` dict on each interface.
    struct SpeedSample {
        var rxBytes: Int
        var txBytes: Int
        var timestamp: TimeInterval
    }

    public private(set) var interfaces: [Interface] = []
    public private(set) var registeredDestinations: [Data: Destination] = [:]
    public internal(set) var paths: [Data: PathEntry] = [:]
    public private(set) var knownIdentities: [Data: Identity] = [:] // by destination hash
    /// When each known identity was last announced. Used by `cleanKnownDestinations()`.
    /// Mirrors Python's `Identity.known_destinations[hash][0]` (last_announce field).
    var knownDestinationAnnouncedAt: [Data: Date] = [:]
    /// When each known identity was last used (recalled for outbound). nil = never used.
    /// Mirrors Python's `Identity.known_destinations[hash][4]` (last_use field, 0 = never).
    var knownDestinationLastUsed: [Data: Date] = [:]
    /// Destinations explicitly marked as retained — never swept by `cleanKnownDestinations`.
    /// Mirrors Python's last_use == -1 sentinel.
    var retainedDestinations: Set<Data> = []

    /// Most recent ratchet public key learned per destination, from
    /// announces. 32 bytes each. Used so outbound encryption can target
    /// the destination's freshest ratchet (forward secrecy).
    public private(set) var knownRatchets: [Data: Data] = [:]

    /// Wall-clock receive time per learned ratchet. Aged out per
    /// `ratchetExpiry` — matches Python's `Identity._remember_ratchet`
    /// / `Identity.get_ratchet` (which discard entries older than
    /// `RATCHET_EXPIRY`).
    public private(set) var knownRatchetTimes: [Data: Date] = [:]

    /// Expiry window for learned ratchets. Defaults to 30 days,
    /// matching `Identity.RATCHET_EXPIRY`.
    public var ratchetExpiry: TimeInterval = 60 * 60 * 24 * 30

    /// Optional directory where learned ratchets are persisted, one
    /// file per destination (`<dir>/<desthex>`), matching Python's
    /// `<storagepath>/ratchets/<hex>` layout. Set by `Reticulum.start`.
    public var ratchetsDirectory: URL?
    public private(set) var links: [Data: Link] = [:]               // by link id
    public private(set) var linkRoutes: [Data: LinkRoute] = [:]     // by link id
    /// Active tunnel entries keyed by tunnel ID (SHA-256 of pubkey+ifaceHash).
    /// Mirrors Python's `Transport.tunnels` dict.
    public var tunnels: [Data: TunnelEntry] = [:]
    public private(set) var isRunning: Bool = false

    /// Unix timestamp when `start()` was called. Used to compute transport uptime.
    /// Mirrors Python's `Transport.start_time`.
    public private(set) var startTime: TimeInterval = 0

    /// Identity used to answer incoming link requests on registered
    /// destinations. The host sets this when it knows its local identity.
    public var ownerIdentity: Identity?

    /// Optional network identity, used for remote management and interface discovery.
    /// Once set, it cannot be changed (mirrors Python's Transport.network_identity
    /// which can only be set if not already set).
    public private(set) var networkIdentity: Identity?

    /// Returns whether a network identity has been set.
    /// Mirrors Python's `Transport.has_network_identity()`.
    public var hasNetworkIdentity: Bool { networkIdentity != nil }

    /// Set the network identity. Only takes effect if not already set.
    /// Mirrors Python's `Transport.set_network_identity(identity)`.
    public func setNetworkIdentity(_ identity: Identity) {
        guard networkIdentity == nil else { return }
        networkIdentity = identity
    }

    /// When `true`, this node relays announces it sees to its other
    /// interfaces (a transport-enabled mesh node). When `false`, the node
    /// only originates and consumes announces (an edge node).
    public var transportEnabled: Bool = true

    /// When `true`, this node is attached as a *client* to an external shared
    /// instance (e.g. an `rnsd` daemon over a `LocalInterface`), and that
    /// instance performs all packet filtering/routing on our behalf. In that
    /// case `filterAndRecord` must not re-filter (mirrors Python's
    /// `if Transport.owner.is_connected_to_shared_instance: return True`).
    /// Defaults to `false` for standalone / embedded transport nodes.
    public var isConnectedToSharedInstance: Bool = false

    /// Per-instance propagation limit; defaults to `pathfinderM`.
    public var propagationLimit: UInt8 = UInt8(Transport.pathfinderM)

    /// Per-session hop-count obfuscation delta. When non-zero, packets that
    /// originate locally (`hops == 0`) — our own traffic and traffic relayed for
    /// directly-connected local clients — have their hop count rewritten to this
    /// value when injected into the wider network, hiding that they came from
    /// here. `0` disables the feature (the default). Set to a random value in
    /// 2...7 at startup when the `local_hops_delta` config option is enabled.
    /// Mirrors Python's `Transport.local_hops_delta`.
    public var localHopsDelta: UInt8 = 0

    /// 16-byte random instance id. Generated on first access, but can be
    /// overridden before `start()` to restore a persisted identity across
    /// restarts. Matches `Transport.identity.hash` semantics in Python.
    public var transportInstanceID: Data = {
        var bytes = Data(count: Constants.truncatedHashLength)
        _ = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, Constants.truncatedHashLength, $0.baseAddress!)
        }
        return bytes
    }()

    /// Most-recent validated announce packet keyed by destination hash.
    /// Used to answer path requests on behalf of remote destinations we
    /// have a path to.
    public private(set) var cachedAnnounces: [Data: Packet] = [:]

    /// Path responsiveness state per destination hash.
    /// Mirrors Python's `Transport.path_states` dict.
    private var pathStates: [Data: UInt8] = [:]
    private let pathStatesLock = NSLock()

    /// Reverse lookup table for multi-hop proof forwarding.
    /// Maps truncated packet hash (16 bytes) → (receiveInterface, outboundInterface).
    /// When a DATA packet is forwarded, the entry is stored so that the resulting
    /// proof can be forwarded back to the originating interface.
    /// Mirrors Python's `Transport.reverse_table`.
    private var reverseTable: [Data: (receiveIface: any Interface, outboundIface: any Interface)] = [:]
    private let reverseTableLock = NSLock()

    /// Dedup keys for path requests we've already processed —
    /// `destinationHash + tag`. FIFO bounded.
    private var pathRequestTags: [Data] = []
    private var pathRequestTagSet: Set<Data> = []
    public var pathRequestCacheCap: Int = 4096

    /// Dedup keys for announces already seen — `destinationHash + randomHash`.
    /// Bounded to `announceCacheCap` entries (FIFO).
    private var announceCache: [Data] = []
    private var announceCacheSet: Set<Data> = []
    public var announceCacheCap: Int = 4096

    /// A forwarded announce pending a single retransmission. Mirrors Python's
    /// `Transport.announce_table` 9-tuple (`IDX_AT_*`). Swift forwards the first
    /// copy immediately, then retransmits once more (`PATHFINDER_R`) after the
    /// grace window unless the announce is heard carried on by neighbours.
    struct AnnounceTableEntry {
        var timestamp: TimeInterval           // IDX_AT_TIMESTAMP — when forwarded
        var retransmitTimeout: TimeInterval   // IDX_AT_RTRNS_TMO — next retry time
        var retries: Int                      // IDX_AT_RETRIES   — transmissions so far
        var hops: Int                         // IDX_AT_HOPS      — raw wire hops at receipt
        var packet: Packet                    // IDX_AT_PACKET    — the received announce
        var localRebroadcasts: Int            // IDX_AT_LCL_RBRD  — sibling rebroadcasts heard
        var blockRebroadcasts: Bool           // IDX_AT_BLCK_RBRD — emit as PATH_RESPONSE
        var attachedInterfaceName: String?    // IDX_AT_ATTCHD_IF — restrict retransmit to one iface
        var receivingInterfaceName: String    // iface the announce arrived on (never echoed back)
        var receivingInterfaceMode: InterfaceMode  // for the announce-propagation filter on retry
    }
    /// Pending announce retransmissions keyed by destination hash. Guarded by `lock`.
    private var announceTable: [Data: AnnounceTableEntry] = [:]

    /// Per-interface announce and path-request frequency tracker.
    /// Mirrors Python's Interface.ia_freq_deque etc.
    private var ifaceFreqTrackers: [ObjectIdentifier: InterfaceFreqTracker] = [:]

    /// Per-interface ingress burst control state.
    /// Mirrors Python's per-interface ic_burst_active, held_announces, etc.
    private var ingressStates: [ObjectIdentifier: IngressControlState] = [:]

    /// Root directory for the on-disk packet cache (announce sub-cache).
    /// Mirrors Python's `RNS.Reticulum.cachepath`.
    /// Set by `Reticulum.start()`.
    public var cacheDirectory: URL?

    /// Blackholed identities: identity hash → BlackholeEntry.
    /// Mirrors Python's `Transport.blackholed_identities` dict.
    public var blackholedIdentities: [Data: BlackholeEntry] = [:]

    /// Cumulative bytes received across all interfaces (inbound).
    /// Mirrors Python's `Transport.traffic_rxb`.
    public private(set) var trafficRxBytes: Int = 0
    /// Cumulative bytes transmitted across all interfaces (outbound).
    /// Mirrors Python's `Transport.traffic_txb`.
    public private(set) var trafficTxBytes: Int = 0

    /// Per-destination announce rate tracking.
    /// Mirrors Python's `Transport.announce_rate_table`.
    private var announceRateTable: [Data: AnnounceRateEntry] = [:]
    /// Maximum announce timestamps kept per destination.
    /// Mirrors Python's `Transport.MAX_RATE_TIMESTAMPS = 16`.
    public static let maxRateTimestamps: Int = 16
    /// Grace wait before announcing connectivity readiness (seconds).
    /// Python: `Transport.READY_WAIT = 60`.
    public static let readyWait: TimeInterval = 60
    /// Reverse path table entry lifetime (seconds). Python: `Transport.REVERSE_TIMEOUT = 8*60`.
    public static let reverseTimeout: TimeInterval = 8 * 60
    /// Timeout for tunnel-sourced path entries. Python: `Transport.TUNNEL_PATH_TIMEOUT = 60*60*8`.
    public static let tunnelPathTimeout: TimeInterval = 60 * 60 * 8
    /// Maximum random blobs kept in memory. Python: `Transport.MAX_RANDOM_BLOBS = 64`.
    public static let maxRandomBlobs: Int = 64
    /// Number of random blobs persisted to disk. Python: `Transport.PERSIST_RANDOM_BLOBS = 32`.
    public static let persistRandomBlobs: Int = 32

    /// Per-interface last-sampled byte counts and timestamp for speed computation.
    private var ifaceSpeedSamples: [ObjectIdentifier: SpeedSample] = [:]
    /// Per-interface current RX speed (bits/sec). Mirrors Python `Interface.current_rx_speed`.
    private var ifaceCurrentRxSpeed: [ObjectIdentifier: Double] = [:]
    /// Per-interface current TX speed (bits/sec). Mirrors Python `Interface.current_tx_speed`.
    private var ifaceCurrentTxSpeed: [ObjectIdentifier: Double] = [:]
    /// Aggregate RX speed across all interfaces (bits/sec). Mirrors Python `Transport.speed_rx`.
    public private(set) var speedRx: Double = 0
    /// Aggregate TX speed across all interfaces (bits/sec). Mirrors Python `Transport.speed_tx`.
    public private(set) var speedTx: Double = 0

    // MARK: - Packet PHY stats cache
    // Mirrors Python's Transport.local_client_rssi_cache / snr_cache / q_cache.
    // Capped at LOCAL_CLIENT_CACHE_MAXSIZE = 512 entries.
    public static let localClientCacheMaxSize: Int = 512
    private var packetRssiCache: [(hash: Data, rssi: Float)] = []
    private var packetSnrCache:  [(hash: Data, snr: Float)] = []
    private var packetQCache:    [(hash: Data, quality: Float)] = []

    // MARK: - Interface discovery integration
    // Mirrors Python's Transport.interface_announcer / discovery_handler / blackhole_updater.

    /// Active interface-discovery listener. Created by `discoverInterfaces(storagePath:...)`.
    /// Mirrors Python `Transport.discovery_handler`.
    public var discoveryHandler: InterfaceDiscovery?

    /// The `AnnounceHandler` registered with this transport for interface discovery.
    /// Kept so it can be deregistered by `stopDiscoverInterfaces()`.
    public var discoveryAnnounceHandler: InterfaceAnnounceHandler?

    /// Active blackhole-list updater. Created by `enableBlackholeUpdater()`.
    /// Mirrors Python `Transport.blackhole_updater`.
    public var blackholeUpdater: BlackholeUpdater?

    // MARK: - Transport identity
    // The transport's own Identity, used for SINGLE management/probe destinations
    // and as the transport instance ID on the wire. Mirrors Python's
    // `Transport.identity`. For a non-transport node (unless
    // `static_transport_identity` is set) this is a fresh ephemeral identity
    // generated at startup — see `internalIdentity` for the persistent one.
    public var transportIdentity: Identity?

    // The persistent on-disk transport identity. Equals `transportIdentity`
    // except when an ephemeral transport identity is in use, in which case this
    // retains the stable identity (used e.g. to derive the RPC auth key so it
    // stays constant across runs). Mirrors Python's `Transport._identity` /
    // `Transport.internal_identity()`.
    public var internalIdentity: Identity?

    // MARK: - Management destinations
    public private(set) var probeDestination: Destination?
    public private(set) var remoteManagementDestination: Destination?
    public var remoteManagementAllowed: [Identity] = []

    public var onAnnounceReceived: ((Announce.Decoded, any Interface) -> Void)?
    public var onPacketDelivered: ((Packet, Destination, any Interface) -> Void)?
    public var onLinkEstablished: ((Link) -> Void)?

    /// Fires when a path request lands on a destination we have registered
    /// locally. The host should respond by emitting a fresh signed
    /// announce for that destination on the supplied interface (Transport
    /// doesn't own destination identities, so it can't sign on its own).
    public var onPathRequested: ((Data, any Interface) -> Void)?

    /// Externally registered announce handlers (mirrors Python's
    /// `Transport.announce_handlers`). Use `register(announceHandler:)`.
    private var announceHandlers: [any AnnounceHandler] = []
    private let announceHandlerLock = NSLock()

    /// Outstanding packet receipts. Bounded to `maxReceipts`, swept by the
    /// jobs loop every second. Matches Python's `Transport.receipts`.
    private var receipts: [PacketReceipt] = []
    private let receiptsLock = NSLock()

    /// Per-interface announce queues. Keyed by interface name.
    private var announceQueues: [String: AnnounceQueue] = [:]
    private let queueLock = NSLock()

    /// Packet hashlist for replay/loop prevention. Two-generation rolling
    /// set — mirrors Python's `packet_hashlist` / `packet_hashlist_prev`.
    private var packetHashlist: Set<Data> = []
    private var packetHashlistPrev: Set<Data> = []
    private let hashlistLock = NSLock()
    /// Rotate the current hashlist into the previous slot when it reaches
    /// this size. Half of Python's 1M default.
    public var hashlistMaxSize: Int = 500_000

    let lock = NSLock()

    // Background jobs timer — nil until `start()`.
    private var jobsTimer: DispatchSourceTimer?
    /// Last time `cleanKnownDestinations` was invoked by the jobs loop.
    /// Used to amortise the sweep at `knownDestinationsCleanInterval` cadence.
    private var lastKnownDestinationsClean: Date = .distantPast

    public init() {}

    // MARK: - Announce handlers

    /// Register a handler that is called whenever a matching announce arrives.
    /// Matches Python's `Transport.register_announce_handler`.
    public func register(announceHandler: any AnnounceHandler) {
        announceHandlerLock.lock(); defer { announceHandlerLock.unlock() }
        announceHandlers.append(announceHandler)
    }

    /// Remove a previously registered announce handler.
    public func deregister(announceHandler: any AnnounceHandler) {
        announceHandlerLock.lock(); defer { announceHandlerLock.unlock() }
        announceHandlers.removeAll { $0 === announceHandler }
    }

    // MARK: - Path queries

    /// True if this Transport has a known path to `destinationHash`.
    /// Mirrors Python's `Transport.has_path(destination_hash)`.
    public func hasPath(to destinationHash: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return paths[destinationHash] != nil
    }

    /// Hop count to `destinationHash`, or nil if no path is known.
    /// Mirrors Python's `Transport.hops_to(destination_hash)`.
    public func hopsTo(_ destinationHash: Data) -> UInt8? {
        lock.lock(); defer { lock.unlock() }
        return paths[destinationHash]?.hops
    }

    /// The next-hop destination hash (transport ID) for a known path, or nil.
    /// Mirrors Python's `Transport.next_hop(destination_hash)`.
    public func nextHop(to destinationHash: Data) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return paths[destinationHash]?.nextHopTransportID
    }

    /// The interface name the next hop is reachable on, or nil if unknown.
    /// Mirrors Python's `Transport.next_hop_interface(destination_hash)`.
    public func nextHopInterfaceName(for destinationHash: Data) -> String? {
        lock.lock(); defer { lock.unlock() }
        return paths[destinationHash]?.nextHopInterfaceName
    }

    /// The live `Interface` object for the next hop, or nil.
    public func nextHopInterface(for destinationHash: Data) -> (any Interface)? {
        guard let name = nextHopInterfaceName(for: destinationHash) else { return nil }
        return interfaces.first { $0.name == name }
    }

    // MARK: - Interface management

    /// Bring an interface offline. The interface stays registered but no longer
    /// forwards packets. Mirrors Python `Reticulum.halt_interface()`.
    public func halt(interfaceName: String) {
        lock.lock()
        let iface = interfaces.first { $0.name == interfaceName }
        lock.unlock()
        iface?.stop()
    }

    /// Bring a previously halted interface back online.
    /// Mirrors Python `Reticulum.resume_interface()`.
    public func resume(interfaceName: String) {
        lock.lock()
        let iface = interfaces.first { $0.name == interfaceName }
        lock.unlock()
        try? iface?.start()
    }

    /// Drop all paths that route through `transportHash`. Returns count of dropped paths.
    /// Mirrors Python `Reticulum.drop_all_via(transport_hash)`.
    @discardableResult
    public func dropAllPaths(via transportHash: Data) -> Int {
        lock.lock()
        let toRemove = Array(paths.filter { $0.value.nextHopTransportID == transportHash }.keys)
        for k in toRemove { paths.removeValue(forKey: k) }
        lock.unlock()
        return toRemove.count
    }

    /// Drop all queued announce packets from all interface queues.
    /// Mirrors Python `Transport.drop_announce_queues()`.
    /// Sort registered interfaces by bitrate (descending) so that higher-bandwidth
    /// interfaces are preferred for outbound traffic.
    /// Mirrors Python's `Transport.prioritize_interfaces()`.
    public func prioritizeInterfaces() {
        lock.lock()
        interfaces.sort { $0.bitrate > $1.bitrate }
        lock.unlock()
    }

    public func dropAnnounceQueues() {
        lock.lock()
        announceQueues.removeAll()
        lock.unlock()
    }

    /// Extract the announce emission timestamp from a random blob (bytes 5..9, big-endian).
    /// Mirrors Python `Transport.timebase_from_random_blob(random_blob)`.
    public static func timebaseFromRandomBlob(_ blob: Data) -> TimeInterval {
        guard blob.count >= 10 else { return 0 }
        var ts: UInt64 = 0
        for i in 5..<10 { ts = (ts << 8) | UInt64(blob[i]) }
        return TimeInterval(ts)
    }

    /// Returns the maximum emission timestamp across multiple random blobs.
    /// Mirrors Python `Transport.timebase_from_random_blobs(random_blobs)`.
    public static func timebaseFromRandomBlobs(_ blobs: [Data]) -> TimeInterval {
        blobs.reduce(0) { max($0, timebaseFromRandomBlob($1)) }
    }

    /// Returns true if the interface is a local-client interface.
    /// Mirrors Python `Transport.from_local_client(packet)` — in Swift, callers supply the interface directly.
    public func fromLocalClient(interface iface: any Interface) -> Bool {
        isLocalClientInterface(iface)
    }

    /// Returns true if the interface is one that serves a locally-connected
    /// shared-instance client — the SERVER side. Mirrors Python
    /// `Transport.is_local_client_interface(interface)`, which is true only for a
    /// per-client connection whose `parent_interface.is_local_shared_instance`.
    /// In Swift the per-client sockets are collapsed into a single
    /// `LocalClientServingInterface` (e.g. `PosixTCPServer` on the shared-instance
    /// port), so that protocol conformance is exactly the "local client" marker.
    ///
    /// NOTE: this is the opposite end from `LocalInterface`. A `LocalInterface` is
    /// *this* node's connection *to* a shared instance (the client side) and is
    /// therefore NOT a local-client interface — see `interfaceToSharedInstance`.
    public func isLocalClientInterface(_ interface: any Interface) -> Bool {
        `interface` is any LocalClientServingInterface
    }

    /// Returns true if the interface is this node's own connection *to* a shared
    /// instance (the client side). Mirrors Python
    /// `Transport.interface_to_shared_instance(interface)` (true when the interface
    /// has `is_connected_to_shared_instance`). In Swift that is `LocalInterface`.
    public func interfaceToSharedInstance(_ interface: any Interface) -> Bool {
        `interface` is LocalInterface
    }

    /// Interfaces currently serving one or more locally-connected shared-instance
    /// clients, excluding `excluded` (typically the interface the triggering
    /// packet arrived on). Mirrors a non-empty Python `Transport.local_client_interfaces`.
    private func localClientServingInterfaces(excluding excluded: (any Interface)?) -> [any Interface] {
        interfaces.filter { iface in
            guard let serving = iface as? any LocalClientServingInterface, serving.clientCount > 0 else { return false }
            return iface !== excluded
        }
    }

    /// Whether the local hop-count obfuscation delta should be applied when
    /// transmitting `packet` out over `interface`. True only for our own freshly
    /// originated packets (`hops == 0`) that are addressed to real (single/link)
    /// destinations and leave over a non-local, non-shared-instance interface,
    /// while the feature is enabled and we're not behind a shared instance.
    /// Mirrors Python `Transport.should_apply_delta(packet, interface)`.
    func shouldApplyDelta(_ packet: Packet, interface: any Interface) -> Bool {
        return !isConnectedToSharedInstance
            && packet.hops == 0
            && localHopsDelta != 0
            && packet.destinationType != .plain
            && packet.destinationType != .group
            && !isLocalClientInterface(interface)
            && !interfaceToSharedInstance(interface)
    }

    /// Return a copy of `packet` with its hop count rewritten to `hops`. When
    /// `transportInsert` is true, also promote it to a HEADER_2 transport packet
    /// carrying this instance's transport id (used when obfuscating a locally
    /// originated HEADER_1 announce as it is injected into transport).
    /// Mirrors Python `Transport.mangle_hops(raw, hops, transport_insert)`.
    func mangleHops(_ packet: Packet, hops: UInt8, transportInsert: Bool = false) -> Packet {
        var p = packet
        p.hops = hops
        if transportInsert {
            p.headerType    = .type2
            p.transportType = .transport
            p.transportID   = transportInstanceID
        }
        return p
    }

    /// Hop count to stamp when relaying `packet` (received on `sourceInterface`)
    /// onward. Normally the received hop count + 1, but obfuscated to
    /// `localHopsDelta` when the packet came from a directly-connected local
    /// client and is NOT staying within the local-client domain (and the feature
    /// is enabled). `staysLocal` is the site-specific "don't obfuscate" condition
    /// (`instance_local_link` for link traffic, `proof_for_local_client` for
    /// proofs, `to_local_client` for data). Mirrors the
    /// `packet.hops if not from_local_client or <staysLocal> or local_hops_delta == 0
    /// else local_hops_delta` idiom in Python `Transport.inbound()`.
    func relayHops(_ packet: Packet, from sourceInterface: any Interface, staysLocal: Bool) -> UInt8 {
        if localHopsDelta != 0, isLocalClientInterface(sourceInterface), !staysLocal {
            return localHopsDelta
        }
        return packet.hops &+ 1
    }

    /// Clear transient in-memory queues (held announces, receipts, reverse table).
    /// Mirrors Python `Transport.void_queues()`.
    public func voidQueues() {
        lock.lock()
        for key in ingressStates.keys { ingressStates[key]?.heldAnnounces = [:] }
        lock.unlock()
        receiptsLock.lock()
        receipts.removeAll()
        receiptsLock.unlock()
        reverseTableLock.lock()
        reverseTable.removeAll()
        reverseTableLock.unlock()
    }

    /// Tear down all active and pending links, then stop all interfaces.
    /// Mirrors Python `Transport.detach_interfaces()`. After tearing down
    /// any links, waits 150 ms so the teardown packets can leave the local
    /// transport before the interfaces stop. Mirrors RNS commit 695d4d86.
    public func detachInterfaces() {
        lock.lock()
        let allLinks = links.values.map { $0 }
        lock.unlock()
        var closedLinks = 0
        for link in allLinks {
            do { try link.teardown(); closedLinks += 1 } catch { /* log and continue */ }
        }
        if closedLinks > 0 { Thread.sleep(forTimeInterval: 0.15) }
        for iface in interfaces { iface.stop() }
    }

    /// Interface statistics snapshot. Mirrors the structure returned by
    /// Python's `Reticulum.get_interface_stats()`.
    public struct InterfaceStats {
        public let name: String
        public let isOnline: Bool
        public let bitrate: Int
        public let rxBytes: Int
        public let txBytes: Int
        public let rxPackets: Int
        public let txPackets: Int
        public let hwMtu: Int?
        /// Incoming announce frequency in Hz. Mirrors Python `Interface.incoming_announce_frequency()`.
        public let incomingAnnounceFrequency: Double
        /// Outgoing announce frequency in Hz. Mirrors Python `Interface.outgoing_announce_frequency()`.
        public let outgoingAnnounceFrequency: Double
        /// Incoming path-request frequency in Hz. Mirrors Python `Interface.incoming_pr_frequency()`.
        public let incomingPrFrequency: Double
        /// Outgoing path-request frequency in Hz. Mirrors Python `Interface.outgoing_pr_frequency()`.
        public let outgoingPrFrequency: Double
        /// Current RX throughput in bits/sec. Mirrors Python `Interface.current_rx_speed`.
        public let currentRxSpeed: Double
        /// Current TX throughput in bits/sec. Mirrors Python `Interface.current_tx_speed`.
        public let currentTxSpeed: Double
    }

    /// Aggregate transport-level traffic statistics.
    /// Mirrors the top-level `rxb`/`txb`/`rxs`/`txs` fields in Python's `Reticulum.get_interface_stats()`.
    public struct TransportStats {
        public let trafficRxBytes: Int
        public let trafficTxBytes: Int
        /// Aggregate RX speed (bits/sec). Mirrors Python `Transport.speed_rx`.
        public let speedRx: Double
        /// Aggregate TX speed (bits/sec). Mirrors Python `Transport.speed_tx`.
        public let speedTx: Double
    }

    /// Returns aggregate transport-level traffic statistics.
    public func getTransportStats() -> TransportStats {
        lock.lock(); defer { lock.unlock() }
        return TransportStats(
            trafficRxBytes: trafficRxBytes,
            trafficTxBytes: trafficTxBytes,
            speedRx: speedRx,
            speedTx: speedTx
        )
    }

    /// Returns statistics for all registered interfaces.
    /// Mirrors Python's `Reticulum.get_interface_stats()`.
    public func getInterfaceStats() -> [InterfaceStats] {
        lock.lock()
        let snapshot = interfaces
        let trackers = ifaceFreqTrackers
        lock.unlock()
        return snapshot.map { iface in
            let tracker = trackers[ObjectIdentifier(iface)]
            return InterfaceStats(
                name: iface.name,
                isOnline: iface.isOnline,
                bitrate: iface.bitrate,
                rxBytes: iface.rxBytes,
                txBytes: iface.txBytes,
                rxPackets: iface.rxPackets,
                txPackets: iface.txPackets,
                hwMtu: iface.hwMtu,
                incomingAnnounceFrequency: tracker?.incomingAnnounceFrequency() ?? 0,
                outgoingAnnounceFrequency: tracker?.outgoingAnnounceFrequency() ?? 0,
                incomingPrFrequency: tracker?.incomingPathRequestFrequency() ?? 0,
                outgoingPrFrequency: tracker?.outgoingPathRequestFrequency() ?? 0,
                currentRxSpeed: currentRxSpeed(for: iface),
                currentTxSpeed: currentTxSpeed(for: iface)
            )
        }
    }

    // MARK: - Announce rate table (mirrors Python Transport.announce_rate_table)

    /// Check whether an announce from `destinationHash` on `interface` should be blocked
    /// by the per-destination rate limiter. Updates the rate table as a side effect.
    /// Returns `false` (not blocked) when `interface.announceRateTarget == nil`.
    /// Mirrors Python's rate_blocked logic in `Transport.inbound` announce handling.
    public func isAnnounceRateBlocked(destinationHash: Data,
                                       interface: any Interface,
                                       now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let target = interface.announceRateTarget else { return false }

        if announceRateTable[destinationHash] == nil {
            // First announce — seed the entry, never blocked.
            announceRateTable[destinationHash] = AnnounceRateEntry(
                last: now, violations: 0, blockedUntil: 0, timestamps: [now]
            )
            return false
        }

        var entry = announceRateTable[destinationHash]!
        entry.timestamps.append(now)
        while entry.timestamps.count > Transport.maxRateTimestamps {
            entry.timestamps.removeFirst()
        }

        let currentRate = now - entry.last

        if now > entry.blockedUntil {
            if currentRate < target {
                entry.violations += 1
            } else {
                entry.violations = max(0, entry.violations - 1)
            }

            if entry.violations > interface.announceRateGrace {
                // Block for rateTarget + ratePenalty seconds from the last recorded time.
                entry.blockedUntil = entry.last + target + interface.announceRatePenalty
                announceRateTable[destinationHash] = entry
                return true
            } else {
                entry.last = now
                announceRateTable[destinationHash] = entry
                return false
            }
        } else {
            announceRateTable[destinationHash] = entry
            return true  // still within block window
        }
    }

    /// Test helper: number of timestamps stored for `destinationHash` in the rate table.
    public func announceRateTimestampCount(for destinationHash: Data) -> Int {
        announceRateTable[destinationHash]?.timestamps.count ?? 0
    }

    /// Snapshot of a rate table entry for external consumption.
    /// Mirrors the dict fields returned by Python's `Reticulum.get_rate_table()`.
    public struct RateTableEntry {
        public var destinationHash: Data
        public var last: TimeInterval
        public var rateViolations: Int
        public var blockedUntil: TimeInterval
        public var timestamps: [TimeInterval]
    }

    /// Returns a snapshot of the current announce rate table.
    /// Mirrors Python's `Reticulum.get_rate_table()`.
    public func getRateTable() -> [RateTableEntry] {
        lock.lock(); defer { lock.unlock() }
        return announceRateTable.map { (hash, entry) in
            RateTableEntry(
                destinationHash: hash,
                last: entry.last,
                rateViolations: entry.violations,
                blockedUntil: entry.blockedUntil,
                timestamps: entry.timestamps
            )
        }
    }

    /// Test helper: directly insert a rate table entry for testing getRateTable().
    public func testInjectReceipt(_ receipt: PacketReceipt) {
        receiptsLock.lock(); defer { receiptsLock.unlock() }
        receipts.append(receipt)
    }

    public func testReceiptCount() -> Int {
        receiptsLock.lock(); defer { receiptsLock.unlock() }
        return receipts.count
    }

    public func testInjectRateEntry(for destinationHash: Data, last: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        announceRateTable[destinationHash] = AnnounceRateEntry(
            last: last, violations: 0, blockedUntil: 0, timestamps: [last]
        )
    }

    /// Seed a named announce queue so tests can verify `dropAnnounceQueues()` clears it.
    public func testInjectAnnounceQueue(interfaceName: String) {
        queueLock.lock(); defer { queueLock.unlock() }
        if announceQueues[interfaceName] == nil {
            announceQueues[interfaceName] = AnnounceQueue()
        }
    }

    /// Returns `true` if a queue entry exists for the given interface name.
    public func hasAnnounceQueue(for interfaceName: String) -> Bool {
        queueLock.lock(); defer { queueLock.unlock() }
        return announceQueues[interfaceName] != nil
    }

    // MARK: - Ingress burst control (mirrors Python Interface.should_ingress_limit / hold_announce / process_held_announces)

    /// Checks whether inbound announces on `interface` should be held due to burst flooding.
    /// Updates internal burst-active state as a side effect.
    /// Returns `false` when `interface.ingressControl == false`.
    ///
    /// Mirrors Python's `Interface.should_ingress_limit()`.
    public func shouldIngressLimit(on interface: any Interface,
                                   now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard interface.ingressControl else { return false }
        let key = ObjectIdentifier(interface)
        guard var state = ingressStates[key],
              let tracker = ifaceFreqTrackers[key] else { return false }

        let age = now - interface.createdAt.timeIntervalSince1970
        let threshold = age < IngressControlState.icNewTime
            ? IngressControlState.icBurstFreqNew
            : IngressControlState.icBurstFreq
        let freq = tracker.incomingAnnounceFrequency(now: now)

        if state.burstActive {
            // Deactivate when frequency drops below threshold AND hold period has elapsed.
            if freq < threshold && now > state.burstActivated + IngressControlState.icBurstHold {
                if tracker.incomingAnnounceSampleCount >= InterfaceFreqTracker.minSamples {
                    state.burstActive = false
                    ingressStates[key] = state
                    return false
                }
            }
            return true
        } else {
            if freq > threshold {
                state.burstActive = true
                state.burstActivated = now
                state.heldRelease = now + IngressControlState.icBurstPenalty
                ingressStates[key] = state
                return true
            }
            return false
        }
    }

    /// Checks whether inbound path requests on `interface` should be suppressed
    /// due to a path-request burst. Mirrors Python's `Interface.should_ingress_limit_pr()`.
    public func shouldIngressLimitPR(on interface: any Interface,
                                     now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard interface.ingressControl else { return false }
        let key = ObjectIdentifier(interface)
        guard var state = ingressStates[key],
              let tracker = ifaceFreqTrackers[key] else { return false }

        let age = now - interface.createdAt.timeIntervalSince1970
        let threshold = age < IngressControlState.icNewTime
            ? IngressControlState.icPrBurstFreqNew
            : IngressControlState.icPrBurstFreq
        let freq = tracker.incomingPathRequestFrequency(now: now)

        if state.prBurstActive {
            if freq < threshold && now > state.prBurstActivated + IngressControlState.icBurstHold {
                state.prBurstActive = false
                ingressStates[key] = state
                return false
            }
            return true
        } else {
            if freq > threshold {
                state.prBurstActive = true
                state.prBurstActivated = now
                ingressStates[key] = state
                return true
            }
            return false
        }
    }

    /// Checks whether outbound path requests on `interface` should be suppressed
    /// due to outgoing frequency exceeding `ecPrFreq`. Mirrors Python's
    /// `Interface.should_egress_limit_pr()`.
    public func shouldEgressLimitPR(on interface: any Interface,
                                    now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard interface.egressControl else { return false }
        let key = ObjectIdentifier(interface)
        guard let tracker = ifaceFreqTrackers[key] else { return false }
        let freq = tracker.outgoingPathRequestFrequency(now: now)
        if freq > interface.ecPrFreq {
            return tracker.outgoingPathRequestSampleCount >= InterfaceFreqTracker.minSamples
        }
        return false
    }

    /// Hold `packet` on `interface` for deferred replay when burst ends.
    /// Newer packets for the same destination overwrite older ones.
    /// Capped at `IngressControlState.maxHeldAnnounces`.
    ///
    /// Mirrors Python's `Interface.hold_announce(packet)`.
    public func holdAnnounce(_ packet: Packet, destinationHash: Data, on interface: any Interface) {
        // Don't hold announces that are already at (or one below) the maximum
        // propagation distance — replaying them later would push them past the
        // hop limit, so they'd be dropped anyway. Python (RNS 1.3.8):
        //   if announce_packet.hops >= RNS.Transport.PATHFINDER_M-1: return
        guard Int(packet.hops) < Transport.pathfinderM - 1 else { return }
        let key = ObjectIdentifier(interface)
        guard var state = ingressStates[key] else { return }
        if state.heldAnnounces[destinationHash] != nil {
            // Overwrite existing held announce for same destination (most recent wins).
            state.heldAnnounces[destinationHash] = packet
        } else if state.heldAnnounces.count < IngressControlState.maxHeldAnnounces {
            state.heldAnnounces[destinationHash] = packet
        }
        ingressStates[key] = state
    }

    /// Release the lowest-hop held announce on `interface` if the release timer has elapsed
    /// and the interface is no longer in burst mode. Returns the released packet or nil.
    ///
    /// Mirrors Python's `Interface.process_held_announces()`.
    @discardableResult
    public func processHeldAnnounces(for interface: any Interface,
                                     now: TimeInterval = Date().timeIntervalSince1970) -> Packet? {
        let key = ObjectIdentifier(interface)
        guard var state = ingressStates[key] else { return nil }
        guard !state.heldAnnounces.isEmpty, now > state.heldRelease else { return nil }

        // Check current frequency is below threshold before releasing.
        let tracker = ifaceFreqTrackers[key]
        let age = now - interface.createdAt.timeIntervalSince1970
        let threshold = age < IngressControlState.icNewTime
            ? IngressControlState.icBurstFreqNew
            : IngressControlState.icBurstFreq
        let freq = tracker?.incomingAnnounceFrequency(now: now) ?? 0
        guard freq < threshold else { return nil }

        // Select lowest-hop held announce (mirrors Python's min-hops selection).
        guard let (bestHash, bestPacket) = state.heldAnnounces
            .min(by: { $0.value.hops < $1.value.hops }) else { return nil }

        state.heldAnnounces.removeValue(forKey: bestHash)
        state.heldRelease = now + IngressControlState.icHeldReleaseInterval
        ingressStates[key] = state

        // Re-inject the packet into the transport pipeline.
        handleIncoming(packet: bestPacket, from: interface)
        return bestPacket
    }

    /// Number of held announces on `interface`. Test helper.
    public func heldAnnounceCount(for interface: any Interface) -> Int {
        ingressStates[ObjectIdentifier(interface)]?.heldAnnounces.count ?? 0
    }

    /// Returns the ingress control state for `interface`, or nil if not yet created.
    /// Mirrors Python's per-interface `ic_burst_active` etc. fields.
    public func ingressState(for interface: any Interface) -> IngressControlState? {
        lock.lock(); defer { lock.unlock() }
        return ingressStates[ObjectIdentifier(interface)]
    }

    /// Returns the number of queued announces for `interface`, or nil if no queue exists.
    /// Mirrors Python's `len(interface.announce_queue)`.
    public func announceQueueCount(for interface: any Interface) -> Int? {
        queueLock.lock(); defer { queueLock.unlock() }
        return announceQueues[interface.name]?.entries.count
    }

    /// Force-set the `heldRelease` timestamp for `interface`. Test helper.
    public func forceHeldRelease(for interface: any Interface, to timestamp: TimeInterval) {
        let key = ObjectIdentifier(interface)
        guard var state = ingressStates[key] else { return }
        state.heldRelease = timestamp
        ingressStates[key] = state
    }

    // MARK: - Per-interface speed tracking (mirrors Python count_traffic_loop)

    /// Sample current byte counts for all interfaces and compute per-interface and
    /// aggregate RX/TX speeds (bits/sec). Call this from the jobs loop or a dedicated
    /// periodic job. Mirrors Python's `Transport.count_traffic_loop`.
    ///
    /// - Parameter now: Injection point for testing; defaults to `Date().timeIntervalSince1970`.
    public func sampleInterfaceSpeeds(now: TimeInterval = Date().timeIntervalSince1970) {
        var totalRxSpeed: Double = 0
        var totalTxSpeed: Double = 0
        let snapshot = interfaces
        for iface in snapshot {
            let key = ObjectIdentifier(iface)
            let currentRx = iface.rxBytes
            let currentTx = iface.txBytes
            if let prior = ifaceSpeedSamples[key] {
                let tsDiff = now - prior.timestamp
                guard tsDiff > 0 else { continue }
                let rxDiff = currentRx - prior.rxBytes
                let txDiff = currentTx - prior.txBytes
                let rxSpeed = Double(rxDiff) * 8.0 / tsDiff   // bits/sec
                let txSpeed = Double(txDiff) * 8.0 / tsDiff
                ifaceCurrentRxSpeed[key] = rxSpeed
                ifaceCurrentTxSpeed[key] = txSpeed
                totalRxSpeed += rxSpeed
                totalTxSpeed += txSpeed
                // Accumulate transport-level TX total from interface diffs.
                // Mirrors Python: Transport.traffic_txb += txDiff (count_traffic_loop).
                // RX is already counted per-packet in handleIncoming, so only TX is added here.
                if txDiff > 0 { trafficTxBytes += txDiff }
            }
            ifaceSpeedSamples[key] = SpeedSample(rxBytes: currentRx, txBytes: currentTx, timestamp: now)
        }
        speedRx = totalRxSpeed
        speedTx = totalTxSpeed
    }

    /// Current RX speed for `interface` in bits/sec.
    /// Mirrors Python's `Interface.current_rx_speed`.
    public func currentRxSpeed(for interface: any Interface) -> Double {
        ifaceCurrentRxSpeed[ObjectIdentifier(interface)] ?? 0
    }

    /// Current TX speed for `interface` in bits/sec.
    /// Mirrors Python's `Interface.current_tx_speed`.
    public func currentTxSpeed(for interface: any Interface) -> Double {
        ifaceCurrentTxSpeed[ObjectIdentifier(interface)] ?? 0
    }

    // MARK: - Interface frequency notifications (mirrors Python Interface.received_announce / sent_announce etc.)

    /// Notify that an announce was received on `interface`.
    /// Mirrors Python's `interface.received_announce()` call in `Transport.inbound`.
    public func notifyIncomingAnnounce(on interface: any Interface) {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.recordIncomingAnnounce()
    }

    /// Overload accepting an explicit timestamp — used by tests and internally.
    public func notifyIncomingAnnounce(on interface: any Interface, at t: TimeInterval) {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.recordIncomingAnnounce(at: t)
    }

    /// Notify that an announce was sent out on `interface`.
    /// Mirrors Python's `interface.sent_announce()` call in `Transport.outbound`.
    public func notifyOutgoingAnnounce(on interface: any Interface) {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.recordOutgoingAnnounce()
    }

    public func notifyOutgoingAnnounce(on interface: any Interface, at t: TimeInterval) {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.recordOutgoingAnnounce(at: t)
    }

    /// Notify that a path request was received on `interface`.
    /// Mirrors Python's `interface.received_path_request()` call.
    public func notifyIncomingPathRequest(on interface: any Interface) {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.recordIncomingPathRequest()
    }

    public func notifyIncomingPathRequest(on interface: any Interface, at t: TimeInterval) {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.recordIncomingPathRequest(at: t)
    }

    /// Notify that a path request was sent out on `interface`.
    /// Mirrors Python's `interface.sent_path_request()` call.
    public func notifyOutgoingPathRequest(on interface: any Interface) {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.recordOutgoingPathRequest()
    }

    public func notifyOutgoingPathRequest(on interface: any Interface, at t: TimeInterval) {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.recordOutgoingPathRequest(at: t)
    }

    /// Incoming announce frequency (Hz) for the given interface.
    public func incomingAnnounceFrequency(for interface: any Interface) -> Double {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.incomingAnnounceFrequency() ?? 0
    }

    /// Outgoing announce frequency (Hz) for the given interface.
    public func outgoingAnnounceFrequency(for interface: any Interface) -> Double {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.outgoingAnnounceFrequency() ?? 0
    }

    /// Incoming path-request frequency (Hz) for the given interface.
    public func incomingPathRequestFrequency(for interface: any Interface) -> Double {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.incomingPathRequestFrequency() ?? 0
    }

    /// Outgoing path-request frequency (Hz) for the given interface.
    public func outgoingPathRequestFrequency(for interface: any Interface) -> Double {
        ifaceFreqTrackers[ObjectIdentifier(interface)]?.outgoingPathRequestFrequency() ?? 0
    }

    // MARK: - Management utilities

    /// Returns a snapshot of the path table for display/export.
    /// Mirrors Python's `Reticulum.get_path_table(max_hops:)`.
    public struct PathTableEntry {
        public let destinationHash: Data
        public let via: Data?
        public let hops: UInt8
        public let interfaceName: String
        public let lastHeard: Date
        public let expires: Date
    }

    public func getPathTable(maxHops: UInt8? = nil) -> [PathTableEntry] {
        lock.lock(); defer { lock.unlock() }
        return paths.values
            .filter { maxHops == nil || $0.hops <= maxHops! }
            .map { PathTableEntry(
                destinationHash: $0.destinationHash,
                via: $0.nextHopTransportID,
                hops: $0.hops,
                interfaceName: $0.nextHopInterfaceName,
                lastHeard: $0.lastHeard,
                expires: $0.expires
            )}
    }

    /// Returns the number of currently active links.
    /// Mirrors Python's `Reticulum.get_link_count()`.
    public func getLinkCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return links.values.filter { $0.status == .active }.count
    }

    /// Returns all currently active links as an array.
    /// Mirrors Python's `Transport.active_links` list.
    public var activeLinks: [Link] {
        lock.lock(); defer { lock.unlock() }
        return links.values.filter { $0.status == .active }
    }

    // MARK: - Packet PHY stats cache

    /// Returns the cached RSSI for a packet hash, or nil if not in cache.
    /// Mirrors Python's `Reticulum.get_packet_rssi(packet_hash)`.
    public func getPacketRssi(packetHash: Data) -> Float? {
        packetRssiCache.last(where: { $0.hash == packetHash })?.rssi
    }

    /// Returns the cached SNR for a packet hash, or nil if not in cache.
    /// Mirrors Python's `Reticulum.get_packet_snr(packet_hash)`.
    public func getPacketSnr(packetHash: Data) -> Float? {
        packetSnrCache.last(where: { $0.hash == packetHash })?.snr
    }

    /// Returns the cached quality for a packet hash, or nil if not in cache.
    /// Mirrors Python's `Reticulum.get_packet_q(packet_hash)`.
    public func getPacketQ(packetHash: Data) -> Float? {
        packetQCache.last(where: { $0.hash == packetHash })?.quality
    }

    // MARK: - Path responsiveness

    /// Mark a known path as unresponsive. Returns true if the path exists.
    /// Mirrors Python's `Transport.mark_path_unresponsive`.
    @discardableResult
    public func markPathUnresponsive(for destinationHash: Data) -> Bool {
        lock.lock()
        let exists = paths[destinationHash] != nil
        lock.unlock()
        guard exists else { return false }
        pathStatesLock.lock()
        pathStates[destinationHash] = Transport.stateUnresponsive
        pathStatesLock.unlock()
        return true
    }

    /// Mark a known path as responsive. Returns true if the path exists.
    /// Mirrors Python's `Transport.mark_path_responsive`.
    @discardableResult
    public func markPathResponsive(for destinationHash: Data) -> Bool {
        lock.lock()
        let exists = paths[destinationHash] != nil
        lock.unlock()
        guard exists else { return false }
        pathStatesLock.lock()
        pathStates[destinationHash] = Transport.stateResponsive
        pathStatesLock.unlock()
        return true
    }

    /// Reset responsiveness state to unknown.
    /// Mirrors Python's `Transport.mark_path_unknown_state`.
    @discardableResult
    public func markPathUnknownState(for destinationHash: Data) -> Bool {
        lock.lock()
        let exists = paths[destinationHash] != nil
        lock.unlock()
        guard exists else { return false }
        pathStatesLock.lock()
        pathStates[destinationHash] = Transport.stateUnknown
        pathStatesLock.unlock()
        return true
    }

    /// Returns true if the path is explicitly marked as unresponsive.
    /// Mirrors Python's `Transport.path_is_unresponsive`.
    public func pathIsUnresponsive(to destinationHash: Data) -> Bool {
        pathStatesLock.lock(); defer { pathStatesLock.unlock() }
        return pathStates[destinationHash] == Transport.stateUnresponsive
    }

    /// Block until a path to `destinationHash` is known, or the timeout
    /// expires. Sends a path request if no path is currently known.
    /// Mirrors Python's `Transport.await_path`.
    ///
    /// - Parameters:
    ///   - destinationHash: 16-byte destination hash to resolve.
    ///   - timeout: Seconds to wait before giving up. Defaults to `pathRequestTimeout`.
    ///   - onInterface: Optional interface to send the path request on.
    /// - Returns: `true` if a path was found, `false` if the timeout expired.
    public func awaitPath(
        to destinationHash: Data,
        timeout: TimeInterval = Transport.pathRequestTimeout,
        onInterface: (any Interface)? = nil
    ) -> Bool {
        if hasPath(to: destinationHash) { return true }
        try? requestPath(for: destinationHash, onInterface: onInterface)
        let deadline = Date().addingTimeInterval(timeout)
        while !hasPath(to: destinationHash), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return hasPath(to: destinationHash)
    }

    // MARK: - Path / latency utilities

    /// Returns the bitrate of the outgoing interface for the next hop to
    /// `destinationHash`, or nil if no path is known.
    /// Mirrors Python's `Transport.next_hop_interface_bitrate`.
    public func nextHopInterfaceBitrate(for destinationHash: Data) -> Int? {
        guard let iface = nextHopInterface(for: destinationHash) else { return nil }
        return iface.bitrate > 0 ? iface.bitrate : nil
    }

    /// Returns the per-bit transmission latency (seconds/bit) for the next-hop interface.
    /// Mirrors Python's `Transport.next_hop_per_bit_latency(destination_hash)`.
    public func nextHopPerBitLatency(for destinationHash: Data) -> Double? {
        guard let bitrate = nextHopInterfaceBitrate(for: destinationHash), bitrate > 0 else { return nil }
        return 1.0 / Double(bitrate)
    }

    /// Returns the per-byte transmission latency (seconds/byte) for the next-hop interface.
    /// Mirrors Python's `Transport.next_hop_per_byte_latency(destination_hash)`.
    public func nextHopPerByteLatency(for destinationHash: Data) -> Double? {
        guard let perBit = nextHopPerBitLatency(for: destinationHash) else { return nil }
        return perBit * 8
    }

    /// Returns the hardware MTU for the next-hop interface if the interface
    /// supports MTU auto-configuration or has a fixed MTU, otherwise nil.
    /// Mirrors Python's `Transport.next_hop_interface_hw_mtu`.
    public func nextHopInterfaceHwMtu(for destinationHash: Data) -> Int? {
        guard let iface = nextHopInterface(for: destinationHash) else { return nil }
        guard iface.autoconfigureMtu || iface.fixedMtu else { return nil }
        return iface.hwMtu
    }

    /// Returns the estimated first-hop timeout for a path to `destinationHash`.
    /// Falls back to `Constants.defaultPerHopTimeout` when no bitrate is available.
    /// Mirrors Python's `Transport.first_hop_timeout`.
    public func firstHopTimeout(for destinationHash: Data) -> TimeInterval {
        guard let bitrate = nextHopInterfaceBitrate(for: destinationHash), bitrate > 0 else {
            return Constants.defaultPerHopTimeout
        }
        let perByteLatency = 8.0 / Double(bitrate)
        return Double(Constants.mtu) * perByteLatency + Constants.defaultPerHopTimeout
    }

    /// Returns the extra proof timeout added to a forwarded link request based on
    /// the receiving interface's bitrate. Returns 0 when interface is nil or bitrate is 0.
    /// Mirrors Python's `Transport.extra_link_proof_timeout`.
    public static func extraLinkProofTimeout(for interface: (any Interface)?) -> TimeInterval {
        guard let iface = interface, iface.bitrate > 0 else { return 0.0 }
        return (8.0 / Double(iface.bitrate)) * Double(Constants.mtu)
    }

    // MARK: - Identity recall

    /// Return the Identity associated with `destinationHash`, if we have
    /// learned it from an announce. Mirrors Python's `Identity.recall`.
    public func recall(identity destinationHash: Data) -> Identity? {
        lock.lock(); defer { lock.unlock() }
        return knownIdentities[destinationHash]
    }

    /// Return the app data from the most recent announce for `destinationHash`,
    /// if any. Mirrors Python's `Identity.recall_app_data`.
    public func recallAppData(forDestination destinationHash: Data) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return knownIdentities[destinationHash]?.appData
    }

    /// Get the 10-byte ratchet ID of the currently known ratchet for a destination.
    /// Returns nil if no ratchet is known. Mirrors Python's `Identity.current_ratchet_id()`.
    public func currentRatchetID(forDestination destinationHash: Data) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let ratchetPub = knownRatchets[destinationHash] else { return nil }
        return Identity.ratchetID(forPublicKey: ratchetPub)
    }

    // MARK: - Lifecycle

    public func register(interface: Interface) {
        // Raw-bytes handler used by real interfaces — verifies IFAC, parses packet.
        interface.rawInboundHandler = { [weak self] rawBytes, sourceInterface in
            guard let self else { return }
            guard let verified = sourceInterface.unwrapIfac(rawBytes) else { return }
            guard let packet = try? Packet.unpack(verified) else { return }
            self.handleIncoming(packet: packet, from: sourceInterface)
        }
        // Packet handler kept for test-stub loopback interfaces that deliver
        // pre-parsed packets directly (they don't use rawInboundHandler).
        interface.inboundHandler = { [weak self] packet, sourceInterface in
            self?.handleIncoming(packet: packet, from: sourceInterface)
        }
        // TCPServerInterface spawns per-client sub-interfaces (mirrors Python's
        // TCPServerInterfaceClient model). Wire up the client connect/disconnect
        // callbacks so each accepted connection becomes a routing endpoint.
        if let tcpServer = interface as? TCPServerInterface {
            tcpServer.onClientConnected = { [weak self] clientIface in
                self?.register(interface: clientIface)
            }
            tcpServer.onClientDisconnected = { [weak self] clientIface in
                self?.deregister(interface: clientIface)
            }
        }
        // I2PInterface dials one I2PInterfacePeer per configured destination
        // (mirrors Python registering each peer via Transport.add_interface).
        // Peers register when their SAM tunnel comes up and deregister when
        // it drops; each re-registration re-synthesizes the tunnel, matching
        // Python's reconnect → synthesize_tunnel flow.
        if let i2p = interface as? I2PInterface {
            i2p.onPeerConnected = { [weak self] peerIface in
                self?.register(interface: peerIface)
            }
            i2p.onPeerDisconnected = { [weak self] peerIface in
                self?.deregister(interface: peerIface)
            }
        }
        interfaces.append(interface)
        // Create a frequency tracker for this interface.
        ifaceFreqTrackers[ObjectIdentifier(interface)] = InterfaceFreqTracker()
        // Create ingress burst control state for this interface.
        ingressStates[ObjectIdentifier(interface)] = IngressControlState()
        // Synthesize a tunnel for interfaces that request it.
        if interface.wantsTunnel {
            synthesizeTunnel(interface)
        }
    }

    /// Remove an interface from the transport. Cleans up all per-interface state.
    /// Mirrors Python `Transport.remove_interface()` added in e7a317f0.
    public func deregister(interface iface: any Interface) {
        interfaces.removeAll { $0 === iface }
        let key = ObjectIdentifier(iface)
        ifaceFreqTrackers.removeValue(forKey: key)
        ingressStates.removeValue(forKey: key)
        ifaceSpeedSamples.removeValue(forKey: key)
        ifaceCurrentRxSpeed.removeValue(forKey: key)
        ifaceCurrentTxSpeed.removeValue(forKey: key)
    }

    /// Derive IFAC credentials from a network name and/or access key and attach
    /// them to `interface`. Mirrors Python `Reticulum._add_interface` IFAC setup.
    ///
    /// - Parameters:
    ///   - interface: The interface to configure.
    ///   - netname: Human-readable network name (e.g. `"mynet"`).
    ///   - netkey:  Pre-shared access key string (e.g. `"s3cr3t"`).
    ///   - size:    IFAC signature-tail bytes (1–32, default 16).
    public static func configureIfac(
        on interface: any Interface,
        netname: String? = nil,
        netkey: String? = nil,
        size: Int = Constants.defaultIfacSize
    ) {
        var origin = Data()
        if let n = netname { origin += Hashes.fullHash(Data(n.utf8)) }
        if let k = netkey  { origin += Hashes.fullHash(Data(k.utf8)) }
        let originHash = Hashes.fullHash(origin)
        let key = HKDF.derive(length: Constants.keySize, derivedFrom: originHash, salt: Constants.ifacSalt)

        interface.ifacKey = key
        interface.ifacSize = size
    }

    public func register(destination: Destination) {
        lock.lock(); defer { lock.unlock() }
        registeredDestinations[destination.hash] = destination
    }

    /// Remove a previously registered destination.
    /// Mirrors Python's `Transport.deregister_destination`.
    public func deregister(destination: Destination) {
        lock.lock(); defer { lock.unlock() }
        registeredDestinations.removeValue(forKey: destination.hash)
    }

    public func register(link: Link) {
        guard let id = link.linkID else { return }
        lock.lock(); defer { lock.unlock() }
        links[id] = link
    }

    /// Bulk-load a path entry — used by `PathStore.apply` to rehydrate
    /// state from disk on stack startup. No validation here: the caller is
    /// expected to have produced these entries from a previous live state.
    public func restore(path: PathEntry, forDestination destinationHash: Data) {
        lock.lock(); defer { lock.unlock() }
        paths[destinationHash] = path
    }

    /// Directly insert an announce packet into the announce cache for testing.
    /// Mirrors the side-effect of processing a real announce packet.
    public func cacheAnnounce(_ packet: Packet, forDestination hash: Data) {
        lock.lock(); defer { lock.unlock() }
        cachedAnnounces[hash] = packet
    }

    /// Inject a synthetic path table entry for testing.
    /// Sets `nextHopTransportID` to `nextHop` so requestor-ID suppression can be tested.
    public func injectPath(_ destinationHash: Data,
                           nextHop: Data,
                           receivedOn interface: any Interface,
                           hops: UInt8,
                           announcePacketHash: Data?) {
        let entry = PathEntry(
            destinationHash: destinationHash,
            nextHopInterfaceName: interface.name,
            hops: hops,
            lastHeard: Date(),
            identityHash: Data(count: 16),
            nextHopTransportID: nextHop,
            cachedAnnounceHash: announcePacketHash
        )
        restore(path: entry, forDestination: destinationHash)
    }

    public func restore(identity: Identity, forDestination destinationHash: Data, announcedAt: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        knownIdentities[destinationHash] = identity
        if knownDestinationAnnouncedAt[destinationHash] == nil {
            knownDestinationAnnouncedAt[destinationHash] = announcedAt
        }
    }

    public func restore(ratchet: Data, forDestination destinationHash: Data) {
        restore(ratchet: ratchet, forDestination: destinationHash, receivedAt: Date())
    }

    public func restore(ratchet: Data, forDestination destinationHash: Data, receivedAt: Date) {
        lock.lock(); defer { lock.unlock() }
        knownRatchets[destinationHash] = ratchet
        knownRatchetTimes[destinationHash] = receivedAt
    }

    /// Drop learned ratchets whose `received` time is older than
    /// `ratchetExpiry`. Mirrors Python's `Identity._clean_ratchets`.
    public func sweepKnownRatchets(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        for (hash, received) in knownRatchetTimes {
            if now.timeIntervalSince(received) > ratchetExpiry {
                knownRatchets.removeValue(forKey: hash)
                knownRatchetTimes.removeValue(forKey: hash)
                if let dir = ratchetsDirectory {
                    try? FileManager.default.removeItem(
                        at: dir.appendingPathComponent(hash.hexString)
                    )
                }
            }
        }
    }

    /// Persist a learned ratchet to `<ratchetsDirectory>/<desthex>`
    /// using the simple `{ratchet, received}` layout the rest of the
    /// stack reads.
    private func persistKnownRatchet(_ ratchet: Data, forDestination hash: Data, receivedAt: Date) {
        guard let dir = ratchetsDirectory else { return }
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let url = dir.appendingPathComponent(hash.hexString)
        let payload: [String: Any] = [
            "ratchet": ratchet.hexString,
            "received": ISO8601DateFormatter().string(from: receivedAt),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Bulk-load all learned ratchets from `ratchetsDirectory`,
    /// dropping any whose `received` is older than `ratchetExpiry`.
    public func loadKnownRatchets() {
        guard let dir = ratchetsDirectory,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return }
        let now = Date()
        let formatter = ISO8601DateFormatter()
        lock.lock(); defer { lock.unlock() }
        for filename in entries {
            guard let destHash = Data(hex: filename) else { continue }
            let url = dir.appendingPathComponent(filename)
            guard let raw = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let rHex = obj["ratchet"] as? String,
                  let rData = Data(hex: rHex),
                  let recHex = obj["received"] as? String,
                  let received = formatter.date(from: recHex)
            else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            if now.timeIntervalSince(received) > ratchetExpiry {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            knownRatchets[destHash] = rData
            knownRatchetTimes[destHash] = received
        }
    }

    /// Encrypt `plaintext` for `destinationHash` using the freshest
    /// ratchet we know for that destination, falling back to the
    /// destination identity's static X25519 key when no ratchet has
    /// been seen.
    public func encrypt(_ plaintext: Data, forDestination destinationHash: Data) throws -> Data {
        lock.lock()
        let identity = knownIdentities[destinationHash]
        let ratchet = knownRatchets[destinationHash]
        lock.unlock()
        guard let identity else { throw TransportError.unknownDestination }
        return try identity.encrypt(plaintext, ratchetPublicKey: ratchet)
    }

    public enum TransportError: Swift.Error { case unknownDestination }

    // MARK: - Known destinations persistence
    // Mirrors Python's Identity.save_known_destinations() / load_known_destinations().

    private struct PersistedDestination: Codable {
        var publicKey: String   // hex-encoded 64-byte public key
        var appData: String?    // hex-encoded optional app data
        var timestamp: Double
    }

    /// Persist `knownIdentities` to a JSON file at `url`.
    /// Mirrors Python's `Identity.save_known_destinations()`.
    public func saveKnownDestinations(to url: URL) throws {
        lock.lock()
        let snapshot = knownIdentities
        lock.unlock()
        var map: [String: PersistedDestination] = [:]
        for (destHash, identity) in snapshot {
            map[destHash.hexString] = PersistedDestination(
                publicKey: identity.publicKeyBytes.hexString,
                appData: identity.appData?.hexString,
                timestamp: Date().timeIntervalSince1970
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(map).write(to: url, options: .atomic)
    }

    /// Load previously persisted `knownIdentities` from `url`.
    /// Mirrors Python's `Identity.load_known_destinations()`.
    public func loadKnownDestinations(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let map = try JSONDecoder().decode([String: PersistedDestination].self, from: data)
        lock.lock()
        defer { lock.unlock() }
        for (hashHex, entry) in map {
            guard let destHash = Data(hex: hashHex),
                  destHash.count == Constants.truncatedHashLength,
                  let pubKeyBytes = Data(hex: entry.publicKey),
                  pubKeyBytes.count == Constants.keySize,
                  let identity = try? Identity(publicKeyBytes: pubKeyBytes) else { continue }
            if let adHex = entry.appData { identity.appData = Data(hex: adHex) }
            if knownIdentities[destHash] == nil {
                knownIdentities[destHash] = identity
                knownDestinationAnnouncedAt[destHash] = Date(timeIntervalSince1970: entry.timestamp)
            }
        }
    }

    // MARK: - Known destination lifecycle

    /// Mark that a destination was used (e.g., recalled for outbound encryption).
    /// Mirrors Python's `Identity._used_destination_data()` which:
    ///   - returns False if the destination is not in known_destinations
    ///   - returns False (and skips update) if the destination is retained (slot[4] < 0)
    ///   - otherwise sets the last-used timestamp and returns True
    @discardableResult
    public func markDestinationUsed(_ destinationHash: Data, at date: Date = Date()) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard knownIdentities[destinationHash] != nil else { return false }
        guard !retainedDestinations.contains(destinationHash) else { return false }
        knownDestinationLastUsed[destinationHash] = date
        return true
    }

    /// Remove stale known-identity entries that no longer have an active path and
    /// haven't been heard from / used recently.
    /// Mirrors Python's `Identity.clean_known_destinations()`.
    ///
    /// Stale conditions (matching Python logic):
    ///   - no active path AND never used AND last_announce > UNUSED_DESTINATION_LINGER ago → remove
    ///   - no active path AND was used BUT unused_for > DESTINATION_TIMEOUT * 1.25 → remove
    ///   - retained destinations are never removed
    public func cleanKnownDestinations(now: Date = Date()) {
        lock.lock()
        let snapshot = knownIdentities
        lock.unlock()

        var toRemove: [Data] = []
        for destHash in snapshot.keys {
            lock.lock()
            let isRetained = retainedDestinations.contains(destHash)
            let hasPath = paths[destHash] != nil && !(paths[destHash]!.isExpired)
            let announcedAt = knownDestinationAnnouncedAt[destHash] ?? now
            let lastUsed = knownDestinationLastUsed[destHash]
            lock.unlock()

            guard !isRetained, !hasPath else { continue }

            let wasUsed = lastUsed != nil
            if !wasUsed {
                let lingerExpiry = announcedAt.addingTimeInterval(Transport.unusedDestinationLinger)
                if now >= lingerExpiry { toRemove.append(destHash) }
            } else {
                let unusedFor = now.timeIntervalSince(lastUsed!)
                if unusedFor > Transport.destinationTimeout * 1.25 { toRemove.append(destHash) }
            }
        }

        lock.lock()
        let ratchetsDir = ratchetsDirectory
        for h in toRemove {
            knownIdentities.removeValue(forKey: h)
            knownDestinationAnnouncedAt.removeValue(forKey: h)
            knownDestinationLastUsed.removeValue(forKey: h)
        }
        lock.unlock()

        // Mirrors Python 1.3.4 Identity.clean_known_destinations: also delete
        // the on-disk ratchet file so stale ratchets don't accumulate.
        if let dir = ratchetsDir {
            for h in toRemove {
                let url = dir.appendingPathComponent(h.hexString)
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    /// Pin a destination so it is never removed by `cleanKnownDestinations`.
    /// Mirrors Python `Identity._retain_destination_data(destination_hash)`.
    @discardableResult
    public func retainDestinationData(_ destinationHash: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard knownIdentities[destinationHash] != nil else { return false }
        retainedDestinations.insert(destinationHash)
        return true
    }

    /// Unpin a previously retained destination so it becomes eligible for cleanup.
    /// Mirrors Python `Identity._unretain_destination_data(destination_hash)`.
    @discardableResult
    public func unretainDestinationData(_ destinationHash: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard knownIdentities[destinationHash] != nil else { return false }
        retainedDestinations.remove(destinationHash)
        return true
    }

    /// Pin all destinations associated with the given identity hash.
    /// Mirrors Python `Identity._retain_identity(identity_hash)`.
    @discardableResult
    public func retainIdentity(_ identityHash: Data) -> Bool {
        lock.lock()
        let matching = knownIdentities.keys.filter { destHash in
            guard let id = knownIdentities[destHash] else { return false }
            return id.hash == identityHash
        }
        for destHash in matching { retainedDestinations.insert(destHash) }
        lock.unlock()
        return !matching.isEmpty
    }

    public func unregister(link: Link) {
        guard let id = link.linkID else { return }
        lock.lock(); defer { lock.unlock() }
        links.removeValue(forKey: id)
    }

    public func start() throws {
        startTime = Date().timeIntervalSince1970
        for interface in interfaces { try interface.start() }
        setupManagementDestinations()
        isRunning = true
        startJobsLoop()
    }

    /// Create management/probe/network destinations based on the current config.
    /// Mirrors Python's Transport.start() destination setup block.
    private func setupManagementDestinations() {
        guard let identity = transportIdentity else { return }

        // Probe destination: responds to PROVE_ALL, no links.
        if Reticulum.probeDestinationEnabled() {
            if let probe = try? Destination(identity: identity, direction: .in, kind: .single,
                                             appName: "rnstransport", aspects: ["probe"]) {
                probe.acceptsLinks = false
                probe.setProofStrategy(.proveAll)
                probeDestination = probe
                register(destination: probe)
            }
        }

        // Remote management destination: /status and /path handlers.
        if Reticulum.remoteManagementEnabled() {
            if let mgmt = try? Destination(identity: identity, direction: .in, kind: .single,
                                            appName: "rnstransport", aspects: ["remote", "management"]) {
                let allowed = remoteManagementAllowed
                mgmt.registerRequestHandler(path: "/status", allow: .list, allowedList: allowed) {
                    [weak self] _, data, _, _, _ -> Data? in
                    guard let self else { return nil }
                    guard let data, case .array(let arr) = (try? MsgPack.decode(data)) ?? .nil,
                          let first = arr.first else { return nil }
                    let stats = self.getInterfaceStats()
                    let statsArr = MsgPack.Value.array(stats.map { s -> MsgPack.Value in
                        .map([(.string("name"), .string(s.name)),
                              (.string("rxb"),  .int(Int64(s.rxBytes))),
                              (.string("txb"),  .int(Int64(s.txBytes)))])
                    })
                    var response: [MsgPack.Value] = [statsArr]
                    if case .bool(true) = first {
                        response.append(.int(Int64(self.getLinkCount())))
                    }
                    return MsgPack.encode(.array(response))
                }
                mgmt.registerRequestHandler(path: "/path", allow: .list, allowedList: allowed) {
                    [weak self] _, data, _, _, _ -> Data? in
                    guard let self else { return nil }
                    guard let data, case .array(let arr) = (try? MsgPack.decode(data)) ?? .nil,
                          !arr.isEmpty, case .string(let command) = arr[0] else { return nil }
                    let filterHash: Data? = {
                        guard arr.count > 1, case .bytes(let b) = arr[1] else { return nil }
                        return b
                    }()
                    switch command {
                    case "table":
                        let table = self.getPathTable()
                        let filtered = filterHash == nil ? table : table.filter { $0.destinationHash == filterHash }
                        let entries = filtered.map { e -> MsgPack.Value in
                            let via: MsgPack.Value = e.via.map { .bytes($0) } ?? .nil
                            return .map([(.string("hash"), .bytes(e.destinationHash)),
                                         (.string("hops"), .int(Int64(e.hops))),
                                         (.string("via"),  via),
                                         (.string("expires"), .double(e.expires.timeIntervalSince1970))])
                        }
                        return MsgPack.encode(.array(entries))
                    case "rates":
                        let rates = self.getRateTable()
                        let filtered = filterHash == nil ? rates : rates.filter { $0.destinationHash == filterHash }
                        let entries = filtered.map { r -> MsgPack.Value in
                            .map([(.string("hash"), .bytes(r.destinationHash)),
                                  (.string("last"), .double(r.last)),
                                  (.string("rate_violations"), .int(Int64(r.rateViolations)))])
                        }
                        return MsgPack.encode(.array(entries))
                    default: return nil
                    }
                }
                remoteManagementDestination = mgmt
                register(destination: mgmt)
            }
        }

        // Network/instance destinations when networkIdentity is set.
        setupNetworkDestinations()
    }

    /// Creates `rnstransport.network` and `rnstransport.network.instance.<hex>` destinations.
    /// Mirrors Python's `Transport.instance_destination` and `Transport.network_destination` setup.
    public func setupNetworkDestinations() {
        guard let netIdentity = networkIdentity else { return }
        let hexHash = netIdentity.hash.map { String(format: "%02x", $0) }.joined()
        if let instanceDest = try? Destination(identity: netIdentity, direction: .in, kind: .single,
                                                appName: "rnstransport",
                                                aspects: ["network", "instance", hexHash]) {
            register(destination: instanceDest)
        }
        if let netDest = try? Destination(identity: netIdentity, direction: .in, kind: .single,
                                           appName: "rnstransport", aspects: ["network"]) {
            register(destination: netDest)
        }
    }

    public func stop() {
        jobsTimer?.cancel()
        jobsTimer = nil
        for interface in interfaces { interface.stop() }
        isRunning = false
    }

    // MARK: - Jobs loop

    private func startJobsLoop() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + Transport.jobInterval,
                       repeating: Transport.jobInterval)
        timer.setEventHandler { [weak self] in self?.runJobs() }
        timer.resume()
        jobsTimer = timer
    }

    private func runJobs() {
        sweepExpiredPaths()
        sweepExpiredReceipts()
        sweepKnownRatchets()
        sweepReverseTable()
        processAnnounceRetries()
        drainAnnounceQueues()
        sampleInterfaceSpeeds()
        sweepExpiredBlackholes()
        // Process held announces for each interface (mirrors Python's per-interface job loop).
        for iface in interfaces { processHeldAnnounces(for: iface) }
        // Periodically clean known destinations (mirrors Python commit b408699e:
        // periodically clean known destinations based on local relevance).
        // Throttled to once per `knownDestinationsCleanInterval` because the
        // sweep walks every known identity and inspects its path/use state.
        let now = Date()
        if now.timeIntervalSince(lastKnownDestinationsClean) >= Transport.knownDestinationsCleanInterval {
            cleanKnownDestinations(now: now)
            lastKnownDestinationsClean = now
        }
    }

    // MARK: - Announce retransmission (announce_table)

    /// Process pending announce retransmissions. Mirrors the announce_table
    /// loop in Python's `Transport.jobs()`: an entry whose grace window has
    /// elapsed is retransmitted once more (`PATHFINDER_R = 1`) and then
    /// completed. Driven by the jobs timer in production; tests pass an
    /// explicit `now` to step the clock deterministically.
    func processAnnounceRetries(now: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        var completed: [Data] = []
        var toTransmit: [AnnounceTableEntry] = []
        for (destinationHash, stored) in announceTable {
            var entry = stored
            // These two completion guards are a faithful mirror of Python's
            // `if/elif` pair (Transport.jobs); at the default constants
            // (localRebroadcastsMax=2, pathRequestRetries=1) they both trip at
            // retries==2, i.e. after exactly one retransmission.
            if entry.retries > 0 && entry.retries >= Transport.localRebroadcastsMax {
                // Enough local rebroadcasts / retries — done.
                completed.append(destinationHash)
            } else if entry.retries > Transport.pathRequestRetries {
                // Retry limit (PATHFINDER_R) reached.
                completed.append(destinationHash)
            } else if now > entry.retransmitTimeout {
                entry.retransmitTimeout = now + Transport.pathfinderG
                    + Double.random(in: 0 ..< Transport.pathfinderRW)
                entry.retries += 1
                announceTable[destinationHash] = entry
                toTransmit.append(entry)
            }
        }
        for destinationHash in completed { announceTable.removeValue(forKey: destinationHash) }
        let snapshot = interfaces
        lock.unlock()

        for entry in toTransmit { retransmitAnnounce(entry, interfaces: snapshot, now: now) }
    }

    /// Re-emit a held announce on every eligible interface, reusing the same
    /// announce-propagation filter and per-interface rate queue as the
    /// immediate forward in `handleAnnounce`. `now` flows from the jobs clock so
    /// the rate queue and the retry schedule share one timebase (tests inject it).
    private func retransmitAnnounce(_ entry: AnnounceTableEntry, interfaces snapshot: [any Interface],
                                    now: TimeInterval) {
        var forwarded = entry.packet
        forwarded.hops = UInt8(truncatingIfNeeded: entry.hops + 1)
        forwarded.headerType = .type2
        forwarded.transportID = transportInstanceID
        // A blocked rebroadcast goes out as a path response (Python sets
        // `announce_context = PATH_RESPONSE` when `block_rebroadcasts`).
        if entry.blockRebroadcasts { forwarded.context = .pathResponse }
        let emitted = announceEmitted(forwarded)
        for iface in snapshot where iface.isOnline && iface.isRoutingEndpoint
            && iface.name != entry.receivingInterfaceName {
            if let restrict = entry.attachedInterfaceName, iface.name != restrict { continue }
            guard Transport.shouldForwardAnnounce(
                outboundMode: iface.mode,
                nextHopMode: entry.receivingInterfaceMode,
                localDestination: false,
                announcesFromInternal: iface.announcesFromInternal
            ) else { continue }
            queueLock.lock()
            if announceQueues[iface.name] == nil { announceQueues[iface.name] = AnnounceQueue() }
            let queue = announceQueues[iface.name]!
            queueLock.unlock()
            let canSend = queue.shouldTransmit(
                packet: forwarded, now: now, bitrate: iface.bitrate, emitted: emitted
            )
            if canSend { try? iface.send(forwarded) }
        }
    }

    /// Receive-side cancel for a pending announce retransmission. Called when a
    /// forwarded (HEADER_2) announce arrives for a destination we are about to
    /// retransmit. Mirrors Python's `Transport.inbound()` announce_table block:
    ///   - hops == stored + 1 → a sibling at our own distance rebroadcast it;
    ///     once `LOCAL_REBROADCASTS_MAX` are heard the retry is dropped.
    ///   - hops == stored + 2 → a downstream node passed our rebroadcast on;
    ///     if it happened before our retry timer, no further tries are needed.
    private func noteAnnounceRebroadcastHeard(destinationHash: Data, incomingHops: Int) {
        lock.lock(); defer { lock.unlock() }
        guard var entry = announceTable[destinationHash] else { return }
        if incomingHops == entry.hops + 1 {
            entry.localRebroadcasts += 1
            if entry.retries > 0 && entry.localRebroadcasts >= Transport.localRebroadcastsMax {
                announceTable.removeValue(forKey: destinationHash)
                return
            }
            announceTable[destinationHash] = entry
        } else if incomingHops == entry.hops + 2 && entry.retries > 0 {
            if Date().timeIntervalSince1970 < entry.retransmitTimeout {
                announceTable.removeValue(forKey: destinationHash)
            }
        }
    }

    /// Remove stale reverse-table entries. Proofs that never arrive within
    /// a reasonable window are dropped to prevent unbounded memory growth.
    private func sweepReverseTable(maxAge: TimeInterval = 600) {
        // The reverse table stores entries for proof forwarding. If a proof
        // hasn't arrived within maxAge seconds, the entry is stale.
        // In Python, the reverse table entries are removed when proofs arrive;
        // we add a sweep to handle the case where proofs never arrive.
        // Simple approach: limit size (entries are at most a few hundred bytes each)
        reverseTableLock.lock()
        if reverseTable.count > 4096 {
            // Drop oldest half when table grows too large
            let keysToRemove = Array(reverseTable.keys.prefix(reverseTable.count / 2))
            for key in keysToRemove { reverseTable.removeValue(forKey: key) }
        }
        reverseTableLock.unlock()
    }

    // MARK: - Path expiry

    /// Remove paths whose `expires` timestamp has passed.
    /// Mirrors Python's path table expiry in `Transport.jobs()`.
    public func sweepExpiredPaths(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        paths = paths.filter { !$0.value.isExpired }
    }

    /// Expire the path for a specific destination immediately.
    /// Mirrors Python's `Transport.expire_path(destination_hash)`.
    @discardableResult
    public func expirePath(for destinationHash: Data) -> Bool {
        lock.lock()
        let existed = paths[destinationHash] != nil
        paths.removeValue(forKey: destinationHash)
        cachedAnnounces.removeValue(forKey: destinationHash)
        lock.unlock()
        return existed
    }

    /// Drop a known path (alias for `expirePath`, matches Python's
    /// `Reticulum.drop_path` / `Transport.expire_path` usage in LXMF).
    @discardableResult
    public func dropPath(for destinationHash: Data) -> Bool {
        expirePath(for: destinationHash)
    }

    // MARK: - Receipt management

    func trackReceipt(_ receipt: PacketReceipt) {
        receiptsLock.lock()
        // Enforce cap by culling the oldest entry first.
        while receipts.count >= Transport.maxReceipts {
            let oldest = receipts.removeFirst()
            oldest.cull()
        }
        receipts.append(receipt)
        receiptsLock.unlock()
    }

    private func sweepExpiredReceipts() {
        receiptsLock.lock()
        for receipt in receipts { receipt.checkTimeout() }
        receipts.removeAll { $0.status != .sent }
        receiptsLock.unlock()
    }

    /// Look up a receipt by packet hash and mark it delivered via
    /// explicit proof (hash + Ed25519 signature). Mirrors Python's
    /// `PacketReceipt.validate_proof`.
    func deliverProof(packetHash: Data, proof: Data) {
        receiptsLock.lock()
        let match = receipts.first { $0.packetHash == packetHash }
        receiptsLock.unlock()
        match?.validateExplicitProof(proof)
    }

    // MARK: - Outbound

    /// Send a packet and optionally generate a delivery receipt.
    ///
    /// For DATA packets to SINGLE destinations, a `PacketReceipt` is
    /// created (matching Python's `Transport.outbound`). The receipt is
    /// returned so the caller can attach callbacks.
    @discardableResult
    public func send(_ packet: Packet, generateReceipt: Bool = true) throws -> PacketReceipt? {
        var receipt: PacketReceipt? = nil

        // Generate receipt for DATA → SINGLE (not PLAIN, not link/resource contexts).
        if generateReceipt,
           packet.packetType == .data,
           packet.destinationType == .single,
           packet.context == .none || packet.context == .request || packet.context == .response {
            if let hashable = try? packet.hashablePart() {
                let hash = Hashes.fullHash(hashable)
                // Use the remote peer's identity (public key) for proof validation.
                // Look up from knownIdentities first (outbound to remote peer);
                // fall back to the local registered destination's identity if
                // this is a loopback packet addressed to a local destination.
                lock.lock()
                let peerIdentity = knownIdentities[packet.destinationHash]
                    ?? registeredDestinations[packet.destinationHash]?.identity
                lock.unlock()
                let timeout = defaultTimeout(for: packet.destinationHash)
                let r = PacketReceipt(packetHash: hash, peerIdentity: peerIdentity, timeout: timeout)
                trackReceipt(r)
                receipt = r
            }
        }

        // Check for local delivery: if the destination is registered on this transport,
        // deliver directly without sending over any interface.
        // Mirrors Python's shared-instance local client delivery mechanism.
        lock.lock()
        let localDest = packet.destinationType == .single ? registeredDestinations[packet.destinationHash] : nil
        let path = paths[packet.destinationHash]
        lock.unlock()

        if let localDest, packet.packetType == .data {
            // Deliver locally. For self-addressed packets, bypass the interface layer.
            if let plaintext = try? localDest.decrypt(packet.data) {
                localDest.onPacketReceived?(plaintext, packet)
                // For proof-generating strategies, deliver the proof directly to the receipt.
                let shouldProve: Bool
                switch localDest.proofStrategy {
                case .proveAll: shouldProve = true
                case .proveApp: shouldProve = localDest.onProofRequested?(packet) == true
                case .proveNone: shouldProve = false
                }
                if shouldProve, let r = receipt,
                   let identity = localDest.identity, identity.hasPrivateKey,
                   let hashable = try? packet.hashablePart() {
                    let fullHash = Hashes.fullHash(hashable)
                    if let sig = try? identity.sign(fullHash) {
                        let proofData = Reticulum.shouldUseImplicitProof() ? sig : fullHash + sig
                        if proofData.count == PacketReceipt.implicitProofLength {
                            _ = r.validateImplicitProof(proofData)
                        } else {
                            _ = r.validateExplicitProof(proofData)
                        }
                    }
                }
            }
            return receipt
        }

        // Route via known path if available; otherwise broadcast.
        // Only SINGLE destinations are routed via the path table.
        // PLAIN and GROUP destinations are broadcast directly (Python: excluded from path routing).
        if let path, packet.packetType != .announce,
           packet.destinationType == .single {
            guard let outbound = interfaces.first(where: {
                $0.name == path.nextHopInterfaceName && $0.isOnline
            }) else {
                // Path exists but interface is offline — broadcast as fallback.
                for iface in interfaces where iface.isOnline && iface.isRoutingEndpoint {
                    try? iface.send(deltaMangled(packet, for: iface))
                }
                return receipt
            }
            var routed = packet
            // Mirror Python Transport.outbound(): add HEADER_2 with the stored
            // next-hop transport ID whenever one is known.  This covers:
            //   • hops > 1 (multi-hop) — nextHopTransportID is always populated
            //   • hops == 1 via a backbone — announce arrived as HEADER_2 so
            //     nextHopTransportID carries the backbone's identity hash
            // Direct 1-hop peers send their announce as HEADER_1, leaving
            // nextHopTransportID nil, so we send HEADER_1 back to them too.
            if let nhID = path.nextHopTransportID {
                routed.headerType = .type2
                routed.transportID = nhID
            }
            // Local hop-count obfuscation: hide that this packet originated here.
            if shouldApplyDelta(packet, interface: outbound) { routed.hops = localHopsDelta }
            try outbound.send(routed)
            // Update path timestamp on successful send (mirrors Python's path_entry[IDX_PT_TIMESTAMP]).
            lock.lock()
            if var updated = paths[packet.destinationHash] {
                updated.lastHeard = Date()
                paths[packet.destinationHash] = updated
            }
            lock.unlock()
        } else {
            for iface in interfaces where iface.isOnline && iface.isRoutingEndpoint {
                try? iface.send(deltaMangled(packet, for: iface))
            }
        }
        return receipt
    }

    /// If local hop-count obfuscation applies to `packet` on `iface`, return an
    /// obfuscated copy (hops → `localHopsDelta`, with transport-header insertion
    /// for HEADER_1 announces); otherwise return `packet` unchanged. Mirrors the
    /// per-interface `should_apply_delta` / `mangle_hops` branch in Python
    /// `Transport.outbound()`'s broadcast loop.
    private func deltaMangled(_ packet: Packet, for iface: any Interface) -> Packet {
        guard shouldApplyDelta(packet, interface: iface) else { return packet }
        let insert = packet.packetType == .announce && packet.headerType == .type1
        return mangleHops(packet, hops: localHopsDelta, transportInsert: insert)
    }

    /// Broadcast on every online routing-endpoint interface *except* the one specified.
    /// Used when relaying an announce so we don't send it back where it
    /// came from.
    public func send(_ packet: Packet, exceptInterface excluded: Interface) {
        for interface in interfaces where interface.isOnline && interface.isRoutingEndpoint && interface !== excluded {
            try? interface.send(packet)
            // Mirrors Python: `interface.sent_announce()` when relaying an announce.
            if packet.packetType == .announce { notifyOutgoingAnnounce(on: interface) }
        }
    }

    /// Convenience — announce an inbound destination on all interfaces.
    @discardableResult
    /// Announce a destination on all interfaces, or a specific interface.
    /// - Parameter onInterface: If specified, the announce is only sent on this interface.
    ///   Mirrors Python's `Destination.announce(attached_interface=...)`.
    /// - Parameter isPathResponse: If true, the announce is sent as a path response (not re-forwarded).
    ///   Mirrors Python's `Destination.announce(path_response=True)`.
    public func announce(
        destination: Destination,
        appData: Data? = nil,
        ratchet: Data? = nil,
        isPathResponse: Bool = false,
        onInterface: (any Interface)? = nil
    ) throws -> PacketReceipt? {
        let packet = try Announce.make(for: destination, appData: appData, ratchet: ratchet, isPathResponse: isPathResponse)
        if let iface = onInterface {
            try iface.send(packet)
            return nil
        }
        return try send(packet, generateReceipt: false)
    }

    /// Default receipt timeout for a destination. Uses hop count if a path
    /// is known; otherwise falls back to a single-hop estimate.
    /// Mirrors Python's `get_first_hop_timeout` + `TIMEOUT_PER_HOP`.
    private func defaultTimeout(for destinationHash: Data) -> TimeInterval {
        let perHop: TimeInterval = 6
        let hops = TimeInterval(hopsTo(destinationHash) ?? 1)
        return max(perHop, hops * perHop)
    }

    // MARK: - Inbound

    /// Wire-format hash of the well-known path-request destination, plain
    /// kind, name "rnstransport.path.request" — matches the Python
    /// reference `Transport.path_request_destination`.
    public static let pathRequestDestinationHash: Data = {
        let nameHash = Destination.computeNameHash(
            appName: "rnstransport",
            aspects: ["path", "request"]
        )
        return Destination.computeHash(identity: nil, nameHash: nameHash, kind: .plain)
    }()

    /// Wire-format hash of the well-known tunnel synthesize destination, plain
    /// kind, name "rnstransport.tunnel.synthesize" — matches Python
    /// `Transport.tunnel_synthesize_destination`.
    public static let tunnelSynthesizeHash: Data = {
        let nameHash = Destination.computeNameHash(
            appName: "rnstransport",
            aspects: ["tunnel", "synthesize"]
        )
        return Destination.computeHash(identity: nil, nameHash: nameHash, kind: .plain)
    }()

    func handleIncoming(packet: Packet, from interface: Interface) {
        // Count inbound traffic bytes. Mirrors Python `Transport.traffic_rxb` accumulation.
        // We count per-packet here (unlike Python which samples interface diffs) so the counter
        // is immediately accurate without waiting for the jobs loop.
        if let raw = try? packet.pack() { trafficRxBytes += raw.count }

        // Cache packet PHY stats (RSSI/SNR/quality) for the truncated packet hash.
        // Uses truncated hash (16 bytes) to match Python's packet.packet_hash semantics.
        if let pktHash = try? packet.truncatedPacketHash() {
            if let rssi = packet.rssi {
                packetRssiCache.append((hash: pktHash, rssi: rssi))
                if packetRssiCache.count > Transport.localClientCacheMaxSize { packetRssiCache.removeFirst() }
            }
            if let snr = packet.snr {
                packetSnrCache.append((hash: pktHash, snr: snr))
                if packetSnrCache.count > Transport.localClientCacheMaxSize { packetSnrCache.removeFirst() }
            }
            if let quality = packet.quality {
                packetQCache.append((hash: pktHash, quality: quality))
                if packetQCache.count > Transport.localClientCacheMaxSize { packetQCache.removeFirst() }
            }
        }

        // Drop duplicate or replayed packets. Link handshake packets
        // (LRR and LRPROOF) are exempt so retransmissions work.
        guard filterAndRecord(packet: packet) else { return }

        // CACHE_REQUEST: serve cached announce packet if available.
        // Mirrors Python: `if packet.context == CACHE_REQUEST: if cache_request_packet(packet): return`
        if packet.packetType == .data, packet.context == .cacheRequest {
            if cacheRequestPacket(packet) { return }
        }

        if packet.packetType == .data,
           packet.destinationType == .plain,
           packet.destinationHash == Transport.pathRequestDestinationHash {
            handlePathRequest(packet, from: interface)
            return
        }

        if packet.packetType == .data,
           packet.destinationType == .plain,
           packet.destinationHash == Transport.tunnelSynthesizeHash {
            handleTunnelSynthesizePacket(data: packet.data, from: interface)
            return
        }

        switch packet.packetType {
        case .announce:
            handleAnnounce(packet, from: interface)
        case .linkRequest:
            handleLinkRequest(packet, from: interface)
        case .proof where packet.context == .lrproof:
            handleLinkRequestProof(packet, from: interface)
        case .data where packet.destinationType == .link && packet.context == .lrrtt:
            handleLinkRTT(packet, from: interface)
        case .data where packet.destinationType == .link && packet.context == .linkClose:
            handleLinkClose(packet, from: interface)
        case .data where packet.destinationType == .link:
            handleLinkData(packet, from: interface)
        case .proof where packet.destinationType == .link:
            // Non-LRPROOF proofs over a link (e.g. RESOURCE_PRF) are
            // encrypted with the link key — let Link.receive decrypt them.
            handleLinkData(packet, from: interface)
        case .proof where packet.destinationType != .link:
            // Explicit proof for a sent DATA packet. Try to match it to an
            // outstanding receipt before handing off to general delivery.
            handleProofDelivery(packet, from: interface)
        case .data, .proof:
            handleDelivery(packet, from: interface)
        }
    }

    private func handleLinkRequest(_ packet: Packet, from interface: Interface) {
        lock.lock()
        let destination = registeredDestinations[packet.destinationHash]
        let path = paths[packet.destinationHash]
        lock.unlock()

        // Use the destination's own identity to answer the link request.
        // This is correct: each registered destination carries its private
        // identity, so we do not need the transport-wide ownerIdentity here.
        // (ownerIdentity is still needed for tunnel synthesis — synthesizeTunnel.)
        if let destination, let owner = destination.identity, destination.acceptsLinks {
            do {
                let link = try Link.answer(
                    request: packet,
                    destination: destination,
                    owner: owner,
                    transport: self
                )
                link.onEstablished = { [weak self] l in
                    self?.onLinkEstablished?(l)
                    destination.onLinkEstablished?(l)
                }
                link.startWatchdog()
                try link.sendProof()
            } catch {
                // Malformed request — drop silently.
            }
            return
        }

        // Not for us — forward toward the responder if we know a path, and
        // remember the link's two-sided routing so the proof/RTT/close
        // packets that come back addressed to link_id can be steered.
        guard transportEnabled, let path else { return }
        guard packet.hops < propagationLimit else { return }
        guard let outbound = interfaces.first(where: {
            $0.name == path.nextHopInterfaceName && $0.isOnline
        }) else { return }
        guard outbound !== interface else { return }

        // link_id derives from the LRR packet's hashable part with signalling bytes
        // stripped — mirrors Python's Link.link_id_from_lr_packet so all nodes
        // (initiator, relay, responder) agree on the same link_id value.
        guard let linkIDHashable = try? Link.linkIDHashable(for: packet, dataLength: packet.data.count) else {
            return
        }
        let linkID = Hashes.truncatedHash(linkIDHashable)
        let route = LinkRoute(
            linkID: linkID,
            initiatorSideInterfaceName: interface.name,
            responderSideInterfaceName: outbound.name,
            destinationHash: packet.destinationHash,
            lastHeard: Date()
        )
        lock.lock(); linkRoutes[linkID] = route; lock.unlock()

        var forwarded = packet
        // instance_local_link: a link whose both ends are local clients of this
        // instance stays local, so keep real hops; otherwise obfuscate a link
        // request relayed on behalf of a local client. Python inbound() line 1731.
        let instanceLocalLink = isLocalClientInterface(interface) && isLocalClientInterface(outbound)
        forwarded.hops = relayHops(packet, from: interface, staysLocal: instanceLocalLink)

        // If the incoming LINKREQUEST is HEADER_2 addressed to us as relay, we
        // must convert it before forwarding. Mirrors Python Transport lines 1565–1576:
        //
        //   remaining_hops > 1 → update transport_id to next hop, keep HEADER_2
        //   remaining_hops == 1 → strip transport header, forward as HEADER_1
        //
        // Swift stores path.hops = raw wire hops (no inbound +1), so the
        // equivalence is:
        //   path.hops == 0  ↔  Python remaining_hops == 1  → strip headers
        //   path.hops  > 0  ↔  Python remaining_hops  > 1  → update transport_id
        //
        // Without this conversion, the responder receives HEADER_2 with our
        // transport_id, fails the identity check (transport_id ≠ responder's ID),
        // and silently drops the link request.
        if forwarded.headerType == .type2, forwarded.transportID == transportInstanceID {
            if path.hops == 0 {
                // Destination is directly reachable on outbound interface.
                // Strip the transport header so the responder sees a plain HEADER_1.
                forwarded.headerType = .type1
                forwarded.transportType = .broadcast
                forwarded.transportID = nil
            } else {
                // More relay hops needed — replace our transport_id with the
                // next relay's transport_id so that node forwards it onward.
                forwarded.transportID = path.nextHopTransportID ?? transportInstanceID
            }
        }

        // Clamp/strip the link-request MTU signalling for the next hop (mirrors
        // Python's link-MTU handling in `Transport.inbound()`). This is safe for
        // routing because the link_id is hashed with signalling bytes removed.
        clampRelayedLinkRequestMtu(&forwarded, prevHop: interface, nextHop: outbound)

        try? outbound.send(forwarded)
    }

    /// Clamp or strip the 3-byte MTU signalling tail of a relayed LINKREQUEST so
    /// the link is not negotiated above what a relay hop can carry. Mirrors
    /// Python `Transport.inbound()` (lines ~1604-1626):
    ///   - next hop declares no HW MTU, or cannot autoconfigure/fixed MTU →
    ///     disable the upgrade and drop the signalling bytes;
    ///   - otherwise, if the next- or prev-hop HW MTU is below the requested
    ///     path MTU, clamp the signalling to the smallest HW MTU on the path.
    /// With Swift's production interfaces (all `hwMtu == nil`) only the strip
    /// branch fires today; the clamp branch is exercised by tests with an
    /// interface that declares HW MTU, ready for when real interfaces do.
    private func clampRelayedLinkRequestMtu(_ packet: inout Packet,
                                            prevHop: any Interface, nextHop: any Interface) {
        let base = Constants.keySize
        guard packet.data.count == base + 3,
              let pathMtu = Link.mtuFromSignalling(Data(packet.data.suffix(3)))
        else { return }   // no MTU signalling present
        let nhMtu = nextHop.hwMtu
        let phMtu = prevHop.hwMtu
        if nhMtu == nil || (!nextHop.autoconfigureMtu && !nextHop.fixedMtu) {
            // Next hop cannot carry an upgraded MTU — disable the upgrade.
            packet.data = Data(packet.data.prefix(base))
        } else if let nh = nhMtu, nh < pathMtu || (phMtu.map { $0 < pathMtu } ?? false) {
            // Clamp to the smallest HW MTU on the path. INTENTIONAL DIVERGENCE
            // from Python: when the next hop reports an MTU below the path MTU
            // but the prev hop reports no HW MTU, Python computes `min(nh, None)`,
            // raises TypeError, and *drops* the link request. We instead clamp to
            // the next-hop MTU (the binding constraint when the prev hop is
            // unknown) and forward, so a recoverable link still establishes —
            // strictly better than dropping it on a Python `min(None)` crash.
            let clamped = min(nh, phMtu ?? nh)
            packet.data = Data(packet.data.prefix(base)) + Link.mtuSignallingBytes(mtu: clamped)
        }
    }

    private func handleLinkRequestProof(_ packet: Packet, from interface: Interface) {
        if let link = lookupLink(packet.destinationHash) {
            do {
                try link.validateProof(packet)
                // Fire the transport-level callback for the initiator side.
                // The destination's onLinkEstablished is intentionally NOT
                // fired here — it belongs to the responder side and is wired
                // in handleLinkRequest.
                onLinkEstablished?(link)
            } catch {
                // Bad proof — drop.
            }
            return
        }
        // Relay path: forward LRPROOF toward the initiator.
        forwardLinkTraffic(packet, from: interface)
        // Mirrors Python Transport.py line 2199:
        //   RNS.Identity._used_destination_data(link_entry[IDX_LT_DSTHASH])
        // Mark the destination as recently used so cleanKnownDestinations doesn't
        // evict it while the link is active. Only fires when the destination hash
        // is already known (markDestinationUsed returns false otherwise).
        lock.lock()
        let destHash = linkRoutes[packet.destinationHash]?.destinationHash
        lock.unlock()
        if let destHash { markDestinationUsed(destHash) }
    }

    private func handleLinkRTT(_ packet: Packet, from interface: Interface) {
        if let link = lookupLink(packet.destinationHash) {
            try? link.receiveRTT(packet)
            return
        }
        forwardLinkTraffic(packet, from: interface)
    }

    private func handleLinkData(_ packet: Packet, from interface: Interface) {
        if let link = lookupLink(packet.destinationHash) {
            try? link.receive(packet, from: interface)
            return
        }
        forwardLinkTraffic(packet, from: interface)
    }

    private func handleLinkClose(_ packet: Packet, from interface: Interface) {
        if let link = lookupLink(packet.destinationHash) {
            link.receiveTeardown(packet)
            return
        }
        forwardLinkTraffic(packet, from: interface)
    }

    private func lookupLink(_ linkID: Data) -> Link? {
        lock.lock(); defer { lock.unlock() }
        return links[linkID]
    }

    private func forwardLinkTraffic(_ packet: Packet, from sourceInterface: Interface) {
        guard transportEnabled else { return }
        guard packet.hops < propagationLimit else { return }
        lock.lock()
        var route = linkRoutes[packet.destinationHash]
        lock.unlock()
        guard route != nil else { return }
        // Steer to the side that didn't deliver the packet.
        let outboundName: String
        if sourceInterface.name == route!.initiatorSideInterfaceName {
            outboundName = route!.responderSideInterfaceName
        } else if sourceInterface.name == route!.responderSideInterfaceName {
            outboundName = route!.initiatorSideInterfaceName
        } else {
            return
        }
        guard let outbound = interfaces.first(where: {
            $0.name == outboundName && $0.isOnline
        }) else { return }
        var forwarded = packet
        // instance_local_link: both sides of this link are local clients, so the
        // traffic never leaves the local-client domain and must keep its real
        // hop count even under local hop-count obfuscation.
        let initIface = interfaces.first { $0.name == route!.initiatorSideInterfaceName }
        let respIface = interfaces.first { $0.name == route!.responderSideInterfaceName }
        let instanceLocalLink = (initIface.map(isLocalClientInterface) ?? false)
                             && (respIface.map(isLocalClientInterface) ?? false)
        forwarded.hops = relayHops(packet, from: sourceInterface, staysLocal: instanceLocalLink)
        try? outbound.send(forwarded)
        route!.lastHeard = Date()
        lock.lock(); linkRoutes[packet.destinationHash] = route; lock.unlock()
    }

    private func handleProofDelivery(_ packet: Packet, from interface: Interface) {
        let proofData = packet.data
        // packet.destinationHash is the truncated hash of the original DATA packet.
        let proofKey = packet.destinationHash

        // Multi-hop: check if this proof needs to be forwarded back via the reverse table.
        // Mirrors Python: if packet.destination_hash in Transport.reverse_table: forward it.
        reverseTableLock.lock()
        let reverseEntry = reverseTable.removeValue(forKey: proofKey)
        reverseTableLock.unlock()
        if let (receiveIface, outboundIface) = reverseEntry {
            // Only forward if the proof arrived on the outbound interface (it
            // came from the direction of the destination, not the source).
            if (interface as AnyObject) === (outboundIface as AnyObject) {
                var forwarded = packet
                // proof_for_local_client: the proof is headed back to a local
                // client, so it stays in the local domain — keep its real hops.
                let proofForLocalClient = isLocalClientInterface(receiveIface)
                forwarded.hops = relayHops(packet, from: interface, staysLocal: proofForLocalClient)
                try? receiveIface.send(forwarded)
            }
            // Don't stop here — also try to match against local receipts below
            // in case this relay is also the originator (uncommon but valid).
        }

        if proofData.count == PacketReceipt.explicitProofLength {
            // Explicit proof: [32-byte hash][64-byte sig]. Pre-filter by hash.
            let proofHash = proofData.prefix(Constants.fullHashLength)
            receiptsLock.lock()
            let match = receipts.first { $0.packetHash == proofHash }
            receiptsLock.unlock()
            if let match {
                match.validateExplicitProof(proofData)
                return
            }
        } else if proofData.count == PacketReceipt.implicitProofLength {
            // Implicit proof: 64-byte signature only. Must try every receipt
            // (matches Python: "check every single outstanding receipt").
            receiptsLock.lock()
            let snapshot = receipts
            receiptsLock.unlock()
            for receipt in snapshot {
                if receipt.validateImplicitProof(proofData) {
                    receiptsLock.lock()
                    receipts.removeAll { $0 === receipt }
                    receiptsLock.unlock()
                    return
                }
            }
        }

        handleDelivery(packet, from: interface)
    }

    private func handleAnnounce(_ packet: Packet, from interface: Interface) {
        // Mirrors Python: `interface.received_announce()` called on valid announce receipt.
        notifyIncomingAnnounce(on: interface)

        // Ingress burst limiting: hold announces during flooding bursts.
        // Mirrors Python: `if interface.should_ingress_limit(): interface.hold_announce(packet); return`
        // Only applies to unknown destinations (known paths exempt — Python checks path_requests too).
        do {
            let decoded = try Announce.validate(packet)

            // Announce-retry cancel (mirrors Python `Transport.inbound()`'s
            // announce_table handling): if we have a pending retransmission for
            // this destination and we hear it carried on by another transport
            // node (a forwarded HEADER_2 announce), cancel or de-prioritise our
            // retry. Runs before the duplicate filter, since a neighbour's
            // rebroadcast is itself a duplicate that would otherwise be dropped.
            if transportEnabled, packet.headerType == .type2, packet.transportID != nil {
                noteAnnounceRebroadcastHeard(destinationHash: decoded.destinationHash,
                                             incomingHops: Int(packet.hops))
            }

            // Dedup: same announce instance heard from any interface is
            // processed once and re-relayed at most once.
            let dedupKey = decoded.destinationHash + decoded.randomHash
            lock.lock()
            let alreadySeen = announceCacheSet.contains(dedupKey)
            if !alreadySeen {
                announceCacheSet.insert(dedupKey)
                announceCache.append(dedupKey)
                while announceCache.count > announceCacheCap {
                    let evicted = announceCache.removeFirst()
                    announceCacheSet.remove(evicted)
                }
            }
            // Mirrors Python: SINGLE announces are allowed through the duplicate filter
            // multiple times, so that the same announce received via different paths
            // can update the path table with the better (fewer hops) path.
            if alreadySeen {
                // Only re-process if the incoming path is better than what we already have.
                let existingHops = paths[decoded.destinationHash]?.hops ?? UInt8.max
                if packet.hops >= existingHops {
                    lock.unlock()
                    return  // Already seen and not a better path
                }
                // Better path — fall through to update
            }
            lock.unlock()

            // Blackhole filter: drop announces from blackholed identities.
            // Mirrors Python's blackholed_identities check in announce handler.
            if isBlackholed(decoded.identity.hash) { return }

            // Ingress burst limiting for unknown destinations (mirrors Python).
            // Known destinations are exempt (path requests for them may be pending).
            lock.lock()
            let isKnownDest = registeredDestinations[decoded.destinationHash] != nil
                           || paths[decoded.destinationHash] != nil
            lock.unlock()
            if !isKnownDest && shouldIngressLimit(on: interface) {
                holdAnnounce(packet, destinationHash: decoded.destinationHash, on: interface)
                return
            }

            // Per-destination rate limiting (mirrors Python's announce_rate_table check).
            // Only active when interface.announceRateTarget != nil.
            // A rate-blocked announce is still validated but the path table is not updated.
            let rateBlocked = isAnnounceRateBlocked(destinationHash: decoded.destinationHash,
                                                     interface: interface)
            if rateBlocked { return }

            let emittedAt = announceEmitted(packet)
            let randomBlob = announceRandomBlob(packet)
            let now = Date()
            // Paths learned via ROAMING interfaces expire after 6 hours, paths via
            // ACCESS_POINT interfaces expire after 1 hour, and all others use the
            // normal 7-day expiry. Mirrors Python's ROAMING_PATH_EXPIRY /
            // AP_PATH_EXPIRY checks in Transport.announce_handler.
            let pathLifetime: TimeInterval
            switch interface.mode {
            case .roaming:     pathLifetime = Transport.roamingPathExpiry
            case .accessPoint: pathLifetime = Transport.apPathExpiry
            default:           pathLifetime = Transport.pathExpiry
            }
            let entry = PathEntry(
                destinationHash: decoded.destinationHash,
                nextHopInterfaceName: interface.name,
                hops: packet.hops,
                lastHeard: now,
                identityHash: decoded.identity.hash,
                expires: now.addingTimeInterval(pathLifetime),
                // If the announce came in as HEADER_2, the upstream
                // transport's ID is in `transportID`. Future outbound
                // traffic toward this destination should be addressed
                // there so that node can forward it on.
                nextHopTransportID: packet.transportID,
                announceEmittedAt: emittedAt
            )
            lock.lock()
            // Path update logic (mirrors Python's Transport.announce_handler):
            // 1. Always update if we have no path yet.
            // 2. Update if new path has fewer hops.
            // 3. Update if same hops (newer announce).
            // 4. Update if more hops but the announce was emitted MORE RECENTLY
            //    (the existing path's source may have moved or the old path is stale).
            // 5. Update if the existing path is expired.
            let shouldUpdate: Bool
            let isUnresponsive = pathStates[decoded.destinationHash] == Transport.stateUnresponsive
            let existingBlobs = paths[decoded.destinationHash]?.randomBlobs ?? []
            if let existing = paths[decoded.destinationHash] {
                if let randomBlob, existing.randomBlobs.contains(randomBlob) {
                    // Replay/loop guard: we've already heard this exact announce
                    // (same random blob). Mirrors Python's `if not random_blob in
                    // random_blobs` condition, present in every should_add branch —
                    // blocks announce-replay path forging and network loops.
                    shouldUpdate = false
                } else if packet.hops < existing.hops {
                    shouldUpdate = true  // fewer hops → always better
                } else if packet.hops == existing.hops {
                    shouldUpdate = true  // same hops → accept (newer timestamp)
                } else if existing.isExpired {
                    shouldUpdate = true  // expired path → accept any announce
                } else if emittedAt > existing.announceEmittedAt {
                    shouldUpdate = true  // more recent source announce → accept even if more hops
                } else if isUnresponsive {
                    // Mirrors Python: "if path_is_unresponsive: should_add = True"
                    // Allow updating unresponsive paths with any new announce.
                    shouldUpdate = true
                } else {
                    shouldUpdate = false
                }
            } else {
                shouldUpdate = true  // no existing path
            }
            if shouldUpdate {
                // Cache the announce packet to disk so the path table survives restarts.
                // Mirrors Python: `Transport.cache(packet, force_cache=True, packet_type="announce")`
                let announceHash = (try? Hashes.fullHash(packet.hashablePart())) ?? Data()
                var updatedEntry = entry
                updatedEntry.cachedAnnounceHash = announceHash
                // Record this announce's random blob (newest last, capped) so future
                // replays of it are rejected. Mirrors Python's
                // `random_blobs.append(random_blob); random_blobs[-MAX_RANDOM_BLOBS:]`.
                if let randomBlob {
                    var blobs = existingBlobs
                    if !blobs.contains(randomBlob) { blobs.append(randomBlob) }
                    if blobs.count > Transport.maxRandomBlobs {
                        blobs.removeFirst(blobs.count - Transport.maxRandomBlobs)
                    }
                    updatedEntry.randomBlobs = blobs
                }
                paths[decoded.destinationHash] = updatedEntry
                lock.unlock()
                try? cacheAnnounce(packet, receivingInterfaceName: interface.name)
                lock.lock()
                // Reset responsiveness state when path is updated with fresh announce.
                // Mirrors Python: Transport.mark_path_unknown_state(destination_hash)
                pathStates[decoded.destinationHash] = Transport.stateUnknown
            }
            // Attach app_data to the identity so callers can retrieve it via
            // Identity.recallAppData / Transport.recallAppData.  Python stores this in
            // Identity.known_destination_hashes[hash]["app_data"].
            if let ad = decoded.appData { decoded.identity.appData = ad }
            knownIdentities[decoded.destinationHash] = decoded.identity
            knownDestinationAnnouncedAt[decoded.destinationHash] = Date()
            cachedAnnounces[decoded.destinationHash] = packet
            if let ratchet = decoded.ratchet {
                let now = Date()
                knownRatchets[decoded.destinationHash] = ratchet
                knownRatchetTimes[decoded.destinationHash] = now
                persistKnownRatchet(ratchet, forDestination: decoded.destinationHash, receivedAt: now)
            }
            // If this announce arrived on a tunneled interface, record the path in
            // the tunnel entry so it can be restored if the tunnel reappears.
            // Mirrors Python's `Transport.announce_handler` tunnel path recording.
            if let tunnelID = interface.tunnelID, tunnels[tunnelID] != nil {
                tunnels[tunnelID]!.paths[decoded.destinationHash] = entry
                tunnels[tunnelID]!.expires = Date().addingTimeInterval(Transport.tunnelTimeout)
            }
            lock.unlock()

            onAnnounceReceived?(decoded, interface)
            dispatchAnnounceHandlers(decoded)

            // Relay onto other interfaces if we're a transport-enabled node OR
            // the announce was originated by a directly-connected local client.
            // The local-client alternative mirrors Python's
            // `if (transport_enabled or is_from_local_client) and context !=
            // PATH_RESPONSE:` (Transport.py:1935): a shared instance running with
            // enable_transport = No must still propagate its own clients'
            // announces to the mesh, otherwise no peer ever learns the client's
            // destination.
            //
            // Forward ONLY when the announce also updated the path table — this
            // mirrors Python, where the announce-table insert (and thus the
            // rebroadcast) lives inside `if should_add:`. Because SINGLE
            // announces bypass the packet-hash dedup filter, forwarding every
            // arrival would re-broadcast duplicates/replays endlessly (an
            // announce storm); gating on `shouldUpdate` (which includes the
            // random-blob replay guard) forwards each distinct announce once.
            // Path-response announces are NOT forwarded (mirrors Python:
            // "if context != PATH_RESPONSE: forward to other interfaces").
            // Each outbound interface is rate-limited; announces that exceed
            // the cap are queued for deferred transmission.
            let fromLocalClient = fromLocalClient(interface: interface)
            if shouldUpdate,
               transportEnabled || fromLocalClient,
               !decoded.isPathResponse,
               packet.hops < propagationLimit,
               interfaces.contains(where: { $0.isRoutingEndpoint }) {
                var forwarded = packet
                forwarded.hops = packet.hops &+ 1
                forwarded.headerType = .type2
                forwarded.transportID = transportInstanceID
                let emitted = announceEmitted(forwarded)
                let now = Date().timeIntervalSince1970
                for iface in interfaces where iface.isOnline && iface.isRoutingEndpoint && iface !== interface {
                    // Interface-mode-based forwarding filter (mirrors Python Transport.outbound):
                    // - Announces received from ACCESS_POINT interfaces (clients talking "up")
                    //   must not be re-broadcast to other AP or BOUNDARY interfaces —
                    //   AP clients must not be able to reach each other via the AP.
                    // - Announces received from BOUNDARY interfaces must not be re-broadcast
                    //   to other BOUNDARY or ACCESS_POINT interfaces.
                    // - Announces received on FULL/GATEWAY/ROAMING/POINT_TO_POINT interfaces
                    //   are forwarded freely (including to AP and BOUNDARY interfaces).
                    guard Transport.shouldForwardAnnounce(
                        outboundMode: iface.mode,
                        nextHopMode: interface.mode,
                        localDestination: false,
                        announcesFromInternal: iface.announcesFromInternal
                    ) else { continue }
                    queueLock.lock()
                    if announceQueues[iface.name] == nil {
                        announceQueues[iface.name] = AnnounceQueue()
                    }
                    let queue = announceQueues[iface.name]!
                    queueLock.unlock()
                    let canSend = queue.shouldTransmit(
                        packet: forwarded,
                        now: now,
                        bitrate: iface.bitrate,
                        emitted: emitted
                    )
                    if canSend { try? iface.send(forwarded) }
                }

                // Record this forwarded announce for a single retransmission
                // (Python `PATHFINDER_R = 1`). The first forward just went out
                // above, so the entry starts at `retries = 1`; the jobs loop
                // will retransmit once more after the grace window unless we
                // hear neighbours carry it on. Mirrors the announce_table insert
                // inside Python's `if should_add:` block.
                lock.lock()
                announceTable[decoded.destinationHash] = AnnounceTableEntry(
                    timestamp: now,
                    retransmitTimeout: now + Transport.pathfinderG
                        + Double.random(in: 0 ..< Transport.pathfinderRW),
                    retries: 1,
                    hops: Int(packet.hops),
                    packet: packet,
                    localRebroadcasts: 0,
                    blockRebroadcasts: false,
                    attachedInterfaceName: nil,
                    receivingInterfaceName: interface.name,
                    receivingInterfaceMode: interface.mode
                )
                lock.unlock()
            }

            // If we have any local shared-instance clients connected, retransmit
            // the announce to them immediately — independent of `transportEnabled`
            // and regardless of path-response context. Mirrors Python's
            // "if (len(Transport.local_client_interfaces)): ... new_announce.send()"
            // block: apps sharing this daemon's connection (nomadnet, rnstatus,
            // MeshChatX, …) must see every announce the daemon overhears, even
            // when this instance is not itself acting as a mesh transport/relay
            // node. Unlike the mesh-relay forward above, hops is passed through
            // unchanged (Python: `new_announce.hops = packet.hops`).
            let localTargets = localClientServingInterfaces(excluding: interface)
            if shouldUpdate, !localTargets.isEmpty {
                var localForward = packet
                localForward.headerType = .type2
                localForward.transportID = transportInstanceID
                for iface in localTargets {
                    try? iface.send(localForward)
                }
            }
        } catch {
            // Malformed or unsigned announce — drop silently as RNS does.
        }
    }

    private func handleDelivery(_ packet: Packet, from interface: Interface) {
        lock.lock()
        let destination = registeredDestinations[packet.destinationHash]
        let path = paths[packet.destinationHash]
        lock.unlock()

        if let destination {
            // Stamp the receiving interface on the packet so the app can call
            // packet.prove(destination:) in its callback. Mirrors Python's
            // `packet.receiving_interface = receiving_interface`.
            var deliveredPacket = packet
            deliveredPacket.receivingInterface = interface

            onPacketDelivered?(deliveredPacket, destination, interface)
            // Decrypt and dispatch to destination's application callback.
            if let cb = destination.onPacketReceived {
                if let plaintext = try? destination.decrypt(deliveredPacket.data) {
                    cb(plaintext, deliveredPacket)
                }
            }
            // Generate a delivery proof for DATA packets if the destination's
            // proof strategy requires it. Mirrors Python's `packet.prove()`.
            if packet.packetType == .data {
                switch destination.proofStrategy {
                case .proveAll:
                    sendProof(for: packet, from: interface, destination: destination)
                case .proveApp:
                    if destination.onProofRequested?(packet) == true {
                        sendProof(for: packet, from: interface, destination: destination)
                    }
                case .proveNone:
                    break
                }
            }
            return
        }

        // No local destination — relay if we're transport-enabled and we
        // know a path. Only SINGLE packets are transported over multiple hops.
        // PLAIN and GROUP packets are local-only (not forwarded).
        // LINK-typed packets are routed by their own dispatchers.
        guard transportEnabled,
              packet.destinationType == .single else { return }
        guard let path else { return }
        forward(packet, from: interface, path: path)
    }

    // MARK: - Path requests

    /// Broadcast a path request for `destinationHash`. Any node within
    /// reach that already knows a path will reply by re-broadcasting the
    /// cached announce.
    ///
    /// - Parameters:
    ///   - destinationHash: 16-byte truncated hash of the destination.
    ///   - onInterface: Limit the request to a single interface, or nil to broadcast on all.
    ///   - tag: Optional 16-byte dedup tag. A random tag is generated when nil.
    ///     Mirrors Python's `Transport.request_path(tag=None)`.
    ///   - recursive: When true the request is also forwarded by transport nodes.
    ///     Mirrors Python's `Transport.request_path(recursive=False)`.
    ///     Currently reserved for future use (Python's recursive handling is
    ///     performed by the receiving transport, not the sender).
    public func requestPath(
        for destinationHash: Data,
        onInterface: (any Interface)? = nil,
        tag: Data? = nil,
        recursive: Bool = false
    ) throws {
        guard destinationHash.count == Constants.truncatedHashLength else { return }
        var tag = tag ?? {
            var t = Data(count: Constants.truncatedHashLength)
            _ = t.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, Constants.truncatedHashLength, $0.baseAddress!)
            }
            return t
        }()
        _ = recursive // forwarded-recursion is handled by the receiving transport node
        // Mirrors Python: if transport_enabled: body = destHash + transport_id + tag
        //                 else:                  body = destHash + tag
        let body = transportEnabled
            ? destinationHash + transportInstanceID + tag
            : destinationHash + tag

        // Pre-seed our own dedup so we don't re-process our own request
        // when it bounces back from an interface's local echo.
        let dedupKey = destinationHash + tag
        lock.lock()
        if !pathRequestTagSet.contains(dedupKey) {
            pathRequestTagSet.insert(dedupKey)
            pathRequestTags.append(dedupKey)
        }
        lock.unlock()

        let packet = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.pathRequestDestinationHash,
            data: body
        )
        if let iface = onInterface {
            try iface.send(packet)
            // Mirrors Python: `interface.sent_path_request()` after sending.
            notifyOutgoingPathRequest(on: iface)
        } else {
            try send(packet)
            for iface in interfaces where iface.isOnline {
                notifyOutgoingPathRequest(on: iface)
            }
        }
    }

    private func handlePathRequest(_ packet: Packet, from interface: Interface) {
        // Mirrors Python: `interface.received_path_request()` when a path request arrives.
        notifyIncomingPathRequest(on: interface)
        let body = packet.data
        let hashLen = Constants.truncatedHashLength
        guard body.count >= hashLen + 1 else { return }
        let target = Data(body.prefix(hashLen))

        // Extract the optional requesting transport instance ID and tag.
        // Python body shapes: [target||tag] or [target||tx_id||tag]
        let requestorTransportID: Data?
        let tag: Data
        if body.count > hashLen * 2 {
            requestorTransportID = Data(body[body.startIndex + hashLen ..< body.startIndex + hashLen * 2])
            tag = Data(body.suffix(from: body.startIndex + hashLen * 2))
        } else {
            requestorTransportID = nil
            tag = Data(body.suffix(from: body.startIndex + hashLen))
        }
        let dedupKey = target + tag

        lock.lock()
        let alreadySeen = pathRequestTagSet.contains(dedupKey)
        if !alreadySeen {
            pathRequestTagSet.insert(dedupKey)
            pathRequestTags.append(dedupKey)
            while pathRequestTags.count > pathRequestCacheCap {
                let evicted = pathRequestTags.removeFirst()
                pathRequestTagSet.remove(evicted)
            }
        }
        let cachedAnnounce = cachedAnnounces[target]
        let isLocal = registeredDestinations[target] != nil
        let pathEntry = paths[target]
        lock.unlock()
        if alreadySeen { return }

        if isLocal {
            lock.lock()
            let localDest = registeredDestinations[target]
            lock.unlock()
            if let dest = localDest, dest.identity?.hasPrivateKey == true {
                let pkt = try? Announce.make(for: dest, isPathResponse: true)
                if let pkt { try? interface.send(pkt) }
            }
            onPathRequested?(target, interface)
            return
        }

        if var cachedAnnounce {
            // Suppress answer when the next hop along the path IS the requestor
            // (would create a routing loop). Mirrors Python's requestor_transport_id check.
            if let rID = requestorTransportID,
               let entry = pathEntry,
               let nhID = entry.nextHopTransportID,
               nhID == rID {
                // Requestor IS the next hop — don't send a response.
                return
            }
            cachedAnnounce.context = .pathResponse
            // Python stores announce_hops = packet.hops AFTER inbound +1. Swift doesn't
            // do an inbound increment, so `cachedAnnounce.hops` = raw wire hops (e.g. 0).
            // Mimic Python: set hops = stored path hops + 1 so the recipient computes the
            // correct hops_to and expected_proof_hops for link establishment.
            if let entry = pathEntry {
                cachedAnnounce.hops = entry.hops &+ 1
            }
            // Python always sends path responses as HEADER_2 with the relay's transport_id
            // (mirrors Python: header_type=HEADER_2, transport_type=TRANSPORT,
            //  transport_id=Transport.identity.hash).
            // This ensures the requester stores `received_from = transportInstanceID`
            // in its path table, so outbound packets are correctly addressed to us.
            cachedAnnounce.headerType = .type2
            cachedAnnounce.transportType = .transport
            cachedAnnounce.transportID = transportInstanceID
            try? interface.send(cachedAnnounce)
            return
        }

        // No cached announce and no local destination.
        // If transport is enabled and the incoming interface mode is in DISCOVER_PATHS_FOR,
        // forward the path request on all other interfaces to attempt discovery.
        // Mirrors Python's `should_search_for_unknown` / discovery_path_requests logic.
        // For all other modes (full, point-to-point, boundary) the request is silently ignored.
        // RNS 1.3.6: `recursive_prs` forces discovery regardless of interface mode.
        let shouldDiscover = transportEnabled
            && (interface.recursivePrs || InterfaceMode.discoverPathsFor.contains(interface.mode))
        if shouldDiscover {
            let now = Date().timeIntervalSince1970
            for iface in interfaces where iface !== interface && iface.isOnline && iface.isRoutingEndpoint {
                if shouldEgressLimitPR(on: iface, now: now) { continue }
                try? requestPath(for: target, onInterface: iface)
            }
        }
    }

    // MARK: - Packet hashlist (replay/loop prevention)

    /// Returns `true` if this packet hash has not been seen before and
    /// adds it to the current hashlist. Returns `false` for duplicates.
    /// Mirrors Python's `Transport.packet_filter` + `add_packet_hash`.
    func filterAndRecord(packet: Packet) -> Bool {
        // Filter packets explicitly addressed to a *different* transport instance.
        // Mirrors Python `Transport.packet_filter`:
        //   if packet.transport_id != None and packet.packet_type != ANNOUNCE:
        //       if packet.transport_id != Transport.identity.hash: return False
        // A HEADER_2 packet carries the next-hop transport_id; if that names
        // another node (and it isn't a flooded announce), the packet is meant
        // for that node — dropping it here prevents duplicate forwarding and
        // routing loops on shared media with ≥2 transport nodes. A shared-
        // instance client skips this (the shared instance already filtered).
        if !isConnectedToSharedInstance,
           packet.packetType != .announce,
           let tid = packet.transportID,
           tid != transportInstanceID {
            return false
        }

        // PLAIN destination packets with hops > 1 are dropped.
        // Python: "if destination_type == PLAIN and hops > 1: drop"
        // Allows hops=0 (direct) and hops=1 (one relay hop, e.g. path requests).
        if packet.destinationType == .plain && packet.hops > 1 { return false }

        // GROUP destination packets with hops > 1 are dropped (local broadcast only).
        // Mirrors Python: "if destination_type == GROUP and hops > 1: drop"
        if packet.destinationType == .group && packet.hops > 1 { return false }

        guard let hashable = try? packet.hashablePart() else { return false }
        let hash = Hashes.fullHash(hashable)
        hashlistLock.lock()
        defer { hashlistLock.unlock() }
        // Two-generation dedup: drop if seen in current or previous window.
        if packetHashlist.contains(hash) || packetHashlistPrev.contains(hash) {
            // Mirrors Python: SINGLE announces are allowed through the packet filter
            // multiple times (to allow path table updates via multiple paths).
            if packet.packetType == .announce && packet.destinationType == .single {
                return true
            }
            return false
        }
        // LRR and LRPROOF are excluded from the hashlist (link handshake
        // packets need to be able to pass through multiple times).
        if packet.packetType != .linkRequest && packet.context != .lrproof {
            packetHashlist.insert(hash)
            // Rotate when current generation reaches the size limit.
            if packetHashlist.count >= hashlistMaxSize {
                packetHashlistPrev = packetHashlist
                packetHashlist = []
            }
        }
        return true
    }

    // MARK: - Packet hashlist persistence

    /// Persist the current packet hashlist to disk.
    /// Mirrors Python's `Transport.save_packet_hashlist()`.
    public func savePacketHashlist(to url: URL) throws {
        hashlistLock.lock()
        let snapshot = packetHashlist.union(packetHashlistPrev)
        hashlistLock.unlock()
        let hexList = snapshot.map { $0.hexString }
        let data = try JSONEncoder().encode(hexList)
        try data.write(to: url, options: .atomic)
    }

    /// Load a previously persisted packet hashlist and merge into the current set.
    /// Mirrors Python's hashlist loading in `Transport.__init__`.
    /// A missing file is silently ignored.
    public func loadPacketHashlist(from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        let hexList = try JSONDecoder().decode([String].self, from: data)
        hashlistLock.lock()
        defer { hashlistLock.unlock() }
        for hex in hexList {
            if let h = Data(hex: hex) { packetHashlist.insert(h) }
        }
    }

    /// Add a packet hash to the deduplication hashlist.
    /// Mirrors Python `Transport.add_packet_hash(packet_hash)`.
    public func addPacketHash(_ packetHash: Data) {
        hashlistLock.lock(); defer { hashlistLock.unlock() }
        packetHashlist.insert(packetHash)
    }

    /// Returns true if the packet should be processed (not a duplicate, passes type/hop rules).
    /// Mirrors Python `Transport.packet_filter(packet)` — simplified to dedup check only;
    /// full filtering is done inside `handleIncoming`.
    public func packetFilter(_ packet: Packet) -> Bool {
        guard let hash = try? packet.truncatedPacketHash() else { return true }
        hashlistLock.lock()
        let seen = packetHashlist.contains(hash) || packetHashlistPrev.contains(hash)
        hashlistLock.unlock()
        if seen {
            // Announces for SINGLE destinations pass even if seen (Python parity)
            if packet.packetType == .announce && packet.destinationType == .single { return true }
            return false
        }
        return true
    }

    /// Test helper: directly insert a hash into the packet hashlist.
    func testInsertPacketHash(_ hash: Data) {
        hashlistLock.lock()
        packetHashlist.insert(hash)
        hashlistLock.unlock()
    }

    /// Test helper: check if a hash is in the packet hashlist (current or previous).
    func testContainsPacketHash(_ hash: Data) -> Bool {
        hashlistLock.lock()
        defer { hashlistLock.unlock() }
        return packetHashlist.contains(hash) || packetHashlistPrev.contains(hash)
    }

    // MARK: - Proof generation

    /// Public entry point for `Packet.prove(destination:)`.
    /// Mirrors Python's `Transport.packet_prove(packet, destination)`.
    public func provePacket(_ packet: Packet, from sourceInterface: any Interface, destination: Destination) {
        sendProof(for: packet, from: sourceInterface, destination: destination)
    }

    /// Send an explicit delivery proof for `packet` back on the interface it
    /// arrived on. Wire format: `[32-byte full hash][64-byte Ed25519 sig]`.
    ///
    /// The proof is sent as a PROOF packet whose `destinationHash` is the
    /// truncated hash of the original packet (so the sender can match it to
    /// an outstanding `PacketReceipt`). Mirrors Python's `Identity.prove`.
    private func sendProof(for packet: Packet, from sourceInterface: Interface, destination: Destination) {
        guard let identity = destination.identity,
              identity.hasPrivateKey,
              let hashable = try? packet.hashablePart() else { return }
        let fullHash = Hashes.fullHash(hashable)
        guard let sig = try? identity.sign(fullHash) else { return }

        // Python: if should_use_implicit_proof(): proof_data = signature
        //         else: proof_data = packet_hash + signature
        let proofData: Data = Reticulum.shouldUseImplicitProof()
            ? sig               // implicit: signature only (64 bytes)
            : fullHash + sig    // explicit: hash + signature (96 bytes)

        let truncHash = Data(fullHash.prefix(Constants.truncatedHashLength))
        let proof = Packet(
            destinationType: .single,
            packetType: .proof,
            destinationHash: truncHash,
            context: .none,
            data: proofData
        )
        // Send on the same interface the data packet arrived on, so
        // the proof travels back toward the sender.
        try? sourceInterface.send(proof)
    }

    // MARK: - Announce queue helpers

    /// Decide whether a relayed announce should be transmitted on an outbound interface.
    ///
    /// Mirrors Python `Transport.outbound()` announce-mode filtering as reworked
    /// in RNS 1.3.7 (the `if packet.attached_interface == None:` block for
    /// ANNOUNCE packets).
    ///
    /// Parameters:
    /// - `outboundMode`: mode of the interface we're considering transmitting on.
    /// - `nextHopMode`: mode of the next-hop interface toward the announce's
    ///   source (the interface it arrived on). `nil` means Python's
    ///   `from_interface == None` — no known next hop.
    /// - `localDestination`: true when the announce's destination is registered
    ///   locally (Python's `destinations_map` lookup). Instance-local
    ///   destinations bypass the roaming/boundary/internal mode blocks.
    /// - `announcesFromInternal`: the outbound interface's
    ///   `announces_from_internal` setting.
    ///
    /// Rules (checked on the **outbound** interface, not the receiving interface):
    ///
    /// - **No next hop** (and not local): block — nowhere to attribute the announce.
    /// - **`announces_from_internal == false` + internal next hop** (and not
    ///   local): block relaying announces that came in from an internal interface.
    /// - **AP outbound**: always block — AP-mode interfaces are "last-mile".
    /// - **INTERNAL outbound** (not local): block when the next hop is BOUNDARY.
    ///   (RNS 1.3.7 no longer blocks a roaming next hop here.)
    /// - **ROAMING outbound**: allow if local; else block when the next hop is
    ///   ROAMING or BOUNDARY.
    /// - **BOUNDARY outbound**: allow if local; else block when the next hop is ROAMING.
    /// - **All other outbound modes** (FULL, GATEWAY, POINT_TO_POINT): allow.
    public static func shouldForwardAnnounce(
        outboundMode: InterfaceMode,
        nextHopMode: InterfaceMode?,
        localDestination: Bool = false,
        announcesFromInternal: Bool = true
    ) -> Bool {
        // Top-level guards — only apply when the destination is not instance-local.
        if !localDestination && nextHopMode == nil { return false }
        if !localDestination && !announcesFromInternal && nextHopMode == .internal { return false }

        switch outboundMode {
        case .accessPoint:
            // AP outbound is never used for relayed announces.
            return false
        case .internal:
            // RNS 1.3.7 MODE_INTERNAL: for non-local destinations, block only
            // when the next-hop interface toward the source is boundary.
            if !localDestination {
                guard let nhm = nextHopMode else { return false }
                if nhm == .boundary { return false }
            }
            return true
        case .roaming:
            // Instance-local destinations always allowed.
            if localDestination { return true }
            guard let nhm = nextHopMode else { return false }
            // Block if next-hop came from another roaming or boundary segment.
            return nhm != .roaming && nhm != .boundary
        case .boundary:
            if localDestination { return true }
            guard let nhm = nextHopMode else { return false }
            // Block only if next-hop is roaming (boundary-to-boundary is fine).
            return nhm != .roaming
        default:
            // FULL, GATEWAY, POINT_TO_POINT — forward freely.
            return true
        }
    }

    /// Extract the emission timestamp from an announce's random hash
    /// (bytes [5..9] = 5-byte big-endian unix seconds). Matches Python's
    /// `Transport.announce_emitted(packet)`.
    private func announceEmitted(_ packet: Packet) -> TimeInterval {
        let body = packet.data
        let keysize = Constants.keySize
        let nameHashLen = Constants.nameHashLength
        // random_hash starts at offset keysize + nameHashLen
        let rStart = keysize + nameHashLen
        guard body.count > rStart + 9 else { return Date().timeIntervalSince1970 }
        var ts: UInt64 = 0
        for i in 5..<10 {
            ts = (ts << 8) | UInt64(body[rStart + i])
        }
        return TimeInterval(ts)
    }

    /// Extract the 10-byte announce random blob (the announce's random hash).
    /// Mirrors Python's `random_blob = packet.data[KEYSIZE+NAME_HASH : +10]`.
    /// Returns `nil` if the announce body is too short.
    private func announceRandomBlob(_ packet: Packet) -> Data? {
        let bytes = Array(packet.data)
        let start = Constants.keySize + Constants.nameHashLength
        guard bytes.count >= start + 10 else { return nil }
        return Data(bytes[start ..< start + 10])
    }

    /// Drain any queued announces onto their respective interfaces.
    /// Called from the jobs loop every `jobInterval` seconds.
    private func drainAnnounceQueues() {
        let now = Date().timeIntervalSince1970
        queueLock.lock()
        let snapshot = announceQueues
        queueLock.unlock()
        for (name, queue) in snapshot {
            guard let iface = interfaces.first(where: { $0.name == name && $0.isOnline }) else {
                continue
            }
            let packets = queue.drain(now: now, bitrate: iface.bitrate)
            for pkt in packets { try? iface.send(pkt) }
        }
    }

    private func dispatchAnnounceHandlers(_ decoded: Announce.Decoded) {
        announceHandlerLock.lock()
        let handlers = announceHandlers
        announceHandlerLock.unlock()
        for handler in handlers {
            // Mirrors Python: skip path-response announces unless handler opted in.
            if decoded.isPathResponse && !handler.receivePathResponses { continue }

            guard let filter = handler.aspectFilter else {
                handler.receivedAnnounce(
                    destinationHash: decoded.destinationHash,
                    identity: decoded.identity,
                    appData: decoded.appData,
                    announcePacketHash: decoded.packetHash,
                    isPathResponse: decoded.isPathResponse
                )
                continue
            }
            // Parse "appName.aspect1.aspect2..." and compute the expected hash
            // for this filter paired with the announcing identity.
            let parts = filter.split(separator: ".").map(String.init)
            let appName = parts.first ?? filter
            let aspects = Array(parts.dropFirst())
            let nameHash = Destination.computeNameHash(appName: appName, aspects: aspects)
            let expected = Destination.computeHash(
                identity: decoded.identity,
                nameHash: nameHash,
                kind: .single
            )
            if decoded.destinationHash == expected {
                handler.receivedAnnounce(
                    destinationHash: decoded.destinationHash,
                    identity: decoded.identity,
                    appData: decoded.appData,
                    announcePacketHash: decoded.packetHash,
                    isPathResponse: decoded.isPathResponse
                )
            }
        }
    }

    private func forward(_ packet: Packet, from sourceInterface: Interface, path: PathEntry) {
        guard packet.hops < propagationLimit else { return }
        guard let outbound = interfaces.first(where: {
            $0.name == path.nextHopInterfaceName && $0.isOnline
        }) else { return }
        guard outbound !== sourceInterface else { return }   // never bounce
        var forwarded = packet
        // to_local_client: a directly reachable destination (path.hops == 0) is a
        // local client, so relayed data staying local keeps its real hop count;
        // otherwise obfuscate hops for data relayed on behalf of a local client.
        // Python: `if local_hops_delta != 0 and from_local_client and not to_local_client`.
        forwarded.hops = relayHops(packet, from: sourceInterface, staysLocal: path.hops == 0)
        // Mirror Python's in-transport DATA rewrite (Transport.inbound, the
        // `transport_id == Transport.identity.hash` branch):
        //   • remaining_hops > 1  (Swift path.hops > 0): keep HEADER_2 and
        //     address the next-hop transport so that node forwards onward.
        //   • remaining_hops == 1 (Swift path.hops == 0): the destination is
        //     directly reachable on the outbound interface — strip the
        //     transport header and transmit HEADER_1. The endpoint filters on
        //     transport_id (see filterAndRecord), so a HEADER_2 packet bearing
        //     this relay's id would be dropped. Same logic as the LINKREQUEST
        //     relay path in handleLinkRequest.
        if path.hops > 0 {
            forwarded.headerType = .type2
            forwarded.transportID = path.nextHopTransportID ?? transportInstanceID
        } else {
            forwarded.headerType = .type1
            forwarded.transportType = .broadcast
            forwarded.transportID = nil
        }

        // Store the reverse table entry BEFORE sending, so synchronous loopback
        // interfaces don't race: if the proof arrives in the same call stack (e.g.
        // in-process loopback tests), the entry must already be present.
        // Mirrors Python: Transport.reverse_table[packet.getTruncatedHash()] = entry.
        if let key = try? Hashes.truncatedHash(packet.hashablePart()) {
            reverseTableLock.lock()
            reverseTable[key] = (receiveIface: sourceInterface, outboundIface: outbound)
            reverseTableLock.unlock()
        }

        try? outbound.send(forwarded)
    }

    // MARK: - Tunnel synthesis

    /// Send a tunnel-synthesize packet on `interface` to establish this transport as
    /// a tunnel endpoint for that interface. Matches Python `Transport.synthesize_tunnel`.
    ///
    /// Wire layout of the DATA payload (176 bytes):
    ///   [  0.. 63] 64 bytes: combined public key (X25519 + Ed25519)
    ///   [ 64.. 95] 32 bytes: SHA-256 of interface name ("interface hash")
    ///   [ 96..111] 16 bytes: random hash (replay-prevention nonce)
    ///   [112..175] 64 bytes: Ed25519 signature over bytes 0..111
    public func synthesizeTunnel(_ interface: any Interface) {
        guard let identity = ownerIdentity else { return }

        let publicKey  = identity.publicKeyBytes                          // 64 bytes
        let ifaceHash  = Hashes.fullHash(Data(interface.name.utf8))      // 32 bytes
        let randomHash = Hashes.randomHash()                             // 16 bytes
        let signedData = publicKey + ifaceHash + randomHash              // 112 bytes
        guard let signature = try? identity.sign(signedData) else { return }

        let data = signedData + signature                                 // 176 bytes
        let packet = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: Transport.tunnelSynthesizeHash,
            data: data
        )
        try? interface.send(packet)
        interface.wantsTunnel = false
    }

    /// Handle an incoming tunnel-synthesize packet. Validates the signature and
    /// creates a tunnel entry for the sending transport node.
    /// Matches Python `Transport.tunnel_synthesize_handler`.
    private func handleTunnelSynthesizePacket(data: Data, from interface: any Interface) {
        // Expected: pubkey(64) + ifaceHash(32) + randomHash(16) + signature(64) = 176
        let expectedLength = 64 + 32 + 16 + 64
        guard data.count == expectedLength else { return }

        let publicKey     = data[0..<64]
        let ifaceHash     = data[64..<96]
        let tunnelIDData  = Data(publicKey) + Data(ifaceHash)
        let tunnelID      = Hashes.fullHash(tunnelIDData)
        let randomHash    = data[96..<112]
        let signature     = data[112..<176]
        let signedData    = tunnelIDData + Data(randomHash)

        guard let remoteIdentity = try? Identity(publicKeyBytes: Data(publicKey)) else { return }
        guard remoteIdentity.validate(signature: Data(signature), for: signedData) else { return }

        handleTunnel(tunnelID: tunnelID, interface: interface)
    }

    private func handleTunnel(tunnelID: Data, interface: any Interface) {
        let expires = Date().addingTimeInterval(Transport.tunnelTimeout)
        lock.lock()
        defer { lock.unlock() }
        if tunnels[tunnelID] == nil {
            tunnels[tunnelID] = TunnelEntry(
                tunnelID: tunnelID,
                iface: interface,
                paths: [:],
                expires: expires
            )
        } else {
            tunnels[tunnelID]!.iface = interface
            tunnels[tunnelID]!.expires = expires
        }
        interface.tunnelID = tunnelID
    }
}
