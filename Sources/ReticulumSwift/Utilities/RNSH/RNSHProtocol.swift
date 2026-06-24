import Foundation

/// Constants and message types for the rnsh remote-shell protocol.
/// Python reference: RNS/Utilities/rnsh/protocol.py
///
/// rnsh uses RNS Channel-based messaging where all message type IDs are
/// derived from MSG_MAGIC = 0xac: typeID = ((0xac << 8) & 0xff00) | (val & 0x00ff)

// MARK: - Protocol constants

public enum RNSHProtocol {
    /// RNS application name used to build rnsh destinations.
    /// Python: APP_NAME = "rnsh"
    public static let appName: String = "rnsh"

    /// High byte used in all rnsh message type IDs.
    /// Python: MSG_MAGIC = 0xac
    public static let msgMagic: Int = 0xac

    /// Protocol version advertised in VersionInfoMessage.
    /// Python: PROTOCOL_VERSION = 1
    public static let protocolVersion: Int = 1

    /// Stream ID for stdin (index 0).
    /// Python: STREAM_ID_STDIN = 0
    public static let streamIDStdin: UInt16 = 0

    /// Stream ID for stdout (index 1).
    /// Python: STREAM_ID_STDOUT = 1
    public static let streamIDStdout: UInt16 = 1

    /// Stream ID for stderr (index 2).
    /// Python: STREAM_ID_STDERR = 2
    public static let streamIDStderr: UInt16 = 2

    /// Build a message type ID from a low-byte ordinal.
    /// Python: _make_MSGTYPE(val) = ((MSG_MAGIC << 8) & 0xff00) | (val & 0x00ff)
    public static func makeMessageType(_ val: Int) -> UInt16 {
        return UInt16((msgMagic << 8) & 0xff00) | UInt16(val & 0x00ff)
    }

    /// Register all rnsh message types on a Channel.
    public static func registerMessageTypes(channel: Channel) throws {
        try channel.registerMessageType(RNSHNoopMessage.self)
        try channel.registerMessageType(RNSHWindowSizeMessage.self)
        try channel.registerMessageType(RNSHExecuteCommandMessage.self)
        try channel.registerMessageType(RNSHStreamDataMessage.self)
        try channel.registerMessageType(RNSHVersionInfoMessage.self)
        try channel.registerMessageType(RNSHErrorMessage.self)
        try channel.registerMessageType(RNSHCommandExitedMessage.self)
    }
}

// MARK: - Session state

/// State machine for an rnsh session (both listener and initiator sides).
/// Python: LSState (listener) and similar initiator states in protocol.py
public enum RNSHSessionState: Int {
    /// Waiting for the remote identity to be provided.
    case waitIdent   = 1
    /// Waiting for VersionInfoMessage.
    case waitVersion = 2
    /// Waiting for ExecuteCommandMessage.
    case waitCommand = 3
    /// Command is running; data is being streamed.
    case running     = 4
    /// A protocol error has occurred.
    case error       = 5
    /// Session is tearing down.
    case teardown    = 6
}

// MARK: - Internal MsgPack helpers

extension MsgPack.Value {
    /// Extract an Int from `.int`, `.uint`, or positive fixint values.
    var asInt: Int? {
        switch self {
        case .int(let n):  return Int(n)
        case .uint(let n): return n <= UInt64(Int.max) ? Int(n) : nil
        default:           return nil
        }
    }
}

// MARK: - RNSHNoopMessage (typeID 0xac00)

/// No-operation message — used as a keepalive / heartbeat.
/// Python: class NoopMessage — pack returns empty bytes, unpack is a no-op.
public final class RNSHNoopMessage: MessageBase {
    public override class var typeID: UInt16 { RNSHProtocol.makeMessageType(0) }
    public override func pack() throws -> Data { Data() }
    public override func unpack(_ data: Data) throws {}
}

// MARK: - RNSHWindowSizeMessage (typeID 0xac02)

/// Terminal window-size notification.
/// Python: class WindowSizeMessage — pack/unpack as 4-element msgpack tuple.
public final class RNSHWindowSizeMessage: MessageBase {
    public override class var typeID: UInt16 { RNSHProtocol.makeMessageType(2) }

    public var rows: Int? = nil
    public var cols: Int? = nil
    public var hpix: Int? = nil
    public var vpix: Int? = nil

