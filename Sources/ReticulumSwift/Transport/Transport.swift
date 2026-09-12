//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

/// The Transport system.
///
/// Owns interfaces, registered destinations, and a
/// path table populated from received announces. Announces are validated
/// and forwarded; non-announce packets are delivered to any local
/// destination matching the destination hash.
public final class Transport {

    // MARK: - Constants (mirrors Python Transport class attributes)

    /// Maximum percentage of interface bandwidth used for announce propagation.
    ///
    /// Mirrors Python's `Reticulum.ANNOUNCE_CAP = 2`.
    public static let announceCap: Int = 2

    /// Maximum number of queued announces across all interfaces.
    ///
    /// Mirrors Python's `Reticulum.MAX_QUEUED_ANNOUNCES = 16384`.
    public static let maxQueuedAnnounces: Int = 16384

    /// Lifetime of a queued announce in seconds.
    ///
    /// Mirrors Python's `Reticulum.QUEUED_ANNOUNCE_LIFE = 86400`.
    public static let queuedAnnounceLife: TimeInterval = 86400

    /// Grace period before persist at shutdown (seconds).
    ///
    /// Mirrors Python's `Reticulum.GRACIOUS_PERSIST_INTERVAL = 300`.
    public static let graciousPersistInterval: TimeInterval = 300

    /// Minimum bitrate (bits/second) required for Reticulum to function.
    ///
    /// Mirrors Python's `Reticulum.MINIMUM_BITRATE = 5`.
    public static let minimumBitrate: Int = 5

    /// Resource cache lifetime in seconds.
    ///
    /// Mirrors Python's `Reticulum.RESOURCE_CACHE = 24*60*60`.
    public static let resourceCacheTimeout: TimeInterval = 86400

    /// Background maintenance job interval in seconds.
    ///
    /// Python's global `Reticulum.JOB_INTERVAL = 5*60 = 300`, but Swift's
    /// jobs loop runs every 5 seconds for more responsive sweeps.
    public static let cleanInterval: TimeInterval = 900   // Python: 15*60

    /// Interval between persistent data saves in seconds.
    ///
    /// Mirrors Python's `Reticulum.PERSIST_INTERVAL = 60*60*12`.
    public static let persistInterval: TimeInterval = 43200

    /// Default path expiry: 7 days.
    ///
    /// Python: `Transport.PATHFINDER_E = 60*60*24*7`.
    public static let pathExpiry: TimeInterval = 60 * 60 * 24 * 7
    /// Roaming-mode path expiry: 6 hours.
    ///
    /// Python: `Transport.ROAMING_PATH_TIME = 60*60*6`.
    public static let roamingPathExpiry: TimeInterval = 60 * 60 * 6
    /// Access-point path expiry: 1 day.
    ///
    /// Python: `Transport.AP_PATH_TIME = 60*60*24`.
    public static let apPathExpiry: TimeInterval = 60 * 60 * 24
    /// How often the jobs loop runs (seconds).
    public static let jobInterval: TimeInterval = 5
    /// How often the jobs loop invokes `cleanKnownDestinations`.
    ///
    /// Mirrors Python's periodic clean-jobs scheduler in `Reticulum.__clean_caches`
    /// (RNS commit b408699e). Defaults to 1 hour to amortise the table walk.
    public static let knownDestinationsCleanInterval: TimeInterval = 60 * 60
    /// Maximum receipts tracked simultaneously.
    public static let maxReceipts: Int = 1024
    /// Maximum number of hops Reticulum transports a packet.
    ///
    /// Python: `Transport.PATHFINDER_M = 128`.
    public static let pathfinderM: Int = 128
    /// Announce retransmit retries.
    ///
    /// Python: `Transport.PATHFINDER_R = 1`.
    public static let pathRequestRetries: Int = 1
    /// Retry grace period in seconds.
    ///
    /// Python: `Transport.PATHFINDER_G = 5`.
    public static let pathfinderG: TimeInterval = 5
    /// Random window for announce rebroadcast jitter.
    ///
    /// Python: `Transport.PATHFINDER_RW = 0.5`.
    public static let pathfinderRW: TimeInterval = 0.5
    /// Timeout for `awaitPath` (seconds).
    ///
    /// Python: `Transport.PATH_REQUEST_TIMEOUT = 15`.
    public static let pathRequestTimeout: TimeInterval = 15
    /// Grace time before a path announcement is made, allows directly reachable
    /// peers to respond first.
    ///
    /// Python: `Transport.PATH_REQUEST_GRACE = 0.4`.
    public static let pathRequestGrace: TimeInterval = 0.4
    /// Extra grace time for roaming-mode interfaces.
    ///
    /// Python: `Transport.PATH_REQUEST_RG = 1.5`.
    public static let pathRequestRG: TimeInterval = 1.5
    /// Gate control timeout for path requests.
    ///
    /// Python: `Transport.PATH_REQUEST_GATE_TIMEOUT = 45`
    ///—RNS 1.5.0 cut it from 120, so a gated client clears in well under half the time.
    public static let pathRequestGateTimeout: TimeInterval = 45
    /// Minimum interval between automated path requests.
    ///
    /// Python: `Transport.PATH_REQUEST_MI = 20`.
    public static let pathRequestMinInterval: TimeInterval = 20
    /// Maximum local rebroadcasts of an announce.
    ///
    /// Python: `Transport.LOCAL_REBROADCASTS_MAX = 2`.
    public static let localRebroadcastsMax: Int = 2

    /// Stale threshold for known destinations already in use (7 days).
    ///
    /// Mirrors Python's `Transport.DESTINATION_TIMEOUT`.
    public static let destinationTimeout: TimeInterval = 60 * 60 * 24 * 7
    /// Linger time for never-used, pathless known destinations (6 minutes).
    ///
    /// Mirrors Python's `Transport.UNUSED_DESTINATION_LINGER`.
    public static let unusedDestinationLinger: TimeInterval = 6 * 60

    // Path responsiveness state values.
    public static let stateUnknown: UInt8 = 0x00
    public static let stateUnresponsive: UInt8 = 0x01
    public static let stateResponsive: UInt8 = 0x02

    public struct PathEntry: Equatable {
        public let destinationHash: Data

        /// The interface this route leads through—the value routing resolves.
        ///
        /// The reference stores the interface **object** here (`Transport.py:1639`) and
        /// transmits through it (`:1693`). Names are deliberately not unique: every connection
        /// accepted by one listening interface is named `"Client on <server name>"`
        /// (`TCPInterface.py:590`), so resolving a route by name sends traffic to whichever
        /// peer registered first, whatever the announce said (`bugs/027`).
        ///
        /// **Weak**, so a path can't keep a deregistered interface alive and a route through a
        /// vanished peer stops resolving rather than falling back to a same-named sibling.
        /// Persistence therefore can't store this; it stores `Interface.hash` and resolves it
        /// back through ``Transport/findInterface(fromHash:)`` on load, which is what the
        /// reference does (`:3387-3395`, `:326`).
        public weak var nextHopInterface: (any Interface)?

        /// The interface name captured when this node learned the path, for display only.
        ///
        /// Mirrors the reference's use of the stored object: it's stringified for the path
        /// listing (`Reticulum.py:1532`) and for nothing else. Never resolve a route from this
        ///—that's the preceding defect.
        public let nextHopInterfaceName: String
        public var hops: UInt8
        public var lastHeard: Date
        public let identityHash: Data
        /// Wall-clock time this path expires.
        ///
        /// Paths older than this are
        /// dropped by `sweepExpiredPaths()`. Matches Python's per-entry
        /// `expires` field (`PATHFINDER_E` = 7 days from announce time).
        public var expires: Date
        /// Transport ID of the next hop along this path.
        ///
        /// Learned from
        /// HEADER_2 announces; used to address forwarded outbound
        /// traffic. `nil` means "use this node's own transport ID".
        public var nextHopTransportID: Data?
        /// Unix timestamp (seconds) extracted from the announce's random hash.
        ///
        /// Used to determine if a newer announce should override a worse-hop path.
        /// Mirrors Python's timebase logic in Transport.announce_emitted().
        public var announceEmittedAt: TimeInterval = 0
        /// Full 32-byte SHA-256 hash of the announce packet that established this path.
        ///
        /// Used to retrieve the cached announce from disk when restoring the path table.
        /// Mirrors Python's `path_table[dst][IDX_PT_PACKET]` = packet_hash field.
        public var cachedAnnounceHash: Data?
        /// Recently heard 10-byte announce random blobs for this destination,
        /// newest last and capped at `Transport.maxRandomBlobs`.
        ///
        /// Mirrors Python's
        /// `path_table[dst][IDX_PT_RANDBLOBS]`. An announce whose random blob is
        /// already present is a replay and is rejected (prevents path forging /
        /// network loops via captured announces).
        public var randomBlobs: [Data] = []

        /// A routable path through `nextHopInterface`.
        ///
        /// The display name derives from it, so
        /// the two can never disagree.
        ///
        /// This is the initializer production code uses. There is no name-only production path:
        /// see the guard in `PathTableInterfaceIdentityTests`.
        public init(
            destinationHash: Data,
            nextHopInterface: any Interface,
            hops: UInt8,
            lastHeard: Date,
            identityHash: Data,
            expires: Date? = nil,
            nextHopTransportID: Data? = nil,
            announceEmittedAt: TimeInterval = 0,
            cachedAnnounceHash: Data? = nil,
            randomBlobs: [Data] = []
        ) {
            self.init(destinationHash: destinationHash,
                      nextHopInterfaceName: nextHopInterface.name,
                      hops: hops, lastHeard: lastHeard, identityHash: identityHash,
                      expires: expires, nextHopTransportID: nextHopTransportID,
                      announceEmittedAt: announceEmittedAt,
                      cachedAnnounceHash: cachedAnnounceHash, randomBlobs: randomBlobs)
            self.nextHopInterface = nextHopInterface
        }

        /// A path with a recorded interface *name* and no live interface—**deliberately not
        /// routable**, because routing resolves `nextHopInterface` and there is no name fallback
        /// (`bugs/027`).
        ///
        /// Two legitimate uses: a test that only exercises table bookkeeping (hops, expiry,
        /// responsiveness), and the moment before persistence resolves a stored interface hash
        /// back to an object. Production routing code must use the preceding initializer.
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

        /// A path with **no** interface and no name—the state a restored tunnel path is in
        /// until its endpoint reappears.
        ///
        /// Deliberately distinct from the preceding name-only initializer, which records a name that
        /// couldn't be resolved. This one records that there is nothing to resolve *yet*: the
        /// reference restores a tunnel path with `receiving_interface = None`
        /// (`Transport.py:396-400`) and `handle_tunnel` writes the live interface into every one
        /// of the tunnel's paths when the endpoint comes back (`:2440-2447`). Dropping such paths
        /// instead would make the tunnel table useless in exactly the case it exists for.
        ///
        /// Not routable until attached—same as there, and the same reason
        /// `PathTableInterfaceIdentityTests` forbids production code building a path from a name:
        /// an unroutable path must be visibly unroutable, not one wearing a name that resolves to
        /// somebody else's interface.
        public init(
            unattachedPathTo destinationHash: Data,
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
            self.nextHopInterfaceName = ""
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

        /// Hand-written because `nextHopInterface` is an existential, which the compiler can't synthesise.
        ///
        /// Interfaces compare by **identity**, which is the whole point of `bugs/027`: two
        /// clients of one server are equal by name and aren't the same route.
        public static func == (lhs: PathEntry, rhs: PathEntry) -> Bool {
            lhs.destinationHash == rhs.destinationHash
                && lhs.nextHopInterface === rhs.nextHopInterface
                && lhs.nextHopInterfaceName == rhs.nextHopInterfaceName
                && lhs.hops == rhs.hops
                && lhs.lastHeard == rhs.lastHeard
                && lhs.identityHash == rhs.identityHash
                && lhs.expires == rhs.expires
                && lhs.nextHopTransportID == rhs.nextHopTransportID
                && lhs.announceEmittedAt == rhs.announceEmittedAt
                && lhs.cachedAnnounceHash == rhs.cachedAnnounceHash
                && lhs.randomBlobs == rhs.randomBlobs
        }
    }

    /// Learned routing for an in-flight or active multi-hop link.
    ///
    /// The relay
    /// records which interface saw the LRR (initiator side) and which it
    /// forwarded the LRR onto (responder side); subsequent traffic for the
    /// link is forwarded through whichever interface didn't deliver it.
    public struct LinkRoute: Equatable {
        public let linkID: Data

        /// The two interfaces this relayed link runs between—the values routing resolves.
        ///
        /// The same requirement as `PathEntry.nextHopInterface`, in the link table
        /// (`bugs/027`). Storing names here is the identical defect: two clients accepted by
        /// one `TCPServerInterface` share the name `"Client on <server>"`, so a hairpin relay
        /// between them resolved both sides to whichever registered first—the source—and
        /// `forwardLinkTraffic`'s "which side didn't deliver it" test compared two equal
        /// strings and steered every packet back where it came from.
        ///
        /// Link *establishment* still worked, because the LINKREQUEST is routed through the
        /// path table; only the traffic afterwards was misrouted. That split is why the
        /// failure looked like a resource bug: the link came up, then the transfer stalled.
        ///
        /// Weak, for the same reason as the path table—a route must not keep a
        /// deregistered interface alive, and a vanished peer must stop resolving rather than
        /// falling back to a same-named sibling.
        public weak var initiatorSideInterface: (any Interface)?
        public weak var responderSideInterface: (any Interface)?

        /// Display only, never used to resolve a route.
        public let initiatorSideInterfaceName: String
        public let responderSideInterfaceName: String
        /// Original destination hash from the LINKREQUEST packet.
        ///
        /// Mirrors Python's `link_table[link_id][IDX_LT_DSTHASH]`.
        /// Used by `handleLinkRequestProof` to call `markDestinationUsed`
        /// after a relay node successfully forwards the LRPROOF.
        public let destinationHash: Data
        public var lastHeard: Date

        /// Whether a link-request proof for this route has passed signature validation.
        ///
        /// Mirrors Python's `link_table[link_id][IDX_LT_VALIDATED]`, which starts false and is
        /// set at the single point where the relay verifies a proof against the responder's
        /// recalled identity (`Transport.py:2661`). Nothing else may set it: the flag has to
        /// mean "a proof verified", not "a proof arrived", or anything counting validated
        /// routes ends up counting forgeries.
        public var validated: Bool = false

        /// Hand-written because the interface fields are existentials.
        ///
        /// They compare by
        /// **identity**—two clients of one server are equal by name and aren't the same
        /// route, which is the whole point.
        public static func == (lhs: LinkRoute, rhs: LinkRoute) -> Bool {
            lhs.linkID == rhs.linkID
                && lhs.initiatorSideInterface === rhs.initiatorSideInterface
                && lhs.responderSideInterface === rhs.responderSideInterface
                && lhs.initiatorSideInterfaceName == rhs.initiatorSideInterfaceName
                && lhs.responderSideInterfaceName == rhs.responderSideInterfaceName
                && lhs.destinationHash == rhs.destinationHash
                && lhs.lastHeard == rhs.lastHeard
                && lhs.validated == rhs.validated
        }
    }

    /// A tunnel entry: tracks an interface synthesized as a tunnel endpoint
    /// and the paths learned through it.
    ///
    /// Mirrors Python's `Transport.tunnels` table entries.
    public struct TunnelEntry {
        public let tunnelID: Data
        public weak var iface: (any Interface)?
        public var paths: [Data: PathEntry]
        public var expires: Date
    }

    /// Timeout for tunnel table entries.
    ///
    /// Matches Python `TUNNEL_TIMEOUT` (8 hours).
    public static let tunnelTimeout: TimeInterval = 60 * 60 * 8

    /// Per-destination entry in the announce rate table.
    ///
    /// Mirrors Python's rate_entry dict in `Transport.announce_rate_table`.
    struct AnnounceRateEntry {
        var last: TimeInterval       // timestamp of last accepted announce
        var violations: Int          // cumulative violation count
        var blockedUntil: TimeInterval  // if > now, this entry blocks announces
        var timestamps: [TimeInterval]  // recent announce timestamps (capped at MAX_RATE_TIMESTAMPS)
    }

    /// Snapshot of an interface's byte counts used for speed computation.
    ///
    /// Mirrors Python's `transport_traffic_counter` dict on each interface.
    struct SpeedSample {
        var rxBytes: Int
        var txBytes: Int
        /// Announce and path-request byte totals at the same instant.
        ///
        /// Python keeps all six
        /// in the one `transport_traffic_counter` dict (`Transport.py:645-648`) so every
        /// gauge divides by the same interval; splitting them into separate snapshots would
        /// let two rates describe two slightly different windows.
        var announceRxBytes: Int = 0
        var announceTxBytes: Int = 0
        var pathRequestRxBytes: Int = 0
        var pathRequestTxBytes: Int = 0
        var timestamp: TimeInterval
    }

    /// The four announce and path-request rates `rnstatus` reads as `arxs`, `atxs`, `prxs`
    /// and `ptxs`, in bits per second.
    public struct AnnounceSpeeds: Sendable, Equatable {
        public var announceRx: Double = 0
        public var announceTx: Double = 0
        public var pathRequestRx: Double = 0
        public var pathRequestTx: Double = 0
    }

    public private(set) var interfaces: [Interface] = []

    /// Lowest bitrate (bits/s) among online interfaces, or `nil` before the first successful
    /// computation. `Transport.lowest_interface_bitrate` (`Transport.py:294`), refreshed by
    /// ``prioritizeInterfaces()``.
    ///
    /// Recorded unclamped; ``mediumPathTimeout()`` applies ``minimumBitrate`` at the point of
    /// use, as Python does.
    public private(set) var lowestInterfaceBitrate: Int?
    public private(set) var registeredDestinations: [Data: Destination] = [:]
    public internal(set) var paths: [Data: PathEntry] = [:]
    public private(set) var knownIdentities: [Data: Identity] = [:] // by destination hash
    /// When each known identity was last announced.
    ///
    /// Used by `cleanKnownDestinations()`.
    /// Mirrors Python's `Identity.known_destinations[hash][0]` (last_announce field).
    var knownDestinationAnnouncedAt: [Data: Date] = [:]
    /// When each known identity was last used (recalled for outbound). nil = never used.
    ///
    /// Mirrors Python's `Identity.known_destinations[hash][4]` (last_use field, 0 = never).
    var knownDestinationLastUsed: [Data: Date] = [:]
    /// Full hash of the announce packet that taught each identity—`Identity.remember(packet.get_hash(),
    /// …)` (`Identity.py:577`), field 1 of the entry
    /// (`:107`).
    ///
    /// The reference writes this field and never reads it back: every access to a
    /// `known_destinations` entry indexes 0, 2, 3 or 4. It's carried anyway because the entry is
    /// a positional list—a missing field 1 shifts the public key into the slot the reader takes
    /// as app data.
    var knownDestinationPacketHash: [Data: Data] = [:]
    /// Destinations explicitly marked as retained—never swept by `cleanKnownDestinations`.
    ///
    /// Mirrors Python's last_use == -1 sentinel.
    var retainedDestinations: Set<Data> = []

    /// Most recent ratchet public key learned per destination, from
    /// announces. 32 bytes each.
    ///
    /// Used so outbound encryption can target
    /// the destination's freshest ratchet (forward secrecy).
    public private(set) var knownRatchets: [Data: Data] = [:]

    /// Wall-clock receive time per learned ratchet.
    ///
    /// Aged out per
    /// `ratchetExpiry`—matches Python's `Identity._remember_ratchet`
    /// / `Identity.get_ratchet` (which discard entries older than
    /// `RATCHET_EXPIRY`).
    public private(set) var knownRatchetTimes: [Data: Date] = [:]

    /// Expiry window for learned ratchets.
    ///
    /// Defaults to 30 days,
    /// matching `Identity.RATCHET_EXPIRY`.
    public var ratchetExpiry: TimeInterval = 60 * 60 * 24 * 30

    /// Optional directory where learned ratchets are persisted, one
    /// file per destination (`<dir>/<desthex>`), matching Python's
    /// `<storagepath>/ratchets/<hex>` layout.
    ///
    /// Set by `Reticulum.start`.
    public var ratchetsDirectory: URL?
    public private(set) var links: [Data: Link] = [:]               // by link id
    public private(set) var linkRoutes: [Data: LinkRoute] = [:]     // by link id
    /// Active tunnel entries keyed by tunnel ID (SHA-256 of pubkey+ifaceHash).
    ///
    /// Mirrors Python's `Transport.tunnels` dict.
    public var tunnels: [Data: TunnelEntry] = [:]
    public private(set) var isRunning: Bool = false

    /// Unix timestamp of the `start()` call.
    ///
    /// Used to compute transport uptime.
    /// Mirrors Python's `Transport.start_time`.
    /// `start()` is the only production writer; the setter is module-internal so the
    /// traffic sampler can be driven at fixed timestamps without running a jobs loop.
    public internal(set) var startTime: TimeInterval = 0

    /// Identity used to answer incoming link requests on registered
    /// destinations.
    ///
    /// The host sets this when it knows its local identity.
    public var ownerIdentity: Identity?

    /// Optional network identity, used for remote management and interface discovery.
    ///
    /// Once set, nothing can change it (mirrors Python's Transport.network_identity,
    /// which accepts a value only while still unset).
    public private(set) var networkIdentity: Identity?

    /// Returns whether this node holds a network identity.
    ///
    /// Mirrors Python's `Transport.has_network_identity()`.
    public var hasNetworkIdentity: Bool { networkIdentity != nil }

    /// Set the network identity.
    ///
    /// Only takes effect if not already set.
    /// Mirrors Python's `Transport.set_network_identity(identity)`.
    public func setNetworkIdentity(_ identity: Identity) {
        guard networkIdentity == nil else { return }
        networkIdentity = identity
    }

    /// When `true`, this node relays announces it receives to its other
    /// interfaces (a transport-enabled mesh node).
    ///
    /// When `false`, the node
    /// only originates and consumes announces (an edge node).
    public var transportEnabled: Bool = true

    /// When `true`, this node attaches as a *client* to an external shared
    /// instance (for example, an `rnsd` daemon over a `LocalInterface`), and that
    /// instance performs all packet filtering/routing on this node's behalf.
    ///
    /// In that
    /// case `filterAndRecord` must not re-filter (mirrors Python's
    /// `if Transport.owner.is_connected_to_shared_instance: return True`).
    /// Defaults to `false` for standalone / embedded transport nodes.
    public var isConnectedToSharedInstance: Bool = false

    /// Per-instance propagation limit; defaults to `pathfinderM`.
    public var propagationLimit: UInt8 = UInt8(Transport.pathfinderM)

    /// Whether a link-request proof arriving with an unexpected hop count may
    /// correct the path table (after its signature validates).
    ///
    /// RNS 1.4.1's
    /// headline path-convergence feature. Mirrors Python's
    /// `Transport.ALLOW_LINK_PATH_REBALANCE = True`.
    public static var allowLinkPathRebalance = true

    /// Per-session hop-count obfuscation delta.
    ///
    /// When non-zero, packets that
    /// originate locally (`hops == 0`)—this node's own traffic and traffic relayed for
    /// directly connected local clients—have their hop count rewritten to this
    /// value when injected into the wider network, hiding that they came from
    /// here. `0` disables the feature (the default). Set to a random value in
    /// 2...7 at startup when the `local_hops_delta` config option is enabled.
    /// Mirrors Python's `Transport.local_hops_delta`.
    public var localHopsDelta: UInt8 = 0

    /// 16-byte random instance id.
    ///
    /// Generated on first access, but can be
    /// overridden before `start()` to restore a persisted identity across
    /// restarts. Matches `Transport.identity.hash` semantics in Python.
    public var transportInstanceID: Data = {
        return SecureRandom.bytes(Constants.truncatedHashLength)
    }()

    /// Most-recent validated announce packet keyed by destination hash.
    ///
    /// Used to answer path requests on behalf of remote destinations this
    /// node has a path to.
    public private(set) var cachedAnnounces: [Data: Packet] = [:]

    /// Path responsiveness state per destination hash.
    ///
    /// Mirrors Python's `Transport.path_states` dict.
    private var pathStates: [Data: UInt8] = [:]
    private let pathStatesLock = NSLock()

    /// Reverse lookup table for multi-hop proof forwarding.
    ///
    /// Maps truncated packet hash (16 bytes) → (receiveInterface, outboundInterface).
    /// When Transport forwards a DATA packet, it stores the entry so the resulting
    /// proof can travel back to the originating interface.
    /// Mirrors Python's `Transport.reverse_table`.
    private var reverseTable: [Data: (receiveIface: any Interface, outboundIface: any Interface)] = [:]
    private let reverseTableLock = NSLock()

    /// Dedup keys for path requests already processed—`destinationHash
    /// + tag`. FIFO bounded.
    private var pathRequestTags: [Data] = []
    private var pathRequestTagSet: Set<Data> = []
    public var pathRequestCacheCap: Int = 4096

    /// A destination this node searches for on a peer's behalf, and the peers waiting on that
    /// search.
    ///
    /// Python's `discovery_path_requests` entry (`Transport.py:1879-1881`). `engaged` separates
    /// the two ways an entry comes into being: `true` means this node fanned a request out and
    /// is waiting for an answer, `false` means the entry only records requestors that arrived
    /// while some earlier search was already in flight.
    struct DiscoveryPathRequest {
        let destinationHash: Data
        var timeout: TimeInterval
        var requestingInterfaces: [any Interface]
        var engaged: Bool
    }

