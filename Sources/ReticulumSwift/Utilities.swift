import Foundation

/// Utility functions mirroring Python's `RNS.*` module-level functions.
public enum RNSUtilities {

    // MARK: - Hex representation

    /// Wrapped hex: `"<deadbeef>"`. Mirrors Python `RNS.prettyhexrep(data)`.
    public static func prettyhexrep(_ data: Data) -> String {
        "<" + data.map { String(format: "%02x", $0) }.joined() + ">"
    }

    /// Colon-delimited (or plain) hex string. Mirrors Python `RNS.hexrep(data, delimit=True)`.
    public static func hexrep(_ data: Data, delimit: Bool = true) -> String {
        let hex = data.map { String(format: "%02x", $0) }
        return delimit ? hex.joined(separator: ":") : hex.joined()
    }

    // MARK: - Size / speed formatting (1000-based SI, matching Python)

    /// Human-readable SI size. Mirrors Python `RNS.prettysize(num, suffix='B')`.
    /// Uses 1000 as divisor (SI prefix, matching Python). Base unit uses no decimal ("500 B");
    /// prefixed units use 2 decimals ("1.00 KB").
    /// When suffix == "b", multiplies by 8 first (converts bytes to bits).
    public static func prettysize(_ bytes: Double, suffix: String = "B") -> String {
        let units = ["", "K", "M", "G", "T", "P", "E", "Z"]
        var value = bytes
        if suffix == "b" { value *= 8 }
        for unit in units {
            if abs(value) < 1000.0 {
                if unit.isEmpty {
                    return String(format: "%.0f %@%@", value, unit, suffix)
                } else {
                    return String(format: "%.2f %@%@", value, unit, suffix)
                }
            }
            value /= 1000.0
        }
        return String(format: "%.2f Y%@", value, suffix)
    }

    /// Convenience overload accepting `Int`.
    public static func prettysize(_ bytes: Int, suffix: String = "B") -> String {
        prettysize(Double(bytes), suffix: suffix)
    }

    /// Human-readable data rate. Mirrors Python `RNS.prettyspeed(num, suffix='b')`.
    /// Input is bits per second.
    public static func prettyspeed(_ bps: Double) -> String {
        prettysize(bps / 8, suffix: "b") + "ps"
    }

    // MARK: - Time formatting

    /// Human-readable duration. Mirrors Python `RNS.prettytime(time, verbose=False, compact=False)`.
    ///
    /// - `verbose`: use "1 second" instead of "1s", pluralise.
    /// - `compact`: limit to 2 components; truncate seconds to integer.
    public static func prettytime(_ time: TimeInterval, verbose: Bool = false, compact: Bool = false) -> String {
        var t = time
        let neg = t < 0
        if neg { t = -t }

        let days    = Int(t / 86400); t = t.truncatingRemainder(dividingBy: 86400)
        let hours   = Int(t / 3600);  t = t.truncatingRemainder(dividingBy: 3600)
        let minutes = Int(t / 60);    t = t.truncatingRemainder(dividingBy: 60)
        let seconds: Double = compact ? Double(Int(t)) : (round(t * 100) / 100)

        var components: [String] = []
        var displayed = 0

        func maybeAdd(_ value: Int, singular: String, plural: String, short: String) {
            guard value > 0 && (!compact || displayed < 2) else { return }
            components.append(verbose ? "\(value) \(value == 1 ? singular : plural)" : "\(value)\(short)")
            displayed += 1
        }

        maybeAdd(days,    singular: "day",    plural: "days",    short: "d")
        maybeAdd(hours,   singular: "hour",   plural: "hours",   short: "h")
        maybeAdd(minutes, singular: "minute", plural: "minutes", short: "m")

        if seconds > 0 && (!compact || displayed < 2) {
            let secStr: String
            if verbose {
                let secInt = Int(seconds)
                let plural = seconds == 1 ? "second" : "seconds"
                if seconds == Double(secInt) {
                    secStr = "\(secInt) \(plural)"
                } else {
                    secStr = "\(seconds) \(plural)"
                }
            } else {
                let secInt = Int(seconds)
                if seconds == Double(secInt) {
                    secStr = "\(secInt)s"
                } else {
                    secStr = "\(seconds)s"
                }
            }
            components.append(secStr)
            displayed += 1
        }

        if components.isEmpty { return "0s" }

        var result = ""
        for (i, c) in components.enumerated() {
            if i == 0 { result += c }
            else if i < components.count - 1 { result += ", " + c }
            else { result += " and " + c }
        }
        return neg ? "-\(result)" : result
    }

