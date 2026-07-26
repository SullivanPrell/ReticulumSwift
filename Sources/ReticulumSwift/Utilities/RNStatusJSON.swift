import Foundation

/// `json.dumps`-compatible serialisation for `rnstatus -j`.
///
/// Python reference: `RNS/Utilities/rnstatus.py:343-359` (stats) and
/// `rnstatus.py:187-193` (discovered interfaces).
///
/// Foundation's `JSONSerialization` cannot preserve dictionary key order, and `-j` output
/// *is* ordered — Python emits the stats dict in insertion order (`interfaces`, `rxb`,
/// `txb`, `rxs`, `txs`, the optional transport block, then `rss` last). So this is a small
/// hand-rolled encoder over ``MsgPack/Value``, which already carries its map pairs in wire
/// order.
///
/// Defaults matched to `json.dumps`: `", "` and `": "` separators, `null` for nil,
/// lowercase booleans, `\uXXXX` escaping for non-ASCII (`ensure_ascii=True`) and
/// shortest-round-trip float reprs.
public enum RNStatusJSON {

    // MARK: - bytes → hex normalisation

    /// Python: the two-pass loop at rnstatus.py:346-355.
    ///
    /// Converts every top-level `bytes` value (`transport_id`, `network_id`,
    /// `probe_responder`) and every `bytes` value one level inside an array-valued key
    /// (`interfaces` → `hash`, `ifac_signature`, `parent_interface_hash`) to undelimited
    /// lowercase hex. Values nested deeper are left alone — Python would raise a
    /// `TypeError` out of `json.dumps` for those.
    public static func normaliseStats(_ value: MsgPack.Value) -> MsgPack.Value {
        guard case .map(let pairs) = value else { return value }
        let converted: [(MsgPack.Value, MsgPack.Value)] = pairs.map { key, element in
            if case .bytes(let raw) = element {
                return (key, .string(RNSUtilities.hexrep(raw, delimit: false)))
            }
            if case .array(let items) = element {
                return (key, .array(items.map(normaliseInnerMap)))
            }
            return (key, element)
        }
        return .map(converted)
    }

    /// Python: rnstatus.py:189-191 — every `bytes` value in each discovery entry becomes
    /// undelimited hex. In practice only `stamp` and `discovery_hash` are bytes;
    /// `transport_id` / `network_id` are already hex strings on disk.
    public static func normaliseDiscovered(_ value: MsgPack.Value) -> MsgPack.Value {
        guard case .array(let items) = value else { return value }
        return .array(items.map(normaliseInnerMap))
    }

    private static func normaliseInnerMap(_ value: MsgPack.Value) -> MsgPack.Value {
        guard case .map(let pairs) = value else { return value }
        return .map(pairs.map { key, element in
            if case .bytes(let raw) = element {
                return (key, .string(RNSUtilities.hexrep(raw, delimit: false)))
            }
            return (key, element)
        })
    }

    // MARK: - Discovered entries → msgpack

    /// One discovery entry as a msgpack map, in Python's `info` dict insertion order
    /// (`RNS/Discovery.py:318-410`, plus the persistence and status fields added by
    /// `interface_discovered` and `list_discovered_interfaces`).
    ///
    /// Optional fields are omitted rather than emitted as null, because Python only ever
    /// sets them for the interface types that carry them and `-D` branches on presence.
    public static func msgpackValue(for info: DiscoveredInterfaceInfo) -> MsgPack.Value {
        var pairs: [(MsgPack.Value, MsgPack.Value)] = [
            (.string("type"),         .string(info.type)),
            (.string("transport"),    .bool(info.transport)),
            (.string("name"),         .string(info.name)),
            (.string("received"),     .double(info.received)),
            (.string("stamp"),        .bytes(info.stamp)),
            (.string("value"),        .int(Int64(info.value))),
            (.string("transport_id"), .string(info.transportID)),
            (.string("network_id"),   .string(info.networkID)),
            (.string("hops"),         .int(Int64(info.hops))),
            (.string("latitude"),     info.latitude.map  { .double($0) } ?? .nil),
            (.string("longitude"),    info.longitude.map { .double($0) } ?? .nil),
            (.string("height"),       info.height.map    { .double($0) } ?? .nil),
        ]
        if let value = info.ifacNetname { pairs.append((.string("ifac_netname"), .string(value))) }
        if let value = info.ifacNetkey  { pairs.append((.string("ifac_netkey"),  .string(value))) }
        if let value = info.reachableOn { pairs.append((.string("reachable_on"), .string(value))) }
        if let value = info.port        { pairs.append((.string("port"),         .int(Int64(value)))) }
        if let value = info.frequency   { pairs.append((.string("frequency"),    numeric(value))) }
        if let value = info.bandwidth   { pairs.append((.string("bandwidth"),    numeric(value))) }
        if let value = info.sf          { pairs.append((.string("sf"),           .int(Int64(value)))) }
        if let value = info.cr          { pairs.append((.string("cr"),           .int(Int64(value)))) }
        if let value = info.channel     { pairs.append((.string("channel"),      .int(Int64(value)))) }
        if let value = info.modulation  { pairs.append((.string("modulation"),   .string(value))) }
        if let value = info.configEntry { pairs.append((.string("config_entry"), .string(value))) }
        if let value = info.discoveryHash { pairs.append((.string("discovery_hash"), .bytes(value))) }
        pairs.append((.string("discovered"),  .double(info.discovered)))
        pairs.append((.string("last_heard"),  .double(info.lastHeard)))
        pairs.append((.string("heard_count"), .int(Int64(info.heardCount))))
        if let status = info.status         { pairs.append((.string("status"),      .string(status))) }
        if let code   = info.statusCode     { pairs.append((.string("status_code"), .int(Int64(code)))) }
        return .map(pairs)
    }

