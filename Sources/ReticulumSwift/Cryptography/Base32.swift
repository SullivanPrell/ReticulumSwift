import Foundation

/// RFC 4648 base32, byte-compatible with Python's `base64.b32encode` / `base64.b32decode`.
///
/// Python reference: `RNS/Utilities/rnid.py` uses `base64.b32encode(...)` and
/// `base64.b32decode(...)` on five separate code paths — identity import (`-m`/`-M`),
/// identity info (`-p`), both key exports (`-x`/`-X`) and RSG output (`-B`). Nothing in
/// ReticulumSwift provided base32 before this file.
///
/// Matching CPython exactly matters in two places:
/// - `b32encode` emits the **uppercase** alphabet `A-Z2-7` and always pads to a multiple
///   of 8 characters with `=`.
/// - `b32decode` defaults to `casefold=False`, so a lowercase input is an error rather
///   than being silently accepted. ``decode(_:)`` therefore returns `nil` for lowercase.
public enum Base32 {

    /// RFC 4648 "Base 32 Alphabet" (table 3).
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)

    /// Reverse lookup for ``decode(_:)``; `0xFF` marks a character outside the alphabet.
    private static let reverse: [UInt8] = {
        var table = [UInt8](repeating: 0xFF, count: 256)
        for (index, character) in alphabet.enumerated() { table[Int(character)] = UInt8(index) }
        return table
    }()

    /// Encode `data` as uppercase RFC 4648 base32 with `=` padding.
    /// Python: `base64.b32encode(data).decode("utf-8")`.
    public static func encode(_ data: Data) -> String {
        if data.isEmpty { return "" }
        var out: [UInt8] = []
        out.reserveCapacity((data.count + 4) / 5 * 8)

        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            // Gather up to five bytes into a 40-bit big-endian group.
            var group: UInt64 = 0
            var present = 0
            for offset in 0..<5 {
                group <<= 8
                if index + offset < bytes.count {
                    group |= UInt64(bytes[index + offset])
                    present += 1
                }
            }
            index += 5

            // 5 bytes → 8 characters; a short tail emits only the characters it covers.
            let characters = [1: 2, 2: 4, 3: 5, 4: 7, 5: 8][present] ?? 0
            for slot in 0..<8 {
                if slot < characters {
                    let shift = UInt64(35 - 5 * slot)
                    out.append(alphabet[Int((group >> shift) & 0x1F)])
                } else {
                    out.append(UInt8(ascii: "="))
                }
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Decode uppercase RFC 4648 base32. Returns `nil` for any character outside the
    /// alphabet — including lowercase, which Python rejects too (`casefold=False`).
    ///
    /// Unlike CPython this tolerates a *missing* trailing `=` run, because the RSG decode
    /// ladder (``RNIDEncoding/decodeLadder(_:)``) strips `=` before probing candidates.
    /// Padding that *is* present must still be well formed.
    public static func decode(_ text: String) -> Data? {
        var characters = Array(text.utf8)
        guard !characters.isEmpty else { return Data() }

        // Trailing padding is informational: the count of data characters determines the
        // output length on its own, so strip it and validate the remainder.
        while characters.last == UInt8(ascii: "=") { characters.removeLast() }
        guard !characters.isEmpty else { return Data() }
        // No '=' may survive in the middle of the payload.
        if characters.contains(UInt8(ascii: "=")) { return nil }

        // Only these residues can be produced by a valid encoding of 1…5 bytes.
        let remainder = characters.count % 8
        guard [0, 2, 4, 5, 7].contains(remainder) else { return nil }

        var out = Data()
        out.reserveCapacity(characters.count * 5 / 8)
        var accumulator: UInt64 = 0
        var bits = 0
        for character in characters {
            let value = reverse[Int(character)]
            guard value != 0xFF else { return nil }
            accumulator = (accumulator << 5) | UInt64(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((accumulator >> UInt64(bits)) & 0xFF))
            }
        }
        return out
    }
}