    /// Human-readable sub-second duration. Mirrors Python `RNS.prettyshorttime(time, verbose=False, compact=False)`.
    /// Breaks input seconds down into seconds, milliseconds, and microseconds.
    public static func prettyshorttime(_ time: TimeInterval, verbose: Bool = false, compact: Bool = false) -> String {
        var t = time
        let neg = t < 0
        if neg { t = -t }

        // Round to nearest integer microsecond to avoid float precision artifacts
        let totalMicros = Int((t * 1_000_000).rounded())
        let seconds = totalMicros / 1_000_000
        var remaining = totalMicros % 1_000_000
        let milliseconds = remaining / 1_000
        remaining = remaining % 1_000
        let microseconds: Double = compact ? Double(Int(remaining)) : (round(Double(remaining) * 100) / 100)

        var components: [String] = []
        var displayed = 0

        func maybeAdd(_ value: Int, singular: String, plural: String, short: String) {
            guard value > 0 && (!compact || displayed < 2) else { return }
            components.append(verbose ? "\(value) \(value == 1 ? singular : plural)" : "\(value)\(short)")
            displayed += 1
        }

        maybeAdd(seconds,      singular: "second",      plural: "seconds",      short: "s")
        maybeAdd(milliseconds, singular: "millisecond", plural: "milliseconds", short: "ms")

        if microseconds > 0 && (!compact || displayed < 2) {
            let usStr: String
            if verbose {
                let usInt = Int(microseconds)
                let plural = microseconds == 1 ? "microsecond" : "microseconds"
                if microseconds == Double(usInt) {
                    usStr = "\(usInt) \(plural)"
                } else {
                    usStr = "\(microseconds) \(plural)"
                }
            } else {
                let usInt = Int(microseconds)
                if microseconds == Double(usInt) {
                    usStr = "\(usInt)µs"
                } else {
                    usStr = "\(microseconds)µs"
                }
            }
            components.append(usStr)
            displayed += 1
        }

        if components.isEmpty { return "0us" }

        var result = ""
        for (i, c) in components.enumerated() {
            if i == 0 { result += c }
            else if i < components.count - 1 { result += ", " + c }
            else { result += " and " + c }
        }
        return neg ? "-\(result)" : result
    }

    // MARK: - Frequency / distance formatting

    /// Human-readable frequency. Mirrors Python `RNS.prettyfrequency(hz, suffix="Hz", d=2, lpf=False)`.
    ///
    /// - `lpf`: if true, start at Hz instead of µHz.
    public static func prettyfrequency(_ hz: Double, suffix: String = "Hz", d: Int = 2, lpf: Bool = false) -> String {
        guard hz != 0 else { return "0 Hz" }
        var num = lpf ? hz : hz * 1_000_000
        let units: [String] = lpf ? ["", "K", "M", "G", "T", "P", "E", "Z"]
                                  : ["µ", "m", "", "K", "M", "G", "T", "P", "E", "Z"]
        for unit in units {
            if abs(num) < 1000.0 {
                if d == 2 { return String(format: "%.2f %@%@", num, unit, suffix) }
                else { return "\(round(num * pow(10, Double(d))) / pow(10, Double(d))) \(unit)\(suffix)" }
            }
            num /= 1000.0
        }
        return String(format: "%.2f Y%@", num, suffix)
    }

    /// Human-readable distance. Mirrors Python `RNS.prettydistance(m, suffix="m")`.
    /// Input in meters; output in µm/mm/cm/m/Km.
    public static func prettydistance(_ meters: Double, suffix: String = "m") -> String {
        var num = meters * 1_000_000 // start in µm
        let units = ["µ", "m", "c", ""]
        let divisors: [String: Double] = ["µ": 1000, "m": 10, "c": 100, "": 1000]
        for unit in units {
            let divisor = divisors[unit] ?? 1000.0
            if abs(num) < divisor {
                return String(format: "%.2f %@%@", num, unit, suffix)
            }
            num /= divisor
        }
        return String(format: "%.2f Km", num)
    }

    // MARK: - Base-256 compact representation

