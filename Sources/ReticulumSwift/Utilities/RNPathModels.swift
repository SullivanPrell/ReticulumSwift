import Foundation

// MARK: - Path table entry

/// One row of `rnpath -t`, in the shape Python's `Reticulum.get_path_table()` produces.
///
/// Python reference: `RNS/Reticulum.py:1470-1488`. The entry dict is
/// `{"hash", "timestamp", "via", "hops", "expires", "interface"}` and that **insertion
/// order is observable** — `rnpath -t -j` emits `json.dumps` of these dicts directly.
///
/// This is a separate type from ``Transport/PathTableEntry`` for four reasons:
///
/// 1. `Transport.PathTableEntry.lastHeard` / `.expires` are `Date`, while Python's
///    `timestamp` / `expires` are float seconds — and the JSON output prints the float.
/// 2. A remote `/path` response arrives as MsgPack and must decode into the same type the
///    local path produces, so both feed one renderer.
/// 3. Python's `via` is **never** `None`: `Transport.py:1796` stores
///    `received_from = packet.destination_hash` for a direct peer, where Swift stores `nil`.
///    ``resolvedVia`` applies that substitution in exactly one place.
/// 4. `Transport.PathTableEntry.interfaceName` carries `Interface.name` (the short config
///    section name) where Python carries `str(receiving_interface)` — Swift's
///    ``Interface/displayName``. Because the interface string is the *primary sort key*,
///    resolving it late would order the table correctly-looking but wrong.
public struct RNPathTableEntry: Equatable {

    /// Python key `"hash"`.
    public var destinationHash: Data
    /// Python key `"timestamp"` — last-heard, seconds since the epoch.
    public var timestamp: TimeInterval
    /// Python key `"via"`. Nil only before ``resolvedVia`` is consulted; Python never emits null.
    public var via: Data?
    /// Python key `"hops"`.
    public var hops: UInt8
    /// Python key `"expires"` — seconds since the epoch.
    public var expires: TimeInterval
    /// Python key `"interface"` — `str(receiving_interface)`, i.e. `Interface.displayName`.
    public var interfaceName: String

    public init(destinationHash: Data,
                timestamp: TimeInterval,
                via: Data?,
                hops: UInt8,
                expires: TimeInterval,
                interfaceName: String) {
        self.destinationHash = destinationHash
        self.timestamp = timestamp
        self.via = via
        self.hops = hops
        self.expires = expires
        self.interfaceName = interfaceName
    }

    /// Bridge from the library's own path table.
    ///
    /// - Parameter transport: used to resolve `entry.interfaceName` (an `Interface.name`) to
    ///   the interface's `displayName`, matching Python's `str(receiving_interface)`.
    ///   When no registered interface matches, the stored short name is kept.
    public init(_ entry: Transport.PathTableEntry, resolvingNamesWith transport: Transport?) {
        let resolved = transport?.interfaces.first { $0.name == entry.interfaceName }?.displayName
        self.init(destinationHash: entry.destinationHash,
                  timestamp: entry.lastHeard.timeIntervalSince1970,
                  via: entry.via,
                  hops: entry.hops,
                  expires: entry.expires.timeIntervalSince1970,
                  interfaceName: resolved ?? entry.interfaceName)
    }

    /// Python's `path["via"]`, which is never `None` (Transport.py:1796 stores the
    /// destination hash itself when an announce carries no transport id).
    public var resolvedVia: Data { via ?? destinationHash }

    /// MsgPack shape in Python's key order — what a Python `/path` handler sends back.
    public func msgpackValue() -> MsgPack.Value {
        .map([
            (.string("hash"),      .bytes(destinationHash)),
            (.string("timestamp"), .double(timestamp)),
            (.string("via"),       via.map { .bytes($0) } ?? .nil),
            (.string("hops"),      .uint(UInt64(hops))),
            (.string("expires"),   .double(expires)),
            (.string("interface"), .string(interfaceName)),
        ])
    }