    /// `-d -j`: the normalised array of entries, on one line.
    /// The caller supplies the leading blank line (rnstatus.py:185).
    public static func encodeDiscovered(_ interfaces: [DiscoveredInterfaceInfo]) -> String {
        encode(normaliseDiscovered(.array(interfaces.map(msgpackValue(for:)))))
    }

    /// The wire carries whatever msgpack decoded — in practice an integer for frequency
    /// and bandwidth. Emit the integral form so `-j` shows `867200000`, not `867200000.0`.
    private static func numeric(_ value: Double) -> MsgPack.Value {
        (value == value.rounded() && abs(value) < 9.2e18) ? .int(Int64(value)) : .double(value)
    }

    // MARK: - Encoder

    /// Serialise in map order, matching `json.dumps(obj)` with its default separators.
    public static func encode(_ value: MsgPack.Value) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    private static func write(_ value: MsgPack.Value, into out: inout String) {
        switch value {
        case .nil:           out += "null"
        case .bool(let b):   out += b ? "true" : "false"
        case .int(let n):    out += "\(n)"
        case .uint(let n):   out += "\(n)"
        case .double(let d): out += float(d)
        case .string(let s): writeString(s, into: &out)
        case .bytes(let d):
            // Unreachable after normalisation; Python would raise TypeError here.
            writeString(RNSUtilities.hexrep(d, delimit: false), into: &out)
        case .array(let items):
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += ", " }
                write(item, into: &out)
            }
            out += "]"
        case .map(let pairs):
            out += "{"
            for (index, pair) in pairs.enumerated() {
                if index > 0 { out += ", " }
                // json.dumps stringifies non-string keys; every RNS map is string-keyed.
                if case .string(let key) = pair.0 {
                    writeString(key, into: &out)
                } else {
                    writeString(RNStatusRenderer.pythonStr(pair.0), into: &out)
                }
                out += ": "
                write(pair.1, into: &out)
            }
            out += "}"
        }
    }

    /// Python `json.encoder`: `Infinity` / `-Infinity` / `NaN` are emitted bare (they are
    /// not valid JSON, but `json.dumps` produces them unless `allow_nan=False`).
    private static func float(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        return "\(value)"
    }

    /// `json.dumps` with `ensure_ascii=True`: escape quotes, backslash, control characters
    /// and everything above U+007F, using surrogate pairs beyond the BMP.
    private static func writeString(_ value: String, into out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":  out += "\\\""
            case "\\":  out += "\\\\"
            case "\n":  out += "\\n"
            case "\r":  out += "\\r"
            case "\t":  out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 || scalar.value > 0x7E {
                    if scalar.value > 0xFFFF {
                        let base = scalar.value - 0x10000
                        let high = 0xD800 + (base >> 10)
                        let low  = 0xDC00 + (base & 0x3FF)
                        out += String(format: "\\u%04x\\u%04x", high, low)
                    } else {
                        out += String(format: "\\u%04x", scalar.value)
                    }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}