    /// Destinations with a search in progress, keyed to when the search started.
    ///
    /// `Transport.inflight_path_requests` (`Transport.py:188`). Registered before the search
    /// starts and cleared the moment this node answers the request, so its only job is to
    /// collapse requests that arrive *during* a search into that one search.
    private var inflightPathRequests: [Data: TimeInterval] = [:]

    /// The peers waiting on each in-progress search.
    ///
    /// `Transport.discovery_path_requests` (`Transport.py:192`). Read by the announce handler,
    /// which replays a matching announce to every recorded interface as a path response.
    private var discoveryPathRequests: [Data: DiscoveryPathRequest] = [:]

    /// Dedup keys for announces already seen—`destinationHash + randomHash`.
    ///
    /// Bounded to `announceCacheCap` entries (FIFO).
    private var announceCache: [Data] = []
    private var announceCacheSet: Set<Data> = []
    public var announceCacheCap: Int = 4096

    /// A forwarded announce pending a single retransmission.
    ///
    /// Mirrors Python's
    /// `Transport.announce_table` 9-tuple (`IDX_AT_*`). Swift forwards the first
    /// copy immediately, then retransmits once more (`PATHFINDER_R`) after the
    /// grace window unless neighbours carry the announce on.
    struct AnnounceTableEntry {
        var timestamp: TimeInterval           // IDX_AT_TIMESTAMP—when forwarded
        var retransmitTimeout: TimeInterval   // IDX_AT_RTRNS_TMO—next retry time
        var retries: Int                      // IDX_AT_RETRIES—transmissions so far
        var hops: Int                         // IDX_AT_HOPS—raw wire hops at receipt
        var packet: Packet                    // IDX_AT_PACKET—the received announce
        var localRebroadcasts: Int            // IDX_AT_LCL_RBRD—sibling rebroadcasts heard
        var blockRebroadcasts: Bool           // IDX_AT_BLCK_RBRD—emit as PATH_RESPONSE
        var attachedInterfaceName: String?    // IDX_AT_ATTCHD_IF—restrict retransmit to one iface
        var receivingInterfaceName: String    // iface the announce arrived on (never echoed back)
        var receivingInterfaceMode: InterfaceMode  // for the announce-propagation filter on retry
        // `announces_to_internal` of the receiving interface, captured alongside
        // its mode so the retry pass filters identically to the first forward.
        var receivingInterfaceAnnouncesToInternal: Bool?
    }
    /// Pending announce retransmissions keyed by destination hash.
    ///
    /// Guarded by `lock`.
    private var announceTable: [Data: AnnounceTableEntry] = [:]

    /// Per-interface announce and path-request frequency tracker.
    /// Mirrors Python's Interface.ia_freq_deque and so on
    private var ifaceFreqTrackers: [ObjectIdentifier: InterfaceFreqTracker] = [:]
    /// Guards the `ifaceFreqTrackers` dictionary (not the trackers themselves—each
    /// `InterfaceFreqTracker` is internally synchronized).
    ///
    /// Held alone; a
    /// holder snapshots the tracker reference and releases before calling into it.
    private let trackersLock = NSLock()

    /// Per-interface ingress burst control state.
    /// Mirrors Python's per-interface ic_burst_active, held_announces, and so on
    private var ingressStates: [ObjectIdentifier: IngressControlState] = [:]
    /// Guards `ingressStates`.
    ///
    /// A leaf lock: `processHeldAnnounces` re-enters
    /// `handleIncoming` (which takes `lock`), so a holder MUST snapshot/select
    /// under this lock, release it, then make the reentrant call—never held
    /// across a callout, and never acquires `lock` while held.
    private let ingressLock = NSLock()

    /// Root directory for the on-disk packet cache (announce sub-cache).
    ///
    /// Mirrors Python's `RNS.Reticulum.cachepath`.
    /// Set by `Reticulum.start()`.
    public var cacheDirectory: URL?

    /// Blackholed identities: identity hash → BlackholeEntry.
    ///
    /// Mirrors Python's `Transport.blackholed_identities` dict.
    public var blackholedIdentities: [Data: BlackholeEntry] = [:]
    /// Guards `blackholedIdentities`.
    ///
    /// Leaf lock—held alone, never across a
    /// callout, never acquires `lock` while held (when both a paths read and a
    /// blackhole read are needed, `lock` is taken and released first).
    let blackholeLock = NSLock()

    /// Guards the pure-metrics bookkeeping that's touched from inbound/outbound
    /// threads and the jobs timer with no relation to routing decisions:
    /// `trafficRxBytes`, `trafficTxBytes`, the packet PHY caches, the per-interface
    /// speed sample/current maps, the aggregate `speedRx`/`speedTx`, and the
    /// announce rate table.
    ///
    /// Leaf lock: never held across a callout, and no holder
    /// acquires `lock`. If both are ever needed, `lock` is the outer lock.
    private let metricsLock = NSLock()

    /// Cumulative bytes received across all interfaces (inbound).
    ///
    /// Mirrors Python's `Transport.traffic_rxb`.
    public private(set) var trafficRxBytes: Int = 0
    /// Cumulative bytes transmitted across all interfaces (outbound).
    ///
    /// Mirrors Python's `Transport.traffic_txb`.
    public private(set) var trafficTxBytes: Int = 0

    /// Per-destination announce rate tracking.
    ///
    /// Mirrors Python's `Transport.announce_rate_table`.
    private var announceRateTable: [Data: AnnounceRateEntry] = [:]
    /// Maximum announce timestamps kept per destination.
    ///
    /// Mirrors Python's `Transport.MAX_RATE_TIMESTAMPS = 16`.
    public static let maxRateTimestamps: Int = 16
    /// Grace wait before announcing connectivity readiness (seconds).
    ///
    /// Python: `Transport.READY_WAIT = 60`.
    public static let readyWait: TimeInterval = 60
    /// Reverse path table entry lifetime (seconds).
    ///
    /// Python: `Transport.REVERSE_TIMEOUT = 8*60`.
    public static let reverseTimeout: TimeInterval = 8 * 60
    /// Timeout for tunnel-sourced path entries.
    ///
    /// Python: `Transport.TUNNEL_PATH_TIMEOUT = 60*60*8`.
    public static let tunnelPathTimeout: TimeInterval = 60 * 60 * 8
    /// Maximum random blobs kept in memory.
    ///
    /// Python: `Transport.MAX_RANDOM_BLOBS = 64`.
    public static let maxRandomBlobs: Int = 64
    /// Number of random blobs persisted to disk.
    ///
    /// Python: `Transport.PERSIST_RANDOM_BLOBS = 32`.
    public static let persistRandomBlobs: Int = 32

    /// Per-interface last-sampled byte counts and timestamp for speed computation.
    private var ifaceSpeedSamples: [ObjectIdentifier: SpeedSample] = [:]
    /// Per-interface current RX speed (bits/sec).
    ///
    /// Mirrors Python `Interface.current_rx_speed`.
    private var ifaceCurrentRxSpeed: [ObjectIdentifier: Double] = [:]
    /// Per-interface current TX speed (bits/sec).
    ///
    /// Mirrors Python `Interface.current_tx_speed`.
    private var ifaceCurrentTxSpeed: [ObjectIdentifier: Double] = [:]

    /// Per-interface announce and path-request rates, filled by ``sampleInterfaceSpeeds(now:)``.
    /// Guarded by `metricsLock`, like the two tables above.
    private var ifaceAnnounceSpeeds: [ObjectIdentifier: AnnounceSpeeds] = [:]
    /// Aggregate RX speed across all interfaces (bits/sec).
    ///
    /// Mirrors Python `Transport.speed_rx`.
    public private(set) var speedRx: Double = 0
    /// Aggregate TX speed across all interfaces (bits/sec).
    ///
    /// Mirrors Python `Transport.speed_tx`.
    public private(set) var speedTx: Double = 0

    // MARK: - Transport-level announce and path-request aggregates
    //
    // Python derives all fourteen in the same pass of `count_traffic_loop` that produces
    // `speedRx`/`speedTx` (`Transport.py:645-671`), which is why they live beside those two
    // and are updated in ``sampleInterfaceSpeeds(now:)`` rather than at each recording site.
    //
    // The byte totals accumulate (`+=`) and the speeds and frequencies are reassigned every
    // pass. Mixing the two up is invisible on a busy node and obvious on an idle one: an
    // accumulating speed keeps climbing after the traffic stops.

    /// Cumulative announce bytes received.
    ///
    /// Mirrors Python `Transport.announce_rxb`.
    public private(set) var announceRxBytes: Int = 0
    /// Cumulative announce bytes transmitted.
    ///
    /// Mirrors Python `Transport.announce_txb`.
    public private(set) var announceTxBytes: Int = 0
    /// Aggregate announce RX speed (bits/sec).
    ///
    /// Python `Transport.announce_speed_rx`.
    public private(set) var announceSpeedRx: Double = 0
    /// Aggregate announce TX speed (bits/sec).
    ///
    /// Python `Transport.announce_speed_tx`.
    public private(set) var announceSpeedTx: Double = 0
    /// Summed incoming announce frequency (Hz).
    ///
    /// Python `Transport.announce_freq_rx`.
    public private(set) var announceFreqRx: Double = 0
    /// Summed outgoing announce frequency (Hz).
    ///
    /// Python `Transport.announce_freq_tx`.
    public private(set) var announceFreqTx: Double = 0
    /// Cumulative path-request bytes received.
    ///
    /// Mirrors Python `Transport.pr_rxb`.
    public private(set) var prRxBytes: Int = 0
    /// Cumulative path-request bytes transmitted.
    ///
    /// Mirrors Python `Transport.pr_txb`.
    public private(set) var prTxBytes: Int = 0
    /// Aggregate path-request RX speed (bits/sec).
    ///
    /// Python `Transport.pr_speed_rx`.
    public private(set) var prSpeedRx: Double = 0
    /// Aggregate path-request TX speed (bits/sec).
    ///
    /// Python `Transport.pr_speed_tx`.
    public private(set) var prSpeedTx: Double = 0
    /// Summed incoming path-request frequency (Hz).
    ///
    /// Python `Transport.pr_freq_rx`.
    public private(set) var prFreqRx: Double = 0
    /// Summed outgoing path-request frequency (Hz).
    ///
    /// Python `Transport.pr_freq_tx`.
    public private(set) var prFreqTx: Double = 0

    /// Packets admitted inbound.
    ///
    /// Mirrors Python `Transport.rx_packets` (`Transport.py:1798`).
    public private(set) var rxPackets: Int = 0
    /// Packets handed to an interface.
    ///
    /// Mirrors Python `Transport.tx_packets`
    /// (`Transport.py:1329`).
    public private(set) var txPackets: Int = 0
    /// Inbound packets per second over the last sampling interval.
    ///
    /// Python `Transport.rx_pps`.
    public private(set) var rxPPS: Int = 0
    /// Outbound packets per second over the last sampling interval.
    ///
    /// Python `Transport.tx_pps`.
    public private(set) var txPPS: Int = 0

    /// Timestamp of the last packets-per-second sample, or nil before the first one.
    ///
    /// Python keeps this as the loop-local `cts`, initially unset so the first interval is
    /// measured from `Transport.start_time` (`Transport.py:649-650`).
    private var lastPPSSampleTime: TimeInterval? = nil
    private var lastSampledRxPackets: Int = 0
    private var lastSampledTxPackets: Int = 0

    // MARK: - Packet PHY stats cache
    // Mirrors Python's Transport.local_client_rssi_cache / snr_cache / q_cache.
    // Capped at LOCAL_CLIENT_CACHE_MAXSIZE = 512 entries.
    public static let localClientCacheMaxSize: Int = 512
    private var packetRssiCache: [(hash: Data, rssi: Float)] = []
    private var packetSnrCache:  [(hash: Data, snr: Float)] = []
    private var packetQCache:    [(hash: Data, quality: Float)] = []

    // MARK: - Interface discovery integration
    // Mirrors Python's Transport.interface_announcer / discovery_handler / blackhole_updater.

    /// Active interface-discovery listener.
    ///
    /// Created by `discoverInterfaces(storagePath:...)`.
    /// Mirrors Python `Transport.discovery_handler`.
    public var discoveryHandler: InterfaceDiscovery?

    /// Active interface-discovery announcer, the publish side.
    ///
    /// Created by
    /// `enableDiscovery(stampGenerator:)`. Mirrors Python `Transport.interface_announcer`.
    public var interfaceAnnouncer: InterfaceAnnouncer?

    /// The `AnnounceHandler` registered with this transport for interface discovery.
    ///
    /// Kept so `stopDiscoverInterfaces()` can deregister it.
    public var discoveryAnnounceHandler: InterfaceAnnounceHandler?

    /// Active blackhole-list updater.
    ///
    /// Created by `enableBlackholeUpdater()`.
    /// Mirrors Python `Transport.blackhole_updater`.
    public var blackholeUpdater: BlackholeUpdater?

    // MARK: - Transport identity
    // The transport's own Identity, used for SINGLE management/probe destinations
    // and as the transport instance ID on the wire. Mirrors Python's
    // `Transport.identity`. For a non-transport node (unless
    // `static_transport_identity` is set) this is a fresh ephemeral identity
    // generated at startup—see `internalIdentity` for the persistent one.
    public var transportIdentity: Identity?

    // The persistent on-disk transport identity. Equals `transportIdentity`
    // except when an ephemeral transport identity is in use, in which case this
    // retains the stable identity (used for example, to derive the RPC auth key so it
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

    /// Fires when a path request lands on a locally registered
    /// destination.
    ///
    /// The host should respond by emitting a fresh signed
    /// announce for that destination on the supplied interface (Transport
    /// doesn't own destination identities, so it can't sign on its own).
    public var onPathRequested: ((Data, any Interface) -> Void)?

    /// Externally registered announce handlers (mirrors Python's
    /// `Transport.announce_handlers`).
    ///
    /// Use `register(announceHandler:)`.
    private var announceHandlers: [any AnnounceHandler] = []
    private let announceHandlerLock = NSLock()

    /// Outstanding packet receipts.
    ///
    /// Bounded to `maxReceipts`, swept by the
    /// jobs loop every second. Matches Python's `Transport.receipts`.
    private var receipts: [PacketReceipt] = []
    private let receiptsLock = NSLock()

    /// Per-interface announce queues.
    ///
    /// Keyed by interface name.
    private var announceQueues: [String: AnnounceQueue] = [:]
    private let queueLock = NSLock()

    /// Packet hashlist for replay/loop prevention.
    ///
    /// Two-generation rolling
    /// set—mirrors Python's `packet_hashlist` / `packet_hashlist_prev`.
    private var packetHashlist: Set<Data> = []
    private var packetHashlistPrev: Set<Data> = []
    private let hashlistLock = NSLock()
    /// Rotate the current hashlist into the previous slot when it reaches
    /// this size.
    ///
    /// Half of Python's 1M default.
    public var hashlistMaxSize: Int = 500_000

    let lock = NSLock()

    // Background jobs timer—nil until `start()`.
    private var jobsTimer: DispatchSourceTimer?
    /// Last time the jobs loop invoked `cleanKnownDestinations`.
    ///
    /// Used to amortise the sweep at `knownDestinationsCleanInterval` cadence.
    private var lastKnownDestinationsClean: Date = .distantPast

    public init() {}

    // MARK: - Announce handlers

    /// Register a handler that's called whenever a matching announce arrives.
    ///
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
    ///
    /// Mirrors Python's `Transport.has_path(destination_hash)`.
    public func hasPath(to destinationHash: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return paths[destinationHash] != nil
    }

    /// Hop count to `destinationHash`, or nil when no path exists.
    ///
    /// Mirrors Python's `Transport.hops_to(destination_hash)`.
    public func hopsTo(_ destinationHash: Data) -> UInt8? {
        lock.lock(); defer { lock.unlock() }
        return paths[destinationHash]?.hops
    }

    /// The next-hop destination hash (transport ID) for a known path, or nil.
    ///
    /// Mirrors Python's `Transport.next_hop(destination_hash)`.
    public func nextHop(to destinationHash: Data) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return paths[destinationHash]?.nextHopTransportID
    }

    /// The interface name the next hop is reachable on, or nil if unknown.
    ///
    /// Mirrors Python's `Transport.next_hop_interface(destination_hash)`.
    public func nextHopInterfaceName(for destinationHash: Data) -> String? {
        lock.lock(); defer { lock.unlock() }
        return paths[destinationHash]?.nextHopInterfaceName
    }

    /// The live `Interface` object for the next hop, or nil.
    ///
    /// Reads the stored object rather than re-resolving a name, matching the reference
    /// (`Transport.py:1639`). Nil once that interface is gone—a route through a vanished peer
    /// must stop resolving, not fall back to a same-named sibling (`bugs/027`).
    public func nextHopInterface(for destinationHash: Data) -> (any Interface)? {
        lock.lock(); defer { lock.unlock() }
        return paths[destinationHash]?.nextHopInterface
    }

    /// The registered interface whose `Interface.hash` matches, or nil.
    ///
    /// Mirrors Python's `Transport.find_interface_from_hash` (`Transport.py:2580-2585`), used to
    /// resolve a persisted path entry back to a live interface on load.
    public func findInterface(fromHash hash: Data) -> (any Interface)? {
        lock.lock(); defer { lock.unlock() }
        return interfaces.first { $0.hash == hash }
    }

    /// The `Interface.hash` of every registered interface.
    ///
    /// Mirrors Python's `Transport.interface_hashes()` (`Transport.py:2577`).
    func interfaceHashes() -> Set<Data> {
        lock.lock(); defer { lock.unlock() }
        return Set(interfaces.map { $0.hash })
    }

    /// Gravity of the interface the current path for `destinationHash` was heard
    /// on, or `nil` when there is no path or the interface is no longer
    /// registered.
    ///
    /// Python reads `Transport.path_table[dst][IDX_PT_RVCD_IF].gravity` off a
    /// stored interface object, so it keeps answering after the interface is
    /// detached. Swift stores the interface *name* in the path entry and
    /// re-resolves it here, which matches Python for every registered interface
    /// and diverges once the interface is gone: Python compares against the dead
    /// interface's gravity, Swift returns `nil` and the caller declines the
    /// takeover. That's the fail-closed direction (a path is never pulled onto
    /// another interface on the strength of a stale gravity reading), and it
    /// follows the same resolve-by-name convention as `nextHopInterface(for:)`.
    ///
    /// **Caller must already hold `lock`.** Python's `announce_gravity == None
    /// or current_gravity == None → should_add = False` maps onto this
    /// returning `nil`.
    private func currentPathGravityLocked(_ destinationHash: Data) -> Int? {
        guard let path = paths[destinationHash] else { return nil }
        return path.nextHopInterface?.gravity
    }

    // MARK: - Interface management

    /// Bring an interface offline.
    ///
    /// The interface stays registered but no longer
    /// forwards packets. Mirrors Python `Reticulum.halt_interface()`.
    public func halt(interfaceName: String) {
        lock.lock()
        let iface = interfaces.first { $0.name == interfaceName }
        lock.unlock()
        iface?.stop()
    }

    /// Bring a previously halted interface back online.
    ///
    /// Mirrors Python `Reticulum.resume_interface()`.
    public func resume(interfaceName: String) {
        lock.lock()
        let iface = interfaces.first { $0.name == interfaceName }
        lock.unlock()
        try? iface?.start()
    }

    /// Drop all paths that route through `transportHash`.
    ///
    /// Returns count of dropped paths.
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
    ///
    /// Mirrors Python `Transport.drop_announce_queues()`.
    /// Sort registered interfaces by bitrate (descending) so that higher-bandwidth
    /// interfaces are preferred for outbound traffic.
    /// Mirrors Python's `Transport.prioritize_interfaces()`.
    public func prioritizeInterfaces() {
        lock.lock()
        // Python sorts with `list.sort`, which is stable, so interfaces sharing a bitrate keep
        // registration order. Swift's `sort(by:)` isn't stable and this now runs on every jobs
        // pass, so the index is folded into the comparator: without it, same-bitrate interfaces
        // would be reshuffled every five seconds and announce emission order with them.
        interfaces = interfaces.enumerated()
            .sorted { l, r in
                l.element.bitrate == r.element.bitrate
                    ? l.offset < r.offset
                    : l.element.bitrate > r.element.bitrate
            }
            .map(\.element)
        // `if interface.online and interface.bitrate` (`Transport.py:568`)—Python's `bitrate`
        // is falsy for both `None` and `0`, so an interface that hasn't reported one isn't a
        // candidate for "slowest".
        let candidates = interfaces.filter { $0.isOnline && $0.bitrate > 0 }.map(\.bitrate)
        // Python's `min()` over an empty generator raises and the `except` leaves the previous
        // value standing (`:569`). Mirrored: a node with nothing online has no paths to resolve
        // either, so clearing it would only make the utilities give up sooner on a dead network.
        if let lowest = candidates.min() { lowestInterfaceBitrate = lowest }
        lock.unlock()
    }

    /// A full round trip for one MTU on the slowest online interface, plus one hop's grace.
    /// `Transport.medium_path_timeout()` (`Transport.py:3205`), new in RNS 1.5.x.
    ///
    /// Returns `0`—not ``Constants/defaultPerHopTimeout``—while no bitrate is known. Every
    /// caller wraps this in `max(timeout, …)`, so zero contributes nothing rather than timing
    /// out immediately.
    public func mediumPathTimeout() -> TimeInterval {
        guard let lowest = lowestInterfaceBitrate else { return 0 }
        let bitrate = Double(max(lowest, Transport.minimumBitrate))
        return 2 * (Double(Constants.mtu) * 8 / bitrate) + Constants.defaultPerHopTimeout
    }

    // MARK: - Path request batching (`inflight_path_requests` / `discovery_path_requests`)

    /// How long this node waits for an answer to a search it started on a peer's behalf.
    ///
    /// `discovery_timeout = max(PATH_REQUEST_TIMEOUT, medium_path_timeout())`
    /// (`Transport.py:3556`). The fixed floor covers an ordinary network; the medium term
    /// stretches the wait to a real round trip when the slowest link is slow enough that 15
    /// seconds would expire before the answer could physically arrive.
    func discoveryPathRequestTimeout() -> TimeInterval {
        max(Transport.pathRequestTimeout, mediumPathTimeout())
    }

    /// Claim `destinationHash` as under search, and report whether the claim is new.
    ///
    /// `if not path_request_inflight: Transport.inflight_path_requests[destination_hash] =
    /// time.time()` (`Transport.py:1867-1868`). Registered eagerly—Python's own comment calls
    /// it "early registration to immediately batch duplicates"—so that a duplicate arriving
    /// while the search runs finds the marker rather than starting a second identical fan-out.
    @discardableResult
    func registerInflightPathRequest(_ destinationHash: Data,
                                     at now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if inflightPathRequests[destinationHash] != nil { return false }
        inflightPathRequests[destinationHash] = now
        return true
    }

    /// Release the search claim on `destinationHash`.
    ///
    /// Called from both places Python clears the table: `if answered:` at the tail of
    /// `path_request_handler` (`Transport.py:3595-3599`), and the arrival of a matching announce
    /// (`Transport.py:2478-2481`). Either way the search is over, so the next request for this
    /// destination must be free to start its own.
    func resolveInflightPathRequest(_ destinationHash: Data) {
        lock.lock(); defer { lock.unlock() }
        inflightPathRequests.removeValue(forKey: destinationHash)
    }