    public override func pack() throws -> Data {
        let arr: [MsgPack.Value] = [
            rows.map { .int(Int64($0)) } ?? .nil,
            cols.map { .int(Int64($0)) } ?? .nil,
            hpix.map { .int(Int64($0)) } ?? .nil,
            vpix.map { .int(Int64($0)) } ?? .nil,
        ]
        return MsgPack.encode(.array(arr))
    }

    public override func unpack(_ raw: Data) throws {
        guard case .array(let arr) = try MsgPack.decode(raw), arr.count == 4 else {
            throw ChannelError.invalidMsgType
        }
        rows = arr[0].asInt
        cols = arr[1].asInt
        hpix = arr[2].asInt
        vpix = arr[3].asInt
    }
}

// MARK: - RNSHExecuteCommandMessage (typeID 0xac03)

/// Request to execute a command on the remote host.
/// Python: class ExecuteCommandMesssage (sic) — 10-element msgpack tuple.
public final class RNSHExecuteCommandMessage: MessageBase {
    public override class var typeID: UInt16 { RNSHProtocol.makeMessageType(3) }

    /// Command + arguments (nil means "interactive shell").
    public var cmdline: [String]? = nil
    /// Whether to pipe stdin from the initiator.
    public var pipeStdin: Bool = false
    /// Whether to pipe stdout to the initiator.
    public var pipeStdout: Bool = false
    /// Whether to pipe stderr to the initiator.
    public var pipeStderr: Bool = false
    /// Raw termios flags (preserved as MsgPack value; nil for no-tty).
    public var tcflags: MsgPack.Value? = nil
    /// Terminal type string (e.g. "xterm-256color").
    public var term: String? = nil
    /// Terminal size: rows, cols, horizontal pixels, vertical pixels.
    public var rows: Int? = nil
    public var cols: Int? = nil
    public var hpix: Int? = nil
    public var vpix: Int? = nil

    public override func pack() throws -> Data {
        // Python: umsgpack.packb((cmdline, pipe_stdin, pipe_stdout, pipe_stderr,
        //                          tcflags, term, rows, cols, hpix, vpix))
        let cmdVal: MsgPack.Value
        if let cmdline = cmdline {
            cmdVal = .array(cmdline.map { .string($0) })
        } else {
            cmdVal = .nil
        }
        let arr: [MsgPack.Value] = [
            cmdVal,
            .bool(pipeStdin),
            .bool(pipeStdout),
            .bool(pipeStderr),
            tcflags ?? .nil,
            term.map { .string($0) } ?? .nil,
            rows.map { .int(Int64($0)) } ?? .nil,
            cols.map { .int(Int64($0)) } ?? .nil,
            hpix.map { .int(Int64($0)) } ?? .nil,
            vpix.map { .int(Int64($0)) } ?? .nil,
        ]
        return MsgPack.encode(.array(arr))
    }

    public override func unpack(_ raw: Data) throws {
        guard case .array(let arr) = try MsgPack.decode(raw), arr.count == 10 else {
            throw ChannelError.invalidMsgType
        }
        // cmdline: nil or array of strings
        if case .array(let cmds) = arr[0] {
            cmdline = cmds.compactMap {
                if case .string(let s) = $0 { return s }
                return nil
            }
        } else {
            cmdline = nil
        }
        if case .bool(let b) = arr[1] { pipeStdin  = b }
        if case .bool(let b) = arr[2] { pipeStdout = b }
        if case .bool(let b) = arr[3] { pipeStderr = b }
        tcflags = (arr[4] == .nil) ? nil : arr[4]
        if case .string(let s) = arr[5] { term = s } else { term = nil }
        rows = arr[6].asInt
        cols = arr[7].asInt
        hpix = arr[8].asInt
        vpix = arr[9].asInt
    }
}

// MARK: - RNSHStreamDataMessage (typeID 0xac04)

/// Carries stdin/stdout/stderr bytes between initiator and listener.
/// Python: class StreamDataMessage(RNSStreamDataMessage) — inherits the same
///         2-byte header wire format as RNS.Buffer.StreamDataMessage but has
///         a different typeID (0xac04 vs 0xFF00).
///
/// Wire format: 2-byte big-endian header + payload bytes
///   bit 15 (0x8000): EOF flag
///   bit 14 (0x4000): compressed flag (reserved; not used by rnsh)
///   bits 0-13: stream_id
public final class RNSHStreamDataMessage: MessageBase {
    public override class var typeID: UInt16 { RNSHProtocol.makeMessageType(4) }

