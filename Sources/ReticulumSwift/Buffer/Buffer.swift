//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - StreamDataMessage
// Wire-compatible with Python's RNS.Buffer.StreamDataMessage (MSGTYPE 0xFF00).
// Header: 2 bytes big-endian UInt16
//   bit 15 (0x8000): EOF flag
//   bit 14 (0x4000): compressed flag (bz2; requires BZip2Compressor injected into
//                    StreamDataMessage.compressor for compression; decompression
//                    transparently handled on receive if compressor is set)
//   bits 0-13 (0x3FFF): stream_id

/// Channel message carrying one chunk of a byte stream.
public final class StreamDataMessage: MessageBase {
  /// Largest stream identifier that fits in the stream header.
  public static let streamIDMax: UInt16 = 0x3FFF
  /// Bytes of stream header ahead of the chunk (`Buffer.py`, `HEADER_LEN`).
  public static let headerLength: Int = 2
  /// Bytes of channel and stream header carried by every envelope.
  ///
  /// Channel overhead per envelope: 6-byte channel header + 2-byte stream header
  public static let overhead: Int = 6 + 2

  /// Pluggable compressor for stream data.
  ///
  /// Defaults to `BZip2Compressor`. ``RawChannelWriter`` compresses a chunk with it when that
  /// saves space (`Buffer.py:243-258`), and received chunks with the compressed flag set are
  /// decompressed with it. Set to `nil` to send every chunk uncompressed; readers then can't decode
  /// compressed chunks from peers.
  public static var compressor: (any DataCompressor)? = BZip2Compressor()

  public override class var typeID: UInt16 { SystemMessageTypes.streamData }

  /// Stream this chunk belongs to.
  public var streamID: UInt16 = 0
  /// Chunk payload.
  public var data: Data = Data()
  /// Whether this chunk ends the stream.
  public var eof: Bool = false
  /// True when this message carries bz2-compressed payload.
  public private(set) var isCompressed: Bool = false

  /// Creates a chunk for a stream.
  public convenience init(
    streamID: UInt16, data: Data = Data(), eof: Bool = false,
    compress: Bool = false
  ) {
    self.init()
    self.streamID = streamID
    // Attempt compression if requested and a compressor is available.
    if compress, let c = StreamDataMessage.compressor, !data.isEmpty,
      let compressed = c.compress(data), compressed.count < data.count
    {
      self.data = compressed
      self.isCompressed = true
    } else {
      self.data = data
      self.isCompressed = false
    }
    self.eof = eof
  }

  /// Creates a chunk whose `data` is already bz2-compressed.
  convenience init(streamID: UInt16, compressedData: Data, eof: Bool) {
    self.init()
    self.streamID = streamID
    self.data = compressedData
    self.isCompressed = true
    self.eof = eof
  }

  public override func pack() throws -> Data {
    var header = streamID & StreamDataMessage.streamIDMax
    if eof { header |= 0x8000 }
    if isCompressed { header |= 0x4000 }
    var out = Data([UInt8(header >> 8), UInt8(header & 0xFF)])
    out.append(data)
    return out
  }

