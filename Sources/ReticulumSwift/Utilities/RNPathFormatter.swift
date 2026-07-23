import Foundation

/// Every line `rnpath` prints, as a pure function.
///
/// Python reference: `RNS/Utilities/rnpath.py`. Nothing here does I/O, touches `Transport`
/// or reads the clock unless a `now` is handed in, so all of the string parity is directly
/// assertable from XCTest.
public enum RNPathFormatter {

    // MARK: - pretty_date

    /// Python: `pretty_date(time)` (rnpath.py:528-547) — rnpath's own helper, **not**
    /// `RNS.prettytime`.
    ///
    /// The thresholds are irregular on purpose (two identical `< 10` / `< 60` branches, a
    /// `< 70` special case producing "1 minute", minutes running up to two hours) and there
    /// is no singularisation past the hard-coded "1 minute" / "1 day" cases, so 70 seconds
    /// renders as "1 minutes". Reproduced rather than tidied.
    ///
    /// Callers pass `int(entry["last"])`, so the parameter is an `Int` here too.
    public static func prettyDate(_ timestamp: Int, now: Date = Date()) -> String {
        UtilityFormatting.prettyDate(TimeInterval(timestamp), now: now.timeIntervalSince1970)
    }

    // MARK: - announces/hour

    /// Python: `hour_rate = round(len(timestamps)/span_hours, 3)`, collapsed to an `int`
    /// when `hour_rate - int(hour_rate) == 0`, then rendered with `str()` (rnpath.py:348-350).
    ///
    /// Two traps: Python's `round` is round-half-to-even, and `str(float)` is the shortest
    /// round-tripping representation. `String(format: "%.3f")` would print "2.500" where
    /// Python prints "2.5".
    public static func hourRateString(count: Int, spanHours: Double) -> String {
        guard spanHours != 0, spanHours.isFinite else { return "0" }
        let raw = Double(count) / spanHours
        guard raw.isFinite else { return "0" }
        let rounded = (raw * 1000).rounded(.toNearestOrEven) / 1000
        if rounded == rounded.rounded(.towardZero), abs(rounded) < 9.2e18 {
            // Python: `if hour_rate-int(hour_rate) == 0: hour_rate = int(hour_rate)`.
            return String(Int(rounded))
        }
        return "\(rounded)"
    }

    // MARK: - reason truncation

    /// Python: `trunc(input_str)` with `rmlen = 64` (rnpath.py:178-181) — returns the string
    /// unchanged at 64 or fewer characters, otherwise `input_str[:63] + "…"` (U+2026).
    ///
    /// Python slices by **code point**; Swift's `prefix(_:)` slices by grapheme cluster, so
    /// `"e\u{301}"` counts 1 in Swift and 2 in Python. Operating on `unicodeScalars` keeps
    /// the two in step for combining marks, emoji ZWJ sequences and flags.
    public static func truncateReason(_ reason: String) -> String {
        let scalars = Array(reason.unicodeScalars)
        guard scalars.count > RNPathApp.reasonMaxLength else { return reason }
        var view = String.UnicodeScalarView()
        for scalar in scalars.prefix(RNPathApp.reasonMaxLength - 1) { view.append(scalar) }
        return String(view) + "\u{2026}"
    }

    // MARK: - timestamps