    /// 256-character alphabet for compact hash display. Mirrors Python `RNS.b256`.
    public static let b256Alphabet: [String] = [
        // 0x0 Latin & numerals
        "a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p",
        // 0x1 Latin & numerals
        "q","r","s","t","u","v","x","y","z","æ","ø","0","1","2","3","4",
        // 0x2 Latin & numerals
        "A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P",
        // 0x3 Latin & numerals
        "Q","R","S","T","U","W","X","Y","Z","Æ","Ø","5","6","7","8","9",
        // 0x4 Greek
        "α","β","γ","δ","ε","ζ","η","θ","ι","κ","λ","μ","ν","ξ","π","ρ",
        // 0x5 Greek
        "σ","τ","φ","χ","ψ","ω","Γ","Δ","Θ","Λ","Ξ","Π","Σ","Φ","Ψ","Ω",
        // 0x6 Cyrillic
        "Б","Д","Ж","З","И","Л","П","Ц","Ч","Ш","Щ","Ъ","Ы","Э","Ю","Я",
        // 0x7 Cyrillic
        "б","д","ж","з","и","л","п","ц","ч","ш","щ","ъ","ы","э","ю","я",
        // 0x8 Armenian Capitals
        "Ա","Բ","Գ","Դ","Ե","Զ","Է","Ը","Թ","Ժ","Ի","Խ","Ծ","Կ","Հ","Ձ",
        // 0x9 Armenian Capitals
        "Ղ","Ճ","Մ","Յ","Ն","Շ","Ո","Չ","Պ","Ջ","Վ","Ր","Ց","Ւ","Ք","Ֆ",
        // 0xA Elder Futhark
        "ᚠ","ᚢ","ᚦ","ᚱ","ᚹ","ᚺ","ᚾ","ᛈ","ᛇ","ᛉ","ᛊ","ᛏ","ᛒ","ᛖ","ᛗ","ᛟ",
        // 0xB Katakana
        "ｲ","ｳ","ｵ","ｶ","ｷ","ｹ","ｻ","ｼ","ｽ","ｾ","ﾀ","ﾁ","ﾃ","ﾄ","ﾅ","ﾇ",
        // 0xC Katakana
        "ﾈ","ﾋ","ﾌ","ﾍ","ﾎ","ﾏ","ﾐ","ﾑ","ﾒ","ﾓ","ﾔ","ﾗ","ﾘ","ﾙ","ﾚ","ﾜ",
        // 0xD Shavian
        "𐑐","𐑑","𐑒","𐑔","𐑕","𐑗","𐑙","𐑳","𐑶","𐑸","𐑹","𐑺","𐑻","𐑽","𐑾","𐑿",
        // 0xE Ol Chiki
        "᱑","᱕","᱘","᱙","ᱚ","ᱝ","ᱟ","ᱣ","ᱦ","ᱨ","ᱬ","ᱭ","ᱰ","ᱳ","ᱶ","ᱷ",
        // 0xF Gothic & Deseret
        "𐌳","𐌸","𐌾","𐐀","𐐁","𐐂","𐐆","𐐇","𐐈","𐐉","𐐊","𐐋","𐐌","𐐍","𐐎","𐐏",
    ]

    /// Map a single byte to its b256 character. Mirrors Python `RNS.b256_rep(input_byte)`.
    public static func b256rep(_ byte: UInt8) -> String {
        b256Alphabet[Int(byte)]
    }

    /// Compact hash display using the b256 alphabet. Mirrors Python `RNS.prettyb256rep(data)`.
    /// Each byte maps to one character → 16-byte hash becomes a 16-char string wrapped in `<>`.
    public static func prettyb256rep(_ data: Data) -> String {
        "<" + data.map { b256rep($0) }.joined() + ">"
    }

    /// Encode `data` as a b256 string (no delimiter, no wrapping).
    /// Mirrors Python `RNS.b256rep(data)` which joins all bytes into a single string.
    public static func b256rep(_ data: Data) -> String {
        data.map { b256rep($0) }.joined()
    }

    /// Decode a single b256 character back to its byte value.
    /// Returns `nil` if `ch` is not in the alphabet.
    /// Mirrors Python `RNS.b256_to_byte(point)`.
    public static func b256ToByte(_ ch: Character) -> UInt8? {
        let s = String(ch)
        guard let idx = b256Alphabet.firstIndex(of: s) else { return nil }
        return UInt8(idx)
    }

    /// Decode a b256-encoded string to `Data`.
    /// Returns `nil` if any character is not in the alphabet.
    /// Mirrors Python `RNS.b256_to_bytes(b256rep)`.
    public static func b256ToBytes(_ s: String) -> Data? {
        if s.isEmpty { return Data() }
        var result = Data(capacity: s.count)
        for ch in s {
            guard let byte = b256ToByte(ch) else { return nil }
            result.append(byte)
        }
        return result
    }

    // MARK: - Timestamp formatting

    /// Format a Unix timestamp as `"yyyy-MM-dd HH:mm:ss"`.
    /// Mirrors Python `RNS.timestamp_str(time_s)` using `logtimefmt = "%Y-%m-%d %H:%M:%S"`.
    public static func timestampStr(_ timeS: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: timeS))
    }

    /// Format *now* as `"HH:mm:ss.SSS"` (millisecond precision).
    /// Mirrors Python `RNS.precise_timestamp_str()` using `logtimefmt_p = "%H:%M:%S.%f"` (trimmed to 3ms digits).
    public static func preciseTimestampStr() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
