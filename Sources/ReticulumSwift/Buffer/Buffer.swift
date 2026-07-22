import Foundation

// MARK: - StreamDataMessage
// Wire-compatible with Python's RNS.Buffer.StreamDataMessage (MSGTYPE 0xFF00).
// Header: 2 bytes big-endian UInt16
//   bit 15 (0x8000): EOF flag
//   bit 14 (0x4000): compressed flag (bz2; requires BZip2Compressor injected into
//                    StreamDataMessage.compressor for compression; decompression
//                    transparently handled on receive if compressor is set)
//   bits 0-13 (0x3FFF): stream_id

public final class StreamDataMessage: MessageBase {
    public static let streamIDMax: UInt16 = 0x3FFF
    /// Channel overhead per envelope: 6-byte channel header + 2-byte stream header
    public static let overhead: Int = 6 + 2

    /// Pluggable compressor for stream data.
    ///
    /// Defaults to `BZip2Compressor` so a compressed chunk from a Python
    /// `RNS.Buffer` peer (which sets the compressed flag) can be transparently
    /// decompressed on receive. Compression on *send* stays opt-in per write
    /// (`StreamDataMessage(compress: true)`), so installing a compressor never
    /// changes the wire format unless a caller asks to compress. Set to `nil`
    /// to opt out (compressed chunks from peers can no longer be decoded).
    public static var compressor: (any DataCompressor)? = BZip2Compressor()

    public override class var typeID: UInt16 { SystemMessageTypes.streamData }

    public var streamID: UInt16 = 0
    public var data: Data = Data()
    public var eof: Bool = false
    /// True when this message carries bz2-compressed payload.
    public private(set) var isCompressed: Bool = false

    public convenience init(streamID: UInt16, data: Data = Data(), eof: Bool = false,
                            compress: Bool = false) {
        self.init()
        self.streamID = streamID
        // Attempt compression if requested and a compressor is available.
        if compress, let c = StreamDataMessage.compressor, !data.isEmpty,
           let compressed = c.compress(data), compressed.count < data.count {
            self.data = compressed
            self.isCompressed = true
        } else {
            self.data = data
            self.isCompressed = false
        }
        self.eof = eof
    }

    public override func pack() throws -> Data {
        var header = streamID & StreamDataMessage.streamIDMax
        if eof        { header |= 0x8000 }
        if isCompressed { header |= 0x4000 }
        var out = Data([UInt8(header >> 8), UInt8(header & 0xFF)])
        out.append(data)
        return out
    }

    public override func unpack(_ raw: Data) throws {
        guard raw.count >= 2 else { throw ChannelError.invalidMsgType }
        let header = UInt16(raw[0]) << 8 | UInt16(raw[1])
        eof         = (header & 0x8000) != 0
        isCompressed = (header & 0x4000) != 0
        streamID    = header & StreamDataMessage.streamIDMax
        let body    = raw.count > 2 ? Data(raw.dropFirst(2)) : Data()
        // Transparently decompress if the compressed flag is set, with a
        // hard upper bound of `RawChannelWriter.maxChunkLen` bytes to reject
        // decompression-bomb buffers. Mirrors Python commit 09b0469f's
        // `BZ2Decompressor(max_length=MAX_CHUNK_LEN)` + EOF check.
        if isCompressed, !body.isEmpty, let c = StreamDataMessage.compressor {
            switch c.decompress(body, maxLength: RawChannelWriter.maxChunkLen) {
            case .success(let plain):
                data = plain
            case .exceededMaxLength, .error:
                throw ChannelError.invalidMsgType
            }
        } else {
            data = body
        }
    }
}

// MARK: - RawChannelReader

/// Receives binary stream data arriving on a Channel with a given stream_id.
/// Call `read(count:)` to consume bytes or subscribe via `onDataAvailable`.
/// Wire-compatible with Python's RNS.Buffer.RawChannelReader.
public final class RawChannelReader {
    public let streamID: UInt16
    private let channel: Channel
    private var buffer = Data()
    private var isEOF = false
    private let lock = NSLock()
    private var handlerToken: MessageHandlerToken?
    public var onDataAvailable: ((Int) -> Void)?

    public init(streamID: UInt16, channel: Channel) {
        self.streamID = streamID
        self.channel  = channel
        try? channel._registerMessageType(StreamDataMessage.self, isSystemType: true)
        handlerToken = channel.addMessageHandler { [weak self] msg -> Bool in
            self?._handle(msg) ?? false
        }
    }

    private func _handle(_ message: MessageBase) -> Bool {
        guard let msg = message as? StreamDataMessage, msg.streamID == streamID else { return false }
        lock.lock()
        if !msg.data.isEmpty { buffer.append(msg.data) }
        if msg.eof { isEOF = true }
        let available = buffer.count
        let cb = onDataAvailable
        lock.unlock()
        if available > 0 || msg.eof { cb?(available) }
        return true
    }

