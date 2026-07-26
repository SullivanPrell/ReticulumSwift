import Foundation

/// A decoded view of the `interface_stats` dictionary `rnstatus` renders.
///
/// Python reference: `RNS/Reticulum.py`, `get_interface_stats()` (the builder) and
/// `RNS/Utilities/rnstatus.py:361-675` (the consumer).
///
/// ## Why the raw pairs are kept
///
/// `rnstatus` branches on **presence** (`if "noise_floor" in ifstat`) for eighteen fields
/// and separately on **value** (`ifstat["noise_floor"] != None`). Those two tests select
/// different output: a present-but-nil `cpu_temp` prints a line, an absent one prints
/// nothing. Decoding into a struct of `Optional`s collapses the distinction, so this type
/// deliberately keeps the ordered `[(String, MsgPack.Value)]` pairs and exposes
/// ``has(_:)`` alongside the typed readers.
public struct RNStatusInterfaceStats {

    /// The interface map exactly as it arrived, in wire order.
    public let pairs: [(String, MsgPack.Value)]

    private let index: [String: MsgPack.Value]

    /// Decode one element of the top-level `interfaces` array.
    /// Returns nil for anything that is not a msgpack map.
    public init?(_ value: MsgPack.Value) {
        guard case .map(let raw) = value else { return nil }
        var ordered: [(String, MsgPack.Value)] = []
        var table: [String: MsgPack.Value] = [:]
        ordered.reserveCapacity(raw.count)
        table.reserveCapacity(raw.count)
        for (key, element) in raw {
            guard case .string(let name) = key else { continue }
            ordered.append((name, element))
            table[name] = element
        }
        self.pairs = ordered
        self.index = table
    }

    // MARK: - Accessors

    /// Python: `"key" in ifstat`. True even when the value is msgpack nil.
    public func has(_ key: String) -> Bool { index[key] != nil }

    /// The raw value, or nil when the key is absent.
    public func raw(_ key: String) -> MsgPack.Value? { index[key] }

    public func string(_ key: String) -> String? { index[key]?.asString }
    public func int(_ key: String)    -> Int?    { index[key]?.asInt }
    public func double(_ key: String) -> Double? { index[key]?.asDouble }
    public func bool(_ key: String)   -> Bool?   { index[key]?.asBool }
    public func data(_ key: String)   -> Data?   { index[key]?.asData }

    // MARK: - Derived

    /// Python: `name = ifstat["name"]`.
    public var name: String { string("name") ?? "" }

    /// Python: `ss = "Up" if ifstat["status"] else "Down"` (rnstatus.py:418).
    public var isUp: Bool { bool("status") ?? false }

    /// Python: `ifstat["mode"]`, an `Interface.MODE_*` constant.
    public var mode: UInt8 { UInt8(clamping: int("mode") ?? 0) }

    /// Python: the `modestr` chain at rnstatus.py:421-427. Every unrecognised value —
    /// including `MODE_FULL` itself — falls through to `"Full"`.
    public var modeDescription: String {
        switch mode {
        case InterfaceMode.accessPoint.rawValue:   return "Access Point"
        case InterfaceMode.pointToPoint.rawValue:  return "Point-to-Point"
        case InterfaceMode.roaming.rawValue:       return "Roaming"
        case InterfaceMode.boundary.rawValue:      return "Boundary"
        case InterfaceMode.gateway.rawValue:       return "Gateway"
        case InterfaceMode.internal.rawValue:      return "Internal"
        default:                                   return "Full"
        }
    }
}

// MARK: - Top level

/// The whole `interface_stats` dictionary.
public struct RNStatusStats {

    /// The top-level map in wire order — `interfaces`, `rxb`, `txb`, `rxs`, `txs`,
    /// optionally the transport block, then `rss` last.
    public let pairs: [(String, MsgPack.Value)]

    /// Decoded `interfaces` array, in wire order.
    public let interfaces: [RNStatusInterfaceStats]

    private let index: [String: MsgPack.Value]

    public var rxb: Int    { index["rxb"]?.asInt ?? 0 }
    public var txb: Int    { index["txb"]?.asInt ?? 0 }
    public var rxs: Double { index["rxs"]?.asDouble ?? 0 }
    public var txs: Double { index["txs"]?.asDouble ?? 0 }
    public var rss: Int?   { index["rss"]?.asInt }

    /// Python: `"transport_id" in stats and stats["transport_id"] != None` (rnstatus.py:663).
    /// Note the *value* test as well as presence — Python emits `transport_id` only when
    /// transport is enabled, but a nil value must render identically to an absent key.
    public var hasTransportID: Bool { transportID != nil }

    public var transportID: Data?     { index["transport_id"]?.asData }
    public var networkID: Data?       { index["network_id"]?.asData }
    public var probeResponder: Data?  { index["probe_responder"]?.asData }
    public var transportUptime: TimeInterval? { index["transport_uptime"]?.asDouble }

    /// The raw top-level value, or nil when the key is absent. Used where the int-vs-float
    /// wire type matters (`prettytime` renders `12s` for an int and `12.0s` for a float).
    public func raw(_ key: String) -> MsgPack.Value? { index[key] }