    /// Decode one entry from a `/path` or RPC `path_table` reply.
    ///
    /// Tolerant about integer encoding: the MsgPack decoder returns `.uint` for positive
    /// fixints (0x00…0x7F) and `.int` for the negative range, and remote peers may send
    /// either for `hops`.
    public static func decode(_ value: MsgPack.Value) -> RNPathTableEntry? {
        guard let fields = value.asDictionary,
              let hash = fields["hash"]?.asData,
              let hops = fields["hops"]?.asInt else { return nil }
        return RNPathTableEntry(
            destinationHash: hash,
            timestamp: fields["timestamp"]?.asDouble ?? 0,
            via: fields["via"]?.asData,
            hops: UInt8(clamping: hops),
            expires: fields["expires"]?.asDouble ?? 0,
            interfaceName: fields["interface"]?.asString ?? ""
        )
    }

    /// Decode a whole `/path` `"table"` response.
    public static func decodeTable(_ value: MsgPack.Value) -> [RNPathTableEntry]? {
        guard let elements = value.asArray else { return nil }
        return elements.compactMap { decode($0) }
    }

    /// Python: `sorted(table, key=lambda e: (e["interface"], e["hops"]))` (rnpath.py:254).
    ///
    /// Applied to the **local** table only — the remote branch prints the server's order
    /// unchanged.
    ///
    /// Python's `sorted` is stable, so rows sharing an interface *and* a hop count keep the
    /// order `get_path_table()` produced. Swift's `sort` is not stable, so the input index
    /// is used as the final tie-break to reproduce that. This matters in practice: over RPC
    /// the daemon sends an ordered array, and a hash-based tie-break would reorder every
    /// multi-row group relative to Python.
    public static func sortedForDisplay(_ entries: [RNPathTableEntry]) -> [RNPathTableEntry] {
        entries.enumerated().sorted { lhs, rhs in
            if lhs.element.interfaceName != rhs.element.interfaceName {
                return lhs.element.interfaceName < rhs.element.interfaceName
            }
            if lhs.element.hops != rhs.element.hops { return lhs.element.hops < rhs.element.hops }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

// MARK: - Rate table entry

/// One row of `rnpath -r`, in the shape Python's `Reticulum.get_rate_table()` produces.
///
/// Python reference: `RNS/Reticulum.py:1490-1509` —
/// `{"hash", "last", "rate_violations", "blocked_until", "timestamps"}`, again in an
/// observable insertion order because `-r -j` dumps it directly.
public struct RNPathRateEntry: Equatable {

    public var destinationHash: Data
    public var last: TimeInterval
    public var rateViolations: Int
    public var blockedUntil: TimeInterval
    public var timestamps: [TimeInterval]

    public init(destinationHash: Data,
                last: TimeInterval,
                rateViolations: Int,
                blockedUntil: TimeInterval,
                timestamps: [TimeInterval]) {
        self.destinationHash = destinationHash
        self.last = last
        self.rateViolations = rateViolations
        self.blockedUntil = blockedUntil
        self.timestamps = timestamps
    }

    /// Bridge from ``Transport/RateTableEntry``. Unlike the path table, every field is
    /// already a `TimeInterval` or `Int`, so no `Date` conversion is needed.
    public init(_ entry: Transport.RateTableEntry) {
        self.init(destinationHash: entry.destinationHash,
                  last: entry.last,
                  rateViolations: entry.rateViolations,
                  blockedUntil: entry.blockedUntil,
                  timestamps: entry.timestamps)
    }

    public func msgpackValue() -> MsgPack.Value {
        .map([
            (.string("hash"),            .bytes(destinationHash)),
            (.string("last"),            .double(last)),
            (.string("rate_violations"), .uint(UInt64(max(0, rateViolations)))),
            (.string("blocked_until"),   .double(blockedUntil)),
            (.string("timestamps"),      .array(timestamps.map { .double($0) })),
        ])
    }

    public static func decode(_ value: MsgPack.Value) -> RNPathRateEntry? {
        guard let fields = value.asDictionary,
              let hash = fields["hash"]?.asData else { return nil }
        let timestamps = (fields["timestamps"]?.asArray ?? []).compactMap { $0.asDouble }
        return RNPathRateEntry(
            destinationHash: hash,
            last: fields["last"]?.asDouble ?? 0,
            rateViolations: fields["rate_violations"]?.asInt ?? 0,
            blockedUntil: fields["blocked_until"]?.asDouble ?? 0,
            timestamps: timestamps
        )
    }

    public static func decodeTable(_ value: MsgPack.Value) -> [RNPathRateEntry]? {
        guard let elements = value.asArray else { return nil }
        return elements.compactMap { decode($0) }
    }

    /// Python: `sorted(table, key=lambda e: e["last"])` (rnpath.py:326) — applied in **both**
    /// the local and the remote case, unlike the path table's sort. Stable, for the same
    /// reason as ``RNPathTableEntry/sortedForDisplay(_:)``.
    public static func sortedByLast(_ entries: [RNPathRateEntry]) -> [RNPathRateEntry] {
        entries.enumerated().sorted { lhs, rhs in
            if lhs.element.last != rhs.element.last { return lhs.element.last < rhs.element.last }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

// MARK: - Blackhole entry

/// One row of `rnpath -b` / `rnpath -p`.
///
/// Python reference: `Transport.blackholed_identities` — a dict keyed by 16-byte identity
/// hash whose values are `{"source": bytes|None, "until": float|None, "reason": str|None}`
/// (Transport.py:3578-3584, and `Reticulum.get_blackholed_identities()`).
public struct RNPathBlackholeEntry: Equatable {

    public var identityHash: Data
    /// Identity hash of whoever issued the blackhole, or nil.
    public var source: Data?
    /// Expiry, seconds since the epoch. Nil **or zero** both render as "indefinitely",
    /// because Python tests `if until:` rather than `if until is not None:`.
    public var until: TimeInterval?
    public var reason: String?

    public init(identityHash: Data, source: Data?, until: TimeInterval?, reason: String?) {
        self.identityHash = identityHash
        self.source = source
        self.until = until
        self.reason = reason
    }

    public init(identityHash: Data, entry: Transport.BlackholeEntry) {
        self.init(identityHash: identityHash,
                  source: entry.source,
                  until: entry.until,
                  reason: entry.reason)
    }

    /// Decode the whole `blackholed_identities` map — the RPC reply and the `/list`
    /// response body share this shape.
    ///
    /// A legacy `{bin16 → true}` peer (which Swift's ``RPCServer`` no longer produces) is
    /// tolerated and yields entries with nil source/until/reason rather than being dropped.
    ///
    /// Wire order is preserved: MsgPack maps decode to an ordered pair array, and Python
    /// iterates the resulting dict in that same insertion order, so the printed lines match.
    public static func decodeList(_ value: MsgPack.Value) -> [RNPathBlackholeEntry]? {
        guard case .map(let pairs) = value else { return nil }
        var entries: [RNPathBlackholeEntry] = []
        for (key, item) in pairs {
            guard case .bytes(let hash) = key else { continue }
            let fields = item.asDictionary ?? [:]
            entries.append(RNPathBlackholeEntry(
                identityHash: hash,
                source: fields["source"]?.asData,
                until: fields["until"]?.asDouble,
                reason: fields["reason"]?.asString
            ))
        }
        return entries
    }

    /// Bridge from the dictionary both ``Reticulum/getBlackholedIdentities()`` and
    /// ``RPCClient/blackholedIdentities()`` return.
    ///
    /// Python iterates a dict in insertion order, so its `-b` line order is stable across
    /// runs of the same daemon. Swift's `Dictionary` is unordered, so a deterministic order
    /// is imposed here — a documented divergence, chosen over letting scripted consumers
    /// see the lines churn between invocations.
    public static func list(from table: [Data: Transport.BlackholeEntry]) -> [RNPathBlackholeEntry] {
        sorted(table.map { RNPathBlackholeEntry(identityHash: $0.key, entry: $0.value) })
    }

    /// Deterministic ordering by identity hash — see ``list(from:)``.
    public static func sorted(_ entries: [RNPathBlackholeEntry]) -> [RNPathBlackholeEntry] {
        entries.sorted { $0.identityHash.lexicographicallyPrecedes($1.identityHash) }
    }
}