    func inflightPathRequestTimestamp(for destinationHash: Data) -> TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        return inflightPathRequests[destinationHash]
    }

    func discoveryPathRequest(for destinationHash: Data) -> DiscoveryPathRequest? {
        lock.lock(); defer { lock.unlock() }
        return discoveryPathRequests[destinationHash]
    }

    /// Record `interface` as waiting on the search already running for `destinationHash`.
    ///
    /// `Transport.py:1872-1882`. This creates the entry when none exists yet, because an
    /// earlier request may have started the search that set the in-flight marker, and that
    /// request's own entry has since timed out—the two tables have different lifetimes.
    func batchDiscoveryPathRequest(_ destinationHash: Data, on interface: any Interface) {
        lock.lock(); defer { lock.unlock() }
        if var entry = discoveryPathRequests[destinationHash] {
            // `if not packet.receiving_interface in ...["requesting_interfaces"]`
            // (`Transport.py:1874`). A peer that keeps asking must not multiply the replay it
            // eventually gets.
            guard !entry.requestingInterfaces.contains(where: { $0 === interface }) else { return }
            entry.requestingInterfaces.append(interface)
            discoveryPathRequests[destinationHash] = entry
        } else {
            discoveryPathRequests[destinationHash] = DiscoveryPathRequest(
                destinationHash: destinationHash,
                timeout: Date().timeIntervalSince1970 + discoveryPathRequestTimeout(),
                requestingInterfaces: [interface],
                engaged: false
            )
        }
    }

    /// Mark `destinationHash` as under active search on `interface`'s behalf, and report whether
    /// some earlier search already holds that claim.
    ///
    /// `Transport.py:3533-3572`. Returning `true` is Python's "There is already a waiting path
    /// request … on behalf of path request" branch: the caller logs and returns rather than
    /// fanning out a second time. Peers batched onto the entry before it became engaged keep
    /// their claim on the answer (`existing_requesting_interfaces`, `:3565-3571`).
    func engageDiscoveryPathRequest(_ destinationHash: Data, on interface: any Interface) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if discoveryPathRequests[destinationHash]?.engaged == true { return true }
        var requestors = discoveryPathRequests[destinationHash]?.requestingInterfaces ?? []
        if !requestors.contains(where: { $0 === interface }) { requestors.append(interface) }
        discoveryPathRequests[destinationHash] = DiscoveryPathRequest(
            destinationHash: destinationHash,
            timeout: Date().timeIntervalSince1970 + discoveryPathRequestTimeout(),
            requestingInterfaces: requestors,
            engaged: true
        )
        return false
    }

    /// Remove and return the waiting entry for `destinationHash`.
    ///
    /// `discovery_path_requests.pop(packet.destination_hash)` (`Transport.py:2436`)—pop, not
    /// read: the replay answers the entry, so a later announce for the same destination must
    /// not produce a second one.
    func takeDiscoveryPathRequest(_ destinationHash: Data) -> DiscoveryPathRequest? {
        lock.lock(); defer { lock.unlock() }
        return discoveryPathRequests.removeValue(forKey: destinationHash)
    }

    /// Expire both path request tables.
    ///
    /// `Transport.py:993-1011` collects the stale keys and `:1107-1120` removes them. The two
    /// tables age on different clocks—the in-flight marker on the fixed
    /// ``pathRequestGateTimeout``, each waiting entry on its own deadline—so on a slow network
    /// an entry outlives the marker that created it. A search that nothing ever answers would
    /// otherwise block every later request for that destination for as long as the process runs.
    func sweepPathRequestTables(now: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock(); defer { lock.unlock() }
        inflightPathRequests = inflightPathRequests.filter {
            now <= $0.value + Transport.pathRequestGateTimeout
        }
        discoveryPathRequests = discoveryPathRequests.filter { now <= $0.value.timeout }
    }

    public func dropAnnounceQueues() {
        lock.lock()
        announceQueues.removeAll()
        lock.unlock()
    }

    /// Extract the announce emission timestamp from a random blob (bytes 5..9, big-endian).
    ///
    /// Mirrors Python `Transport.timebase_from_random_blob(random_blob)`.
    public static func timebaseFromRandomBlob(_ blob: Data) -> TimeInterval {
        guard blob.count >= 10 else { return 0 }
        var ts: UInt64 = 0
        for i in 5..<10 { ts = (ts << 8) | UInt64(blob[i]) }
        return TimeInterval(ts)
    }

    /// Returns the maximum emission timestamp across multiple random blobs.
    ///
    /// Mirrors Python `Transport.timebase_from_random_blobs(random_blobs)`.
    public static func timebaseFromRandomBlobs(_ blobs: [Data]) -> TimeInterval {
        blobs.reduce(0) { max($0, timebaseFromRandomBlob($1)) }
    }

    /// Returns true if the interface is a local-client interface.
    ///
    /// Mirrors Python `Transport.from_local_client(packet)`—in Swift, callers supply the interface directly.
    public func fromLocalClient(interface iface: any Interface) -> Bool {
        isLocalClientInterface(iface)
    }

    /// Returns true if the interface is one that serves a locally connected
    /// shared-instance client—the SERVER side.
    ///
    /// Mirrors Python
    /// `Transport.is_local_client_interface(interface)`, which is true only for a
    /// per-client connection whose `parent_interface.is_local_shared_instance`.
    /// In Swift the per-client sockets are collapsed into a single
    /// `LocalClientServingInterface` (for example, `PosixTCPServer` on the shared-instance
    /// port), so that protocol conformance is exactly the "local client" marker.
    ///
    /// NOTE: this is the opposite end from `LocalInterface`. A `LocalInterface` is
    /// *this* node's connection *to* a shared instance (the client side) and is
    /// therefore NOT a local-client interface—see `interfaceToSharedInstance`.
    public func isLocalClientInterface(_ interface: any Interface) -> Bool {
        `interface` is any LocalClientServingInterface
    }

    /// Returns true if the interface is this node's own connection *to* a shared
    /// instance (the client side).
    ///
    /// Mirrors Python
    /// `Transport.interface_to_shared_instance(interface)` (true when the interface
    /// has `is_connected_to_shared_instance`). In Swift that's `LocalInterface`.
    public func interfaceToSharedInstance(_ interface: any Interface) -> Bool {
        `interface` is LocalInterface
    }

    /// Interfaces serving one or more locally connected shared-instance
    /// clients, excluding `excluded` (typically the interface the triggering
    /// packet arrived on).
    ///
    /// Mirrors a non-empty Python `Transport.local_client_interfaces`.
    private func localClientServingInterfaces(excluding excluded: (any Interface)?) -> [any Interface] {
        interfaces.filter { iface in
            guard let serving = iface as? any LocalClientServingInterface, serving.clientCount > 0 else { return false }
            return iface !== excluded
        }
    }

    /// Whether the local hop-count obfuscation delta should be applied when
    /// transmitting `packet` out over `interface`.
    ///
    /// True only for this node's own freshly
    /// originated packets (`hops == 0`) that are addressed to real (single/link)
    /// destinations and leave over a non-local, non-shared-instance interface,
    /// while the feature is enabled and this node isn't behind a shared instance.
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

    /// Return a copy of `packet` with its hop count rewritten to `hops`.
    ///
    /// When
    /// `transportInsert` is true, also promote it to a HEADER_2 transport packet
    /// carrying this instance's transport id (used when obfuscating a locally
    /// originated HEADER_1 announce as it's injected into transport).
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
    /// onward.
    ///
    /// Normally the received hop count + 1, but obfuscated to
    /// `localHopsDelta` when the packet came from a directly connected local
    /// client and isn't staying within the local-client domain (and the feature
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
    ///
    /// Mirrors Python `Transport.void_queues()`.
    public func voidQueues() {
        ingressLock.lock()
        for key in ingressStates.keys { ingressStates[key]?.heldAnnounces = [:] }
        ingressLock.unlock()
        receiptsLock.lock()
        receipts.removeAll()
        receiptsLock.unlock()
        reverseTableLock.lock()
        reverseTable.removeAll()
        reverseTableLock.unlock()
    }

    /// Tear down all active and pending links, then stop all interfaces.
    ///
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

    /// Interface statistics snapshot.
    ///
    /// Mirrors the structure returned by
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
        /// Current RX throughput in bits/sec.
        ///
        /// Mirrors Python `Interface.current_rx_speed`.
        public let currentRxSpeed: Double
        /// Current TX throughput in bits/sec.
        ///
        /// Mirrors Python `Interface.current_tx_speed`.
        public let currentTxSpeed: Double
    }

    /// Aggregate transport-level traffic statistics.
    ///
    /// Mirrors the top-level `rxb`/`txb`/`rxs`/`txs` fields in Python's `Reticulum.get_interface_stats()`.
    public struct TransportStats {
        public let trafficRxBytes: Int
        public let trafficTxBytes: Int
        /// Aggregate RX speed (bits/sec).
        ///
        /// Mirrors Python `Transport.speed_rx`.
        public let speedRx: Double
        /// Aggregate TX speed (bits/sec).
        ///
        /// Mirrors Python `Transport.speed_tx`.
        public let speedTx: Double
        /// Announce byte, speed and frequency totals: Python's `arxb`, `atxb`, `arxs`,
        /// `atxs`, `arxf` and `atxf` (`Reticulum.py:1583-1588`).
        public let announceRxBytes: Int
        public let announceTxBytes: Int
        public let announceSpeedRx: Double
        public let announceSpeedTx: Double
        public let announceFreqRx: Double
        public let announceFreqTx: Double
        /// Path-request totals: `prxb`, `ptxb`, `prxs`, `ptxs`, `prxf`, `ptxf`.
        public let prRxBytes: Int
        public let prTxBytes: Int
        public let prSpeedRx: Double
        public let prSpeedTx: Double
        public let prFreqRx: Double
        public let prFreqTx: Double
        /// Packets per second over the last sampling interval: `rxpps` and `txpps`.
        public let rxPPS: Int
        public let txPPS: Int
    }

    /// Returns aggregate transport-level traffic statistics.
    public func getTransportStats() -> TransportStats {
        metricsLock.lock(); defer { metricsLock.unlock() }
        return TransportStats(
            trafficRxBytes: trafficRxBytes,
            trafficTxBytes: trafficTxBytes,
            speedRx: speedRx,
            speedTx: speedTx,
            announceRxBytes: announceRxBytes,
            announceTxBytes: announceTxBytes,
            announceSpeedRx: announceSpeedRx,
            announceSpeedTx: announceSpeedTx,
            announceFreqRx: announceFreqRx,
            announceFreqTx: announceFreqTx,
            prRxBytes: prRxBytes,
            prTxBytes: prTxBytes,
            prSpeedRx: prSpeedRx,
            prSpeedTx: prSpeedTx,
            prFreqRx: prFreqRx,
            prFreqTx: prFreqTx,
            rxPPS: rxPPS,
            txPPS: txPPS
        )
    }

    /// Returns statistics for all registered interfaces.
    ///
    /// Mirrors Python's `Reticulum.get_interface_stats()`.
    public func getInterfaceStats() -> [InterfaceStats] {
        lock.lock()
        let snapshot = interfaces
        lock.unlock()
        trackersLock.lock()
        let trackers = ifaceFreqTrackers
        trackersLock.unlock()
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

    /// Check whether an announce from `destinationHash` on `interface` warrants blocking
    /// by the per-destination rate limiter.
    ///
    /// Updates the rate table as a side effect.
    /// Returns `false` (not blocked) when `interface.announceRateTarget == nil`.
    /// Mirrors Python's rate_blocked logic in `Transport.inbound` announce handling.
    public func isAnnounceRateBlocked(destinationHash: Data,
                                       interface: any Interface,
                                       now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let target = interface.announceRateTarget else { return false }
        metricsLock.lock(); defer { metricsLock.unlock() }

        guard var entry = announceRateTable[destinationHash] else {
            // First announce—seed the entry, never blocked.
            announceRateTable[destinationHash] = AnnounceRateEntry(
                last: now, violations: 0, blockedUntil: 0, timestamps: [now]
            )
            return false
        }
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
        metricsLock.lock(); defer { metricsLock.unlock() }
        return announceRateTable[destinationHash]?.timestamps.count ?? 0
    }

    /// Snapshot of a rate table entry for external consumption.
    ///
    /// Mirrors the dict fields returned by Python's `Reticulum.get_rate_table()`.
    public struct RateTableEntry {
        public var destinationHash: Data
        public var last: TimeInterval
        public var rateViolations: Int
        public var blockedUntil: TimeInterval
        public var timestamps: [TimeInterval]
    }

    /// Returns a snapshot of the current announce rate table.
    ///
    /// Mirrors Python's `Reticulum.get_rate_table()`.
    public func getRateTable() -> [RateTableEntry] {
        metricsLock.lock(); defer { metricsLock.unlock() }
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
        metricsLock.lock(); defer { metricsLock.unlock() }
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

    /// Checks whether inbound announces on `interface` warrant holding for burst flooding.
    ///
    /// Updates internal burst-active state as a side effect.
    /// Returns `false` when `interface.ingressControl == false`.
    ///
    /// Mirrors Python's `Interface.should_ingress_limit()`.
    public func shouldIngressLimit(on interface: any Interface,
                                   now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard interface.ingressControl else { return false }
        let key = ObjectIdentifier(interface)
        // Lock order: ingressLock > trackersLock > tracker's own lock. The
        // ingressLock covers the read-modify-write on `state` throughout.
        ingressLock.lock(); defer { ingressLock.unlock() }
        guard var state = ingressStates[key],
              let tracker = tracker(for: interface) else { return false }

        let age = now - interface.createdAt.timeIntervalSince1970
        let threshold = age < interface.interfaceState.icNewTime
            ? interface.interfaceState.icBurstFreqNew
            : interface.interfaceState.icBurstFreq
        let freq = tracker.incomingAnnounceFrequency(now: now)

        if state.burstActive {
            // Deactivate when frequency drops below threshold AND hold period has elapsed.
            //
            // The deactivating call still returns `true`: in Python the
            // `return True` sits *outside* the deactivation branch, so the call
            // that clears the flag is itself still limited and only the next one
            // passes. Returning false here would let one extra announce through
            // a burst that's only just subsiding.
            //
            // The sample-count gate is `IC_DEQUE_MIN_SAMPLE` (2), not
            // `IC_BURST_MIN_SAMPLES` (6)—that's RNS 1.4.1 commit 48388756,
            // which fixed the burst flag deadlocking on indefinitely: with a 6
            // sample requirement against a deque that a subsiding burst never
            // refills, the flag could only ever clear if *new* announces arrived,
            // which is precisely what it was suppressing.
            //
            // RNS 1.5.1 added the second window, `ic_burst_sustained` (`Interface.py:194`).
            // With only `burstActivated`, a flood that ran for minutes cleared its own flag
            // fifteen seconds after it *started*—the timer measured the leading edge of the
            // event, so the longer the flood, the less of it was actually suppressed.
            // Refreshing `burstSustained` on every above-threshold look moves the window onto
            // the trailing edge: the burst now expires fifteen seconds after the flood stops.
            if freq < threshold
                && now > state.burstActivated + interface.interfaceState.icBurstHold
                && now > state.burstSustained + interface.interfaceState.icBurstHold {
                if tracker.incomingAnnounceSampleCount >= InterfaceFreqTracker.minSamples {
                    state.burstActive = false
                    ingressStates[key] = state
                }
            } else if freq >= threshold {
                // `>=`, where activation below uses `>`. The asymmetry is deliberate upstream:
                // a stream sitting exactly on the threshold isn't enough to *start* a burst
                // but is enough to keep one alive.
                state.burstSustained = now
                ingressStates[key] = state
            }
            return true
        } else {
            if freq > threshold {
                state.burstActive = true
                state.burstActivated = now
                state.burstSustained = now
                state.heldRelease = now + interface.interfaceState.icBurstPenalty
                ingressStates[key] = state
                return true
            }
            return false
        }
    }

    /// Checks whether inbound path requests on `interface` warrant suppression
    /// due to a path-request burst.
    ///
    /// Mirrors Python's `Interface.should_ingress_limit_pr()`.
    public func shouldIngressLimitPR(on interface: any Interface,
                                     now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard interface.ingressControl else { return false }
        let key = ObjectIdentifier(interface)
        ingressLock.lock(); defer { ingressLock.unlock() }
        guard var state = ingressStates[key],
              let tracker = tracker(for: interface) else { return false }

        let age = now - interface.createdAt.timeIntervalSince1970
        let threshold = age < interface.interfaceState.icNewTime
            ? interface.interfaceState.icPrBurstFreqNew
            : interface.interfaceState.icPrBurstFreq
        let freq = tracker.incomingPathRequestFrequency(now: now)

        if state.prBurstActive {
            // As in `shouldIngressLimit`, the deactivating call itself still
            // returns `true`—Python's `return True` is outside this branch.
            //
            // RNS 1.5.1 gave path-request bursts the same trailing-edge hold window as
            // announce bursts (`ic_pr_burst_sustained`) and, on top of it, a cooldown counter
            // (`Interface.py:216-224`). Even once both windows have elapsed and the frequency
            // has fallen, three further quiet evaluations must follow. Unlike the windows the
            // cooldown counts *looks*, not seconds, and any single busy evaluation refills it,
            // so it demands an unbroken run of quiet rather than merely a quiet instant.
            //
            // Note there is no sample-count gate on this side; the announce branch above has
            // one and this never has.
            if freq < threshold
                && now > state.prBurstActivated + interface.interfaceState.icBurstHold
                && now > state.prBurstSustained + interface.interfaceState.icBurstHold {
                if state.prBurstCooldown <= 0 {
                    state.prBurstActive = false
                } else {
                    state.prBurstCooldown -= 1
                }
                ingressStates[key] = state
            } else {
                // The refill is unconditional; only the sustained stamp checks the threshold.
                state.prBurstCooldown = IngressControlState.icPrBurstCooldown
                if freq >= threshold { state.prBurstSustained = now }
                ingressStates[key] = state
            }
            return true
        } else {
            if freq > threshold {
                state.prBurstActive = true
                state.prBurstActivated = now
                state.prBurstSustained = now
                state.prBurstCooldown = IngressControlState.icPrBurstCooldown
                ingressStates[key] = state
                return true
            }
            return false
        }
    }

    /// Checks whether outbound path requests on `interface` warrant suppression
    /// due to outgoing frequency exceeding `ecPrFreq`.
    ///
    /// Mirrors Python's
    /// `Interface.should_egress_limit_pr()`.
    public func shouldEgressLimitPR(on interface: any Interface,
                                    now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard interface.egressControl else { return false }
        guard let tracker = tracker(for: interface) else { return false }
        // `preemptive: true` (`Interface.py:243`) counts the request this call is about to
        // authorise, so a stream sitting exactly on the threshold is stopped rather than
        // allowed to cross it.
        let freq = tracker.outgoingPathRequestFrequency(preemptive: true, now: now)
        if freq > interface.ecPrFreq {
            // The floor is `EC_BURST_MIN_SAMPLES` (`Interface.py:246`), which RNS 1.5.1 renamed
            // from `IC_BURST_MIN_SAMPLES` and dropped from 6 to 2. It happens to equal the
            // 2-sample minimum that makes a frequency computable at all, but remains a separate
            // knob—see `IngressControlState.ecBurstMinSamples`.
            return tracker.outgoingPathRequestSampleCount >= IngressControlState.ecBurstMinSamples
        }
        return false
    }

    /// Hold `packet` on `interface` for deferred replay when burst ends.
    ///
    /// Newer packets for the same destination overwrite older ones.
    /// Capped at `interface.interfaceState.icMaxHeldAnnounces`.
    ///
    /// Mirrors Python's `Interface.hold_announce(packet)`.
    public func holdAnnounce(_ packet: Packet, destinationHash: Data, on interface: any Interface) {
        // Don't hold announces that are already at (or one below) the maximum
        // propagation distance—replaying them later would push them past the
        // hop limit, so they'd drop anyway. Python (RNS 1.3.8):
        //   if announce_packet.hops >= RNS.Transport.PATHFINDER_M-1: return
        guard Int(packet.hops) < Transport.pathfinderM - 1 else { return }
        let key = ObjectIdentifier(interface)
        ingressLock.lock(); defer { ingressLock.unlock() }
        guard var state = ingressStates[key] else { return }
        if state.heldAnnounces[destinationHash] != nil {
            // Overwrite existing held announce for same destination (most recent wins).
            state.heldAnnounces[destinationHash] = packet
        } else if state.heldAnnounces.count < interface.interfaceState.icMaxHeldAnnounces {
            state.heldAnnounces[destinationHash] = packet
        }
        ingressStates[key] = state
    }

    /// Release the lowest-hop held announce on `interface` if the release timer has elapsed
    /// and the interface is no longer in burst mode.
    ///
    /// Returns the released packet or nil.
    ///
    /// Mirrors Python's `Interface.process_held_announces()`.
    @discardableResult
    public func processHeldAnnounces(for interface: any Interface,
                                     now: TimeInterval = Date().timeIntervalSince1970) -> Packet? {
        let key = ObjectIdentifier(interface)
        // Do the whole select-and-remove under ingressLock, then RELEASE it before
        // re-injecting: handleIncoming re-enters the transport (and takes `lock` /
        // ingressLock again), so holding ingressLock across it would deadlock.
        var released: Packet? = nil
        ingressLock.lock()
        if var state = ingressStates[key],
           !state.heldAnnounces.isEmpty, now > state.heldRelease {
            // Check current frequency is below threshold before releasing.
            let age = now - interface.createdAt.timeIntervalSince1970
            let threshold = age < interface.interfaceState.icNewTime
                ? interface.interfaceState.icBurstFreqNew
                : interface.interfaceState.icBurstFreq
            let freq = tracker(for: interface)?.incomingAnnounceFrequency(now: now) ?? 0
            if freq < threshold,
               // Select lowest-hop held announce (mirrors Python's min-hops selection).
               let (bestHash, bestPacket) = state.heldAnnounces
                   .min(by: { $0.value.hops < $1.value.hops }) {
                state.heldAnnounces.removeValue(forKey: bestHash)
                state.heldRelease = now + interface.interfaceState.icHeldReleaseInterval
                ingressStates[key] = state
                released = bestPacket
            }
        }
        ingressLock.unlock()

        // Re-inject the packet into the transport pipeline (outside ingressLock).
        if let released {
            handleIncoming(packet: released, from: interface)
        }
        return released
    }

    /// Number of held announces on `interface`.
    ///
    /// Test helper.
    public func heldAnnounceCount(for interface: any Interface) -> Int {
        ingressLock.lock(); defer { ingressLock.unlock() }
        return ingressStates[ObjectIdentifier(interface)]?.heldAnnounces.count ?? 0
    }

    /// Returns the ingress control state for `interface`, or nil if not yet created.
    ///
    /// Mirrors Python's per-interface `ic_burst_active` and so on fields.
    public func ingressState(for interface: any Interface) -> IngressControlState? {
        ingressLock.lock(); defer { ingressLock.unlock() }
        return ingressStates[ObjectIdentifier(interface)]
    }

    /// Returns the number of queued announces for `interface`, or nil if no queue exists.
    ///
    /// Mirrors Python's `len(interface.announce_queue)`.
    public func announceQueueCount(for interface: any Interface) -> Int? {
        queueLock.lock(); defer { queueLock.unlock() }
        return announceQueues[interface.name]?.count
    }

    /// Force-set the `heldRelease` timestamp for `interface`.
    ///
    /// Test helper.
    public func forceHeldRelease(for interface: any Interface, to timestamp: TimeInterval) {
        let key = ObjectIdentifier(interface)
        ingressLock.lock(); defer { ingressLock.unlock() }
        guard var state = ingressStates[key] else { return }
        state.heldRelease = timestamp
        ingressStates[key] = state
    }

    // MARK: - Per-interface speed tracking (mirrors Python count_traffic_loop)

    /// Sample current byte counts for all interfaces and compute per-interface and
    /// aggregate RX/TX speeds (bits/sec).
    ///
    /// Call this from the jobs loop or a dedicated
    /// periodic job. Mirrors Python's `Transport.count_traffic_loop`.
    ///
    /// - Parameter now: Injection point for testing; defaults to `Date().timeIntervalSince1970`.
    public func sampleInterfaceSpeeds(now: TimeInterval = Date().timeIntervalSince1970) {
        // Snapshot the interface list under `lock`, then mutate all speed/traffic
        // metrics under `metricsLock` (never both held at once).
        lock.lock()
        let snapshot = interfaces
        lock.unlock()
        // Read the announce and path-request totals before taking `metricsLock`: `counts()`
        // acquires `trackersLock` and then the tracker's own lock, and the sampling pass is
        // the only place that would otherwise nest the three.
        // The four frequency queries prune their deque, so they mutate the tracker and take
        // the same lock `counts()` does. Read them here, in the same pass, so the aggregate
        // frequencies describe the same instant as the byte counters beside them.
        let counters = snapshot.map { iface -> (any Interface, InterfaceFreqTracker.Counts?, (Double, Double, Double, Double)) in
            let tr = tracker(for: iface)
            let freqs = (tr?.incomingAnnounceFrequency(now: now) ?? 0,
                         tr?.outgoingAnnounceFrequency(now: now) ?? 0,
                         tr?.incomingPathRequestFrequency(now: now) ?? 0,
                         tr?.outgoingPathRequestFrequency(now: now) ?? 0)
            return (iface, tr?.counts(), freqs)
        }
        metricsLock.lock(); defer { metricsLock.unlock() }
        var totalRxSpeed: Double = 0
        var totalTxSpeed: Double = 0
        // Python's `arxs`/`atxs`/`prxs`/`ptxs` and `iafreq`/`oafreq`/`ipfreq`/`opfreq`
        // accumulators, reset at the top of every pass (`Transport.py:598-600`).
        var totalAnnounceRxSpeed: Double = 0, totalAnnounceTxSpeed: Double = 0
        var totalPrRxSpeed: Double = 0, totalPrTxSpeed: Double = 0
        var totalAnnounceRxFreq: Double = 0, totalAnnounceTxFreq: Double = 0
        var totalPrRxFreq: Double = 0, totalPrTxFreq: Double = 0
        for (iface, counts, freqs) in counters {
            totalAnnounceRxFreq += freqs.0
            totalAnnounceTxFreq += freqs.1
            totalPrRxFreq += freqs.2
            totalPrTxFreq += freqs.3
            let key = ObjectIdentifier(iface)
            let currentRx = iface.rxBytes
            let currentTx = iface.txBytes
            let sample = SpeedSample(rxBytes: currentRx, txBytes: currentTx,
                                     announceRxBytes: counts?.announceRxBytes ?? 0,
                                     announceTxBytes: counts?.announceTxBytes ?? 0,
                                     pathRequestRxBytes: counts?.pathRequestRxBytes ?? 0,
                                     pathRequestTxBytes: counts?.pathRequestTxBytes ?? 0,
                                     timestamp: now)
            if let prior = ifaceSpeedSamples[key] {
                let tsDiff = now - prior.timestamp
                guard tsDiff > 0 else { continue }
                let rxDiff = currentRx - prior.rxBytes
                let txDiff = currentTx - prior.txBytes
                let rxSpeed = Double(rxDiff) * 8.0 / tsDiff   // bits/sec
                let txSpeed = Double(txDiff) * 8.0 / tsDiff
                ifaceCurrentRxSpeed[key] = rxSpeed
                ifaceCurrentTxSpeed[key] = txSpeed
                // Same interval, same bytes*8/seconds—Python computes all six together
                // (`Transport.py:618-623`). Assigned every pass, including a quiet one, so
                // an idle interface reads zero instead of holding its last rate.
                func rate(_ current: Int, _ previous: Int) -> Double {
                    Double(current - previous) * 8.0 / tsDiff
                }
                let speeds = AnnounceSpeeds(
                    announceRx: rate(sample.announceRxBytes, prior.announceRxBytes),
                    announceTx: rate(sample.announceTxBytes, prior.announceTxBytes),
                    pathRequestRx: rate(sample.pathRequestRxBytes, prior.pathRequestRxBytes),
                    pathRequestTx: rate(sample.pathRequestTxBytes, prior.pathRequestTxBytes))
                ifaceAnnounceSpeeds[key] = speeds
                totalRxSpeed += rxSpeed
                totalTxSpeed += txSpeed
                totalAnnounceRxSpeed += speeds.announceRx
                totalAnnounceTxSpeed += speeds.announceTx
                totalPrRxSpeed += speeds.pathRequestRx
                totalPrTxSpeed += speeds.pathRequestTx
                // The byte totals take the same interval diffs the speeds are derived from,
                // so `arxb` and `arxs` can never describe different traffic.
                announceRxBytes += sample.announceRxBytes - prior.announceRxBytes
                announceTxBytes += sample.announceTxBytes - prior.announceTxBytes
                prRxBytes += sample.pathRequestRxBytes - prior.pathRequestRxBytes
                prTxBytes += sample.pathRequestTxBytes - prior.pathRequestTxBytes
                // Accumulate transport-level TX total from interface diffs.
                // Mirrors Python: Transport.traffic_txb += txDiff (count_traffic_loop).
                // handleIncoming already counts RX per packet, so this adds only TX.
                if txDiff > 0 { trafficTxBytes += txDiff }
            }
            ifaceSpeedSamples[key] = sample
        }
        speedRx = totalRxSpeed
        speedTx = totalTxSpeed
        announceSpeedRx = totalAnnounceRxSpeed
        announceSpeedTx = totalAnnounceTxSpeed
        prSpeedRx = totalPrRxSpeed
        prSpeedTx = totalPrTxSpeed
        announceFreqRx = totalAnnounceRxFreq
        announceFreqTx = totalAnnounceTxFreq
        prFreqRx = totalPrRxFreq
        prFreqTx = totalPrTxFreq
        samplePacketRates(now: now)
    }

    /// Recompute ``rxPPS``/``txPPS`` from the packet counters.
    ///
    /// Mirrors `Transport.py:647-658`. The first interval runs from `start_time`, every later
    /// one from the previous sample, so the reading always describes the interval just ended
    /// rather than the node's lifetime average.
    ///
    /// Callers must hold `metricsLock`.
    private func samplePacketRates(now: TimeInterval) {
        // `if not Transport.start_time: rpps = 0; tpps = 0`—with no start time there is no
        // interval to divide by, and no baseline is recorded either.
        guard startTime > 0 else { rxPPS = 0; txPPS = 0; return }
        let since = lastPPSSampleTime ?? startTime
        let elapsed = now - since
        guard elapsed > 0 else { return }
        // Python's `int(round(x))` is round-half-to-even; Swift's `rounded()` rounds half
        // away from zero, which disagrees on every exact .5 a two-second sample can produce.
        rxPPS = Int((Double(rxPackets - lastSampledRxPackets) / elapsed).rounded(.toNearestOrEven))
        txPPS = Int((Double(txPackets - lastSampledTxPackets) / elapsed).rounded(.toNearestOrEven))
        lastPPSSampleTime = now
        lastSampledRxPackets = rxPackets
        lastSampledTxPackets = txPackets
    }

    /// Current RX speed for `interface` in bits/sec.
    ///
    /// Mirrors Python's `Interface.current_rx_speed`.
    public func currentRxSpeed(for interface: any Interface) -> Double {
        metricsLock.lock(); defer { metricsLock.unlock() }
        return ifaceCurrentRxSpeed[ObjectIdentifier(interface)] ?? 0
    }

    /// Current TX speed for `interface` in bits/sec.
    ///
    /// Mirrors Python's `Interface.current_tx_speed`.
    public func currentTxSpeed(for interface: any Interface) -> Double {
        metricsLock.lock(); defer { metricsLock.unlock() }
        return ifaceCurrentTxSpeed[ObjectIdentifier(interface)] ?? 0
    }

    /// Current announce RX rate for `interface` in bits/sec.
    ///
    /// Mirrors Python's `Interface.current_arx_speed`.
    public func currentAnnounceRxSpeed(for interface: any Interface) -> Double {
        announceSpeeds(for: interface).announceRx
    }

    /// Current announce TX rate for `interface` in bits/sec.
    ///
    /// Mirrors Python's `Interface.current_atx_speed`.
    public func currentAnnounceTxSpeed(for interface: any Interface) -> Double {
        announceSpeeds(for: interface).announceTx
    }

    /// Current path-request RX rate for `interface` in bits/sec.
    ///
    /// Mirrors Python's `Interface.current_prx_speed`.
    public func currentPathRequestRxSpeed(for interface: any Interface) -> Double {
        announceSpeeds(for: interface).pathRequestRx
    }

    /// Current path-request TX rate for `interface` in bits/sec.
    ///
    /// Mirrors Python's `Interface.current_ptx_speed`.
    public func currentPathRequestTxSpeed(for interface: any Interface) -> Double {
        announceSpeeds(for: interface).pathRequestTx
    }

    /// All four rates under one lock acquisition, so a caller reporting them together
    /// describes a single sampling interval.
    public func announceSpeeds(for interface: any Interface) -> AnnounceSpeeds {
        metricsLock.lock(); defer { metricsLock.unlock() }
        return ifaceAnnounceSpeeds[ObjectIdentifier(interface)] ?? AnnounceSpeeds()
    }

    // MARK: - Interface frequency notifications (mirrors Python Interface.received_announce / sent_announce and so on)

    /// Notify that `interface` received an announce.
    ///
    /// Mirrors Python's `interface.received_announce()` call in `Transport.inbound`.
    public func notifyIncomingAnnounce(on interface: any Interface, size: Int = 0) {
        tracker(for: interface)?.recordIncomingAnnounce(size: size)
    }

    /// Overload accepting an explicit timestamp—used by tests and internally.
    public func notifyIncomingAnnounce(on interface: any Interface, at t: TimeInterval,
                                       size: Int = 0) {
        tracker(for: interface)?.recordIncomingAnnounce(size: size, at: t)
    }

    /// Notify that `interface` sent an announce.
    ///
    /// Mirrors Python's `interface.sent_announce()` call in `Transport.outbound`.
    public func notifyOutgoingAnnounce(on interface: any Interface, size: Int = 0) {
        tracker(for: interface)?.recordOutgoingAnnounce(size: size)
    }

    public func notifyOutgoingAnnounce(on interface: any Interface, at t: TimeInterval,
                                       size: Int = 0) {
        tracker(for: interface)?.recordOutgoingAnnounce(size: size, at: t)
    }

    /// Notify that `interface` received a path request.
    ///
    /// Mirrors Python's `interface.received_path_request()` call.
    public func notifyIncomingPathRequest(on interface: any Interface, size: Int = 0) {
        tracker(for: interface)?.recordIncomingPathRequest(size: size)
    }

    public func notifyIncomingPathRequest(on interface: any Interface, at t: TimeInterval,
                                          size: Int = 0) {
        tracker(for: interface)?.recordIncomingPathRequest(size: size, at: t)
    }

    /// Notify that `interface` sent a path request.
    ///
    /// Mirrors Python's `interface.sent_path_request()` call.
    public func notifyOutgoingPathRequest(on interface: any Interface, size: Int = 0) {
        tracker(for: interface)?.recordOutgoingPathRequest(size: size)
    }

    public func notifyOutgoingPathRequest(on interface: any Interface, at t: TimeInterval,
                                          size: Int = 0) {
        tracker(for: interface)?.recordOutgoingPathRequest(size: size, at: t)
    }

    /// Mirrors Python's `interface.protocol_violation()` (`Transport.py:1646` and eight
    /// further call sites).
    ///
    /// Python's helper also logs at `LOG_DEBUG` and returns `None` so
    /// the caller can `return interface.protocol_violation(...)`; here the callers already
    /// return on their own, so this only counts.
    public func notifyProtocolViolation(on interface: any Interface) {
        tracker(for: interface)?.recordProtocolViolation()
    }

    /// Mirrors Python's `interface.ifac_violation()` (`Transport.py:1715` and four others).
    public func notifyIfacViolation(on interface: any Interface) {
        tracker(for: interface)?.recordIfacViolation()
    }

    /// Mirrors Python's `interface.packet_filter_hit()` (`Transport.py:1795`).
    public func notifyPacketFilterHit(on interface: any Interface) {
        tracker(for: interface)?.recordPacketFilterHit()
    }

    /// The announce, path-request and violation counters for `interface`, or all zeroes
    /// when it is not registered.
    ///
    /// Read by `InterfaceStatsPayload`.
    public func interfaceCounts(for interface: any Interface) -> InterfaceFreqTracker.Counts {
        tracker(for: interface)?.counts()
            ?? InterfaceFreqTracker.Counts(announceRxBytes: 0, announceTxBytes: 0,
                                           announceRxCount: 0, announceTxCount: 0,
                                           pathRequestRxBytes: 0, pathRequestTxBytes: 0,
                                           pathRequestRxCount: 0, pathRequestTxCount: 0,
                                           protocolViolations: 0, ifacViolations: 0,
                                           packetFilterHits: 0)
    }

    /// Incoming announce frequency (Hz) for the given interface.
    public func incomingAnnounceFrequency(for interface: any Interface) -> Double {
        tracker(for: interface)?.incomingAnnounceFrequency() ?? 0
    }

    /// Outgoing announce frequency (Hz) for the given interface.
    public func outgoingAnnounceFrequency(for interface: any Interface) -> Double {
        tracker(for: interface)?.outgoingAnnounceFrequency() ?? 0
    }

    /// Incoming path-request frequency (Hz) for the given interface.
    public func incomingPathRequestFrequency(for interface: any Interface) -> Double {
        tracker(for: interface)?.incomingPathRequestFrequency() ?? 0
    }

    /// Outgoing path-request frequency (Hz) for the given interface.
    ///
    /// `preemptive` counts the request the caller is about to send; see
    /// ``InterfaceFreqTracker/outgoingPathRequestFrequency(preemptive:now:)``. It defaults to
    /// `false` so reporting paths (ifstats) keep quoting the frequency actually observed—only
    /// the egress limiter asks the forward-looking question.
    public func outgoingPathRequestFrequency(for interface: any Interface,
                                             preemptive: Bool = false,
                                             now: TimeInterval = Date().timeIntervalSince1970) -> Double {
        tracker(for: interface)?.outgoingPathRequestFrequency(preemptive: preemptive, now: now) ?? 0
    }

    /// Look up the frequency tracker for `interface` under `trackersLock`, then
    /// release the lock before the caller touches the (internally synchronized)
    /// tracker—so `trackersLock` is never held across a callout.
    private func tracker(for interface: any Interface) -> InterfaceFreqTracker? {
        trackersLock.lock(); defer { trackersLock.unlock() }
        return ifaceFreqTrackers[ObjectIdentifier(interface)]
    }

    // MARK: - Management utilities

    /// Returns a snapshot of the path table for display/export.
    ///
    /// Mirrors Python's `Reticulum.get_path_table(max_hops:)`.
    public struct PathTableEntry {
        public let destinationHash: Data
        /// Python's `path_table[dst][1]` (`received_from`), which is **never None**:
        /// Transport.py:1772-1796 stores `packet.transport_id` when the announce carried
        /// one and `packet.destination_hash` when it didn't. `rnpath -t` calls
        /// `prettyhexrep(path["via"])` unguarded, so a null here is a TypeError in the
        /// Python client, not an empty column—hence non-optional.
        public let via: Data
        public let hops: UInt8
        public let interfaceName: String
        public let lastHeard: Date
        public let expires: Date
    }

    public func getPathTable(maxHops: UInt8? = nil) -> [PathTableEntry] {
        lock.lock(); defer { lock.unlock() }
        // Python publishes `str(receiving_interface)`—the display name, "LocalInterface
        // [56156]"—where a path entry stores only the interface's short config name here.
        // Resolving at the producer means every consumer of the table (the RPC path_table,
        // the /path request handler, and rnpath running in-process) reports the same string
        // Python would.
        let displayNames = Dictionary(interfaces.map { ($0.name, $0.displayName) },
                                      uniquingKeysWith: { first, _ in first })
        return paths.values
            .filter { $0.hops <= (maxHops ?? .max) }
            .map { PathTableEntry(
                destinationHash: $0.destinationHash,
                // `nextHopTransportID` is nil exactly when the announce carried no
                // transport id, which is the case where Python falls back to the
                // destination's own hash.
                via: $0.nextHopTransportID ?? $0.destinationHash,
                hops: $0.hops,
                // Fall back to the stored short name when nothing holds that name—a
                // path restored from disk can outlive the interface that heard it.
                interfaceName: displayNames[$0.nextHopInterfaceName] ?? $0.nextHopInterfaceName,
                lastHeard: $0.lastHeard,
                expires: $0.expires
            )}
    }

    /// Returns the number of entries in the link table.
    ///
    /// Mirrors Python's `Transport.link_count()`, which is `len(Transport.link_table)`
    /// (`Transport.py:3211`). The link table holds one entry per link this node *relays*, so
    /// the count measures transit load. A link this node terminates never enters it—those live
    /// in `links`, and `activeLinks` reports them.
    ///
    /// This used to return `links.values.filter { $0.status == .active }.count`, which is a
    /// different quantity and, on a transport node carrying traffic for others, an unrelated
    /// one. `rnstatus` prints the value as "N entries in link table"
    /// (`rnstatus.py:711`), so a two-node setup that relayed nothing still claimed one entry.
    public func getLinkCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return linkRoutes.count
    }

    /// Returns the number of link-table entries whose link-request proof this node validated.
    ///
    /// The quantity Python's `Transport.active_link_count()` (`Transport.py:3215`) means to
    /// report. Its own expression doesn't:
    /// `sum(1 for e in (True for entry in Transport.link_table if entry[IDX_LT_VALIDATED]))`
    /// iterates a dict, so `entry` is a link ID and `entry[7]` is that ID's eighth byte rather
    /// than the validated flag. It reports roughly 255 of every 256 entries as active however
    /// many the relay verified, which makes reproducing it worse than useless—`rnstatus` shows
    /// the number to an operator, and a number that tracks nothing is worse than no number.
    ///
    /// `validated` is set at exactly one place, where `handleLinkRequestProof` checks the
    /// signature, so this counts verified proofs rather than arrived ones.
    public func getActiveLinkCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return linkRoutes.values.filter { $0.validated }.count
    }

    /// Returns all active links as an array.
    ///
    /// Mirrors Python's `Transport.active_links` list.
    public var activeLinks: [Link] {
        lock.lock(); defer { lock.unlock() }
        return links.values.filter { $0.status == .active }
    }

    // MARK: - Packet PHY stats cache

    /// Accept either hash width for a PHY-cache lookup.
    ///
    /// The caches are keyed by the *truncated* 16-byte packet hash, but Python keys its
    /// equivalents by the full 32-byte `packet.packet_hash` (Transport.py:1500/1507/1514)
    /// and a Python `rnprobe` therefore asks a Swift daemon over RPC with 32 bytes. Since
    /// the truncated hash is by definition the first 16 bytes of the full one, narrowing
    /// the key here makes both spellings resolve without changing what's stored.
    private static func phyCacheKey(_ packetHash: Data) -> Data {
        packetHash.count > Constants.truncatedHashLength
            ? packetHash.prefix(Constants.truncatedHashLength)
            : packetHash
    }

    /// Returns the cached RSSI for a packet hash, or nil if not in cache.
    ///
    /// Mirrors Python's `Reticulum.get_packet_rssi(packet_hash)`.
    public func getPacketRssi(packetHash: Data) -> Float? {
        let key = Transport.phyCacheKey(packetHash)
        metricsLock.lock(); defer { metricsLock.unlock() }
        return packetRssiCache.last(where: { $0.hash == key })?.rssi
    }

    /// Returns the cached SNR for a packet hash, or nil if not in cache.
    ///
    /// Mirrors Python's `Reticulum.get_packet_snr(packet_hash)`.
    public func getPacketSnr(packetHash: Data) -> Float? {
        let key = Transport.phyCacheKey(packetHash)
        metricsLock.lock(); defer { metricsLock.unlock() }
        return packetSnrCache.last(where: { $0.hash == key })?.snr
    }

    /// Returns the cached quality for a packet hash, or nil if not in cache.
    ///
    /// Mirrors Python's `Reticulum.get_packet_q(packet_hash)`.
    public func getPacketQ(packetHash: Data) -> Float? {
        let key = Transport.phyCacheKey(packetHash)
        metricsLock.lock(); defer { metricsLock.unlock() }
        return packetQCache.last(where: { $0.hash == key })?.quality
    }

    // MARK: - Path responsiveness

    /// Mark a known path as unresponsive.
    ///
    /// Returns true if the path exists.
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

    /// Mark a known path as responsive.
    ///
    /// Returns true if the path exists.
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
    ///
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
    ///
    /// Mirrors Python's `Transport.path_is_unresponsive`.
    public func pathIsUnresponsive(to destinationHash: Data) -> Bool {
        pathStatesLock.lock(); defer { pathStatesLock.unlock() }
        return pathStates[destinationHash] == Transport.stateUnresponsive
    }

    /// Block until a path to `destinationHash` exists, or the timeout
    /// expires.
    ///
    /// Sends a path request when no path exists.
    /// Mirrors Python's `Transport.await_path`.
    ///
    /// - Parameters:
    ///   - destinationHash: 16-byte destination hash to resolve.
    ///   - timeout: Seconds to wait before giving up. Defaults to `pathRequestTimeout`.
    ///   - onInterface: Optional interface to send the path request on.
    /// - Returns: `true` when a path turns up, `false` when the timeout expires.
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
    /// `destinationHash`, or nil when no path exists.
    ///
    /// Mirrors Python's `Transport.next_hop_interface_bitrate`.
    public func nextHopInterfaceBitrate(for destinationHash: Data) -> Int? {
        guard let iface = nextHopInterface(for: destinationHash) else { return nil }
        return iface.bitrate > 0 ? iface.bitrate : nil
    }

    /// Returns the per-bit transmission latency (seconds/bit) for the next-hop interface.
    ///
    /// Mirrors Python's `Transport.next_hop_per_bit_latency(destination_hash)`.
    public func nextHopPerBitLatency(for destinationHash: Data) -> Double? {
        guard let bitrate = nextHopInterfaceBitrate(for: destinationHash), bitrate > 0 else { return nil }
        return 1.0 / Double(bitrate)
    }

    /// Returns the per-byte transmission latency (seconds/byte) for the next-hop interface.
    ///
    /// Mirrors Python's `Transport.next_hop_per_byte_latency(destination_hash)`.
    public func nextHopPerByteLatency(for destinationHash: Data) -> Double? {
        guard let perBit = nextHopPerBitLatency(for: destinationHash) else { return nil }
        return perBit * 8
    }

    /// Returns the hardware MTU for the next-hop interface if the interface
    /// supports MTU auto-configuration or has a fixed MTU, otherwise nil.
    ///
    /// Mirrors Python's `Transport.next_hop_interface_hw_mtu`.
    public func nextHopInterfaceHwMtu(for destinationHash: Data) -> Int? {
        guard let iface = nextHopInterface(for: destinationHash) else { return nil }
        guard iface.autoconfigureMtu || iface.fixedMtu else { return nil }
        return iface.hwMtu
    }

    /// Returns the estimated first-hop timeout for a path to `destinationHash`.
    ///
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
    /// the receiving interface's bitrate.
    ///
    /// Returns 0 when interface is nil or bitrate is 0.
    /// Mirrors Python's `Transport.extra_link_proof_timeout`.
    public static func extraLinkProofTimeout(for interface: (any Interface)?) -> TimeInterval {
        guard let iface = interface, iface.bitrate > 0 else { return 0.0 }
        return (8.0 / Double(iface.bitrate)) * Double(Constants.mtu)
    }

    // MARK: - Identity recall

    /// Return the Identity associated with `destinationHash`, if a previous
    /// announce carried it.
    ///
    /// Mirrors Python's `Identity.recall`.
    public func recall(identity destinationHash: Data) -> Identity? {
        lock.lock(); defer { lock.unlock() }
        return knownIdentities[destinationHash]
    }

    /// Return the app data from the most recent announce for `destinationHash`,
    /// if any.
    ///
    /// Mirrors Python's `Identity.recall_app_data`.
    public func recallAppData(forDestination destinationHash: Data) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return knownIdentities[destinationHash]?.appData
    }

    /// Get the 10-byte ratchet ID of the known ratchet for a destination.
    ///
    /// Returns nil when no ratchet exists. Mirrors Python's `Identity.current_ratchet_id()`.
    public func currentRatchetID(forDestination destinationHash: Data) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let ratchetPub = knownRatchets[destinationHash] else { return nil }
        return Identity.ratchetID(forPublicKey: ratchetPub)
    }

    /// The 32-byte ratchet PUBLIC key known for a destination, or nil.
    ///
    /// Mirrors Python's `Identity.get_ratchet(destination_hash)`, which is what
    /// `Destination.encrypt` feeds to `identity.encrypt(plaintext, ratchet=…)`
    /// (Destination.py:594-600). Distinct from ``currentRatchetID(forDestination:)``,
    /// which returns the 10-byte *identifier* derived from this key and can't be used
    /// as an encryption target.
    public func currentRatchetKey(forDestination destinationHash: Data) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return knownRatchets[destinationHash]
    }

    // MARK: - Lifecycle

    public func register(interface: Interface) {
        // register()/deregister() run on network-callback threads (TCP-server
        // accept, I2P peer up/down) and—under stress—can target the SAME
        // interface concurrently. Everything that mutates Transport-owned state
        // OR the interface's Transport-owned callbacks happens under `lock` so
        // two register()s (or a register racing a deregister) can't interleave.
        // Without this, the `inboundHandler`/`rawInboundHandler` closure pointers
        // are torn by concurrent writes (an ARC refcount race that corrupts the
        // heap and surfaces as unrelated "Duplicate keys" dictionary traps), and
        // the per-interface bookkeeping dicts can end up with orphaned entries.
        //
        // `lock` is the outer lock; the per-interface leaf locks are acquired
        // nested inside it (global order: lock > ingressLock > trackersLock,
        // lock > metricsLock). No leaf-lock holder ever acquires `lock`, so this
        // introduces no cycle. `synthesizeTunnel` is the one callout—snapshot
        // its trigger under `lock`, then run it after releasing (act-outside).
        let key = ObjectIdentifier(interface)
        lock.lock()
        // Raw-bytes handler used by real interfaces—verifies IFAC, parses packet.
        interface.rawInboundHandler = { [weak self] rawBytes, sourceInterface in
            guard let self else { return }
            guard let verified = sourceInterface.unwrapIfac(rawBytes) else {
                // Python counts every one of these through `interface.ifac_violation()`
                // (`Transport.py:1715`, `:1749`, `:1773`, `:1777`, `:1784`). This port
                // decides all five inside `unwrapIfac`, so one call covers them.
                self.notifyIfacViolation(on: sourceInterface)
                return
            }
            // `if interface and len(raw) > interface.HW_MTU + (interface.ifac_size or 0):
            //      return interface.protocol_violation(...)` (`Transport.py:1789`, RNS 1.5.0).
            //
            // A frame past the medium's own hardware MTU can't have a legitimate origin
            // by a peer on that medium. This port bounded frame size only inside the HDLC
            // deframer, which leaves UDP, RNode/KISS, AutoInterface, Weave and the KISS-framed
            // I2P path with no inbound bound at all. Here—the one funnel every interface's
            // raw bytes pass through—covers all of them, which is the same reason Python
            // moved the check to `preprocess_inbound` rather than into each interface.
            //
            // Python compares against `HW_MTU`, which its base class leaves as `None`; the
            // resulting `None + int` would raise, and `inbound`'s blanket `except`
            // (`Transport.py:1683`) would turn that into a logged drop of every packet on such
            // an interface. Every shipped interface sets one, so that branch is unreachable
            // upstream—skipping the check when `hwMtu` is nil keeps the reachable behaviour
            // and declines to reproduce the unreachable bug.
            //
            // The comparison is against the *post-IFAC* bytes on both sides: Python runs
            // `handle_ifac` first (`:1766`) and still adds `ifac_size` back into the
            // allowance, so a frame that filled the medium before the tag was stripped is
            // still accepted.
            if let hwMtu = sourceInterface.hwMtu,
               verified.count > hwMtu + sourceInterface.ifacSize {
                self.notifyProtocolViolation(on: sourceInterface)
                return
            }
            guard let packet = try? Packet.unpack(verified) else {
                // `protocol_violation(f"Malformed packet ({len(raw)} bytes)")`
                // (`Transport.py:1794`).
                self.notifyProtocolViolation(on: sourceInterface)
                return
            }
            // `if len(raw) > RNS.Reticulum.MTU: return ... protocol_violation("Excessive
            // announce packet frame size ...")` (`Transport.py:1804`).
            //
            // Announces are the one packet type every transport node floods onward, so an
            // unbounded one is an amplification path rather than merely a large frame. The
            // ceiling is the protocol MTU, not the interface's—a legitimate announce fits in
            // 500 bytes on every medium, so a larger one is malformed no matter how wide the
            // link that carried it.
            if packet.packetType == .announce, verified.count > Constants.mtu {
                self.notifyProtocolViolation(on: sourceInterface)
                return
            }
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
        trackersLock.lock()
        ifaceFreqTrackers[key] = InterfaceFreqTracker()
        trackersLock.unlock()
        // Create ingress burst control state for this interface.
        ingressLock.lock()
        ingressStates[key] = IngressControlState()
        ingressLock.unlock()
        let wantsTunnel = interface.wantsTunnel
        lock.unlock()
        // A restored path or tunnel waiting for this interface can go in now.
        // Outside the lock: the installers take it themselves.
        drainPendingRestores()
        // Synthesize a tunnel for interfaces that request it (outside all locks).
        if wantsTunnel {
            synthesizeTunnel(interface)
        }
    }

    // MARK: - Deferred restore

    /// Entries read from `destination_table` that couldn't be installed yet because the
    /// interface they name wasn't registered at the time.
    ///
    /// Only the path table needs this. A tunnel path doesn't depend on an interface being
    /// present—the reference restores it with `receiving_interface = None`
    /// (`Transport.py:398-400`)—so `TunnelStore` resolves every entry on the spot.
    ///
    /// **This exists because of an ordering difference from the reference, not as an
    /// optimisation.** Python builds every configured interface in `__apply_config()` and only
    /// then calls `Transport.start()`, which restores the tables (`Reticulum.py:340,346`)—so
    /// by the time it resolves `find_interface_from_hash`, every interface exists. In this port
    /// `rnsd` itself synthesises the daemon's interfaces *after* `Reticulum.start()`,
    /// so the restore ran against an empty interface set and **dropped every entry, always**.
    /// The path table has never survived a restart in a real daemon, whatever its on-disk format
    /// (`bugs/041`).
    ///
    /// Holding the entries and installing them as their interfaces appear fixes that without
    /// making any caller responsible for an ordering. The alternative—moving the restore to
    /// after interface synthesis—would be a correction at whichever call site happened to be
    /// looked at, and there are three that register interfaces.
    ///
    /// Bounded: `sweepPendingRestores()` discards whatever is still pending after
    /// ``pendingRestoreWindow``, so this can't install a path minutes later when a discovered
    /// interface appears—which would be a real divergence, since the reference drops such an
    /// entry permanently.
    var pendingPathRestores: [PathStore.Entry] = []
    /// When the pending entries were read, so they can expire.
    var pendingRestoresReadAt: Date?

    /// How long a restored entry waits for its interface.
    ///
    /// Startup, plus slack for an interface
    /// whose construction is slow (a serial port opening, an I2P tunnel building).
    public static let pendingRestoreWindow: TimeInterval = 30

    /// Install any pending entries whose interface is now registered.
    func drainPendingRestores() {
        lock.lock()
        let paths = pendingPathRestores
        lock.unlock()
        guard !paths.isEmpty else { return }

        let installed = PathStore(entries: paths).install(into: self)
        guard !installed.isEmpty else { return }

        lock.lock()
        pendingPathRestores.removeAll { installed.contains($0.destinationHash) }
        lock.unlock()
    }

    /// Give up on entries whose interface never arrived, matching the reference's outcome for
    /// an interface that isn't there when the tables load (`Transport.py:334,348`).
    func sweepPendingRestores(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard let readAt = pendingRestoresReadAt,
              now.timeIntervalSince(readAt) > Transport.pendingRestoreWindow else { return }
        if !pendingPathRestores.isEmpty {
            Reticulum.log("Giving up on \(pendingPathRestores.count) restored path table "
                          + "entr(ies) whose interface never registered", level: .debug)
        }
        pendingPathRestores = []
        pendingRestoresReadAt = nil
    }

    /// Remove an interface from the transport.
    ///
    /// Cleans up all per-interface state.
    /// Mirrors Python `Transport.remove_interface()` added in e7a317f0.
    public func deregister(interface iface: any Interface) {
        // Held under `lock` for the whole body so it's atomic with respect to a
        // concurrent register() of the same interface (see register() for the
        // lock-hierarchy rationale). The per-interface leaf locks are acquired
        // nested inside `lock`.
        let key = ObjectIdentifier(iface)
        lock.lock()
        interfaces.removeAll { $0 === iface }
        trackersLock.lock()
        ifaceFreqTrackers.removeValue(forKey: key)
        trackersLock.unlock()
        ingressLock.lock()
        ingressStates.removeValue(forKey: key)
        ingressLock.unlock()
        metricsLock.lock()
        ifaceSpeedSamples.removeValue(forKey: key)
        ifaceCurrentRxSpeed.removeValue(forKey: key)
        ifaceCurrentTxSpeed.removeValue(forKey: key)
        ifaceAnnounceSpeeds.removeValue(forKey: key)
        metricsLock.unlock()
        lock.unlock()
    }

    /// Derive IFAC credentials from a network name and/or access key and attach
    /// them to `interface`.
    ///
    /// Mirrors Python `Reticulum._add_interface` IFAC setup.
    ///
    /// - Parameters:
    ///   - interface: The interface to configure.
    ///   - netname: Human-readable network name (for example, `"mynet"`).
    ///   - netkey:  Pre-shared access key string (for example, `"s3cr3t"`).
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
        // Python derives the IFAC identity from the key and signs `full_hash(key)` with it
        // (`Reticulum.py:972-973`). `rnstatus` prints the last bytes of that signature as the
        // segment's "Access" fingerprint, so an interface holding a key but no identity reports
        // no access code where a Python node on the same segment reports one—the stats payload
        // emits `ifac_signature` nil (`InterfaceStatsPayload.swift:98-107`). Derived, never
        // random: two nodes on one segment must produce the same signature.
        interface.ifacIdentity = try? Identity(privateKeyBytes: key)
    }

    public func register(destination: Destination) {
        lock.lock(); defer { lock.unlock() }
        registeredDestinations[destination.hash] = destination
    }

    /// Remove a previously registered destination.
    ///
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

    /// Bulk-load a path entry—used by `PathStore.apply` to rehydrate
    /// state from disk on stack startup.
    ///
    /// No validation here: the caller is
    /// expected to have produced these entries from a previous live state.
    public func restore(path: PathEntry, forDestination destinationHash: Data) {
        lock.lock(); defer { lock.unlock() }
        paths[destinationHash] = path
    }

    /// Bulk-load a tunnel entry—used by `TunnelStore.apply` to rehydrate `storage/tunnels` at
    /// start (`Transport.py:403`).
    public func restore(tunnel: TunnelEntry) {
        lock.lock(); defer { lock.unlock() }
        tunnels[tunnel.tunnelID] = tunnel
    }

    /// Directly insert a relayed-link route, so a test can drive a hairpin relay without
    /// standing up two peers and driving a full link handshake through them.
    public func restore(linkRoute: LinkRoute) {
        lock.lock(); defer { lock.unlock() }
        linkRoutes[linkRoute.linkID] = linkRoute
    }

    /// Directly insert an announce packet into the announce cache for testing.
    ///
    /// Mirrors the side-effect of processing a real announce packet.
    public func cacheAnnounce(_ packet: Packet, forDestination hash: Data) {
        lock.lock(); defer { lock.unlock() }
        cachedAnnounces[hash] = packet
    }

    /// Inject a synthetic path table entry for testing.
    ///
    /// Sets `nextHopTransportID` to `nextHop` so a test can drive requestor-ID suppression.
    public func injectPath(_ destinationHash: Data,
                           nextHop: Data,
                           receivedOn interface: any Interface,
                           hops: UInt8,
                           announcePacketHash: Data?) {
        let entry = PathEntry(
            destinationHash: destinationHash,
            nextHopInterface: interface,
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
    /// `ratchetExpiry`.
    ///
    /// Mirrors Python's `Identity._clean_ratchets`.
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

    /// Persist a learned ratchet to `<ratchetsDirectory>/<desthex>`.
    ///
    /// `umsgpack.packb({"ratchet": ratchet, "received": time.time()})`—`Identity.py:424,434`,
    /// read straight back with `umsgpack.unpackb` at `:493`. The raw key and a float timestamp:
    /// the reference gates on `len(ratchet_data["ratchet"]) == RATCHETSIZE//8` and does
    /// arithmetic on `received` (`:494`), so a hex string and an ISO-8601 date—which is what
    /// the port wrote—fail both.
    ///
    /// `bugs/029`'s fifth divergence, and the one that cost the most: this path carries matching
    /// directory *and* filenames on both sides, so it read as correct in a listing, and both
    /// implementations *delete* what they can't parse here (`Identity._clean_ratchets`,
    /// `:459-462,476`, and `loadKnownRatchets` below). Each side silently destroyed the other's
    /// forward-secrecy state on the first start after a switch.
    private func persistKnownRatchet(_ ratchet: Data, forDestination hash: Data, receivedAt: Date) {
        guard let dir = ratchetsDirectory else { return }
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        let payload = MsgPack.Value.map([
            (.string("ratchet"), .bytes(ratchet)),
            (.string("received"), .double(receivedAt.timeIntervalSince1970)),
        ])
        try? MsgPack.encode(payload).write(to: dir.appendingPathComponent(hash.hexString),
                                           options: .atomic)
    }

    /// Bulk-load all learned ratchets from `ratchetsDirectory`,
    /// dropping any whose `received` is older than `ratchetExpiry`.
    ///
    /// Mirrors `Identity.get_ratchet` (`:487-497`) for the read and `_clean_ratchets`
    /// (`:452-482`) for the removal of expired and corrupt files.
    public func loadKnownRatchets() {
        guard let dir = ratchetsDirectory,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return }
        let now = Date()
        lock.lock(); defer { lock.unlock() }
        for filename in entries {
            guard let destHash = Data(hex: filename) else { continue }
            let url = dir.appendingPathComponent(filename)
            guard let raw = try? Data(contentsOf: url),
                  case .map(let pairs)? = try? MsgPack.decode(raw)
            else {
                // "Corrupted ratchet data while reading …, removing file" (`Identity.py:459-462`,
                // unlinked at `:476`). This is also what retires the port's own JSON ratchets on
                // the first start after `bugs/029`: unlike `paths.json` and its siblings, these
                // sit at a name the reference *does* use, so leaving them in place would only
                // leave a file a Python daemon deletes anyway.
                try? FileManager.default.removeItem(at: url)
                continue
            }
            var fields: [String: MsgPack.Value] = [:]
            for (key, value) in pairs {
                if case .string(let name) = key { fields[name] = value }
            }
            guard case .bytes(let ratchet)? = fields["ratchet"],
                  ratchet.count == Constants.ratchetSize,
                  let receivedAt = fields["received"]?.asDouble
            else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            let received = Date(timeIntervalSince1970: receivedAt)
            if now.timeIntervalSince(received) > ratchetExpiry {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            knownRatchets[destHash] = ratchet
            knownRatchetTimes[destHash] = received
        }
    }

    /// Encrypt `plaintext` for `destinationHash` using the freshest
    /// ratchet known for that destination, falling back to the
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

    /// The entry's `last_use` slot, as the reference types it.
    ///
    /// Not one type: `remember` seeds it with the integer `0` (`Identity.py:107`), retention
    /// writes the integer `-1` (`:255`), and use writes `time.time()`, a float (`:246`). msgpack
    /// preserves that distinction—a fixint versus a float64—so writing everything as a double
    /// would produce a file the reference never would, even though its own reader is arithmetic
    /// and would not notice.
    private static func lastUseValue(retained: Bool, lastUsed: Date?) -> MsgPack.Value {
        if retained { return .int(-1) }
        guard let lastUsed else { return .uint(0) }
        return .double(lastUsed.timeIntervalSince1970)
    }

    /// Persist `knownIdentities` to `url` in the reference's format.
    ///
    /// `umsgpack.dump(Identity.known_destinations)` (`Identity.py:198`): a map keyed by the raw
    /// destination hash whose values are `[last_announce, packet_hash, public_key, app_data,
    /// last_use]` (`:107`). Positional—the reader indexes 0, 2, 3 and 4 directly (`:146-149`,
    /// `:314-324`)—so field 1 stays on the wire even though nothing reads it.
    ///
    /// Written atomically, as `Identity.py:196-200` does with an explicit temp file and
    /// `os.replace`. `Data.write(options: .atomic)` is that same write-then-rename, so a torn
    /// file isn't observable on either side.
    public func saveKnownDestinations(to url: URL) throws {
        lock.lock()
        let snapshot = knownIdentities
        let announcedAt = knownDestinationAnnouncedAt
        let lastUsed = knownDestinationLastUsed
        let retained = retainedDestinations
        let packetHashes = knownDestinationPacketHash
        lock.unlock()

        let pairs: [(MsgPack.Value, MsgPack.Value)] = snapshot.map { destHash, identity in
            let lastUse = Transport.lastUseValue(retained: retained.contains(destHash),
                                                 lastUsed: lastUsed[destHash])
            return (.bytes(destHash), .array([
                .double(announcedAt[destHash]?.timeIntervalSince1970
                        ?? Date().timeIntervalSince1970),
                .bytes(packetHashes[destHash] ?? Data()),
                .bytes(identity.publicKeyBytes),
                identity.appData.map(MsgPack.Value.bytes) ?? .nil,
                lastUse,
            ]))
        }
        try MsgPack.encode(.map(pairs)).write(to: url, options: .atomic)
    }

    /// Load previously persisted `knownIdentities` from `url`.
    ///
    /// Mirrors Python's `Identity.load_known_destinations()` (`Identity.py:216-240`).
    public func loadKnownDestinations(from url: URL) throws {
        guard case .map(let pairs) = try MsgPack.decode(Data(contentsOf: url)) else {
            throw MsgPack.Error.typeMismatch
        }
        lock.lock()
        defer { lock.unlock() }
        for (key, value) in pairs {
            // `if len(known_destination) == RNS.Reticulum.TRUNCATED_HASHLENGTH//8` (:225)—a key
            // that isn't a destination hash is skipped, and doesn't abort the load.
            guard case .bytes(let destHash) = key,
                  destHash.count == Constants.truncatedHashLength,
                  case .array(var fields) = value else { continue }
            // `[e[0], e[1], e[2], e[3], 0]` (:226-229)—an entry written by an older reference
            // has four fields and is backfilled with a zero `last_use`, not discarded.
            if fields.count == 4 { fields.append(.double(0)) }
            guard fields.count == 5,
                  case .bytes(let publicKey) = fields[2],
                  publicKey.count == Constants.keySize,
                  let identity = try? Identity(publicKeyBytes: publicKey) else { continue }

            if case .bytes(let appData) = fields[3] { identity.appData = appData }
            guard knownIdentities[destHash] == nil else { continue }
            knownIdentities[destHash] = identity
            knownDestinationAnnouncedAt[destHash] =
                Date(timeIntervalSince1970: fields[0].asDouble ?? 0)
            if case .bytes(let packetHash) = fields[1] {
                knownDestinationPacketHash[destHash] = packetHash
            }
            // 0 is "never used", a negative value is the retention sentinel, and anything else is
            // a use time (`Identity.py:314-324`). Reading it back is what keeps a pinned
            // destination pinned across a restart.
            let lastUse = fields[4].asDouble ?? 0
            if lastUse < 0 {
                retainedDestinations.insert(destHash)
            } else if lastUse > 0 {
                knownDestinationLastUsed[destHash] = Date(timeIntervalSince1970: lastUse)
            }
        }
    }

    // MARK: - Known destination lifecycle

    /// Mark that a destination was used (for example, recalled for outbound encryption).
    /// Mirrors Python's `Identity._used_destination_data()` which:
    ///   - returns False if the destination isn't in known_destinations
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
    ///
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
            let hasPath = paths[destHash].map { !$0.isExpired } ?? false
            let announcedAt = knownDestinationAnnouncedAt[destHash] ?? now
            let lastUsed = knownDestinationLastUsed[destHash]
            lock.unlock()

            guard !isRetained, !hasPath else { continue }

            if let lastUsed {
                let unusedFor = now.timeIntervalSince(lastUsed)
                if unusedFor > Transport.destinationTimeout * 1.25 { toRemove.append(destHash) }
            } else {
                let lingerExpiry = announcedAt.addingTimeInterval(Transport.unusedDestinationLinger)
                if now >= lingerExpiry { toRemove.append(destHash) }
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

    /// Pin a destination so it's never removed by `cleanKnownDestinations`.
    ///
    /// Mirrors Python `Identity._retain_destination_data(destination_hash)`.
    @discardableResult
    public func retainDestinationData(_ destinationHash: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard knownIdentities[destinationHash] != nil else { return false }
        retainedDestinations.insert(destinationHash)
        return true
    }

    /// Unpin a previously retained destination so it becomes eligible for cleanup.
    ///
    /// Mirrors Python `Identity._unretain_destination_data(destination_hash)`.
    @discardableResult
    public func unretainDestinationData(_ destinationHash: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard knownIdentities[destinationHash] != nil else { return false }
        retainedDestinations.remove(destinationHash)
        return true
    }

    /// Pin all destinations associated with the given identity hash.
    ///
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
        // `Transport.prioritize_interfaces()` (`Transport.py:524`)—after the interfaces are
        // up, so `isOnline` is meaningful when the lowest bitrate is taken.
        prioritizeInterfaces()
        setupManagementDestinations()
        isRunning = true
        startJobsLoop()
    }

    /// Create management/probe/network destinations based on the current config.
    ///
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
                // Registered as a NATIVE handler, not a bytes one: Python's rnstatus does
                // `isinstance(request_receipt.response, list)` on the decoded value
                // (rnstatus.py:112). A bytes handler makes `dispatchRequest` wrap the
                // reply as `[request_id, BIN(<msgpack>)]`, Python receives `bytes`, the
                // isinstance test fails and rnstatus reports "Couldn't get RNS status
                // from remote transport instance". A Swift client would NOT catch this—`handleIncomingResponse`
                // unwraps a .bytes payload transparently.
                mgmt.registerNativeRequestHandler(path: "/status", allow: .list, allowedList: allowed) {
                    [weak self] _, data, _, _, _ -> MsgPack.Value? in
                    guard let self else { return nil }
                    // Python also guards on `remote_identity != None` (Transport.py:2851);
                    // here the `.list` allow policy in `Link.dispatchRequest` already
                    // requires an identified peer whose hash is in `allowed`, so reaching
                    // this closure implies it.
                    guard case .array(let arr) = data, let first = arr.first else { return nil }
                    // Python: response = [Transport.owner.get_interface_stats()], plus the
                    // link count when data[0] is True (Transport.py:2855-2856). rnstatus then
                    // reads the returned dict's "interfaces", "rxb", "txs", "transport_id"…
                    // keys, so this must be the full stats payload, not a summary of it.
                    var response: [MsgPack.Value] = [InterfaceStatsPayload.build(self)]
                    if case .bool(true) = first {
                        response.append(.int(Int64(self.getLinkCount())))
                    }
                    return .array(response)
                }
                mgmt.registerRequestHandler(path: "/path", allow: .list, allowedList: allowed) {
                    [weak self] _, data, _, _, _ -> Data? in
                    guard let self else { return nil }
                    guard let data, case .array(let arr) = (try? MsgPack.decode(data)) ?? .nil,
                          !arr.isEmpty, case .string(let command) = arr[0] else { return nil }
                    // Python: data = [command, destination_hash, max_hops]
                    let filterHash: Data? = {
                        guard arr.count > 1, case .bytes(let b) = arr[1] else { return nil }
                        return b
                    }()
                    let maxHops: UInt8? = {
                        guard arr.count > 2, let hops = arr[2].asInt, hops >= 0 else { return nil }
                        return UInt8(min(hops, 255))
                    }()
                    switch command {
                    case "table":
                        // The entries must carry every key `get_path_table()` produces—rnpath
                        // renders `path["interface"]` and `path["expires"]` directly,
                        // so an abridged entry raises a KeyError on the Python side.
                        let table = self.getPathTable(maxHops: maxHops)
                        let filtered = filterHash == nil ? table : table.filter { $0.destinationHash == filterHash }
                        let entries = filtered.map { e -> MsgPack.Value in
                            .map([(.string("hash"),      .bytes(e.destinationHash)),
                                         (.string("timestamp"), .double(e.lastHeard.timeIntervalSince1970)),
                                         (.string("via"),       .bytes(e.via)),
                                         (.string("hops"),      .int(Int64(e.hops))),
                                         (.string("expires"),   .double(e.expires.timeIntervalSince1970)),
                                         (.string("interface"), .string(e.interfaceName))])
                        }
                        return MsgPack.encode(.array(entries))
                    case "rates":
                        // Likewise: rnpath computes an announce rate from
                        // `entry["timestamps"]` and reads `entry["blocked_until"]`.
                        let rates = self.getRateTable()
                        let filtered = filterHash == nil ? rates : rates.filter { $0.destinationHash == filterHash }
                        let entries = filtered.map { r -> MsgPack.Value in
                            .map([(.string("hash"),            .bytes(r.destinationHash)),
                                  (.string("last"),            .double(r.last)),
                                  (.string("rate_violations"), .int(Int64(r.rateViolations))),
                                  (.string("blocked_until"),   .double(r.blockedUntil)),
                                  (.string("timestamps"),      .array(r.timestamps.map { .double($0) }))])
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
    ///
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

    /// Internal rather than private so a test can drive one pass directly: the defect this
    /// visibility exists for is a job that stops being *called*, which no test of the job
    /// itself can see.
    func runJobs() {
        // `Transport.prioritize_interfaces()` in the interface-jobs block (`Transport.py:1151`).
        // Refreshes both the bitrate ordering and `lowestInterfaceBitrate`.
        prioritizeInterfaces()
        sweepPendingRestores()
        sweepExpiredPaths()
        sweepPathRequestTables()
        sweepExpiredReceipts()
        sweepKnownRatchets()
        sweepReverseTable()
        sweepLinkRoutes()
        processAnnounceRetries()
        drainAnnounceQueues()
        sampleInterfaceSpeeds()
        sweepExpiredBlackholes()
        synthesizePendingTunnels()
        // Process held announces for each interface (mirrors Python's per-interface job loop).
        // Snapshot under `lock`—register/deregister mutate `interfaces` on
        // network-callback threads while this jobs loop runs.
        lock.lock()
        let heldSnapshot = interfaces
        lock.unlock()
        for iface in heldSnapshot { processHeldAnnounces(for: iface) }
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

    /// Process pending announce retransmissions.
    ///
    /// Mirrors the announce_table
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
            // retries==2, that is, after exactly one retransmission.
            if entry.retries > 0 && entry.retries >= Transport.localRebroadcastsMax {
                // Enough local rebroadcasts / retries—done.
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
                announcesFromInternal: iface.announcesFromInternal,
                nextHopAnnouncesToInternal: entry.receivingInterfaceAnnouncesToInternal
            ) else { continue }
            queueLock.lock()
            let queue = announceQueues[iface.name, default: AnnounceQueue()]
            announceQueues[iface.name] = queue
            queueLock.unlock()
            let canSend = queue.shouldTransmit(
                packet: forwarded, now: now, bitrate: iface.bitrate,
                announceCap: iface.announceCap, emitted: emitted
            )
            if canSend { try? transmit(forwarded, on: iface) }
        }
    }

    /// Receive-side cancel for a pending announce retransmission.
    ///
    /// Called when a
    /// forwarded (HEADER_2) announce arrives for a destination this node is about to
    /// retransmit. Mirrors Python's `Transport.inbound()` announce_table block:
    ///   - hops == stored + 1 → a sibling at this node's distance rebroadcast it;
    ///     once `LOCAL_REBROADCASTS_MAX` are heard the retry is dropped.
    ///   - hops == stored + 2 → a downstream node passed this rebroadcast on;
    ///     if it happened before the retry timer, no further tries are needed.
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

    /// Remove stale reverse-table entries.
    ///
    /// Proofs that never arrive within
    /// a reasonable window are dropped to prevent unbounded memory growth.
    private func sweepReverseTable(maxAge: TimeInterval = 600) {
        // The reverse table stores entries for proof forwarding. If a proof
        // hasn't arrived within maxAge seconds, the entry is stale.
        // In Python, the reverse table entries are removed when proofs arrive;
        // a sweep handles the case where proofs never arrive.
        // Simple approach: limit size (entries are at most a few hundred bytes each)
        reverseTableLock.lock()
        if reverseTable.count > 4096 {
            // Drop oldest half when table grows too large
            let keysToRemove = Array(reverseTable.keys.prefix(reverseTable.count / 2))
            for key in keysToRemove { reverseTable.removeValue(forKey: key) }
        }
        reverseTableLock.unlock()
    }

    /// Drop link-relay routes whose last activity is older than the link timeout.
    ///
    /// Mirrors Python's `link_table` cull in `Transport.jobs()` (LINK_TIMEOUT =
    /// STALE_TIME * 1.25). Without this a transport relay accumulates one permanent
    /// `linkRoutes` entry per link it ever forwarded—an unbounded memory leak over
    /// days/weeks. `lastHeard` is refreshed on every forwarded link packet
    /// (including keepalives), so a live relayed link is never swept. Wire-neutral.
    private func sweepLinkRoutes(now: Date = Date()) {
        let maxAge = Link.staleTime * 1.25
        lock.lock(); defer { lock.unlock() }
        linkRoutes = linkRoutes.filter { now.timeIntervalSince($0.value.lastHeard) < maxAge }
    }

    // MARK: - Path expiry

    /// Remove paths whose `expires` timestamp has passed.
    ///
    /// Mirrors Python's path table expiry in `Transport.jobs()`.
    public func sweepExpiredPaths(now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        let expired = paths.compactMap { $0.value.isExpired ? $0.key : nil }
        for dh in expired {
            paths.removeValue(forKey: dh)
            // Drop the parallel cached announce so it can't outlive its path.
            // (An orphaned cachedAnnounce is never served—handlePathRequest
            // requires a live path entry—so dropping it's wire-neutral, and it
            // stops cachedAnnounces from growing unbounded alongside path expiry.)
            cachedAnnounces.removeValue(forKey: dh)
        }
        // Drop the parallel responsiveness state for expired paths too (under its
        // own lock; order is lock > pathStatesLock). Otherwise pathStates grows
        // unbounded alongside path churn.
        if !expired.isEmpty {
            pathStatesLock.lock()
            for dh in expired { pathStates.removeValue(forKey: dh) }
            pathStatesLock.unlock()
        }
    }

    /// Expire the path for a specific destination immediately.
    ///
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

    /// Conclude the receipt for a link data packet whose proof a `Link` has already validated.
    ///
    /// Separate from ``deliverProof(packetHash:proof:)`` because the signature over a link data
    /// packet is made with the link's own signing key, which no receipt can verify—see
    /// `Link.handleDataProof` (`bugs/014`).
    func concludeLinkReceipt(packetHash: Data, proofPacket: Packet?) {
        receiptsLock.lock()
        let match = receipts.first { $0.packetHash == packetHash }
        receiptsLock.unlock()
        match?.markDeliveredByLinkProof(proofPacket)
    }

    /// Look up a receipt by packet hash and mark it delivered via
    /// explicit proof (hash + Ed25519 signature).
    ///
    /// Mirrors Python's
    /// `PacketReceipt.validate_proof`.
    func deliverProof(packetHash: Data, proof: Data) {
        receiptsLock.lock()
        let match = receipts.first { $0.packetHash == packetHash }
        receiptsLock.unlock()
        match?.validateExplicitProof(proof)
    }

    // MARK: - Outbound

    /// Whether `packet` is one the reference would generate a delivery receipt for.
    ///
    /// Python's predicate, verbatim (`Transport.py:1113-1124`): a DATA packet to a non-PLAIN
    /// destination whose context is outside the link-control range (`KEEPALIVE`…`LRPROOF`) and
    /// outside the resource range (`RESOURCE`…`RESOURCE_RCL`).
    ///
    /// This port gated on `destinationType == .single` instead, which excluded **every link
    /// packet**—so a message sent over a link got no receipt, nothing could ever prove it, and
    /// LXMF had no choice but to call `send()` returning "delivered" (`bugs/014`). The reference
    /// has no such restriction; a LINK destination is simply not PLAIN.
    static func shouldGenerateReceipt(for packet: Packet) -> Bool {
        guard packet.packetType == .data else { return false }
        guard packet.destinationType != .plain else { return false }
        let context = packet.context.rawValue
        // Link control: KEEPALIVE (0xFA) … LRPROOF (0xFF).
        if context >= Packet.Context.keepalive.rawValue { return false }
        // Resource transfer: RESOURCE (0x01) … RESOURCE_RCL (0x07). Resources carry their own
        // proof mechanism, so a per-part receipt would be duplicated bookkeeping.
        if context >= Packet.Context.resource.rawValue,
           context <= Packet.Context.resourceReceiverCancel.rawValue { return false }
        return true
    }

    /// Send a packet and optionally generate a delivery receipt.
    ///
    /// A `PacketReceipt` is created for any packet ``shouldGenerateReceipt(for:)`` accepts,
    /// matching Python's `Transport.outbound`. The receipt is returned so the caller can attach
    /// callbacks.
    @discardableResult
    public func send(_ packet: Packet, generateReceipt: Bool = true) throws -> PacketReceipt? {
        // `if self.hops >= RNS.Transport.PATHFINDER_M: return False` (`Packet.py:292`, added in
        // RNS 1.5.0), which `Transport._outbound` restates as `hops > PATHFINDER_M-1`. This is
        // the single funnel every outbound packet passes through, so the gate lives here rather
        // than at each construction site.
        //
        // `Packet.unpack` already refuses to *parse* a packet at or past the limit, so a peer
        // discards this frame the moment it arrives. Emitting it's pure waste, and on a
        // transport-mode node it's an amplification path. Returning nil rather than throwing
        // mirrors Python's `return False`: a refused send isn't an error condition.
        guard Int(packet.hops) < Transport.pathfinderM else { return nil }

        var packet = packet
        // Give the packet the transmit cap of the link it belongs to, mirroring Python's
        // `self.MTU = destination.mtu` for LINK-typed packets (`Packet.py:153-154`). Done here
        // because this is the single funnel every link packet passes through—the alternative
        // is stamping it at the ten `destinationType: .link` construction sites in `Link`, which
        // is the shape that let `bugs/013` come back three times.
        //
        // Without it, `pack()` caps every packet at the base 500 bytes, so once MTU discovery
        // raises a link the resource parts `bugs/016` sizes from that MTU, and every
        // interface and the transfer dies silently (`bugs/033`).
        if packet.destinationType == .link {
            lock.lock(); let link = links[packet.destinationHash]; lock.unlock()
            if let link { packet.mtu = max(packet.mtu, link.establishedMtu) }
        }
        var receipt: PacketReceipt? = nil

        if generateReceipt, Transport.shouldGenerateReceipt(for: packet) {
            if let hashable = try? packet.hashablePart() {
                let hash = Hashes.fullHash(hashable)
                // Use the remote peer's identity (public key) for proof validation.
                // Look up from knownIdentities first (outbound to remote peer);
                // fall back to the local registered destination's identity if
                // this is a loopback packet addressed to a local destination.
                //
                // A LINK packet has neither: its destination hash is a link ID, and its proof is
                // signed with the link's own signing key, which only the `Link` holds. Those
                // `Link.receive` concludes receipts after validating the signature
                // against `peerSigPub`—see `PacketReceipt.markDeliveredByLinkProof`.
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
            guard let outbound = path.nextHopInterface, outbound.isOnline else {
                // Path exists but interface is offline—broadcast as fallback.
                for iface in interfaces where iface.isOnline && iface.isRoutingEndpoint {
                    try? transmit(deltaMangled(packet, for: iface), on: iface)
                }
                return receipt
            }
            var routed = packet
            // A transport header is inserted only when the packet must be handed onward
            // through another node—that is, the destination is at least one hop away and the
            // path carries the next hop's transport ID (learned from a HEADER_2 announce).
            // The `hops >= 1` guard is the fix: a destination *zero* hops away is directly
            // reachable and must go out as-is (HEADER_1), even when a next-hop transport ID
            // is on file. That 0-hop-with-transport-ID combination arises for exactly one
            // topology—a shared instance's own local clients as seen from a sibling client,
            // whose path is learned via the instance's HEADER_2 announce yet is delivered
            // locally. Stamping HEADER_2 there published a stray transport header addressed to
            // the shared instance; a Python peer drops such a packet (a local client isn't the
            // addressed transport), so a Swift `rncp`/LXMF/NomadNet client's link request never
            // reached a Python peer across a shared instance. A directly connected 1-hop peer
            // learns its path from a HEADER_1 announce, leaving `nextHopTransportID` nil, so it
            // still goes out HEADER_1; a 1-hop backbone-relayed path keeps its HEADER_2. Mirrors
            // Python Transport.outbound()'s hop-count branches (Transport.py:1150-1188).
            if let nhID = path.nextHopTransportID, path.hops >= 1 {
                routed.headerType = .type2
                routed.transportID = nhID
            }
            // Local hop-count obfuscation: hide that this packet originated here.
            if shouldApplyDelta(packet, interface: outbound) { routed.hops = localHopsDelta }
            try transmit(routed, on: outbound)
            // Update path timestamp on successful send (mirrors Python's path_entry[IDX_PT_TIMESTAMP]).
            lock.lock()
            if var updated = paths[packet.destinationHash] {
                updated.lastHeard = Date()
                paths[packet.destinationHash] = updated
            }
            lock.unlock()
        } else {
            for iface in interfaces where iface.isOnline && iface.isRoutingEndpoint {
                try? transmit(deltaMangled(packet, for: iface), on: iface)
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

    /// Hand `packet` to `interface` and count it.
    ///
    /// Mirrors Python's `Transport.transmit(interface, raw)` (`Transport.py:1325-1330`),
    /// which every outbound path funnels through and which increments `tx_packets` once the
    /// interface has accepted the frame. Eighteen sites in this file route through here.
    /// A counter maintained at each of those sites instead would only ever be as complete
    /// as the last one someone remembered to update.
    func transmit(_ packet: Packet, on interface: any Interface) throws {
        try interface.send(packet)
        metricsLock.lock()
        txPackets += 1
        metricsLock.unlock()
    }

    /// Broadcast on every online routing-endpoint interface *except* the one specified.
    ///
    /// Used when relaying an announce so it doesn't go back where it
    /// came from.
    public func send(_ packet: Packet, exceptInterface excluded: Interface) {
        for interface in interfaces where interface.isOnline && interface.isRoutingEndpoint && interface !== excluded {
            try? transmit(packet, on: interface)
            // Mirrors Python: `interface.sent_announce()` when relaying an announce.
            if packet.packetType == .announce {
                notifyOutgoingAnnounce(on: interface, size: packet.rawByteCount)
            }
        }
    }

    /// Convenience—announce an inbound destination on all interfaces.
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
            try transmit(packet, on: iface)
            return nil
        }
        return try send(packet, generateReceipt: false)
    }

    /// Default receipt timeout for a destination.
    ///
    /// Uses hop count if a path
    /// is known; otherwise falls back to a single-hop estimate.
    /// Mirrors Python's `get_first_hop_timeout` + `TIMEOUT_PER_HOP`.
    private func defaultTimeout(for destinationHash: Data) -> TimeInterval {
        let perHop: TimeInterval = 6
        let hops = TimeInterval(hopsTo(destinationHash) ?? 1)
        return max(perHop, hops * perHop)
    }

    // MARK: - Inbound

    /// Wire-format hash of the well-known path-request destination, plain
    /// kind, name "rnstransport.path.request"—matches the Python
    /// reference `Transport.path_request_destination`.
    public static let pathRequestDestinationHash: Data = {
        let nameHash = Destination.computeNameHash(
            appName: "rnstransport",
            aspects: ["path", "request"]
        )
        return Destination.computeHash(identity: nil, nameHash: nameHash, kind: .plain)
    }()

    /// Wire-format hash of the well-known tunnel synthesize destination, plain
    /// kind, name "rnstransport.tunnel.synthesize"—matches Python
    /// `Transport.tunnel_synthesize_destination`.
    public static let tunnelSynthesizeHash: Data = {
        let nameHash = Destination.computeNameHash(
            appName: "rnstransport",
            aspects: ["tunnel", "synthesize"]
        )
        return Destination.computeHash(identity: nil, nameHash: nameHash, kind: .plain)
    }()

    func handleIncoming(packet: Packet, from interface: Interface) {
        // Count inbound traffic bytes + cache packet PHY stats under `metricsLock`.
        // handleIncoming runs concurrently for every inbound frame across
        // interfaces, so these counter/array mutations must be serialized. The
        // packet pack/hash work is done first (outside the lock) so the lock is
        // held only for the mutations. `lock` isn't held here.
        // Mirrors Python `Transport.traffic_rxb` accumulation and the
        // local_client_rssi/snr/q caches (LOCAL_CLIENT_CACHE_MAXSIZE = 512).
        // Use packedBytes()/hashablePart-based hashing (NOT pack()): an inbound
        // link packet may legitimately exceed the base MTU once a larger link
        // MTU is negotiated, and pack()'s MTU guard would throw—undercounting
        // traffic and (via filterAndRecord) dropping the packet entirely.
        let rawByteCount = (try? packet.packedBytes())?.count
        let pktHash = try? packet.truncatedPacketHash()
        metricsLock.lock()
        if let n = rawByteCount { trafficRxBytes += n }
        if let pktHash {
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
        metricsLock.unlock()

        // Drop duplicate or replayed packets. Link handshake packets
        // (LRR and LRPROOF) are exempt so retransmissions work.
        //
        // `if not Transport.packet_filter(packet): return interface.packet_filter_hit()`
        // (`Transport.py:1795`). `filterAndRecord` is this port's live filter—the public
        // `packetFilter` covers only the hashlist branch and no production path calls it—so
        // this guard is the one place a filtered frame is observable.
        guard filterAndRecord(packet: packet) else {
            notifyPacketFilterHit(on: interface)
            return
        }

        // `Transport.rx_packets += 1` (`Transport.py:1798`)—after the packet filter and
        // before the hop increment, so a frame the filter rejected is never counted as
        // received traffic. `rnstatus -p` divides this into the sampling interval.
        metricsLock.lock()
        rxPackets += 1
        metricsLock.unlock()

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
            // Non-LRPROOF proofs over a link (for example, RESOURCE_PRF) are
            // encrypted with the link key—let Link.receive decrypt them.
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
        // identity, so the transport-wide ownerIdentity isn't needed here.
        // (ownerIdentity is still needed for tunnel synthesis—synthesizeTunnel.)
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
                // Malformed request—drop silently.
            }
            return
        }

        // Not for this node—forward toward the responder if a path is known, and
        // remember the link's two-sided routing so the proof/RTT/close
        // packets that come back addressed to link_id can be steered. As with
        // DATA relay, a non-transport shared instance still relays link requests
        // to/from a directly connected local client (Python `transport_enabled or
        // from_local_client or for_local_client_link`, Transport.py:1573).
        let fromLocalLR = fromLocalClient(interface: interface)
        let forLocalLR: Bool = {
            guard let p = path, p.hops == 0, let nh = p.nextHopInterface else { return false }
            return isLocalClientInterface(nh)
        }()
        guard transportEnabled || fromLocalLR || forLocalLR, let path else { return }
        guard packet.hops < propagationLimit else { return }
        guard let outbound = path.nextHopInterface, outbound.isOnline else { return }
        guard outbound !== interface else { return }

        // link_id derives from the LRR packet's hashable part with signalling bytes
        // stripped—mirrors Python's Link.link_id_from_lr_packet so all nodes
        // (initiator, relay, responder) agree on the same link_id value.
        guard let linkIDHashable = try? Link.linkIDHashable(for: packet, dataLength: packet.data.count) else {
            return
        }
        let linkID = Hashes.truncatedHash(linkIDHashable)
        let route = LinkRoute(
            linkID: linkID,
            initiatorSideInterface: interface,
            responderSideInterface: outbound,
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

        // If the incoming LINKREQUEST is HEADER_2 addressed to this node as relay,
        // Transport must convert it before forwarding. Mirrors Python Transport lines 1565–1576:
        //
        //   remaining_hops > 1 → update transport_id to next hop, keep HEADER_2
        //   remaining_hops == 1 → strip transport header, forward as HEADER_1
        //
        // Swift stores path.hops = raw wire hops (no inbound +1), so the
        // equivalence is:
        //   path.hops == 0  ↔  Python remaining_hops == 1  → strip headers
        //   path.hops  > 0  ↔  Python remaining_hops  > 1  → update transport_id
        //
        // Without this conversion, the responder receives HEADER_2 with this node's
        // transport_id, fails the identity check (transport_id ≠ responder's ID),
        // and silently drops the link request.
        if forwarded.headerType == .type2, forwarded.transportID == transportInstanceID {
            if path.hops == 0 {
                // Destination is directly reachable on outbound interface.
                // Strip the transport header so the responder receives a plain HEADER_1.
                forwarded.headerType = .type1
                forwarded.transportType = .broadcast
                forwarded.transportID = nil
            } else {
                // More relay hops needed—replace this transport_id with the
                // next relay's transport_id so that node forwards it onward.
                forwarded.transportID = path.nextHopTransportID ?? transportInstanceID
            }
        }

        // Clamp/strip the link-request MTU signalling for the next hop (mirrors
        // Python's link-MTU handling in `Transport.inbound()`). This is safe for
        // routing because the link_id is hashed with signalling bytes removed.
        clampRelayedLinkRequestMtu(&forwarded, prevHop: interface, nextHop: outbound)

        try? transmit(forwarded, on: outbound)
    }

    /// Clamp or strip the 3-byte MTU signalling tail of a relayed LINKREQUEST so
    /// the link isn't negotiated above what a relay hop can carry. Mirrors
    /// Python `Transport.inbound()` (lines ~1604-1626):
    ///   - next hop declares no HW MTU, or can't autoconfigure/fixed MTU →
    ///     disable the upgrade and drop the signalling bytes;
    ///   - otherwise, if the next- or prev-hop HW MTU is below the requested
    ///     path MTU, clamp the signalling to the smallest HW MTU on the path.
    /// With Swift's production interfaces (all `hwMtu == nil`) only the strip
    /// branch fires today; tests with an
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
            // Next hop can't carry an upgraded MTU—disable the upgrade.
            packet.data = Data(packet.data.prefix(base))
        } else if let nh = nhMtu, nh < pathMtu || (phMtu.map { $0 < pathMtu } ?? false) {
            // Clamp to the smallest HW MTU on the path. INTENTIONAL DIVERGENCE
            // from Python: when the next hop reports an MTU below the path MTU
            // but the prev hop reports no HW MTU, Python computes `min(nh, None)`,
            // raises TypeError, and *drops* the link request. This port instead clamps to
            // the next-hop MTU (the binding constraint when the prev hop is
            // unknown) and forward, so a recoverable link still establishes—strictly
            // better than dropping it on a Python `min(None)` crash.
            let clamped = min(nh, phMtu ?? nh)
            packet.data = Data(packet.data.prefix(base)) + Link.mtuSignallingBytes(mtu: clamped)
        }
    }

    private func handleLinkRequestProof(_ packet: Packet, from interface: Interface) {
        if let link = lookupLink(packet.destinationHash) {
            let proofHops = Int(packet.hops)
            // Python's `hops_to` returns PATHFINDER_M for an unknown path, never
            // None, so `link.expected_hops` is always an int and a pathless link
            // compares against a sentinel that can never equal a real hop count—that is,
            // it ALWAYS disagrees and always re-balances. Swift models the
            // unknown case as nil, so map it onto the same sentinel; treating nil
            // as "agrees" would skip re-balancing for exactly the pathless links
            // that most need it.
            if (link.expectedHops ?? Transport.pathfinderM) != proofHops {
                // RNS 1.4.1 path re-balancing at the link terminus. Python
                // re-balances *before* validating the proof, and then accepts the
                // proof only if the hop counts agree (Transport.py:2276-2317):
                // re-balancing sets `expected_hops = packet.hops`, so a successful
                // re-balance is what makes them agree. Ordering matters twice
                // over—the path table and `expectedHops` must be corrected
                // before the link goes active, or every `onEstablished` observer
                // reads the stale hop count.
                //
                // Re-balancing verifies the signature itself rather than relying
                // on `validateProof`, which hasn't run yet; a forged proof
                // therefore still can't move a path.
                if Transport.allowLinkPathRebalance, link.status == .pending,
                   link.proofSignatureIsValid(packet) {
                    rebalancePath(for: link, toHops: proofHops)
                }
                // Still disagreeing means the re-balance didn't happen—disabled,
                // already latched for this link, or a bad signature. In
                // every one of those cases Python never reaches `validate_proof`
                // and the link simply stays pending until it times out.
                guard (link.expectedHops ?? Transport.pathfinderM) == proofHops else { return }
            }
            do {
                try link.validateProof(packet)
                // Fire the transport-level callback for the initiator side.
                // The destination's onLinkEstablished is intentionally NOT
                // fired here—it belongs to the responder side and is wired
                // in handleLinkRequest.
                onLinkEstablished?(link)
            } catch {
                // Bad proof—drop.
            }
            return
        }
        // Relay path: a proof only gets forwarded once its signature checks out.
        //
        // Python guards the transmit with three conditions (`Transport.py:2641-2669`), and
        // this is the one place a relayed proof can be examined, so all three live here rather
        // than inside `forwardLinkTraffic`, which carries ordinary link traffic that has no
        // signature to check.
        lock.lock()
        let route = linkRoutes[packet.destinationHash]
        lock.unlock()
        guard let route else { return }

        // 1. Direction. A proof travels responder→initiator, so it must arrive on the side
        //    facing the responder: `packet.receiving_interface == link_entry[IDX_LT_NH_IF]`.
        //    Without this, anyone on the initiator side can replay a genuine proof back at the
        //    responder, and `forwardLinkTraffic`'s "steer to the other side" would send it.
        guard interface === route.responderSideInterface else { return }

        // 2. Recall. Python calls `RNS.Identity.recall(link_entry[IDX_LT_DSTHASH])` and, when
        //    that returns None, dies on `.get_public_key()` inside the enclosing
        //    `except Exception` (`Transport.py:2671`)—logged, not transmitted, and no protocol
        //    violation, because the proof may be genuine and this node simply can't tell.
        guard let responderIdentity = recall(identity: route.destinationHash) else { return }

        // 3. Signature.
        guard Link.proofSignatureIsValid(packet, responderIdentity: responderIdentity) else {
            notifyProtocolViolation(on: interface)
            return
        }

        // `link_table[…][IDX_LT_VALIDATED] = True` (Transport.py:2661). Set only here, after
        // the signature verified, so the flag records verification rather than arrival.
        //
        // Python sets it one line below its transmit, this port one line ahead. The
        // verification that the flag records has already happened either way—the signature
        // guard sits directly ahead of it—but the transmit isn't a boundary here.
        // Python's goes out through a socket, so the initiator's reply arrives on a later
        // pass, while an in-process interface calls straight through: the initiator receives
        // the proof and answers with a link RTT packet *inside* `forwardLinkTraffic`, and that
        // reply reaches the validation gate before this line would otherwise run.
        lock.lock()
        linkRoutes[packet.destinationHash]?.validated = true
        lock.unlock()

        forwardLinkTraffic(packet, from: interface)

        // Mirrors Python Transport.py line 2199:
        //   RNS.Identity._used_destination_data(link_entry[IDX_LT_DSTHASH])
        // Mark the destination as recently used so cleanKnownDestinations doesn't
        // evict it while the link is active. Only fires when the destination hash
        // is already known (markDestinationUsed returns false otherwise).
        markDestinationUsed(route.destinationHash)
    }

    /// Correct this link's hop expectation, and the path table entry behind it,
    /// from a link-request proof that arrived over a different number of hops
    /// than the path table predicted.
    ///
    /// This is RNS 1.4.1's dynamic path re-balancing at the link terminus
    /// (Python `Transport.inbound`, the `for link in Transport.pending_links`
    /// block). A link request is the first real round-trip to a destination, so
    /// its proof is the earliest trustworthy measurement of the true hop count
    ///—announces may have arrived over a longer route, or the topology may
    /// have shortened since. Correcting the path table here makes every
    /// subsequent packet to that destination use the right hop expectation
    /// instead of waiting for the next announce.
    ///
    /// Latched by `link.rebalanced` so each link re-balances at most once,
    /// matching Python's `if not link.rebalanced:` guard.
    private func rebalancePath(for link: Link, toHops hops: Int) {
        // Claim the latch on the link first, under the link's own lock and
        // *before* taking `lock`: a read-then-write across two threads could
        // otherwise let two proofs both pass the guard, and taking `lock` while
        // holding a link lock would invert the established order.
        guard link.claimRebalance(toHops: hops) else { return }
        lock.lock()
        defer { lock.unlock() }
        let destinationHash = link.destination.hash
        if var entry = paths[destinationHash], entry.hops != UInt8(truncatingIfNeeded: hops) {
            entry.hops = UInt8(truncatingIfNeeded: hops)
            paths[destinationHash] = entry
        }
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
        guard packet.hops < propagationLimit else { return }
        lock.lock()
        let stored = linkRoutes[packet.destinationHash]
        lock.unlock()
        guard var route = stored else { return }
        // `if not link_entry[IDX_LT_VALIDATED]: ... protocol_violation("Link packet received
        // before link validation")` (`Transport.py:2124-2128`). A link-table entry appears when
        // a transport node relays a link request, and turns valid only once that node verifies the
        // responder's proof. Carrying traffic before that means forwarding packets for a link
        // that may never complete, and anyone can arrange it by pushing a link request through
        // the node.
        //
        // Upstream's condition excludes ANNOUNCE, LINKREQUEST and LRPROOF (`:2122`), and only
        // the last can reach this function. A proof relayed from `handleLinkRequestProof`
        // arrives with the flag already up, so the exemption changes nothing on that path—but
        // it's upstream's condition, and it keeps a proof arriving by any other route (a
        // duplicate, or one for a torn-down link) from charging the sender.
        if packet.context != .lrproof, !route.validated {
            notifyProtocolViolation(on: sourceInterface)
            return
        }
        let initIface = route.initiatorSideInterface
        let respIface = route.responderSideInterface
        // A non-transport shared instance still relays link traffic when either
        // side of the link is a directly connected local client (Python's
        // for_local_client_link, Transport.py:1573).
        let touchesLocalClient = (initIface.map(isLocalClientInterface) ?? false)
                              || (respIface.map(isLocalClientInterface) ?? false)
        guard transportEnabled || touchesLocalClient else { return }
        // Steer to the side that didn't deliver the packet—compared by identity, not by
        // name. With names, a hairpin between two clients of one listening interface compares
        // two equal strings, matches the first branch, and sends the packet back out the
        // interface it arrived on (`bugs/027`).
        let outboundCandidate: (any Interface)?
        if sourceInterface === route.initiatorSideInterface {
            outboundCandidate = route.responderSideInterface
        } else if sourceInterface === route.responderSideInterface {
            outboundCandidate = route.initiatorSideInterface
        } else {
            return
        }
        guard let outbound = outboundCandidate, outbound.isOnline else { return }
        var forwarded = packet
        // instance_local_link: both sides of this link are local clients, so the
        // traffic never leaves the local-client domain and must keep its real
        // hop count even under local hop-count obfuscation.
        let instanceLocalLink = (initIface.map(isLocalClientInterface) ?? false)
                             && (respIface.map(isLocalClientInterface) ?? false)
        forwarded.hops = relayHops(packet, from: sourceInterface, staysLocal: instanceLocalLink)
        try? transmit(forwarded, on: outbound)
        route.lastHeard = Date()
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
                // client, so it stays in the local domain—keep its real hops.
                let proofForLocalClient = isLocalClientInterface(receiveIface)
                forwarded.hops = relayHops(packet, from: interface, staysLocal: proofForLocalClient)
                try? transmit(forwarded, on: receiveIface)
            }
            // Don't stop here—also try to match against local receipts below
            // in case this relay is also the originator (uncommon but valid).
        }

        if proofData.count == PacketReceipt.explicitProofLength {
            // Explicit proof: [32-byte hash][64-byte sig]. Pre-filter by hash.
            let proofHash = proofData.prefix(Constants.fullHashLength)
            receiptsLock.lock()
            let match = receipts.first { $0.packetHash == proofHash }
            receiptsLock.unlock()
            if let match {
                // Hand the inbound packet to the receipt as well: it carries the PHY
                // metadata (rssi/snr/quality) the interface stamped on it, which is what
                // Python's `receipt.proof_packet` exposes. Mirrors Python's
                // `receipt.validate_proof_packet(packet)` (Transport.py:2302).
                match.validateExplicitProof(proofData, packet: packet)
                return
            }
        } else if proofData.count == PacketReceipt.implicitProofLength {
            // Implicit proof: 64-byte signature only. Must try every receipt
            // (matches Python: "check every single outstanding receipt").
            receiptsLock.lock()
            let snapshot = receipts
            receiptsLock.unlock()
            for receipt in snapshot {
                if receipt.validateImplicitProof(proofData, packet: packet) {
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
        // Python's announce admission gate (`Transport.py:1806-1811`). Three
        // decisions, in this order, before anything else looks at the announce:
        //
        //  1. A blackholed announcer drops without a sound. The blackhole test
        //     sits inside `validate_announce`, after the public key loads and
        //     before it verifies the signature (`Identity.py:551-556`), so a
        //     blackholed peer never costs a verification.
        //  2. An announce whose signature doesn't verify is a protocol
        //     violation, not a silent drop. Without this the operator has no
        //     signal that a peer is putting forgeries on the wire.
        //  3. Only an announce that survives both reaches `received_announce`,
        //     so the interface's announce counter describes announces this node
        //     accepted rather than every announce-shaped frame that arrived.
        //
        // Order 1-before-2 is observable: it decides whether a blackholed peer
        // sending a bad signature shows up in the protocol-violation counter.
        switch Identity.validateAnnounce(
            packet, onlyValidateSignature: true, isBlackholed: { self.isBlackholed($0) }
        ) {
        case .blackholed:
            return
        case .invalid:
            notifyProtocolViolation(on: interface)
            return
        case .valid:
            break
        }

        notifyIncomingAnnounce(on: interface, size: packet.rawByteCount)

        // An announce for a destination this node owns is dropped here and goes no further.
        //
        // Python computes `local_destination` from `destinations_map` and hangs the ENTIRE
        // announce block off it being nil (`Transport.py:1767-1772`)—path table, identity
        // caching, announce handlers and relay are all inside that one `if`. It then repeats the
        // ownership test at the path-table admission check (`:1806-1807`), which is a fair signal
        // of how load-bearing it is.
        //
        // This isn't a rare case. A transport-enabled neighbour reflects announces back to their
        // originator by design: `Transport.outbound`'s broadcast loop (`:1197`) has no
        // receiving-interface exclusion, and the PATHFINDER_R retransmission re-sends with
        // `attached_interface = None` (`:604-637`). Every node hears its own announces come back,
        // and every node is expected to ignore them.
        //
        // Without this, a node learns a path to itself, re-caches its own identity from the wire,
        // hands its own announce to every registered handler, and may relay it onward. The symptom
        // that surfaced it (`swift_devel/bugs/047`): a lone LXMF propagation node, on a mesh with
        // nobody else on it, peered with itself.
        //
        // One ordering difference from the reference, with no observable consequence: Python
        // checks the announce signature before this gate and the full announce after it, so an
        // invalid announce for an owned destination is rejected there and dropped here. Either way
        // it goes nowhere.
        lock.lock()
        let isOwnDestination = registeredDestinations[packet.destinationHash] != nil
        lock.unlock()
        if isOwnDestination { return }

        // Ingress burst limiting: hold announces during flooding bursts.
        // Mirrors Python: `if interface.should_ingress_limit(): interface.hold_announce(packet); return`
        // Only applies to unknown destinations (known paths exempt—Python checks path_requests too).
        do {
            // The admission gate at the top of this function already verified this
            // signature over these same bytes, so skip the second verification the
            // way Python's `announce_signature_validated` does (`Identity.py:559`).
            let decoded = try Announce.validate(packet, signatureVerified: true)

            // Announce-retry cancel (mirrors Python `Transport.inbound()`'s
            // announce_table handling): if a retransmission is pending for
            // this destination and another transport node carries it on
            // (a forwarded HEADER_2 announce), cancel or de-prioritise the
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
                // Only re-process if the incoming path is strictly better (fewer
                // hops) than the stored one—OR the current path has been marked
                // unresponsive, in which case Python allows the SAME announce
                // (same random blob) arriving via an alternate, longer route to
                // revive the path (D2; handled by the more-hops/equal-emission
                // branch in the freshness ladder below, which intentionally skips
                // the blob check). Without this unresponsive exception the
                // early return would swallow the reviving announce before the
                // ladder ever runs.
                let existingHops = paths[decoded.destinationHash]?.hops ?? UInt8.max
                // pathStatesLock guards pathStates everywhere (mark*/
                // pathIsUnresponsive); read it under that lock even while holding
                // `lock` (order: lock > pathStatesLock, a pure leaf).
                pathStatesLock.lock()
                let unresponsive = pathStates[decoded.destinationHash] == Transport.stateUnresponsive
                pathStatesLock.unlock()
                // RNS 1.4.1 gravity: the *same* announce re-arriving on a
                // strictly higher-gravity interface is exactly how a path is
                // pulled onto a preferred interface, and it arrives with equal
                // hops—so it must not be swallowed here either.
                //
                // Python has no hop-based early return at all: `packet_filter`
                // returns True unconditionally for a duplicate SINGLE announce
                // (Transport.py:1417-1425), and every duplicate reaches the
                // `should_add` ladder. This early return is a Swift-only
                // optimisation, so every ladder branch that a duplicate can
                // still satisfy needs a matching exemption here.
                //
                // Which branches those are: the ladder's remaining accept
                // branches all require `!blobSeen`, and a duplicate that already
                // updated the path recorded its blob on the first pass—so for a
                // duplicate only the two exempted below (gravity takeover, and
                // reviving an unresponsive path, both of which turn on equal
                // emission rather than an unheard blob) can fire.
                //
                // Known residual divergence: the dedup cache is populated earlier,
                // *before* the ingress-burst and announce-rate filters run. An
                // announce dropped by one of those never reaches the
                // ladder and so never records its blob, yet its cache entry
                // survives—a later copy at equal-or-greater hops is then
                // swallowed here where Python would still evaluate it. Narrow
                // (it needs a first copy dropped by a rate limiter and a second
                // copy on a non-shorter route) and fail-closed, so it's left
                // as-is rather than reordering the filters around the cache.
                let higherGravity = currentPathGravityLocked(decoded.destinationHash)
                    .map { interface.gravity > $0 } ?? false
                if packet.hops >= existingHops, !unresponsive, !higherGravity {
                    lock.unlock()
                    return  // Already seen, not a better path, and path is responsive
                }
                // Better path, reviving an unresponsive one, or a gravity
                // takeover—fall through.
            }
            lock.unlock()

            // Ingress burst limiting for unknown destinations (mirrors Python).
            // Known destinations are exempt (path requests for them may be pending).
            lock.lock()
            let isKnownDest = registeredDestinations[decoded.destinationHash] != nil
                           || paths[decoded.destinationHash] != nil
            // `if packet.destination_hash in Transport.path_requests or … in
            // Transport.discovery_path_requests: pass` (`Transport.py:1819-1821`). This node
            // asked the network for exactly this destination on a peer's behalf, so holding the
            // answer behind the burst limiter would strand the very requestors the waiting entry
            // holds open for—and the entry would then time out having achieved nothing.
            //
            // Upstream exempts its client-side `path_requests` table here too; this port has no
            // such table, so this checks only the half that exists.
            let awaitedByDiscovery = discoveryPathRequests[decoded.destinationHash] != nil
            lock.unlock()
            if !isKnownDest && !awaitedByDiscovery && shouldIngressLimit(on: interface) {
                holdAnnounce(packet, destinationHash: decoded.destinationHash, on: interface)
                return
            }

            // Per-destination rate limiting (mirrors Python's announce_rate_table check).
            // Only active when interface.announceRateTarget != nil.
            // A rate-blocked announce is still validated but the path table isn't updated.
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
                nextHopInterface: interface,
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
            // 1. Always update if no path is known yet.
            // 2. Update if new path has fewer hops.
            // 3. Update if same hops (newer announce).
            // 4. Update if more hops but the announce was emitted MORE RECENTLY
            //    (the existing path's source may have moved or the old path is stale).
            // 5. Update if the existing path is expired.
            let shouldUpdate: Bool
            pathStatesLock.lock()
            let isUnresponsive = pathStates[decoded.destinationHash] == Transport.stateUnresponsive
            pathStatesLock.unlock()
            let existingBlobs = paths[decoded.destinationHash]?.randomBlobs ?? []
            if let existing = paths[decoded.destinationHash] {
                // Path-table freshness gate—a faithful port of Python's
                // `should_add` ladder (Transport.inbound, Transport.py:1801-1875).
                //
                // The critical invariant the previous "fewer hops always wins"
                // logic violated: an announce may only replace an existing path
                // when it's genuinely NEWER—its emission timestamp must exceed
                // `path_timebase`, the MAX emission across every random blob
                // recorded for that path—or it's the same announce arriving to
                // revive a path previously marked unresponsive. Emission
                // timestamps are second-resolution (5-byte unix seconds in the
                // announce's random hash), so two announces made in the same second
                // tie and neither displaces the other; path convergence to a
                // shorter route therefore happens across successive (later)
                // announces, not within a single announce flood. Accepting a
                // stale/replayed/reordered announce here—which the old ladder did
                //—degrades paths network-wide and enables path forgery once the
                // 64-blob replay window rolls over.
                //
                // Python's `path_announce_emitted` loop (1834-1838) takes the max
                // over blobs with an early break; that yields the same >/==/<
                // ordering against `announce_emitted` as the full max, so the
                // existing `timebaseFromRandomBlobs` helper is exact here.
                let pathTimebase = Transport.timebaseFromRandomBlobs(existing.randomBlobs)
                let blobSeen = randomBlob.map { existing.randomBlobs.contains($0) } ?? false
                if packet.hops <= existing.hops {
                    // Fewer-or-equal hops (Python 1820-1844): accept a fresh,
                    // previously unheard announce that's more recently emitted…
                    if !blobSeen && emittedAt > pathTimebase {
                        shouldUpdate = true
                    } else if emittedAt != pathTimebase {
                        // …otherwise it's only a gravity takeover candidate when
                        // the emission timebase matches exactly, that is, it's
                        // literally the same announce reaching this node again by
                        // another route (Python: `if announce_emitted !=
                        // path_timebase: should_add = False`).
                        shouldUpdate = false
                    } else if let currentGravity = currentPathGravityLocked(decoded.destinationHash) {
                        // RNS 1.4.1: the same announce arriving on an interface
                        // with strictly higher gravity pulls the path onto that
                        // interface.
                        shouldUpdate = interface.gravity > currentGravity
                    } else {
                        // Python: `announce_gravity == None or current_gravity
                        // == None → should_add = False`.
                        shouldUpdate = false
                    }
                } else if existing.isExpired {
                    // More hops, but the path has expired (Python 1842-1853):
                    // accept any announce not already heard.
                    shouldUpdate = !blobSeen
                } else if emittedAt > pathTimebase {
                    // More hops, not expired, but more recently emitted
                    // (Python 1858-1864): accept if unheard.
                    shouldUpdate = !blobSeen
                } else if emittedAt == pathTimebase {
                    // More hops, same emission (Python 1870-1875): only replace to
                    // revive an unresponsive path. No blob check here—Python
                    // deliberately allows the SAME announce (same blob, arriving via
                    // an alternate longer route) to take over when the shorter path
                    // has gone dead. Pairs with the unresponsive exception in the
                    // duplicate early return above (D2).
                    shouldUpdate = isUnresponsive
                } else {
                    // More hops and strictly older emission: ignore (Python's
                    // implicit else—should_add stays False).
                    shouldUpdate = false
                }
            } else {
                shouldUpdate = true  // no existing path (Python 1877-1880)
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
                // Reset responsiveness state whenever the path table is updated.
                //
                // Python calls `mark_path_unknown_state` UNCONDITIONALLY inside
                // `if should_add:` (Transport.py:2053), immediately after the
                // path_table assignment—so every accepted announce resets the
                // state, gravity takeover included. The per-branch inline
                // `mark_path_unknown_state` calls higher up the ladder are
                // redundant with it, and three branches omit them (the
                // unknown-destination, gravity and unresponsive-revive
                // branches); none of those escapes this tail call.
                //
                // Don't be tempted to preserve the old state on a gravity
                // takeover: a latched `stateUnresponsive` would immediately let
                // the `emittedAt == pathTimebase → shouldUpdate = isUnresponsive`
                // branch below hand the path to any longer, lower-gravity route
                // that repeats the same announce, silently undoing the takeover.
                pathStatesLock.lock()
                pathStates[decoded.destinationHash] = Transport.stateUnknown
                pathStatesLock.unlock()
            }
            // Attach app_data to the identity so callers can retrieve it via
            // Identity.recallAppData / Transport.recallAppData. Python stores this in
            // Identity.known_destination_hashes[hash]["app_data"].
            if let ad = decoded.appData { decoded.identity.appData = ad }
            knownIdentities[decoded.destinationHash] = decoded.identity
            knownDestinationAnnouncedAt[decoded.destinationHash] = Date()
            // `Identity.remember(packet.get_hash(), …)`—Identity.py:577, stored at field 1 of
            // the known-destinations entry (`:107`).
            knownDestinationPacketHash[decoded.destinationHash] =
                (try? Hashes.fullHash(packet.hashablePart())) ?? Data()
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
                tunnels[tunnelID]?.paths[decoded.destinationHash] = entry
                tunnels[tunnelID]?.expires = Date().addingTimeInterval(Transport.tunnelTimeout)
            }
            lock.unlock()

            onAnnounceReceived?(decoded, interface)
            dispatchAnnounceHandlers(decoded)

            // Relay onto other interfaces if this node is transport-enabled OR
            // a directly connected local client originated the announce.
            // The local-client alternative mirrors Python's
            // `if (transport_enabled or is_from_local_client) and context !=
            // PATH_RESPONSE:` (Transport.py:1935): a shared instance running with
            // enable_transport = No must still propagate its own clients'
            // announces to the mesh, otherwise no peer ever learns the client's
            // destination.
            //
            // Forward ONLY when the announce also updated the path table—this
            // mirrors Python, where the announce-table insert (and thus the
            // rebroadcast) lives inside `if should_add:`. Because SINGLE
            // announces bypass the packet-hash dedup filter, forwarding every
            // arrival would re-broadcast duplicates/replays endlessly (an
            // announce storm); gating on `shouldUpdate` (which includes the
            // random-blob replay guard) forwards each distinct announce once.
            // Path-response announces aren't forwarded (mirrors Python:
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
                    //   must not be re-broadcast to other AP or BOUNDARY interfaces—AP
                    //   clients must not be able to reach each other via the AP.
                    // - Announces received from BOUNDARY interfaces must not be re-broadcast
                    //   to other BOUNDARY or ACCESS_POINT interfaces.
                    // - Announces received on FULL/GATEWAY/ROAMING/POINT_TO_POINT interfaces
                    //   are forwarded freely (including to AP and BOUNDARY interfaces).
                    guard Transport.shouldForwardAnnounce(
                        outboundMode: iface.mode,
                        nextHopMode: interface.mode,
                        localDestination: false,
                        announcesFromInternal: iface.announcesFromInternal,
                        nextHopAnnouncesToInternal: interface.announcesToInternal
                    ) else { continue }
                    queueLock.lock()
                    let queue = announceQueues[iface.name, default: AnnounceQueue()]
                    announceQueues[iface.name] = queue
                    queueLock.unlock()
                    let canSend = queue.shouldTransmit(
                        packet: forwarded,
                        now: now,
                        bitrate: iface.bitrate,
                        announceCap: iface.announceCap,
                        emitted: emitted
                    )
                    if canSend { try? transmit(forwarded, on: iface) }
                }

                // Record this forwarded announce for a single retransmission
                // (Python `PATHFINDER_R = 1`). The first forward just went out
                // earlier, so the entry starts at `retries = 1`; the jobs loop
                // retransmits once more after the grace window unless
                // neighbours carry it on. Mirrors the announce_table insert
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
                    receivingInterfaceMode: interface.mode,
                    receivingInterfaceAnnouncesToInternal: interface.announcesToInternal
                )
                lock.unlock()
            }

            // If any local shared-instance clients are connected, retransmit
            // the announce to them immediately—independent of `transportEnabled`
            // and regardless of path-response context. Mirrors Python's
            // "if (len(Transport.local_client_interfaces)): ... new_announce.send()"
            // block: apps sharing this daemon's connection (nomadnet, rnstatus,
            // MeshChatX, …) must see every announce the daemon overhears, even
            // when this instance isn't itself acting as a mesh transport/relay
            // node. Unlike the preceding mesh-relay forward, hops is passed through
            // unchanged (Python: `new_announce.hops = packet.hops`).
            let localTargets = localClientServingInterfaces(excluding: interface)
            if shouldUpdate, !localTargets.isEmpty {
                var localForward = packet
                localForward.headerType = .type2
                localForward.transportID = transportInstanceID
                for iface in localTargets {
                    try? transmit(localForward, on: iface)
                }
            }

            // Answer the peers waiting on a search for this destination
            // (`Transport.py:2433-2455`). This replay is what pays for the batching in
            // `handlePathRequest`: the gate there drops those duplicate requests without an
            // answer of their own, so the announce that resolves the search has to reach every
            // one of them. It goes out as a path response addressed from this instance, because
            // this is the node that now knows the route.
            //
            // Gated on `shouldUpdate` the way upstream nests it inside `if should_add:`—an
            // announce this node declined to learn from isn't an answer it can stand behind.
            // This deliberately keeps path responses, unlike the mesh relay preceding it: the
            // answer to a recursive request usually arrives as one.
            if shouldUpdate, let waiting = takeDiscoveryPathRequest(decoded.destinationHash) {
                var replay = packet
                replay.context = .pathResponse
                replay.headerType = .type2
                replay.transportType = .transport
                replay.transportID = transportInstanceID
                // `new_announce.hops = packet.hops` (`:2454`), where upstream's `packet.hops`
                // already counts this arrival (`:1800`). This port does no inbound increment,
                // so the same wire value is one more than the hop count it stored—the
                // adjustment the known-path answer makes as `entry.hops &+ 1`.
                replay.hops = packet.hops &+ 1
                // Upstream replays to every requesting interface (`:2439`); this port skips the
                // one the announce arrived on. Every other replay here excludes its source—the
                // mesh relay's `iface !== interface`, the local-client replay's
                // `localClientServingInterfaces(excluding:)`—and so does upstream's own
                // local-client replay. The skipped frame can only be redundant: the peer on that
                // interface is the one that just sent this announce.
                for target in waiting.requestingInterfaces where target !== interface {
                    try? transmit(replay, on: target)
                }
            }
            // `# Resolve potential in-flight path requests` (`Transport.py:2478-2481`). The
            // search is over whether or not anyone was waiting on it—but only an announce this
            // node actually learned from ends one, which is why upstream nests this inside `if
            // should_add:` alongside the replay. Releasing the marker for an announce the path
            // table declined would let the next duplicate request start a second fan-out while
            // the first search is still outstanding.
            if shouldUpdate { resolveInflightPathRequest(decoded.destinationHash) }
        } catch {
            // Malformed or unsigned announce—drop silently as RNS does.
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

        // No local destination—relay if this node is transport-enabled, OR the packet
        // is to/from a directly connected local (shared-instance) client. The
        // local-client clauses mirror Python's inbound gate
        // `transport_enabled or from_local_client or for_local_client`
        // (Transport.py:1573): a non-transport shared instance must still carry
        // its clients' traffic—outbound from a client to the mesh
        // (from_local_client) and inbound from the mesh to a client whose
        // destination is one hop away over the serving interface (for_local_client).
        // Only SINGLE packets are transported; PLAIN/GROUP are local-only and
        // Their own dispatchers route LINK-typed packets.
        let fromLocal = fromLocalClient(interface: interface)
        let forLocal: Bool = {
            guard let p = path, p.hops == 0, let nextHop = p.nextHopInterface else { return false }
            return isLocalClientInterface(nextHop)
        }()
        guard transportEnabled || fromLocal || forLocal,
              packet.destinationType == .single else { return }
        guard let path else { return }
        forward(packet, from: interface, path: path)
    }

    // MARK: - Path requests

    /// Broadcast a path request for `destinationHash`.
    ///
    /// Any node within
    /// reach that already knows a path replies by re-broadcasting the
    /// cached announce.
    ///
    /// - Parameters:
    ///   - destinationHash: 16-byte truncated hash of the destination.
    ///   - onInterface: Limit the request to a single interface, or nil to broadcast on all.
    ///   - tag: Optional 16-byte dedup tag. A random tag is generated when nil.
    ///     Mirrors Python's `Transport.request_path(tag=None)`.
    ///   - recursive: When true the request is also forwarded by transport nodes.
    ///     Mirrors Python's `Transport.request_path(recursive=False)`.
    ///     Reserved for future use (Python's recursive handling is
    ///     performed by the receiving transport, not the sender).
    public func requestPath(
        for destinationHash: Data,
        onInterface: (any Interface)? = nil,
        tag: Data? = nil,
        recursive: Bool = false
    ) throws {
        guard destinationHash.count == Constants.truncatedHashLength else { return }
        let tag = tag ?? SecureRandom.bytes(Constants.truncatedHashLength)
        _ = recursive // the receiving transport node handles forwarded recursion
        // Mirrors Python: if transport_enabled: body = destHash + transport_id + tag
        //                 else:                  body = destHash + tag
        let body = transportEnabled
            ? destinationHash + transportInstanceID + tag
            : destinationHash + tag

        // Pre-seed the local dedup entry so this node never re-processes its own
        // request when it bounces back from an interface's local echo.
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
            try transmit(packet, on: iface)
            // Mirrors Python: `interface.sent_path_request(size=len(raw))` after sending
            // (`Transport.py:1601`).
            notifyOutgoingPathRequest(on: iface, size: packet.rawByteCount)
        } else {
            try send(packet)
            for iface in interfaces where iface.isOnline {
                notifyOutgoingPathRequest(on: iface, size: packet.rawByteCount)
            }
        }
    }

    private func handlePathRequest(_ packet: Packet, from interface: Interface) {
        let body = packet.data
        let hashLen = Constants.truncatedHashLength
        // `if not len(packet.data) >= TRUNCATED_HASHLENGTH//8: return` (`Transport.py:1830`).
        // Too short to name a destination, so upstream returns before it looks for a tag and
        // charges nothing.
        guard body.count >= hashLen else { return }
        // `if tag_bytes == None: ... protocol_violation("Tagless path request")`
        // (`:1838-1840`). One byte longer than the preceding case, and upstream treats it very
        // differently: a tag is what makes a request distinguishable from a replay of itself,
        // so nothing can deduplicate a request without one, and upstream declines to act.
        guard body.count > hashLen else {
            notifyProtocolViolation(on: interface)
            return
        }
        let target = Data(body.prefix(hashLen))

        // Extract the optional requesting transport instance ID and tag.
        // Python body shapes: [target||tag] or [target||tx_id||tag]
        let requestorTransportID: Data?
        let rawTag: Data
        if body.count > hashLen * 2 {
            requestorTransportID = Data(body[body.startIndex + hashLen ..< body.startIndex + hashLen * 2])
            rawTag = Data(body.suffix(from: body.startIndex + hashLen * 2))
        } else {
            requestorTransportID = nil
            rawTag = Data(body.suffix(from: body.startIndex + hashLen))
        }
        // `if len(tag_bytes) > RNS.Identity.TRUNCATED_HASHLENGTH//8: tag_bytes = tag_bytes[:...]`
        // (`Transport.py:1842-1843`). The excess isn't merely ignored—it must not reach the
        // dedup key. Keyed on the untruncated bytes, a sender defeats deduplication for free by
        // varying a tail nothing reads, turning one path request into as many recursive
        // fan-outs as it cares to send. The truncated tag is also what gets forwarded, so every
        // hop agrees on the identity of the request.
        // `protocol_violation("Excessive path request tag size")` accompanies the truncation
        // (`:1845`). Upstream truncates and carries on, so this is a counter rather than a
        // rejection—but it's the only trace a peer doing it leaves for the operator.
        let tag: Data
        if rawTag.count > hashLen {
            notifyProtocolViolation(on: interface)
            tag = Data(rawTag.prefix(hashLen))
        } else {
            tag = rawTag
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

        // `interface.received_path_request(size=len(raw))` (`Transport.py:1857`). Upstream
        // counts here, below the length guard, both tag checks and the duplicate check, so the
        // column describes path requests this node acted on. Counting on arrival instead makes
        // it describe path-request-shaped frames, which is a different number on any interface
        // carrying replays.
        notifyIncomingPathRequest(on: interface, size: packet.rawByteCount)

        // `should_ingress_limit = ingress_limited or attached_interface.should_ingress_limit_pr()`
        // (`Transport.py:3427`). Evaluated here, unconditionally, rather than at its single use
        // below: the call advances the burst state machine (it refreshes the sustained stamp
        // and spends cooldown), so gating the call itself on the branch would make the limiter
        // observe only the traffic it's already suppressing.
        //
        // Python's other half—`preprocess_inbound` setting `TC_INGRESS_LIMITED`
        // (`Transport.py:1859`), which `path_request_handler` then passes back in as
        // `ingress_limited`—exists to carry the decision across an inbound queue this port
        // doesn't have. Both paths OR into one flag consumed at one place, so a single
        // evaluation here reaches the same decision.
        let ingressLimited = shouldIngressLimitPR(on: interface)

        // Batch onto a search already running for this destination
        // (`Transport.py:1862-1886`). One inbound request becomes one outbound request per
        // other interface, so a destination that several peers ask for at once would otherwise
        // draw several identical searches. The claim lands before any branch runs, and
        // `answered` releases it again further down—so it only ever collapses requests that
        // arrive while a search is genuinely outstanding.
        //
        // Upstream places this in `inbound()`, ahead of the queue that carries the request to
        // `path_request_handler`; this port has no such queue, so the equivalent position is
        // here: past the tag dedup and the arrival counter, ahead of every answering branch.
        if !registerInflightPathRequest(target) {
            // `if not traffic_class == Transport.TC_INGRESS_LIMITED` (`Transport.py:1870`). A
            // flooding peer's duplicates drop outright rather than enrolling for a replay
            // each—enrolling them would turn the flood into an amplifier again, one announce
            // copy per duplicate, which is the shape the batching exists to prevent.
            if !ingressLimited { batchDiscoveryPathRequest(target, on: interface) }
            return
        }
        // `if answered: ... inflight_path_requests.pop(destination_hash)`
        // (`Transport.py:3595-3599`). Upstream reaches its tail with a flag because its branches
        // fall through; these return, so the release rides on the return itself. Both answering
        // branches set it before they can bail on a cache miss, matching `answered = True` at
        // `:3455` and `:3463`.
        var answered = false
        defer { if answered { resolveInflightPathRequest(target) } }

        if isLocal {
            answered = true
            lock.lock()
            let localDest = registeredDestinations[target]
            lock.unlock()
            if let dest = localDest, dest.identity?.hasPrivateKey == true {
                let pkt = try? Announce.make(for: dest, isPathResponse: true)
                if let pkt { try? transmit(pkt, on: interface) }
            }
            onPathRequested?(target, interface)
            return
        }

        let fromLocal = fromLocalClient(interface: interface)

        // Branch 2 (Python Transport.py:2969): answer from a KNOWN PATH—but only
        // if this node is a transport node OR the request came from a local client. A
        // plain non-transport endpoint must NOT answer path requests naming itself
        // as the relay, or peers route traffic to a node that just drops it.
        // Key off the path table (a real known route), mirroring Python's
        // `destination_hash in path_table`, not merely an overheard cached announce.
        if (transportEnabled || fromLocal), let entry = pathEntry {
            answered = true
            // A known path to the destination exists—this is the branch Python
            // selects on `destination_hash in path_table` (Transport.py:2969). If
            // the cached announce packet has since been evicted, Python logs and
            // simply doesn't answer (get_cached_packet == None, 2974-2975); it
            // doesn't fall through to the forward branches. Mirror that: return
            // without answering rather than dropping into recursive discovery.
            guard let cached = cachedAnnounce else { return }
            // Suppress answer when the next hop along the path IS the requestor
            // (would create a routing loop). Mirrors Python's requestor_transport_id check.
            if let rID = requestorTransportID,
               let nhID = entry.nextHopTransportID,
               nhID == rID {
                return
            }
            var response = cached
            response.context = .pathResponse
            // Python stores announce_hops = packet.hops AFTER its inbound +1. Swift
            // does no inbound increment, so mimic it: hops = stored path hops + 1, so
            // the requester computes the correct hops_to / expected_proof_hops.
            response.hops = entry.hops &+ 1
            // Path responses are always HEADER_2 carrying this instance's transport_id
            // so the requester stores received_from = this node and addresses traffic here.
            response.headerType = .type2
            response.transportType = .transport
            response.transportID = transportInstanceID
            try? transmit(response, on: interface)
            return
        }

        // Branch 3 (Python Transport.py:3032): the request is from a local client
        // and this node couldn't answer it—forward it to the mesh on every
        // other interface (one shared random tag) so an upstream transport can
        // resolve it. Runs regardless of transportEnabled: carrying its clients'
        // path requests onto the network is the whole point of a shared instance.
        if fromLocal {
            let requestTag = SecureRandom.bytes(Constants.truncatedHashLength)
            for iface in interfaces where iface !== interface && iface.isOnline {
                try? requestPath(for: target, onInterface: iface, tag: requestTag)
            }
            return
        }

        // Branch 4 (Python Transport.py:3041): transport-enabled recursive
        // discovery for an unknown destination. The incoming tag is reused on the
        // forwarded requests so cross-hop dedup / loop prevention works.
        // For non-discovering interface modes the request is silently ignored.
        // RNS 1.3.6: `recursive_prs` forces discovery regardless of interface mode.
        //
        // RNS 1.4.1 additionally lets BOUNDARY-mode interfaces trigger discovery,
        // but restricts which interfaces the recursive request may go out on:
        // only boundary and gateway peers (`BOUNDARY_SEARCH_MODES`). Python:
        //
        //     elif attached_interface.mode == MODE_BOUNDARY:
        //         should_search_for_unknown = True
        //         search_mode_filter        = BOUNDARY_SEARCH_MODES
        //     ...
        //     if search_mode_filter and not interface.mode in search_mode_filter: continue
        //
        // The precedence matters: `recursive_prs` and `DISCOVER_PATHS_FOR` are
        // checked first, so a boundary interface that also sets recursive_prs
        // searches unfiltered.
        var searchModeFilter: Set<InterfaceMode>? = nil
        var shouldDiscover = false
        if transportEnabled {
            if interface.recursivePrs || InterfaceMode.discoverPathsFor.contains(interface.mode) {
                shouldDiscover = true
            } else if interface.mode == .boundary {
                shouldDiscover = true
                searchModeFilter = InterfaceMode.boundarySearchModes
            }
        }
        if shouldDiscover {
            // "Abort recursive path request if receiving interface has PR burst active, or
            // should otherwise ingress limit path requests" (`Transport.py:3543-3550`).
            //
            // The gate is on amplification, not on usefulness: the preceding branches still answer
            // from a local destination or a known path while limited. It's only the fan-out—one
            // inbound request becoming one outbound request per interface—that a flooding
            // peer must not get.
            if ingressLimited { return }

            // "There is already a waiting path request … on behalf of path request"
            // (`Transport.py:3541-3542`). The preceding in-flight marker collapses requests
            // that arrive *during* a search; this collapses the case it can't see. The two tables
            // age on different clocks, so on a slow network—where the waiting entry's timeout
            // is a round trip on the slowest link and the marker's is a flat 45 seconds—the
            // marker expires first and a fresh request reaches this branch while the original
            // search is still outstanding. Engaging the entry claims the search; finding it
            // already engaged means someone else is running it.
            if engageDiscoveryPathRequest(target, on: interface) { return }

            let now = Date().timeIntervalSince1970
            for iface in interfaces where iface !== interface && iface.isOnline && iface.isRoutingEndpoint {
                if let filter = searchModeFilter, !filter.contains(iface.mode) { continue }
                if shouldEgressLimitPR(on: iface, now: now) { continue }
                try? requestPath(for: target, onInterface: iface, tag: tag)
            }
            return
        }

        // Branch 5 (Python Transport.py:3069): this node isn't the client's origin, but
        // this node serves local clients—forward the request down to them so a connected
        // client that owns the destination can answer.
        for iface in localClientServingInterfaces(excluding: interface) {
            try? requestPath(for: target, onInterface: iface)
        }
    }

    // MARK: - Packet hashlist (replay/loop prevention)

    /// The six contexts Python answers `True` for before it ever reads the hashlist
    /// (`Transport.py:1635-1640`).
    ///
    /// Every one of them repeats legitimately on the wire—a keepalive repeats until the peer
    /// answers, a resource part repeats when its window times out, a channel message repeats
    /// until the far side acknowledges it. The hashable part of a packet excludes the hop
    /// count, so a retransmission hashes identically to the frame it retransmits; without
    /// this exemption the first copy would filter every copy after it.
    private static let filterExemptContexts: Set<Packet.Context> = [
        .keepalive, .resourceRequest, .resourceProof, .resource, .cacheRequest, .channel,
    ]

    /// The stack's live filter: Python's `Transport.packet_filter` and the
    /// `add_packet_hash` its caller reaches afterwards, merged into one call.
    ///
    /// Returns `false` for a packet the stack should drop—a duplicate, or one of the shapes
    /// `applyFilter` rejects outright. `handleIncoming` counts every `false` as a packet
    /// filter hit, which is what `interface.packet_filter_hit()` does upstream
    /// (`Transport.py:1795`).
    func filterAndRecord(packet: Packet) -> Bool {
        applyFilter(to: packet, recording: true)
    }

    /// Python's `Transport.packet_filter(packet)` verbatim: the same verdict `filterAndRecord`
    /// reaches, without recording the packet.
    ///
    /// Both spellings run this one implementation, so the public filter can't answer
    /// differently from the filter the stack actually applies.
    public func packetFilter(_ packet: Packet) -> Bool {
        applyFilter(to: packet, recording: false)
    }

    /// `Transport.packet_filter` (`Transport.py:1623-1680`), in Python's order.
    ///
    /// The order carries meaning: the context exemptions precede the PLAIN and GROUP
    /// ceilings, and both of those return before the duplicate check, so the filter never
    /// deduplicates a PLAIN or a GROUP packet.
    ///
    /// Python counts a protocol violation at five points in this function, and all five are
    /// unreachable: an `if packet.receiving_interface` guards each one, `Packet.__init__`
    /// leaves that `None` (`Packet.py:166`), `unpack()` never sets it, and the single caller
    /// assigns it only after the filter returns (`Transport.py:1795-1799`). Counting them
    /// here would make this port's `Violatns.` column disagree with the daemon it mirrors,
    /// so it deliberately doesn't—see `RNStatusRenderer`.
    private func applyFilter(to packet: Packet, recording: Bool) -> Bool {
        // A shared instance filters on behalf of the clients attached to it, so a client
        // repeating that work only drops packets the instance already vetted. Python's
        // `add_packet_hash` is likewise a no-op on a client (`Transport.py:1619-1621`),
        // which is why this path records nothing either.
        if isConnectedToSharedInstance { return true }

        // Filter packets explicitly addressed to a *different* transport instance.
        // A HEADER_2 packet carries the next-hop transport_id; if that names another node
        // (and it isn't a flooded announce), that node owns the packet—dropping it
        // here prevents duplicate forwarding and routing loops on shared media with ≥2
        // transport nodes.
        if packet.packetType != .announce,
           let tid = packet.transportID,
           tid != transportInstanceID {
            return false
        }

        if Self.filterExemptContexts.contains(packet.context) {
            if recording { rememberPacketHash(packet) }
            return true
        }

        // An announce only means anything for a SINGLE destination, so a PLAIN or GROUP one
        // is a malformed frame at any hop count and the following ceiling never applies.
        if packet.destinationType == .plain || packet.destinationType == .group {
            if packet.packetType == .announce { return false }
            // Allows hops=0 (direct) and hops=1 (one relay hop, for example, path requests).
            if packet.hops > 1 { return false }
            if recording { rememberPacketHash(packet) }
            return true
        }

        guard let hash = Self.packetHashlistKey(packet) else { return false }
        // Resolved before this path takes `hashlistLock`, because it reads `linkRoutes`
        // under `lock`; the two are only ever acquired in that order.
        let remembers = recording && shouldRememberHash(of: packet)
        hashlistLock.lock()
        defer { hashlistLock.unlock() }
        // Two-generation dedup: drop if seen in current or previous window.
        if packetHashlist.contains(hash) || packetHashlistPrev.contains(hash) {
            // The filter passes SINGLE announces more than once, so that path tables can
            // update via multiple paths. Anything else reaching here with a seen hash is an
            // announce for a LINK destination, which is a malformed frame.
            if packet.packetType == .announce && packet.destinationType == .single {
                return true
            }
            return false
        }
        if remembers { insertPacketHashLocked(hash) }
        return true
    }

    /// Whether this packet is one the hashlist keeps.
    ///
    /// Python's `preprocess_inbound` clears `remember_packet_hash` in two cases
    /// (`Transport.py:1942-1957`), and both are here:
    ///
    /// - The destination is a link this node carries for someone else. On shared media such
    ///   a packet can arrive before this node's turn to route it comes around; storing the
    ///   hash then would filter the copy it must forward, and link transport through this
    ///   node would stall.
    /// - The packet is a link-request proof, which stays out of the list until this node is
    ///   sure the proof isn't destined for somewhere else in the routing chain.
    ///
    /// This port also excludes the link *request*, which Python doesn't; an LRR carries an
    /// ephemeral public key per attempt, so no repeat ever reaches upstream's filter.
    ///
    /// Takes `lock` to read `linkRoutes`, so callers must not already hold `hashlistLock`.
    private func shouldRememberHash(of packet: Packet) -> Bool {
        guard packet.packetType != .linkRequest, packet.context != .lrproof else { return false }
        lock.lock(); defer { lock.unlock() }
        return linkRoutes[packet.destinationHash] == nil
    }

    /// Records a packet that returned early, before the duplicate check.
    ///
    /// Python reaches its `add_packet_hash` for these too—the call sits in `preprocess_inbound`,
    /// past the filter (`Transport.py:1959-1961`), so the list holds an exempt or PLAIN packet
    /// even though the filter never consults the entry. Callers must not hold `hashlistLock`.
    private func rememberPacketHash(_ packet: Packet) {
        guard shouldRememberHash(of: packet), let hash = Self.packetHashlistKey(packet) else { return }
        hashlistLock.lock()
        defer { hashlistLock.unlock() }
        insertPacketHashLocked(hash)
    }

    /// Adds `hash` to the current generation, rotating when it fills.
    ///
    /// Caller holds the lock.
    private func insertPacketHashLocked(_ hash: Data) {
        packetHashlist.insert(hash)
        if packetHashlist.count >= hashlistMaxSize {
            packetHashlistPrev = packetHashlist
            packetHashlist = []
        }
    }

    // MARK: - Packet hashlist persistence

    /// Persist the current packet hashlist to `storage/packet_hashlist.raw`.
    ///
    /// `for packet_hash in Transport.packet_hashlist.copy(): file.write(packet_hash)`—`Transport.py:3315-3323`.
    /// The hashes themselves, concatenated: no delimiters, no length
    /// prefix, no encoding. The reader recovers records by fixed width, so the framing *is* the
    /// hash length.
    public func savePacketHashlist(to url: URL) throws {
        hashlistLock.lock()
        let snapshot = packetHashlist.union(packetHashlistPrev)
        hashlistLock.unlock()
        var raw = Data()
        raw.reserveCapacity(snapshot.count * Constants.fullHashLength)
        var skipped = 0
        for hash in snapshot {
            // A record of the wrong width isn't a short record, it's a shifted file: every
            // hash after it decodes as two halves of its neighbours. The live filter only ever
            // inserts `fullHash(hashablePart())`, so this can't fire from the network—but it
            // is reported rather than dropped in silence, since a silent drop here reads on disk
            // exactly like a hashlist that was simply smaller.
            guard hash.count == Constants.fullHashLength else { skipped += 1; continue }
            raw.append(hash)
        }
        if skipped > 0 {
            Reticulum.log("Skipped \(skipped) packet hashlist entr(ies) that are not "
                          + "\(Constants.fullHashLength) bytes; the file is framed by hash "
                          + "length alone (Transport.py:3323)", level: .error)
        }
        try raw.write(to: url, options: .atomic)
    }

    /// Load a previously persisted packet hashlist and merge into the current set.
    ///
    /// `packet_hash = file.read(hashlen); if len(packet_hash) == hashlen: add … else: done`
    /// (`Transport.py:246-250`)—fixed-width records until a short read ends the file, so a
    /// torn write gives up its trailing partial record and keeps everything before it. A missing
    /// file is silently ignored, as `:244`'s `isfile` gate does.
    public func loadPacketHashlist(from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let raw = try Data(contentsOf: url)
        hashlistLock.lock()
        defer { hashlistLock.unlock() }
        var cursor = raw.startIndex
        while raw.distance(from: cursor, to: raw.endIndex) >= Constants.fullHashLength {
            let next = raw.index(cursor, offsetBy: Constants.fullHashLength)
            packetHashlist.insert(Data(raw[cursor..<next]))
            cursor = next
        }
    }

    /// The one key the hashlist is keyed on: the **full** 32-byte hash of the packet's hashable
    /// part, as Python stores `packet.packet_hash` (`Packet.py:342-344`) and `packet_filter`
    /// compares it (`Transport.py:1417`).
    ///
    /// Every reader and writer of the hashlist must go
    /// through this—`bugs/038` was the public filter computing the 16-byte truncated hash
    /// against a list of 32-byte entries, so "seen" was always false.
    private static func packetHashlistKey(_ packet: Packet) -> Data? {
        guard let hashable = try? packet.hashablePart() else { return nil }
        return Hashes.fullHash(hashable)
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
    ///
    /// Mirrors Python's `Transport.packet_prove(packet, destination)`.
    public func provePacket(_ packet: Packet, from sourceInterface: any Interface, destination: Destination) {
        sendProof(for: packet, from: sourceInterface, destination: destination)
    }

    /// Send an explicit delivery proof for `packet` back on the interface it
    /// arrived on.
    ///
    /// Wire format: `[32-byte full hash][64-byte Ed25519 sig]`.
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
        try? transmit(proof, on: sourceInterface)
    }

    // MARK: - Announce queue helpers

    /// Decide whether a relayed announce should be transmitted on an outbound interface.
    ///
    /// Mirrors Python `Transport.outbound()` announce-mode filtering as reworked
    /// in RNS 1.3.7 (the `if packet.attached_interface == None:` block for
    /// ANNOUNCE packets).
    ///
    /// Parameters:
    /// - `outboundMode`: mode of the interface being considered for transmission.
    /// - `nextHopMode`: mode of the next-hop interface toward the announce's
    ///   source (the interface it arrived on). `nil` means Python's
    ///   `from_interface == None`—no known next hop.
    /// - `localDestination`: true when the announce's destination is registered
    ///   locally (Python's `destinations_map` lookup). Instance-local
    ///   destinations bypass the roaming/boundary/internal mode blocks.
    /// - `announcesFromInternal`: the outbound interface's
    ///   `announces_from_internal` setting.
    ///
    /// Rules (checked on the **outbound** interface, not the receiving interface):
    ///
    /// - **No next hop** (and not local): block—nowhere to attribute the announce.
    /// - **`announces_from_internal == false` + internal next hop** (and not
    ///   local): block relaying announces that came in from an internal interface.
    /// - **AP outbound**: always block—AP-mode interfaces are "last-mile".
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
        announcesFromInternal: Bool = true,
        nextHopAnnouncesToInternal: Bool? = nil
    ) -> Bool {
        // Top-level guards—only apply when the destination isn't instance-local.
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
                // RNS 1.4.1 `announces_to_internal`: read off the *next-hop*
                // (source-side) interface, this opts that interface's announces
                // into internal-mode interfaces and short-circuits the
                // boundary block below. Python: `if
                // from_interface.announces_to_internal == True: pass`, so only
                // an explicit true counts—nil/false fall through.
                if nextHopAnnouncesToInternal == true { return true }
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
            // FULL, GATEWAY, POINT_TO_POINT—forward freely.
            return true
        }
    }

    /// Extract the emission timestamp from an announce's random hash
    /// (bytes [5..9] = 5-byte big-endian unix seconds).
    ///
    /// Matches Python's
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
    ///
    /// Mirrors Python's `random_blob = packet.data[KEYSIZE+NAME_HASH : +10]`.
    /// Returns `nil` if the announce body is too short.
    private func announceRandomBlob(_ packet: Packet) -> Data? {
        let bytes = Array(packet.data)
        let start = Constants.keySize + Constants.nameHashLength
        guard bytes.count >= start + 10 else { return nil }
        return Data(bytes[start ..< start + 10])
    }

    /// Drain any queued announces onto their respective interfaces.
    ///
    /// Called from the jobs loop every `jobInterval` seconds.
    private func drainAnnounceQueues() {
        let now = Date().timeIntervalSince1970
        queueLock.lock()
        let snapshot = announceQueues
        queueLock.unlock()
        lock.lock()
        let ifaceSnapshot = interfaces
        lock.unlock()
        for (name, queue) in snapshot {
            guard let iface = ifaceSnapshot.first(where: { $0.name == name && $0.isOnline }) else {
                continue
            }
            let packets = queue.drain(now: now, bitrate: iface.bitrate,
                                      announceCap: iface.announceCap)
            for pkt in packets { try? transmit(pkt, on: iface) }
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
        guard let outbound = path.nextHopInterface, outbound.isOnline else { return }
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
        //     directly reachable on the outbound interface—strip the
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
        // interfaces don't race: if the proof arrives in the same call stack (for example,
        // in-process loopback tests), the entry must already be present.
        // Mirrors Python: Transport.reverse_table[packet.getTruncatedHash()] = entry.
        if let key = try? Hashes.truncatedHash(packet.hashablePart()) {
            reverseTableLock.lock()
            reverseTable[key] = (receiveIface: sourceInterface, outboundIface: outbound)
            reverseTableLock.unlock()
        }

        try? transmit(forwarded, on: outbound)
    }

    // MARK: - Tunnel synthesis

    /// Send a tunnel-synthesize packet on `interface` to establish this transport as
    /// a tunnel endpoint for that interface.
    ///
    /// Matches Python `Transport.synthesize_tunnel`.
    ///
    /// Wire layout of the DATA payload (176 bytes):
    ///   [  0.. 63] 64 bytes: combined public key (X25519 + Ed25519)
    ///   [ 64.. 95] 32 bytes: SHA-256 of interface name ("interface hash")
    ///   [ 96..111] 16 bytes: random hash (replay-prevention nonce)
    ///   [112..175] 64 bytes: Ed25519 signature over bytes 0..111
    /// Serve every interface that has asked for a tunnel since the last sweep.
    ///
    /// Python synthesizes at two moments: a startup pass over every interface wanting one
    /// (`Transport.py:428-433`) and a direct call after each successful redial
    /// (`TCPInterface.py:298`, `I2PInterface.py:533`). This port's interfaces hold no back-
    /// reference to their transport and connect asynchronously *after* `register`—so the
    /// registration-time check saw nothing, and a per-connect direct call has nowhere to
    /// originate. The jobs loop sweeps instead, which covers startup, connect and reconnect
    /// with one trigger; `synthesizeTunnel` clears the flag (`Transport.py:2385`), so a served
    /// request isn't repeated and a fresh reconnect asks again.
    public func synthesizePendingTunnels() {
        lock.lock()
        let snapshot = interfaces
        lock.unlock()
        for iface in snapshot where iface.wantsTunnel {
            synthesizeTunnel(iface)
        }
    }

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
        try? transmit(packet, on: interface)
        interface.wantsTunnel = false
    }

    /// Handle an incoming tunnel-synthesize packet.
    ///
    /// Validates the signature and
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

        // Upstream's `protocol_violation("Invalid tunnel synthesis packet")`
        // (`Transport.py:2808-2810`) stays deliberately unported, because it's unreachable.
        // It fires from the handler's `except`, and with the length already checked nothing
        // inside can raise: `load_public_key` swallows its own exception (`Identity.py`), and
        // neither X25519 nor Ed25519 rejects a 32-byte value at construction—Ed25519 defers
        // point decoding to verification time. So every correctly sized frame loads a key,
        // reaches `validate`, and either matches or quietly doesn't.
        //
        // CryptoKit behaves the same way (verified against 2000 random values per curve for
        // both curves in both libraries), so this initializer can only throw on a wrong length,
        // which the preceding guard already excludes. Counting a violation here would charge peers
        // for frames upstream never complains about.
        guard let remoteIdentity = try? Identity(publicKeyBytes: Data(publicKey)) else { return }
        // A failing signature is ordinary traffic on a shared medium: upstream reaches
        // `validate`, gets False, and falls off the end of the handler without raising.
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
            tunnels[tunnelID]?.iface = interface
            tunnels[tunnelID]?.expires = expires
        }
        interface.tunnelID = tunnelID
    }
}
