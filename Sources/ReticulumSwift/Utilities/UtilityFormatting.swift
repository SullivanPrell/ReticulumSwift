import Foundation

/// Output formatters belonging to the `rn*` command-line utilities.
///
/// These are deliberately *not* the same as the `RNS.prettysize` / `RNS.prettyspeed`
/// helpers in ``RNSUtilities``. The Python utilities each define their own local
/// `size_str` / `speed_str` / `pretty_date`, and those differ from the library ones in
/// ways that are visible in the output:
///
/// - `speed_str` uses a **lowercase `k`** for kilobits (`"1.50 kbps"`) but an uppercase
///   `K` for kilobytes, whereas `RNS.prettyspeed` always produces `"1.50 Kbps"`.
/// - `speed_str` formats every magnitude with two decimals, including the base unit
///   (`"500.00 bps"`), whereas `prettysize` prints the base unit with none (`"500 b"`).
/// - `size_str`'s terminal yotta case omits the space (`"1.00YB"`), where `prettysize`
///   keeps it.
///
/// Reproducing the utility-local versions keeps `rnstatus` output byte-identical to
/// Python's. Reference: `size_str` in rnstatus.py:42, rncp.py:887 and rnx.py:678 (all
/// three identical), `speed_str` in rnstatus.py:760, `pretty_date` in rnpath.py:528.
public enum UtilityFormatting {

    // MARK: - size_str

    /// Human-readable byte count, matching the `size_str` defined in rnstatus, rncp and rnx.
    ///
    /// - Parameters:
    ///   - value: the quantity to format.
    ///   - suffix: `"B"` for bytes (default). Passing `"b"` multiplies by 8 first, so a
    ///     byte count can be rendered as bits — exactly what the Python helper does.
    public static func sizeStr(_ value: Double, suffix: String = "B") -> String {
        let units = ["", "K", "M", "G", "T", "P", "E", "Z"]
        var number = value
        if suffix == "b" { number *= 8 }

        for unit in units {
            if abs(number) < 1000.0 {
                // Python: base unit prints with no decimals, prefixed units with two.
                return unit.isEmpty
                    ? String(format: "%.0f %@%@", number, unit, suffix)
                    : String(format: "%.2f %@%@", number, unit, suffix)
            }
            number /= 1000.0
        }
        // Python: "%.2f%s%s" — note the missing space, unlike every branch above.
        return String(format: "%.2fY%@", number, suffix)
    }

    /// `Int` convenience overload.
    public static func sizeStr(_ value: Int, suffix: String = "B") -> String {
        sizeStr(Double(value), suffix: suffix)
    }

    // MARK: - speed_str

    /// Human-readable transfer rate, matching `speed_str` in rnstatus.py:760.
    ///
    /// - Parameters:
    ///   - value: rate in bits per second.
    ///   - suffix: `"bps"` (default) keeps bits and uses a lowercase `k` prefix.
    ///     `"Bps"` divides by 8 and uses an uppercase `K`.
    public static func speedStr(_ value: Double, suffix: String = "bps") -> String {
        // Python: bits use lowercase 'k', bytes use uppercase 'K'. Everything above
        // kilo is uppercase in both cases.
        var units = ["", "k", "M", "G", "T", "P", "E", "Z"]
        var number = value
        if suffix == "Bps" {
            number /= 8
            units = ["", "K", "M", "G", "T", "P", "E", "Z"]
        }

        for unit in units {
            if abs(number) < 1000.0 {
                // Python: "%3.2f %s%s" — two decimals at every magnitude, base included.
                return String(format: "%3.2f %@%@", number, unit, suffix)
            }
            number /= 1000.0
        }
        return String(format: "%.2f Y%@", number, suffix)
    }

    // MARK: - pretty_date

    /// Coarse "time ago" phrasing, matching `pretty_date` in rnpath.py:528.
    ///
    /// The Python original returns the bare quantity with no "ago" suffix — callers add
    /// their own wording — and its thresholds are irregular (two identical `< 10` and
    /// `< 60` branches, a `< 70` special case for "1 minute", minutes up to two hours).
    /// Those quirks are reproduced rather than tidied, so output matches.
    ///
    /// - Parameters:
    ///   - timestamp: a Unix timestamp in the past.
    ///   - now: the reference time, injectable so tests need no clock.
    public static func prettyDate(_ timestamp: TimeInterval,
                                  now: TimeInterval = Date().timeIntervalSince1970) -> String {
        let difference = now - timestamp

        // Python derives day_diff/second_diff from a datetime delta, where second_diff is
        // the intra-day remainder rather than the total.
        let dayDifference = Int(floor(difference / 86400))
        let secondDifference = Int(difference) - dayDifference * 86400

        if dayDifference < 0 { return "" }

        if dayDifference == 0 {
            if secondDifference < 10   { return "\(secondDifference) seconds" }
            if secondDifference < 60   { return "\(secondDifference) seconds" }
            if secondDifference < 70   { return "1 minute" }
            if secondDifference < 7200 { return "\(secondDifference / 60) minutes" }
            if secondDifference < 86400 { return "\(secondDifference / 3600) hours" }
        }
        if dayDifference == 1   { return "1 day" }
        if dayDifference < 7    { return "\(dayDifference) days" }
        if dayDifference < 31   { return "\(dayDifference / 7) weeks" }
        if dayDifference < 365  { return "\(dayDifference / 30) months" }
        return "\(dayDifference / 365) years"
    }
}