    public static let streamIDMax: UInt16 = 0x3FFF

    public var streamID: UInt16 = 0
    public var data: Data = Data()
    public var eof: Bool = false

    public override func pack() throws -> Data {
        var header = streamID & RNSHStreamDataMessage.streamIDMax
        if eof { header |= 0x8000 }
        var out = Data([UInt8(header >> 8), UInt8(header & 0xFF)])
        out.append(data)
        return out
    }

    public override func unpack(_ raw: Data) throws {
        guard raw.count >= 2 else { throw ChannelError.invalidMsgType }
        let header = UInt16(raw[0]) << 8 | UInt16(raw[1])
        eof      = (header & 0x8000) != 0
        streamID = header & RNSHStreamDataMessage.streamIDMax
        data     = raw.count > 2 ? Data(raw.dropFirst(2)) : Data()
    }
}

// MARK: - RNSHVersionInfoMessage (typeID 0xac05)

/// Protocol handshake: software version + protocol version.
/// Python: class VersionInfoMessage — 2-element msgpack tuple.
public final class RNSHVersionInfoMessage: MessageBase {
    public override class var typeID: UInt16 { RNSHProtocol.makeMessageType(5) }

    public var swVersion: String = ""
    /// Defaults to the current protocol version constant.
    public var protocolVersion: Int = RNSHProtocol.protocolVersion

    public override func pack() throws -> Data {
        let arr: [MsgPack.Value] = [
            .string(swVersion),
            .int(Int64(protocolVersion)),
        ]
        return MsgPack.encode(.array(arr))
    }

    public override func unpack(_ raw: Data) throws {
        guard case .array(let arr) = try MsgPack.decode(raw), arr.count == 2 else {
            throw ChannelError.invalidMsgType
        }
        if case .string(let s) = arr[0] { swVersion       = s }
        if let v = arr[1].asInt         { protocolVersion = v }
    }
}

// MARK: - RNSHErrorMessage (typeID 0xac06)

/// Protocol error notification.
/// Python: class ErrorMessage — 3-element msgpack tuple (msg, fatal, data).
public final class RNSHErrorMessage: MessageBase {
    public override class var typeID: UInt16 { RNSHProtocol.makeMessageType(6) }

    /// Human-readable error description (nil if none).
    public var msg: String? = nil
    /// True if this error closes the session.
    public var fatal: Bool = false
    /// Optional structured error data (key→value pairs).
    public var errorData: [String: String]? = nil

    public override func pack() throws -> Data {
        let dataVal: MsgPack.Value
        if let d = errorData {
            dataVal = .map(d.map { (.string($0.key), .string($0.value)) })
        } else {
            dataVal = .nil
        }
        let arr: [MsgPack.Value] = [
            msg.map { .string($0) } ?? .nil,
            .bool(fatal),
            dataVal,
        ]
        return MsgPack.encode(.array(arr))
    }

    public override func unpack(_ raw: Data) throws {
        guard case .array(let arr) = try MsgPack.decode(raw), arr.count == 3 else {
            throw ChannelError.invalidMsgType
        }
        if case .string(let s) = arr[0] { msg = s } else { msg = nil }
        if case .bool(let b)   = arr[1] { fatal = b }
        if case .map(let pairs) = arr[2] {
            var d: [String: String] = [:]
            for (k, v) in pairs {
                if case .string(let ks) = k, case .string(let vs) = v {
                    d[ks] = vs
                }
            }
            errorData = d.isEmpty ? nil : d
        } else {
            errorData = nil
        }
    }
}

// MARK: - RNSHCommandExitedMessage (typeID 0xac07)

/// Notification that the remote command has exited.
/// Python: class CommandExitedMessage — packs a *single* msgpack int (not an array).
public final class RNSHCommandExitedMessage: MessageBase {
    public override class var typeID: UInt16 { RNSHProtocol.makeMessageType(7) }

    /// Process exit code (nil if unknown / not yet available).
    public var returnCode: Int? = nil

    public override func pack() throws -> Data {
        if let rc = returnCode {
            return MsgPack.encode(.int(Int64(rc)))
        } else {
            return MsgPack.encode(.nil)
        }
    }

    public override func unpack(_ raw: Data) throws {
        let val = try MsgPack.decode(raw)
        returnCode = val.asInt
    }
}
