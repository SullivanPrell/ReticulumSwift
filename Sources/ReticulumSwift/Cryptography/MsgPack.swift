import Foundation

/// A subset of msgpack large enough to encode the dictionaries Reticulum
/// puts on the wire — `ResourceAdvertisement`, link RTT floats, request /
/// response envelopes — without pulling in a third-party dependency.
///
/// Supported types: nil, bool, int (all widths, signed and unsigned),
/// double, str, bin, array, map. Ext types and timestamp are not
/// implemented because Reticulum doesn't use them.
public enum MsgPack {

    public indirect enum Value: Equatable {
        case `nil`
        case bool(Bool)
        case int(Int64)
        case uint(UInt64)
        case double(Double)
        case string(String)
        case bytes(Data)
        case array([Value])
        case map([(Value, Value)])

        public static func == (lhs: Value, rhs: Value) -> Bool {
            switch (lhs, rhs) {
            case (.nil, .nil): return true
            case (.bool(let a), .bool(let b)): return a == b
            case (.int(let a), .int(let b)): return a == b
            case (.uint(let a), .uint(let b)): return a == b
            case (.int(let a), .uint(let b)): return a >= 0 && UInt64(a) == b
            case (.uint(let a), .int(let b)): return b >= 0 && UInt64(b) == a
            case (.double(let a), .double(let b)): return a == b
            case (.string(let a), .string(let b)): return a == b
            case (.bytes(let a), .bytes(let b)): return a == b
            case (.array(let a), .array(let b)): return a == b
            case (.map(let a), .map(let b)):
                guard a.count == b.count else { return false }
                for i in 0..<a.count {
                    if a[i].0 != b[i].0 || a[i].1 != b[i].1 { return false }
                }
                return true
            default: return false
            }
        }
    }

    public enum Error: Swift.Error {
        case truncated
        case unsupportedType(UInt8)
        case invalidUTF8
        case typeMismatch
    }

    // MARK: - Encode

    public static func encode(_ value: Value) -> Data {
        var out = Data()
        write(value, into: &out)
        return out
    }

    private static func write(_ value: Value, into out: inout Data) {
        switch value {
        case .nil:
            out.append(0xC0)
        case .bool(let b):
            out.append(b ? 0xC3 : 0xC2)
        case .int(let n):
            writeInt(n, into: &out)
        case .uint(let n):
            writeUInt(n, into: &out)
        case .double(let d):
            out.append(0xCB)
            appendBigEndian(d.bitPattern, byteCount: 8, into: &out)
        case .string(let s):
            let bytes = Data(s.utf8)
            writeStringHeader(byteCount: bytes.count, into: &out)
            out.append(bytes)
        case .bytes(let b):
            writeBinHeader(byteCount: b.count, into: &out)
            out.append(b)
        case .array(let elements):
            writeArrayHeader(count: elements.count, into: &out)
            for e in elements { write(e, into: &out) }
        case .map(let pairs):
            writeMapHeader(count: pairs.count, into: &out)
            for (k, v) in pairs { write(k, into: &out); write(v, into: &out) }
        }
    }

    private static func writeUInt(_ n: UInt64, into out: inout Data) {
        if n <= 0x7F {
            out.append(UInt8(n))
        } else if n <= UInt64(UInt8.max) {
            out.append(0xCC); out.append(UInt8(n))
        } else if n <= UInt64(UInt16.max) {
            out.append(0xCD); appendBigEndian(UInt16(n), byteCount: 2, into: &out)
        } else if n <= UInt64(UInt32.max) {
            out.append(0xCE); appendBigEndian(UInt32(n), byteCount: 4, into: &out)
        } else {
            out.append(0xCF); appendBigEndian(n, byteCount: 8, into: &out)
        }
    }

    private static func writeInt(_ n: Int64, into out: inout Data) {
        if n >= 0 { writeUInt(UInt64(n), into: &out); return }
        if n >= -32 {
            out.append(UInt8(bitPattern: Int8(n)))
        } else if n >= Int64(Int8.min) {
            out.append(0xD0); out.append(UInt8(bitPattern: Int8(n)))
        } else if n >= Int64(Int16.min) {
            out.append(0xD1)
            appendBigEndian(UInt16(bitPattern: Int16(n)), byteCount: 2, into: &out)
        } else if n >= Int64(Int32.min) {
            out.append(0xD2)
            appendBigEndian(UInt32(bitPattern: Int32(n)), byteCount: 4, into: &out)
        } else {
            out.append(0xD3)
            appendBigEndian(UInt64(bitPattern: n), byteCount: 8, into: &out)
        }
    }