    /// `RNS.timestamp_str(t)` — local time, `"%Y-%m-%d %H:%M:%S"`.
    ///
    /// Locale and calendar are pinned to `en_US_POSIX` / Gregorian so a non-Gregorian system
    /// calendar cannot shift the year field. ``RNSUtilities/timestampStr(_:)`` sets neither.
    public static func timestampString(_ timestamp: TimeInterval,
                                       timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let timeZone { formatter.timeZone = timeZone }
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    // MARK: - Path table (-t)

    /// Python: rnpath.py:289.
    ///
    /// ```
    /// print(prettyhexrep(hash)+" is "+str(hops)+" hop"+m_str+" away via "
    ///       +prettyhexrep(via)+" on "+interface+" expires "+timestamp_str(expires))
    /// ```
    ///
    /// `m_str` is a **space** for one hop and `"s"` otherwise (rnpath.py:287-288), so a
    /// one-hop row reads `… is 1 hop  away via …` with two spaces. That is a quirk of the
    /// original, not a typo here.
    public static func pathTableLine(_ entry: RNPathTableEntry, timeZone: TimeZone? = nil) -> String {
        let plural = entry.hops == 1 ? " " : "s"
        return RNSUtilities.prettyhexrep(entry.destinationHash)
            + " is \(entry.hops) hop\(plural) away via "
            + RNSUtilities.prettyhexrep(entry.resolvedVia)
            + " on \(entry.interfaceName) expires "
            + timestampString(entry.expires, timeZone: timeZone)
    }

    // MARK: - Rate table (-r)

    /// Message Python's `except` branch prints for an entry whose `timestamps` list is
    /// empty — `entry["timestamps"][0]` raises `IndexError` and `str(e)` is this text
    /// (rnpath.py:371-373).
    public static let emptyTimestampsErrorMessage = "list index out of range"

    /// Python: rnpath.py:369. Returns `nil` for the entries Python fails on, i.e. those with
    /// an empty `timestamps` list — the caller then prints the two-line error and *continues*
    /// with the remaining entries, exactly as the Python `except` does.
    public static func rateLine(_ entry: RNPathRateEntry, now: TimeInterval) -> String? {
        guard let startTimestamp = entry.timestamps.first else { return nil }

        let lastString = prettyDate(Int(entry.last), now: Date(timeIntervalSince1970: now))
        // Python: span = max(time.time() - start_ts, 3600.0) — a one-hour floor, so a
        // destination first heard 5 minutes ago is still reported per *hour*.
        let span = max(now - startTimestamp, 3600.0)
        let spanString = prettyDate(Int(startTimestamp), now: Date(timeIntervalSince1970: now))
        let rate = hourRateString(count: entry.timestamps.count, spanHours: span / 3600.0)

        let violationString: String
        if entry.rateViolations > 0 {
            let plural = entry.rateViolations == 1 ? "" : "s"
            violationString = ", \(entry.rateViolations) active rate violation\(plural)"
        } else {
            violationString = ""
        }

        let blockedString: String
        if entry.blockedUntil > now {
            // Python: bli = time.time()-(int(blocked_until)-time.time()) — the remaining time
            // expressed as a *past* timestamp so pretty_date can phrase it.
            let reflected = now - (Double(Int(entry.blockedUntil)) - now)
            blockedString = ", new announces allowed in "
                + prettyDate(Int(reflected), now: Date(timeIntervalSince1970: now))
        } else {
            blockedString = ""
        }

        return RNSUtilities.prettyhexrep(entry.destinationHash)
            + " last heard \(lastString) ago, \(rate) announces/hour in the last \(spanString)"
            + violationString + blockedString
    }

    /// Python: rnpath.py:372 — the first of the two lines printed for a failing entry.
    public static func rateErrorLine(_ entry: RNPathRateEntry) -> String {
        "Error while processing entry for " + RNSUtilities.prettyhexrep(entry.destinationHash)
    }

    // MARK: - Blackhole list (-b / -p)

    /// Python: rnpath.py:189 — `f"for {prettytime(max(0, until-now))}"` when `until` is
    /// *truthy*, else `"indefinitely"`. An `until` of exactly 0 is falsy in Python and so
    /// renders "indefinitely", not "for 0s".
    private static func untilString(_ until: TimeInterval?, now: TimeInterval) -> String {
        guard let until, until != 0 else { return "indefinitely" }
        return "for " + RNSUtilities.prettytime(max(0, until - now))
    }

    /// Python: rnpath.py:190.
    private static func reasonString(_ reason: String?) -> String {
        guard let reason, !reason.isEmpty else { return "" }
        return " (\(truncateReason(reason)))"
    }

    /// Python: rnpath.py:191 — `f" by {prettyhexrep(source)}" if source != Transport.identity.hash else ""`.
    ///
    /// Two documented divergences: a `nil` source omits the fragment (Python would call
    /// `prettyhexrep(None)`, raise, and abort the whole listing with exit 20), and a `nil`
    /// local transport identity is treated as "never equal", so the fragment *is* printed
    /// (Python would raise `AttributeError` on `Transport.identity.hash`).
    private static func byString(_ source: Data?, localTransportIdentityHash: Data?) -> String {
        guard let source, source != localTransportIdentityHash else { return "" }
        return " by " + RNSUtilities.prettyhexrep(source)
    }

    /// Python: rnpath.py:199 — the line that is actually printed.
    public static func blackholeLine(_ entry: RNPathBlackholeEntry,
                                     now: TimeInterval,
                                     localTransportIdentityHash: Data?) -> String {
        RNSUtilities.prettyhexrep(entry.identityHash)
            + " blackholed "
            + untilString(entry.until, now: now)
            + reasonString(entry.reason)
            + byString(entry.source, localTransportIdentityHash: localTransportIdentityHash)
    }

    /// Python: rnpath.py:192 — the string the substring filter is matched against, which is
    /// **not** the printed line.
    ///
    /// ```
    /// filter_str = f"{prettyhexrep(hash)} {until_str} {reason_str} {by_str}"
    /// ```
    ///
    /// Because `reason_str` and `by_str` already carry a leading space, the join produces
    /// *double* spaces before them; and the literal `" blackholed "` from the printed line
    /// never appears here. Filtering against the rendered output would silently disagree
    /// with Python whenever a reason or source is present.
    public static func blackholeFilterString(_ entry: RNPathBlackholeEntry,
                                             now: TimeInterval,
                                             localTransportIdentityHash: Data?) -> String {
        RNSUtilities.prettyhexrep(entry.identityHash)
            + " " + untilString(entry.until, now: now)
            + " " + reasonString(entry.reason)
            + " " + byString(entry.source, localTransportIdentityHash: localTransportIdentityHash)
    }

    /// Python: `filter not in filter_str` — a plain, case-sensitive, code-point-literal
    /// substring test.
    ///
    /// `String.contains(_:)` matches canonically-equivalent Unicode, so a precomposed needle
    /// would match a decomposed haystack where Python's `in` returns False. `.literal`
    /// disables that normalisation.
    public static func filterMatches(_ needle: String, in haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }   // Python: `"" in s` is True
        return haystack.range(of: needle, options: .literal) != nil
    }

