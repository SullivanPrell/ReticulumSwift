import Foundation

/// ASCII armour for encoded RSGs.
///
/// Python reference: `wrap_rsg` / `wrap_rsg_str` / `unwrap_rsg` (rnid.py:518-564). The two
/// wrap functions differ only in whether they operate on `bytes` or `str`; every encoded
/// RSG is ASCII, so this port collapses them into one `String`-based implementation.
public enum RSGArmour {

    /// `"#### Start of rsg data #########################################"` — exactly 64
    /// characters, 41 trailing `#`.
    /// Python: `RSG_ASCII_HEADER + b"#"*(RSG_ASCII_ROW_WIDTH-len(RSG_ASCII_HEADER))`.
    public static let header: String = RNIDApp.rsgAsciiHeader
        + String(repeating: "#", count: RNIDApp.rsgAsciiRowWidth - RNIDApp.rsgAsciiHeader.count)

    /// `"########################################### End of rsg data ####"` — exactly 64
    /// characters, 43 leading `#`.
    /// Python: `b"#"*(RSG_ASCII_ROW_WIDTH-len(RSG_ASCII_FOOTER)) + RSG_ASCII_FOOTER`.
    public static let footer: String =
        String(repeating: "#", count: RNIDApp.rsgAsciiRowWidth - RNIDApp.rsgAsciiFooter.count)
        + RNIDApp.rsgAsciiFooter

    /// Python: `wrap_rsg(rsg)`.
    ///
    /// Header, then successive 64-character rows each followed by `\n`, with the final short
    /// row right-padded with `=` to 64, then the footer with **no** trailing newline. An
    /// empty payload yields `header + "\n" + footer` because the loop never runs.
    public static func wrap(_ payload: String) -> String {
        var wrapped = header + "\n"
        var remaining = Substring(payload)
        while !remaining.isEmpty {
            var chunk = String(remaining.prefix(RNIDApp.rsgAsciiRowWidth))
            remaining = remaining.dropFirst(chunk.count)
            if chunk.count < RNIDApp.rsgAsciiRowWidth {
                chunk += String(repeating: String(RNIDApp.rsgPadding),
                                count: RNIDApp.rsgAsciiRowWidth - chunk.count)
            }
            wrapped += chunk + "\n"
        }
        wrapped += footer
        return wrapped
    }

    /// Convenience for the value ``RSG/create(signer:message:embed:meta:output:)`` returns.
    public static func wrap(_ encoded: RSG.Encoded) -> String {
        switch encoded {
        case .text(let text):   return wrap(text)
        case .binary(let data): return wrap(String(decoding: data, as: UTF8.self))
        }
    }

    /// Python: `unwrap_rsg(wrapped_rsg)` (rnid.py:553-564).
    ///
    /// Skips blank lines and any line starting with `#` (which discards both the header and
    /// the footer), concatenating the rest with no separator. The trailing `=` padding is
    /// **not** stripped here — Python leaves that to `get_rsg_data`.
    ///
    /// This is **dead code in the reference tree**: `grep` finds exactly one occurrence, the
    /// `def` line. It is not called anywhere in `rnid.py` and is not among the symbols
    /// `rngit` imports. Ported for API parity only — no `rnid` code path ever accepts
    /// armoured text as input, and wiring this in would add a behaviour Python does not have.
    public static func unwrap(_ wrapped: String) -> String? {
        var unwrapped = ""
        for line in wrapped.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if line.hasPrefix("#") { continue }
            unwrapped += line
        }
        return unwrapped.isEmpty ? nil : unwrapped
    }
}