    private static func writeStringHeader(byteCount n: Int, into out: inout Data) {
        if n <= 31 {
            out.append(0xA0 | UInt8(n))
        } else if n <= 0xFF {
            out.append(0xD9); out.append(UInt8(n))
        } else if n <= 0xFFFF {
            out.append(0xDA); appendBigEndian(UInt16(n), byteCount: 2, into: &out)
        } else {
            out.append(0xDB); appendBigEndian(UInt32(n), byteCount: 4, into: &out)
        }
    }

    private static func writeBinHeader(byteCount n: Int, into out: inout Data) {
        if n <= 0xFF {
            out.append(0xC4); out.append(UInt8(n))
        } else if n <= 0xFFFF {
            out.append(0xC5); appendBigEndian(UInt16(n), byteCount: 2, into: &out)
        } else {
            out.append(0xC6); appendBigEndian(UInt32(n), byteCount: 4, into: &out)
        }
    }

    private static func writeArrayHeader(count n: Int, into out: inout Data) {
        if n <= 15 {
            out.append(0x90 | UInt8(n))
        } else if n <= 0xFFFF {
            out.append(0xDC); appendBigEndian(UInt16(n), byteCount: 2, into: &out)
        } else {
            out.append(0xDD); appendBigEndian(UInt32(n), byteCount: 4, into: &out)
        }
    }

    private static func writeMapHeader(count n: Int, into out: inout Data) {
        if n <= 15 {
            out.append(0x80 | UInt8(n))
        } else if n <= 0xFFFF {
            out.append(0xDE); appendBigEndian(UInt16(n), byteCount: 2, into: &out)
        } else {
            out.append(0xDF); appendBigEndian(UInt32(n), byteCount: 4, into: &out)
        }
    }

    private static func appendBigEndian<T: FixedWidthInteger & UnsignedInteger>(
        _ value: T, byteCount: Int, into out: inout Data
    ) {
        for i in stride(from: byteCount - 1, through: 0, by: -1) {
            out.append(UInt8((value >> (8 * i)) & 0xFF))
        }
    }

    // MARK: - Decode

    public static func decode(_ data: Data) throws -> Value {
        var cursor = data.startIndex
        let value = try read(data, cursor: &cursor)
        return value
    }

    /// Maximum msgpack nesting depth. Legitimate Reticulum payloads are shallow
    /// (a few levels at most); bounding recursion means a maliciously deeply
    /// nested wire payload (e.g. thousands of nested 1-element arrays in a tiny
    /// packet) can't overflow the stack and crash the process. Wire-neutral: no
    /// valid packet approaches this depth.
    private static let maxDepth = 64

    private static func read(_ data: Data, cursor: inout Int, depth: Int = 0) throws -> Value {
        guard depth <= MsgPack.maxDepth else { throw Error.truncated }
        guard cursor < data.endIndex else { throw Error.truncated }
        let tag = data[cursor]; cursor += 1

        switch tag {
        case 0x00...0x7F: return .uint(UInt64(tag))
        case 0xE0...0xFF: return .int(Int64(Int8(bitPattern: tag)))
        case 0x80...0x8F:
            return try readMap(count: Int(tag & 0x0F), data: data, cursor: &cursor, depth: depth)
        case 0x90...0x9F:
            return try readArray(count: Int(tag & 0x0F), data: data, cursor: &cursor, depth: depth)
        case 0xA0...0xBF:
            return try readString(byteCount: Int(tag & 0x1F), data: data, cursor: &cursor)
        case 0xC0: return .nil
        case 0xC2: return .bool(false)
        case 0xC3: return .bool(true)
        case 0xC4: return try readBin(byteCount: Int(try readUInt(8, data, &cursor)), data: data, cursor: &cursor)
        case 0xC5: return try readBin(byteCount: Int(try readUInt(16, data, &cursor)), data: data, cursor: &cursor)
        case 0xC6: return try readBin(byteCount: Int(try readUInt(32, data, &cursor)), data: data, cursor: &cursor)
        case 0xCA:
            let bits = UInt32(try readUInt(32, data, &cursor))
            return .double(Double(Float(bitPattern: bits)))
        case 0xCB:
            return .double(Double(bitPattern: try readUInt(64, data, &cursor)))
        case 0xCC: return .uint(try readUInt(8, data, &cursor))
        case 0xCD: return .uint(try readUInt(16, data, &cursor))
        case 0xCE: return .uint(try readUInt(32, data, &cursor))
        case 0xCF: return .uint(try readUInt(64, data, &cursor))
        case 0xD0:
            let raw = UInt8(try readUInt(8, data, &cursor))
            return .int(Int64(Int8(bitPattern: raw)))
        case 0xD1:
            let raw = UInt16(try readUInt(16, data, &cursor))
            return .int(Int64(Int16(bitPattern: raw)))
        case 0xD2:
            let raw = UInt32(try readUInt(32, data, &cursor))
            return .int(Int64(Int32(bitPattern: raw)))
        case 0xD3:
            let raw = try readUInt(64, data, &cursor)
            return .int(Int64(bitPattern: raw))
        case 0xD9: return try readString(byteCount: Int(try readUInt(8, data, &cursor)), data: data, cursor: &cursor)
        case 0xDA: return try readString(byteCount: Int(try readUInt(16, data, &cursor)), data: data, cursor: &cursor)
        case 0xDB: return try readString(byteCount: Int(try readUInt(32, data, &cursor)), data: data, cursor: &cursor)
        case 0xDC: return try readArray(count: Int(try readUInt(16, data, &cursor)), data: data, cursor: &cursor, depth: depth)
        case 0xDD: return try readArray(count: Int(try readUInt(32, data, &cursor)), data: data, cursor: &cursor, depth: depth)
        case 0xDE: return try readMap(count: Int(try readUInt(16, data, &cursor)), data: data, cursor: &cursor, depth: depth)
        case 0xDF: return try readMap(count: Int(try readUInt(32, data, &cursor)), data: data, cursor: &cursor, depth: depth)
        default:
            throw Error.unsupportedType(tag)
        }
    }

