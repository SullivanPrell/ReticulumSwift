import Foundation

// MARK: - PickleValue

/// A Swift value that can be serialized to Python pickle protocol 4.
///
/// Covers the subset of Python objects that RNS RPC responses need:
/// None, bool, int, float, str, bytes, list, dict.
public indirect enum PickleValue {
    case none
    case bool(Bool)
    case int(Int)
    case float(Double)
    case string(String)
    case bytes(Data)
    case array([PickleValue])
    case dict([(PickleValue, PickleValue)])  // ordered key-value pairs

    // Convenience constructor for string-keyed dicts
    public static func stringDict(_ pairs: [(String, PickleValue)]) -> PickleValue {
        .dict(pairs.map { (.string($0.0), $0.1) })
    }
}

// MARK: - PickleEncoder

/// Serializes `PickleValue` trees into Python pickle protocol 4 bytes.
///
/// The output is accepted by Python's `pickle.loads()` and is wire-compatible
/// with every response format the Python RNS RPC clients expect.
///
/// Opcodes used:
///   0x80 0x04  PROTO 4
///   0x4e       NONE
///   0x88/89    NEWTRUE / NEWFALSE
///   0x4b       BININT1  (0-255, 1-byte)
///   0x4c       BININT2  (0-65535, 2-byte LE)
///   0x4a       BININT   (signed 32-bit LE)
///   0x8a       LONG1    (variable-length signed, for int > 2^31-1)
///   0x47       BINFLOAT (big-endian IEEE 754 double)
///   0x8c/94    SHORT_BINUNICODE + MEMOIZE  (string ≤255 UTF-8 bytes)
///   0x8d/94    BINUNICODE8 + MEMOIZE       (string >255 bytes)
///   0x43/94    SHORT_BINBYTES + MEMOIZE    (bytes ≤255)
///   0x42/94    BINBYTES + MEMOIZE          (bytes >255)
///   0x5d/94    EMPTY_LIST + MEMOIZE
///   0x28/65    MARK / APPENDS              (non-empty list items)
///   0x7d/94    EMPTY_DICT + MEMOIZE
///   0x28/75    MARK / SETITEMS             (non-empty dict key-value pairs)
///   0x2e       STOP
public struct PickleEncoder {

    /// Encode `value` and return the complete pickle protocol 4 byte blob.
    public static func encode(_ value: PickleValue) -> Data {
        var out = Data()
        out.append(contentsOf: [0x80, 0x04])   // PROTO 4
        append(value, to: &out)
        out.append(0x2e)                         // STOP
        return out
    }

    // MARK: - Private helpers

    private static func append(_ value: PickleValue, to out: inout Data) {
        switch value {

        case .none:
            out.append(0x4e)                     // NONE

        case .bool(let b):
            out.append(b ? 0x88 : 0x89)          // NEWTRUE / NEWFALSE

        case .int(let i):
            appendInt(i, to: &out)

        case .float(let f):
            out.append(0x47)                     // BINFLOAT
            let bits = f.bitPattern               // UInt64
            out.append(contentsOf: [
                UInt8((bits >> 56) & 0xff),
                UInt8((bits >> 48) & 0xff),
                UInt8((bits >> 40) & 0xff),
                UInt8((bits >> 32) & 0xff),
                UInt8((bits >> 24) & 0xff),
                UInt8((bits >> 16) & 0xff),
                UInt8((bits >>  8) & 0xff),
                UInt8( bits        & 0xff),
            ])

        case .string(let s):
            appendString(s, to: &out)

        case .bytes(let b):
            appendBytes(b, to: &out)

        case .array(let items):
            out.append(contentsOf: [0x5d, 0x94]) // EMPTY_LIST + MEMOIZE
            if !items.isEmpty {
                out.append(0x28)                 // MARK
                for item in items { append(item, to: &out) }
                out.append(0x65)                 // APPENDS
            }

        case .dict(let pairs):
            out.append(contentsOf: [0x7d, 0x94]) // EMPTY_DICT + MEMOIZE
            if !pairs.isEmpty {
                out.append(0x28)                 // MARK
                for (k, v) in pairs {
                    append(k, to: &out)
                    append(v, to: &out)
                }
                out.append(0x75)                 // SETITEMS
            }
        }
    }

    private static func appendInt(_ i: Int, to out: inout Data) {
        if i >= 0 && i <= 255 {
            out.append(contentsOf: [0x4b, UInt8(i)])                   // BININT1
        } else if i > 255 && i <= 65535 {
            out.append(0x4c)                                             // BININT2 (LE)
            out.append(UInt8( i       & 0xff))
            out.append(UInt8((i >> 8) & 0xff))
        } else if i >= Int(Int32.min) && i <= Int(Int32.max) {
            var le = Int32(i).littleEndian
            out.append(0x4a)                                             // BININT
            withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
        } else {
            // LONG1: 0x8a <n-bytes> <signed little-endian n-byte int>
            var val = i
            var bytes: [UInt8] = []
            repeat {
                bytes.append(UInt8(bitPattern: Int8(truncatingIfNeeded: val)))
                val >>= 8
            } while val != 0 && val != -1
            // Ensure sign bit is correct
            if i > 0 && (bytes.last! & 0x80) != 0 { bytes.append(0x00) }
            if i < 0 && (bytes.last! & 0x80) == 0 { bytes.append(0xff) }
            out.append(0x8a)                                             // LONG1
            out.append(UInt8(bytes.count))
            out.append(contentsOf: bytes)
        }
    }