    /// Decode the map returned by `get_interface_stats()`.
    /// Returns nil for anything without an `interfaces` array — which is also the guard
    /// that catches a malformed `/status` response from a remote instance.
    public init?(_ value: MsgPack.Value) {
        guard case .map(let raw) = value else { return nil }
        var ordered: [(String, MsgPack.Value)] = []
        var table: [String: MsgPack.Value] = [:]
        for (key, element) in raw {
            guard case .string(let name) = key else { continue }
            ordered.append((name, element))
            table[name] = element
        }
        guard let list = table["interfaces"]?.asArray else { return nil }
        self.pairs = ordered
        self.index = table
        self.interfaces = list.compactMap { RNStatusInterfaceStats($0) }
    }

    // MARK: - Sorting

    /// Python: the `if sorting == …` chain at rnstatus.py:362-387.
    ///
    /// Two properties matter and are easy to get wrong:
    /// - The **default direction is descending** (`reverse=not sort_reverse`); `-r` makes
    ///   it ascending.
    /// - Python's sort is **stable in both directions** — `reverse=True` preserves the
    ///   original order of equal elements. Swift's `sort` gives no such guarantee, so this
    ///   decorates each element with its input index and breaks ties on that, ascending,
    ///   regardless of direction.
    ///
    /// An unrecognised token leaves the order untouched, matching Python's silent no-op.
    public func sortedInterfaces(by sort: RNStatusApp.Sort?, reverse sortReverse: Bool) -> [RNStatusInterfaceStats] {
        guard let sort else { return interfaces }

        // Python would raise TypeError comparing None against int when any interface
        // reports `bitrate: None` and `-s rate` is given (rnstatus.py:365). Swift treats a
        // missing/nil numeric as 0 instead of aborting — see the deviation note in the
        // rnstatus port summary. Swift daemons never emit a nil bitrate.
        func key(_ i: RNStatusInterfaceStats) -> Double {
            switch sort {
            case .rate, .bitrate: return i.double("bitrate") ?? 0
            case .rx:             return i.double("rxb") ?? 0
            case .tx:             return i.double("txb") ?? 0
            case .rxs:            return i.double("rxs") ?? 0
            case .txs:            return i.double("txs") ?? 0
            case .traffic:        return (i.double("rxb") ?? 0) + (i.double("txb") ?? 0)
            case .announces, .announce:
                return (i.double("incoming_announce_frequency") ?? 0)
                     + (i.double("outgoing_announce_frequency") ?? 0)
            case .arx:            return i.double("incoming_announce_frequency") ?? 0
            case .atx:            return i.double("outgoing_announce_frequency") ?? 0
            case .prx:            return i.double("incoming_pr_frequency") ?? 0
            case .ptx:            return i.double("outgoing_pr_frequency") ?? 0
            case .held:           return i.double("held_announces") ?? 0
            }
        }

        // Python: reverse = not sort_reverse → descending unless -r was given.
        let descending = !sortReverse
        let decorated = interfaces.enumerated().map { (offset: $0.offset, key: key($0.element), value: $0.element) }
        return decorated.sorted { lhs, rhs in
            if lhs.key != rhs.key { return descending ? lhs.key > rhs.key : lhs.key < rhs.key }
            return lhs.offset < rhs.offset   // stability, in both directions
        }.map(\.value)
    }

    // MARK: - Visibility filters

    /// Interface display-name prefixes hidden unless `-a` is given (rnstatus.py:394-399).
    static let hiddenPrefixes = [
        "LocalInterface[",
        "TCPInterface[Client",
        "BackboneInterface[Client on",
        "AutoInterfacePeer[",
        "WeaveInterfacePeer[",
        "I2PInterfacePeer[Connected peer",
    ]

    /// Whether an interface is excluded from the render.
    ///
    /// Python nests two gates (rnstatus.py:393-403): the outer one is bypassed by `-a`,
    /// the inner one — a non-connectable `I2PInterface[` — is applied unconditionally and
    /// therefore hides the interface even under `-a`.
    public static func shouldHide(_ stats: RNStatusInterfaceStats, showAll: Bool) -> Bool {
        let name = stats.name
        let i2pNonConnectable = name.hasPrefix("I2PInterface[")
            && stats.has("i2p_connectable")
            && stats.bool("i2p_connectable") == false

        // rnstatus.py:403 — re-applied outside the `dispall or …` guard.
        if i2pNonConnectable { return true }
        if showAll { return false }
        return hiddenPrefixes.contains { name.hasPrefix($0) }
    }

    /// The name / burst filter applied inside the visibility gate (rnstatus.py:404-413).
    ///
    /// Python's first branch (`name_filter == None and burst_filter == None`) is dead in
    /// practice because `main()` always passes `burst_filter=args.burst`, a bool — which is
    /// why `burstFilter` is a plain `Bool` here rather than an Optional.
    ///
    /// Worth knowing: `-B` on its own renders no burst indicator at all, because
    /// `burst_str` only appears on the Announces/Path Rqs. continuation lines, which need
    /// `-A`/`-P`.
    public static func passesFilters(_ stats: RNStatusInterfaceStats,
                                     nameFilter: String?,
                                     burstFilter: Bool) -> Bool {
        let name = stats.name
        // Python truthiness: an empty filter string counts as "no filter".
        let filter = (nameFilter?.isEmpty == false) ? nameFilter : nil

        if !burstFilter {
            guard let filter else { return true }
            return name.lowercased().contains(filter.lowercased())
        }

        // Python requires BOTH keys to be present before consulting either value.
        let burstActive = stats.has("burst_active") && stats.has("pr_burst_active")
            && ((stats.bool("burst_active") ?? false) || (stats.bool("pr_burst_active") ?? false))
        let nameMatches = filter.map { name.lowercased().contains($0.lowercased()) } ?? false
        return burstActive || nameMatches
    }
}