    // MARK: - Default path-request mode

    /// Python: rnpath.py:474, including its leading carriage return.
    ///
    /// ```
    /// print("\rPath found, destination "+prettyhexrep(dh)+" is "+str(hops)+" hop"+ms
    ///       +" away via "+next_hop+" on "+next_hop_interface)
    /// ```
    ///
    /// `ms` is `""` for one hop here — unlike ``pathTableLine(_:timeZone:)``, which uses a
    /// space. The two branches genuinely differ.
    ///
    /// `interfaceName` must be the literal string `"None"` when unknown, because Python's
    /// local `get_next_hop_if_name` is `str(Transport.next_hop_interface(...))`.
    public static func pathFoundLine(destinationHash: Data,
                                     hops: UInt8,
                                     nextHop: Data,
                                     interfaceName: String) -> String {
        let plural = hops != 1 ? "s" : ""
        return "\rPath found, destination " + RNSUtilities.prettyhexrep(destinationHash)
            + " is \(hops) hop\(plural) away via " + RNSUtilities.prettyhexrep(nextHop)
            + " on " + interfaceName
    }

    // MARK: - JSON (-j)

    /// Python: `json.dumps(table)` after every `bytes` value has been replaced by
    /// `RNS.hexrep(v, delimit=False)` (rnpath.py:273-280).
    ///
    /// Hand-rolled because `JSONSerialization` preserves neither Python's key order nor its
    /// float formatting. Key order is Python's dict-insertion order — hash, timestamp, via,
    /// hops, expires, interface — which is deliberately *not* the order Swift's own
    /// ``RPCServer`` happens to emit.
    ///
    /// A nil `via` is serialised as the destination hash, never `null`: Python's `via` is
    /// never `None` (Transport.py:1796).
    public static func pathTableJSON(_ entries: [RNPathTableEntry]) -> String {
        let objects = entries.map { entry -> String in
            [
                "\"hash\": " + jsonString(RNSUtilities.hexrep(entry.destinationHash, delimit: false)),
                "\"timestamp\": " + jsonNumber(entry.timestamp),
                "\"via\": " + jsonString(RNSUtilities.hexrep(entry.resolvedVia, delimit: false)),
                "\"hops\": \(entry.hops)",
                "\"expires\": " + jsonNumber(entry.expires),
                "\"interface\": " + jsonString(entry.interfaceName),
            ].joined(separator: ", ")
        }
        return "[" + objects.map { "{\($0)}" }.joined(separator: ", ") + "]"
    }

    /// Python: `json.dumps(table)` for the rate table (rnpath.py:327-333), applied *after*
    /// the sort. Key order: hash, last, rate_violations, blocked_until, timestamps.
    public static func rateTableJSON(_ entries: [RNPathRateEntry]) -> String {
        let objects = entries.map { entry -> String in
            [
                "\"hash\": " + jsonString(RNSUtilities.hexrep(entry.destinationHash, delimit: false)),
                "\"last\": " + jsonNumber(entry.last),
                "\"rate_violations\": \(entry.rateViolations)",
                "\"blocked_until\": " + jsonNumber(entry.blockedUntil),
                "\"timestamps\": [" + entry.timestamps.map { jsonNumber($0) }.joined(separator: ", ") + "]",
            ].joined(separator: ", ")
        }
        return "[" + objects.map { "{\($0)}" }.joined(separator: ", ") + "]"
    }

    /// Python's `repr(float)` — the shortest representation that round-trips.
    ///
    /// Swift's `Double.description` uses the same rule, so an integral value prints `9.0`
    /// rather than `9`, matching `json.dumps`. Non-finite values use Python's `json.dumps`
    /// spelling (`Infinity` / `NaN`), which is not strict JSON but is what Python emits.
    public static func jsonNumber(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
        return "\(value)"
    }

    /// `json.dumps` string escaping with its default `ensure_ascii=True`, so any non-ASCII
    /// scalar becomes `\uXXXX` (surrogate pairs above the BMP).
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":      out += "\\\""
            case "\\":      out += "\\\\"
            case "\n":      out += "\\n"
            case "\r":      out += "\\r"
            case "\t":      out += "\\t"
            case "\u{08}":  out += "\\b"
            case "\u{0C}":  out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else if scalar.isASCII {
                    out.unicodeScalars.append(scalar)
                } else if scalar.value <= 0xFFFF {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    let value = scalar.value - 0x10000
                    out += String(format: "\\u%04x\\u%04x",
                                  0xD800 + (value >> 10),
                                  0xDC00 + (value & 0x3FF))
                }
            }
        }
        return out + "\""
    }
}