    /// Returns up to `count` bytes, or nil if fewer are available and not EOF.
    public func read(_ count: Int) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard buffer.count >= count || isEOF else { return nil }
        let take = min(count, buffer.count)
        if take == 0 { return isEOF ? Data() : nil }
        let slice = buffer.prefix(take)
        buffer.removeFirst(take)
        return Data(slice)
    }

    /// All buffered bytes currently available.
    public var availableBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return buffer.count
    }

    public var atEOF: Bool {
        lock.lock(); defer { lock.unlock() }
        return isEOF && buffer.isEmpty
    }

    // MARK: - io.RawIOBase metadata (Python parity)

    /// Always `true` — readers are readable. Mirrors Python `RNSInputBuffer.readable()`.
    public var readable:  Bool { true  }
    /// Always `false` — readers are not writable. Mirrors Python `RNSInputBuffer.writable()`.
    public var writable:  Bool { false }
    /// Always `false` — readers are not seekable. Mirrors Python `RNSInputBuffer.seekable()`.
    public var seekable:  Bool { false }

    /// Whether `close()` has been called.
    public private(set) var isClosed: Bool = false

    /// Fill `buffer` with available bytes, up to `buffer.count`.
    /// Returns the number of bytes written, or `nil` when the stream is closed and empty.
    /// Mirrors Python's `RNSInputBuffer.readinto(bytearray)`.
    public func readinto(_ buf: inout [UInt8]) -> Int? {
        lock.lock()
        let available = buffer.count
        let closed    = isClosed
        lock.unlock()

        if available == 0 { return closed ? nil : 0 }

        let take = min(available, buf.count)
        lock.lock()
        let slice = buffer.prefix(take)
        buffer.removeFirst(take)
        lock.unlock()

        for (i, byte) in slice.enumerated() { buf[i] = byte }
        return take
    }

    public func close() {
        if let token = handlerToken {
            channel.removeMessageHandler(token)
            handlerToken = nil
        }
        lock.lock()
        onDataAvailable = nil
        isClosed = true
        lock.unlock()
    }

    deinit { close() }
}

// MARK: - RawChannelWriter

/// Sends binary stream data over a Channel with a given stream_id.
/// Wire-compatible with Python's RNS.Buffer.RawChannelWriter.
public final class RawChannelWriter {
    public let streamID: UInt16
    private let channel: Channel
    public static let maxChunkLen: Int = 1024 * 16

    public init(streamID: UInt16, channel: Channel) {
        self.streamID = streamID
        self.channel  = channel
    }

    // MARK: - io.RawIOBase metadata (Python parity)

    /// Always `false` — writers are not readable. Mirrors Python `RNSOutputBuffer.readable()`.
    public var readable:  Bool { false }
    /// Always `true` — writers are writable. Mirrors Python `RNSOutputBuffer.writable()`.
    public var writable:  Bool { true  }
    /// Always `false` — writers are not seekable. Mirrors Python `RNSOutputBuffer.seekable()`.
    public var seekable:  Bool { false }

    /// Whether `close()` has been called.
    public private(set) var isClosed: Bool = false

    /// Write bytes, chunked to fit the channel MDU. Returns bytes consumed.
    @discardableResult
    public func write(_ bytes: Data) throws -> Int {
        let maxData = channel.mdu - 2   // 2-byte stream header
        var consumed = 0
        var remaining = bytes
        while !remaining.isEmpty {
            let chunk = remaining.prefix(min(maxData, RawChannelWriter.maxChunkLen))
            remaining = remaining.dropFirst(chunk.count)
            let msg = StreamDataMessage(streamID: streamID, data: Data(chunk), eof: false)
            try channel.send(msg)
            consumed += chunk.count
        }
        return consumed
    }

    /// Send an EOF signal to the remote reader and mark this writer closed.
    public func close() throws {
        isClosed = true
        let msg = StreamDataMessage(streamID: streamID, data: Data(), eof: true)
        try? channel.send(msg)
    }
}

// MARK: - Buffer

/// Factory for creating stream readers and writers over a Channel.
/// Wire-compatible with Python's RNS.Buffer.
public enum Buffer {
    public static func createReader(
        streamID: UInt16,
        channel: Channel,
        onDataAvailable: ((Int) -> Void)? = nil
    ) -> RawChannelReader {
        let reader = RawChannelReader(streamID: streamID, channel: channel)
        reader.onDataAvailable = onDataAvailable
        return reader
    }

    public static func createWriter(streamID: UInt16, channel: Channel) -> RawChannelWriter {
        RawChannelWriter(streamID: streamID, channel: channel)
    }

    /// Returns a (reader, writer) pair for bidirectional use.
    public static func createBidirectionalBuffer(
        receiveStreamID: UInt16,
        sendStreamID: UInt16,
        channel: Channel,
        onDataAvailable: ((Int) -> Void)? = nil
    ) -> (RawChannelReader, RawChannelWriter) {
        let reader = RawChannelReader(streamID: receiveStreamID, channel: channel)
        reader.onDataAvailable = onDataAvailable
        let writer = RawChannelWriter(streamID: sendStreamID, channel: channel)
        return (reader, writer)
    }
}