    private static func readUInt(_ bits: Int, _ data: Data, _ cursor: inout Int) throws -> UInt64 {
        let byteCount = bits / 8
        guard cursor + byteCount <= data.endIndex else { throw Error.truncated }
        var n: UInt64 = 0
        for _ in 0..<byteCount { n = (n << 8) | UInt64(data[cursor]); cursor += 1 }
        return n
    }

    private static func readString(byteCount: Int, data: Data, cursor: inout Int) throws -> Value {
        guard cursor + byteCount <= data.endIndex else { throw Error.truncated }
        let slice = data.subdata(in: cursor..<(cursor + byteCount))
        cursor += byteCount
        guard let s = String(data: slice, encoding: .utf8) else { throw Error.invalidUTF8 }
        return .string(s)
    }

    private static func readBin(byteCount: Int, data: Data, cursor: inout Int) throws -> Value {
        guard cursor + byteCount <= data.endIndex else { throw Error.truncated }
        let slice = data.subdata(in: cursor..<(cursor + byteCount))
        cursor += byteCount
        return .bytes(slice)
    }

    private static func readArray(count: Int, data: Data, cursor: inout Int, depth: Int) throws -> Value {
        var values: [Value] = []
        // Bound the pre-allocation by the bytes actually remaining: every array
        // element occupies at least one wire byte, so a legitimate `count` can
        // never exceed the remaining byte count. Without this bound, a tiny packet
        // carrying a 32-bit length (~4e9) forces a multi-gigabyte reserveCapacity
        // and crashes the process. Wire-neutral: valid data still reserves enough,
        // and the loop reads exactly `count` elements — throwing .truncated as soon
        // as the bytes run out, so a malformed count can't spin either.
        values.reserveCapacity(min(count, max(0, data.endIndex - cursor)))
        for _ in 0..<count { values.append(try read(data, cursor: &cursor, depth: depth + 1)) }
        return .array(values)
    }

    private static func readMap(count: Int, data: Data, cursor: inout Int, depth: Int) throws -> Value {
        var pairs: [(Value, Value)] = []
        // Bound the pre-allocation by remaining bytes (each pair is at least two
        // wire bytes, so remaining-bytes is a safe upper bound). Prevents the same
        // reserveCapacity allocation-DoS as readArray. Wire-neutral.
        pairs.reserveCapacity(min(count, max(0, data.endIndex - cursor)))
        for _ in 0..<count {
            let k = try read(data, cursor: &cursor, depth: depth + 1)
            let v = try read(data, cursor: &cursor, depth: depth + 1)
            pairs.append((k, v))
        }
        return .map(pairs)
    }

    // MARK: - Convenience

    /// Encode a Double as msgpack `float64` (9 bytes). Kept for the LRRTT
    /// path which only ever carries a float.
    public static func encodeDouble(_ value: Double) -> Data {
        encode(.double(value))
    }

    /// Decode a numeric msgpack value to Double.
    public static func decodeDouble(_ data: Data) throws -> Double {
        switch try decode(data) {
        case .double(let d): return d
        case .int(let n):    return Double(n)
        case .uint(let n):   return Double(n)
        default: throw Error.typeMismatch
        }
    }
}