    private static func appendString(_ s: String, to out: inout Data) {
        let utf8 = Data(s.utf8)
        if utf8.count <= 255 {
            out.append(0x8c)                                             // SHORT_BINUNICODE
            out.append(UInt8(utf8.count))
        } else {
            out.append(0x8d)                                             // BINUNICODE8
            var len = UInt64(utf8.count).littleEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        }
        out.append(contentsOf: utf8)
        out.append(0x94)                                                 // MEMOIZE
    }

    private static func appendBytes(_ b: Data, to out: inout Data) {
        if b.count <= 255 {
            out.append(0x43)                                             // SHORT_BINBYTES
            out.append(UInt8(b.count))
        } else {
            out.append(0x42)                                             // BINBYTES
            var len = UInt32(b.count).littleEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        }
        out.append(contentsOf: b)
        out.append(0x94)                                                 // MEMOIZE
    }
}

// MARK: - PickleDecoder

/// Extracts typed values from a pickle protocol 4 blob without a full parse.
///
/// Used by RPCServer to pull parameters (hashes, ints) out of incoming RPC call payloads.
/// Finds values by scanning for the pickle encoding of their string key, then reads
/// the value opcode immediately after the key's MEMOIZE byte.
public struct PickleDecoder {
    let data: Data

    public init(_ data: Data) {
        self.data = data
    }

    // MARK: - Value extraction

    /// Returns the 16-byte hash stored under `key`, or nil if absent or wrong length.
    ///
    /// The value must be encoded as SHORT_BINBYTES (0x43) with length 16.
    public func bytes16(for key: String) -> Data? {
        guard let off = valueOffset(after: key) else { return nil }
        // SHORT_BINBYTES: 0x43 0x10 <16 bytes>
        guard off + 2 + 16 <= data.count,
              data[off] == 0x43,
              data[off + 1] == 16 else { return nil }
        return Data(data[(off + 2)..<(off + 2 + 16)])
    }

    /// Returns the integer stored under `key`, or nil if absent, None, or not an int opcode.
    public func int(for key: String) -> Int? {
        guard let off = valueOffset(after: key) else { return nil }
        return readInt(at: off)
    }

    /// Returns true if the value stored under `key` is pickle None (0x4e).
    public func isNone(for key: String) -> Bool {
        guard let off = valueOffset(after: key) else { return false }
        return data[off] == 0x4e
    }

    /// Returns the string stored under `key`, or nil if absent or not a unicode opcode.
    public func string(for key: String) -> String? {
        guard let off = valueOffset(after: key) else { return nil }
        return readString(at: off)
    }

    // MARK: - Private helpers

    /// Returns the byte offset of the value opcode immediately after the encoded key `key`.
    private func valueOffset(after key: String) -> Int? {
        let utf8 = Array(key.utf8)
        guard utf8.count <= 255 else { return nil }
        // Key is encoded: 0x8c <len> <utf8> 0x94
        var pattern = Data([0x8c, UInt8(utf8.count)])
        pattern.append(contentsOf: utf8)
        pattern.append(0x94)              // MEMOIZE after the key string
        guard let range = data.range(of: pattern) else { return nil }
        return range.upperBound          // first byte of the value opcode
    }

    private func readInt(at off: Int) -> Int? {
        guard off < data.count else { return nil }
        switch data[off] {
        case 0x4b:                        // BININT1
            guard off + 1 < data.count else { return nil }
            return Int(data[off + 1])
        case 0x4c:                        // BININT2
            guard off + 2 < data.count else { return nil }
            return Int(data[off + 1]) | (Int(data[off + 2]) << 8)
        case 0x4a:                        // BININT (signed 32-bit LE)
            guard off + 4 < data.count else { return nil }
            let lo = UInt32(data[off+1])
                   | UInt32(data[off+2]) << 8
                   | UInt32(data[off+3]) << 16
                   | UInt32(data[off+4]) << 24
            return Int(Int32(bitPattern: lo))
        default:
            return nil
        }
    }

    private func readString(at off: Int) -> String? {
        guard off < data.count else { return nil }
        switch data[off] {
        case 0x8c:                        // SHORT_BINUNICODE
            guard off + 1 < data.count else { return nil }
            let len = Int(data[off + 1])
            let start = off + 2
            guard start + len <= data.count else { return nil }
            return String(bytes: data[start..<(start + len)], encoding: .utf8)
        default:
            return nil
        }
    }
}
