import Foundation

/// Encoders and decoders completing the rnx wire types declared in `RNXProtocol.swift`.
///
/// Python reference: `RNS/Utilities/rnx.py:155-160` (request decode),
/// `rnx.py:167-252` (result build), `rnx.py:379-385` (request build),
/// `rnx.py:441-457` (result decode).
///
/// Everything here exists because `RNXProtocol.swift` shipped encode-only for the
/// request and decode-only for the result, which is exactly the half a client needs and
/// exactly the wrong half for a listener.

// MARK: - RNXRequest

public extension RNXRequest {

    /// Full memberwise initialiser. The declared `init(command:)` suppressed the
    /// synthesised one, so every other field had to be assigned post-hoc.
    init(command: String,
         timeout: TimeInterval? = nil,
         stdoutLimit: Int? = nil,
         stderrLimit: Int? = nil,
         stdin: Data? = nil,
         timeoutPacksAsInteger: Bool = false) {
        self.init(command: command)
        self.timeout = timeout
        self.stdoutLimit = stdoutLimit
        self.stderrLimit = stderrLimit
        self.stdin = stdin
        self.timeoutPacksAsInteger = timeoutPacksAsInteger
    }

    /// The 5-element msgpack array Python builds at rnx.py:379-385.
    ///
    /// Pass this to `link.request(path:nativeValue:)` — **never** to
    /// `link.request(path:data:)`, which wraps the bytes as msgpack `.bytes` so a Python
    /// listener's `data[0]` becomes an `int`, `.decode("utf-8")` raises inside the
    /// response generator, and no response is ever sent.
    ///
    /// Element `[1]` follows ``RNXRequest/timeoutPacksAsInteger``.
    func packedValue() -> MsgPack.Value {
        let timeoutValue: MsgPack.Value
        if let timeout {
            timeoutValue = timeoutPacksAsInteger ? .int(Int64(timeout)) : .double(timeout)
        } else {
            timeoutValue = .nil
        }
        return .array([
            .bytes(Data(command.utf8)),                     // [0] command.encode("utf-8")
            timeoutValue,                                   // [1] timeout (seconds)
            stdoutLimit.map { .int(Int64($0)) } ?? .nil,    // [2] stdout size limit
            stderrLimit.map { .int(Int64($0)) } ?? .nil,    // [3] stderr size limit
            stdin.map { .bytes($0) } ?? .nil,               // [4] stdin data
        ])
    }

    /// Decode the listener side of the request.
    ///
    /// Element `[1]` is accepted as int, uint, float or nil, because Python's own client
    /// sends fixint 15 for the `-w` default and float64 otherwise.
    init(unpacking value: MsgPack.Value) throws {
        guard case .array(let arr) = value, arr.count == 5 else {
            throw RNXError.malformedRequest
        }
        // Python: `command = data[0].decode("utf-8")` — a non-bytes element raises.
        guard case .bytes(let commandBytes) = arr[0],
              let command = String(data: commandBytes, encoding: .utf8) else {
            throw RNXError.malformedRequest
        }
        self.init(command: command,
                  timeout: arr[1].asDouble,
                  stdoutLimit: arr[2].asInt,
                  stderrLimit: arr[3].asInt,
                  stdin: arr[4].asData)
    }

    /// Convenience: msgpack-decode `data`, then ``init(unpacking:)``.
    init(unpackFrom data: Data) throws {
        try self.init(unpacking: try MsgPack.decode(data))
    }
}

// MARK: - RNXResult

public extension RNXResult {

    /// Build the 8-element result Python assembles at rnx.py:167-176.
    init(executed: Bool,
         returnCode: Int? = nil,
         stdout: Data? = nil,
         stderr: Data? = nil,
         totalStdoutLength: Int? = nil,
         totalStderrLength: Int? = nil,
         startedAt: TimeInterval? = nil,
         concludedAt: TimeInterval? = nil) {
        // Round-trip through the wire encoder: `init(unpackFrom:)` suppressed the
        // synthesised memberwise init, and adding a second designated initialiser to the
        // struct itself would mean editing the shared declaration.
        let value = MsgPack.Value.array([
            .bool(executed),
            returnCode.map { .int(Int64($0)) } ?? .nil,
            stdout.map { .bytes($0) } ?? .nil,
            stderr.map { .bytes($0) } ?? .nil,
            totalStdoutLength.map { .int(Int64($0)) } ?? .nil,
            totalStderrLength.map { .int(Int64($0)) } ?? .nil,
            startedAt.map { .double($0) } ?? .nil,
            concludedAt.map { .double($0) } ?? .nil,
        ])
        // Cannot fail: the array above is exactly the shape the decoder requires.
        // swiftlint:disable:next force_try
        try! self.init(unpackFrom: MsgPack.encode(value))
    }

    /// The 8-element msgpack array a `NativeRequestHandler` returns.
    ///
    /// `Link.dispatchRequest` wraps it as `msgpack([request_id, value])`, which is exactly
    /// Python's `umsgpack.packb([request_id, response])` (Link.py:848). Returning
    /// `.bytes(pack())` instead would give a Python client `response[0]` on a bytes object
    /// — an `int`, truthy for any non-zero first byte, so `executed` would silently read True.
    ///
    /// Index `[6]` always encodes as float64, matching RNS's vendored umsgpack, whose
    /// `_float_precision` auto-detects "double" on any 64-bit build.
    func packedValue() -> MsgPack.Value {
        .array([
            .bool(executed),                                        // [0] executed
            returnCode.map { .int(Int64($0)) } ?? .nil,             // [1] return code
            stdout.map { .bytes($0) } ?? .nil,                      // [2] stdout
            stderr.map { .bytes($0) } ?? .nil,                      // [3] stderr
            totalStdoutLength.map { .int(Int64($0)) } ?? .nil,      // [4] total stdout length
            totalStderrLength.map { .int(Int64($0)) } ?? .nil,      // [5] total stderr length
            startedAt.map { .double($0) } ?? .nil,                  // [6] started
            concludedAt.map { .double($0) } ?? .nil,                // [7] concluded
        ])
    }

    /// ``packedValue()`` msgpack-encoded.
    func pack() -> Data { MsgPack.encode(packedValue()) }

    /// Decode from an already-unpacked msgpack value (the shape a native request handler
    /// and `RequestReceipt.response` deal in).
    ///
    /// Accepts int/uint as well as float at `[6]`/`[7]`, so a Swift-side encoder that
    /// happened to emit an integer timestamp still decodes.
    init(unpacking value: MsgPack.Value) throws {
        guard case .array(let arr) = value, arr.count == 8 else {
            throw RNXError.malformedResponse
        }
        guard case .bool = arr[0] else { throw RNXError.malformedResponse }
        var normalised = arr
        // Widen [6]/[7] before handing to the existing strict `.double`-only decoder.
        if let started = arr[6].asDouble { normalised[6] = .double(started) }
        if let concluded = arr[7].asDouble { normalised[7] = .double(concluded) }
        try self.init(unpackFrom: MsgPack.encode(.array(normalised)))
    }
}
