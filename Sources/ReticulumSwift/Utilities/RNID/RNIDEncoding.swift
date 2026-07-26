import Foundation

/// The four text encodings `rnid` accepts and emits: hex, base32, url-safe base64 and
/// Reticulum's own base256 alphabet.
///
/// Python reference: `RNS/Utilities/rnid.py` — `create_rsg` (:508-514), `get_rsg_data`
/// (:397-411), the `-m`/`-M` import ladder (:282-358) and the `-p`/`-x`/`-X` printers
/// (:971-1027).
public enum RNIDEncoding {

    // MARK: - Hex

    /// Undelimited lowercase hex. Python: `RNS.hexrep(data, delimit=False)`.
    public static func hexEncode(_ data: Data) -> String {
        RNSUtilities.hexrep(data, delimit: false)
    }

    /// Python: `bytes.fromhex(text)`. Accepts either case; requires an even number of
    /// hex digits and nothing else.
    public static func hexDecode(_ text: String) -> Data? {
        let characters = Array(text.utf8)
        guard !characters.isEmpty else { return Data() }
        guard characters.count % 2 == 0 else { return nil }
        var out = Data(capacity: characters.count / 2)
        var index = 0
        while index < characters.count {
            guard let high = nibble(characters[index]), let low = nibble(characters[index + 1]) else { return nil }
            out.append(high << 4 | low)
            index += 2
        }
        return out
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return character - UInt8(ascii: "A") + 10
        default: return nil
        }
    }

    // MARK: - Base32

    /// Python: `base64.b32encode(data).decode("utf-8")`.
    public static func base32Encode(_ data: Data) -> String { Base32.encode(data) }

    /// Python: `base64.b32decode(text)` (case-sensitive; lowercase is rejected).
    public static func base32Decode(_ text: String) -> Data? { Base32.decode(text) }

    // MARK: - Base64 (URL-safe)

    /// Python: `base64.urlsafe_b64encode(data).decode("utf-8")` — the `-`/`_` alphabet,
    /// `=` padding retained.
    public static func base64URLEncode(_ data: Data) -> String {
        var encoded = data.base64EncodedString()
        encoded = encoded.replacingOccurrences(of: "+", with: "-")
        encoded = encoded.replacingOccurrences(of: "/", with: "_")
        return encoded
    }

    /// Python: `base64.urlsafe_b64decode(text)`, but **strict**.
    ///
    /// CPython silently discards characters outside the alphabet and happily returns `b""`
    /// for `"!!!!"`; that behaviour is what makes Python's own `get_rsg_data` ladder
    /// misbehave. This decoder returns `nil` instead. Missing `=` padding is tolerated,
    /// because ``decodeLadder(_:)`` strips padding before probing.
    public static func base64URLDecode(_ text: String) -> Data? {
        var normalised = text.replacingOccurrences(of: "-", with: "+")
        normalised = normalised.replacingOccurrences(of: "_", with: "/")
        while normalised.hasSuffix("=") { normalised.removeLast() }
        guard !normalised.isEmpty else { return Data() }
        // A base64 group is 4 characters; a residue of 1 can never be produced.
        let remainder = normalised.count % 4
        if remainder == 1 { return nil }
        if remainder != 0 { normalised += String(repeating: "=", count: 4 - remainder) }
        // Foundation's decoder ignores unknown characters only when told to; the default
        // options reject them, which is exactly the strictness we want.
        return Data(base64Encoded: normalised)
    }

    // MARK: - Base256

    /// Python: `RNS.b256rep(data)`.
    public static func base256Encode(_ data: Data) -> String { RNSUtilities.b256rep(data) }

    /// Python: `RNS.b256_to_bytes(text)`.
    public static func base256Decode(_ text: String) -> Data? { RNSUtilities.b256ToBytes(text) }

    // MARK: - The get_rsg_data decode ladder

    /// Normalise an RSG supplied as text back to raw bytes.
    ///
    /// **This deliberately diverges from Python**, whose `get_rsg_data` string branch is
    /// broken (rnid.py:397-411):
    ///
    /// - `RSG_PADDING` is the *bytes* literal `b"="`, and `str.strip(bytes)` raises
    ///   `TypeError`, so the base32 and hex attempts can never succeed for `str` input.
    /// - The four attempts are `try: rsg_data = X except: pass`, i.e. **last success wins**,
    ///   while `base64.urlsafe_b64decode("!!!!")` returns `b""` without raising and the
    ///   base256 alphabet contains every hex character. Under those rules base256 would win
    ///   for any hex input and decode it to garbage.
    ///
    /// The port therefore uses **first-plausible-success-wins**. The probe order is
    /// hex → base32 → base64url → base256, i.e. strictest alphabet first: every hex string
    /// is also a valid base64 string, so probing base64 first (as the audit spec proposed)
    /// would swallow hex-armoured RSGs. A candidate is accepted only when its length is
    /// `64` (a legacy RSG, see ``RSG/isLegacyFormat(_:)``) or `>= 65` (a modern RSG) —
    /// the two shapes `validate_rsg` can consume.
    ///
    /// No `rnid` CLI path reaches this function: the CLI always reads RSGs from files as
    /// bytes. It exists because `get_rsg_data` is part of the API `rngit` consumes.
    public static func decodeLadder(_ text: String) -> Data? {
        var stripped = Substring(text)
        while stripped.last == RNIDApp.rsgPadding { stripped = stripped.dropLast() }
        let payload = String(stripped)

        let candidates: [Data?] = [
            hexDecode(payload),
            base32Decode(payload),
            base64URLDecode(payload),
            base256Decode(payload)
        ]
        for candidate in candidates where isPlausibleRSG(candidate) {
            return candidate
        }
        return nil
    }

    /// The two shapes `rsg_is_legacy_format` / `validate_rsg` can consume: exactly the
    /// signature length (a legacy RSG), or a signature followed by a msgpack envelope.
    ///
    /// Requiring the envelope to actually decode is stricter than Python's bare length test,
    /// and it has to be: several of these alphabets are subsets of one another (every hex
    /// string is a valid base64 string), so a length-only gate lets an earlier codec claim a
    /// blob that belongs to a later one.
    private static func isPlausibleRSG(_ candidate: Data?) -> Bool {
        guard let candidate else { return false }
        if candidate.count == RSG.signatureLength { return true }
        guard candidate.count >= RSG.signatureLength + 1 else { return false }
        let envelope = candidate.subdata(in: RSG.signatureLength..<candidate.count)
        guard let decoded = try? MsgPack.decode(envelope), case .map = decoded else { return false }
        return true
    }
}