  public override func unpack(_ raw: Data) throws {
    guard raw.count >= 2 else { throw ChannelError.invalidMsgType }
    let header = UInt16(raw[0]) << 8 | UInt16(raw[1])
    eof = (header & 0x8000) != 0
    isCompressed = (header & 0x4000) != 0
    streamID = header & StreamDataMessage.streamIDMax
    let body = raw.count > 2 ? Data(raw.dropFirst(2)) : Data()
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
///
/// Call `read(count:)` to consume bytes or subscribe via `onDataAvailable`.
/// Wire-compatible with Python's RNS.Buffer.RawChannelReader.
public final class RawChannelReader {
  /// Stream this reader consumes.
  public let streamID: UInt16
  private let channel: Channel
  private var buffer = Data()
  private var isEOF = false
  private let lock = NSLock()
  private var handlerToken: MessageHandlerToken?
  /// Called with the number of readable bytes whenever more data arrives.
  public var onDataAvailable: ((Int) -> Void)?

  /// Creates a reader consuming a stream on `channel`.
  public init(streamID: UInt16, channel: Channel) {
    self.streamID = streamID
    self.channel = channel
    try? channel.registerMessageType(StreamDataMessage.self, isSystemType: true)
    handlerToken = channel.addMessageHandler { [weak self] msg -> Bool in
      self?.handle(msg) ?? false
    }
  }

  private func handle(_ message: MessageBase) -> Bool {
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

  /// Returns up to `count` buffered bytes.
  ///
  /// Returns `nil` when the buffer is empty before the end of the stream, and empty data at its
  /// end (`RawChannelReader._read`).
  public func read(_ count: Int) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    let take = min(count, buffer.count)
    let result = Data(buffer.prefix(take))
    buffer.removeFirst(take)
    return result.isEmpty && !isEOF ? nil : result
  }

  /// All buffered bytes available.
  public var availableBytes: Int {
    lock.lock()
    defer { lock.unlock() }
    return buffer.count
  }

  /// Whether the stream has ended and its buffer is drained.
  public var atEOF: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isEOF && buffer.isEmpty
  }

  // MARK: - io.RawIOBase metadata (Python parity)

  /// Always `true`—readers are readable.
  ///
  /// Mirrors Python `RNSInputBuffer.readable()`.
  public var readable: Bool { true }
  /// Always `false`—readers aren't writable.
  ///
  /// Mirrors Python `RNSInputBuffer.writable()`.
  public var writable: Bool { false }
  /// Always `false`—readers aren't seekable.
  ///
  /// Mirrors Python `RNSInputBuffer.seekable()`.
  public var seekable: Bool { false }

  /// Whether `close()` has been called.
  public private(set) var isClosed: Bool = false

  /// Moves up to `buf.count` buffered bytes into `buf` and returns how many it moved.
  ///
  /// Returns `nil` when the buffer is empty before the end of the stream, and `0` at its end
  /// (`RawChannelReader.readinto`).
  public func readinto(_ buf: inout [UInt8]) -> Int? {
    guard let ready = read(buf.count) else { return nil }
    for (i, byte) in ready.enumerated() { buf[i] = byte }
    return ready.count
  }

  /// Stops consuming the stream and releases its buffer.
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
///
/// Wire-compatible with Python's RNS.Buffer.RawChannelWriter.
public final class RawChannelWriter {
  /// Stream this writer produces.
  public let streamID: UInt16
  private let channel: Channel
  /// Largest input chunk one write consumes, in bytes (`Buffer.py`, `MAX_CHUNK_LEN`).
  public static let maxChunkLen: Int = 1024 * 16
  /// Compression attempts per write, each on a shorter prefix (`COMPRESSION_TRIES`).
  public static let compressionTries: Int = 4
  /// Largest chunk one message carries: the channel MDU less the stream header (`_mdu`).
  private let mdu: Int
  /// Set by `close()`; every later message carries the end-of-stream flag (`_eof`).
  private var eof = false

  /// Creates a writer producing a stream on `channel`.
  public init(streamID: UInt16, channel: Channel) {
    self.streamID = streamID
    self.channel = channel
    self.mdu = channel.mdu - StreamDataMessage.headerLength
  }

  // MARK: - io.RawIOBase metadata (Python parity)

  /// Always `false`—writers aren't readable.
  ///
  /// Mirrors Python `RNSOutputBuffer.readable()`.
  public var readable: Bool { false }
  /// Always `true`—writers are writable.
  ///
  /// Mirrors Python `RNSOutputBuffer.writable()`.
  public var writable: Bool { true }
  /// Always `false`—writers aren't seekable.
  ///
  /// Mirrors Python `RNSOutputBuffer.seekable()`.
  public var seekable: Bool { false }

  /// Whether `close()` has been called.
  public private(set) var isClosed: Bool = false

  /// Sends one message carrying a chunk from the front of `bytes`, and returns how many bytes
  /// of `bytes` it carried.
  ///
  /// The chunk is at most ``maxChunkLen`` bytes. The writer sends it, or its first half or third,
  /// bz2-compressed when that fits one message and saves space, and otherwise as much of it as
  /// fits uncompressed. Returns `0` when the channel window is full (`Buffer.py:232-267`).
  public func write(_ bytes: Data) throws -> Int {
    let (message, carried) = nextMessage(Data(bytes.prefix(RawChannelWriter.maxChunkLen)))
    do {
      try channel.send(message)
    } catch ChannelError.linkNotReady {
      return 0
    }
    return carried
  }

  private func nextMessage(_ chunk: Data) -> (StreamDataMessage, Int) {
    if let compressor = StreamDataMessage.compressor {
      var attempt = 1
      while chunk.count > 32 && attempt < RawChannelWriter.compressionTries {
        let segmentLength = chunk.count / attempt
        if let compressed = compressor.compress(chunk.prefix(segmentLength)),
          compressed.count < mdu, compressed.count < segmentLength
        {
          let message = StreamDataMessage(streamID: streamID, compressedData: compressed, eof: eof)
          return (message, segmentLength)
        }
        attempt += 1
      }
    }
    let plain = Data(chunk.prefix(mdu))
    return (StreamDataMessage(streamID: streamID, data: plain, eof: eof), plain.count)
  }

  /// Waits for room in the channel window, then sends an empty end-of-stream message
  /// (`Buffer.py:269-279`).
  ///
  /// The wait lasts at most ``Channel/closeTimeout``.
  public func close() throws {
    let deadline = Date().addingTimeInterval(channel.closeTimeout)
    while Date() < deadline && !channel.isReadyToSend() {
      Thread.sleep(forTimeInterval: 0.05)
    }
    eof = true
    isClosed = true
    _ = try write(Data())
  }
}

// MARK: - Buffer

/// Factory for creating stream readers and writers over a Channel.
///
/// Wire-compatible with Python's RNS.Buffer.
public enum Buffer {
  /// Creates a reader for a stream on `channel`.
  public static func createReader(
    streamID: UInt16,
    channel: Channel,
    onDataAvailable: ((Int) -> Void)? = nil
  ) -> RawChannelReader {
    let reader = RawChannelReader(streamID: streamID, channel: channel)
    reader.onDataAvailable = onDataAvailable
    return reader
  }

  /// Creates a writer for a stream on `channel`.
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
