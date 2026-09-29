//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import CryptoKit
import XCTest

@testable import ReticulumSwift

/// `RawChannelWriter` and `RawChannelReader` behave as `RNS/Buffer.py` does.
///
/// - `write` sends one message and returns how many input bytes it carried, `0` when the
///   channel isn't ready (`Buffer.py:232-267`).
/// - `close` waits for the channel window, then sends an empty end-of-stream message
///   (`Buffer.py:269-279`).
/// - `read` returns up to the requested count, `nil` when nothing is buffered before the end of
///   the stream, and empty data at its end; `readinto` returns `nil` and `0` for those two cases
///   (`RawChannelReader._read`, `RawChannelReader.readinto`).
final class BufferStreamParityTests: XCTestCase {

  /// Channel envelope header: message type, sequence, and length (`Channel.py`, `Envelope`).
  private let envelopeHeaderLength = 6

  private func incompressible(_ count: Int) -> Data {
    var out = Data()
    var i = 0
    while out.count < count {
      out.append(contentsOf: SHA256.hash(data: Data("buffer:\(i)".utf8)))
      i += 1
    }
    return out.prefix(count)
  }

  private func messages(_ outlet: MockChannelOutlet) throws -> [StreamDataMessage] {
    try outlet.sentPackets.map { raw in
      let message = StreamDataMessage()
      try message.unpack(Data(raw.dropFirst(envelopeHeaderLength)))
      return message
    }
  }

  // MARK: - Writer

  func testWriteSendsOneMessageCarryingAtMostTheWriterMDU() throws {
    let outlet = MockChannelOutlet()
    let channel = Channel(outlet: outlet)
    let writer = Buffer.createWriter(streamID: 0, channel: channel)
    let data = incompressible(2000)

    let written = try writer.write(data)

    let sent = try messages(outlet)
    XCTAssertEqual(sent.count, 1)
    XCTAssertEqual(written, channel.mdu - 2)
    XCTAssertEqual(sent.first?.data, data.prefix(written))
    XCTAssertEqual(sent.first?.isCompressed, false)
  }

  func testWriteCompressesUpToMaxChunkLenInOneMessage() throws {
    let outlet = MockChannelOutlet()
    let channel = Channel(outlet: outlet)
    let writer = Buffer.createWriter(streamID: 0, channel: channel)

    let written = try writer.write(Data(repeating: 0x41, count: 40_000))

    let sent = try messages(outlet)
    XCTAssertEqual(written, RawChannelWriter.maxChunkLen)
    XCTAssertEqual(sent.count, 1)
    XCTAssertEqual(sent.first?.isCompressed, true)
    XCTAssertEqual(sent.first?.data, Data(repeating: 0x41, count: RawChannelWriter.maxChunkLen))
  }

  func testWriteReturnsZeroWhenTheChannelIsNotReady() throws {
    let outlet = MockChannelOutlet()
    outlet.autoDeliver = false
    let channel = Channel(outlet: outlet)
    let writer = Buffer.createWriter(streamID: 0, channel: channel)
    let data = incompressible(20_000)

    var offset = 0
    var last = -1
    while last != 0 && offset < data.count {
      last = try writer.write(data.subdata(in: offset..<data.count))
      offset += last
    }

    XCTAssertEqual(last, 0)
    let carried = try messages(outlet).reduce(Data()) { $0 + $1.data }
    XCTAssertEqual(carried, data.prefix(offset))
  }

  func testCloseWaitsForTheWindowThenEndsTheStream() throws {
    let outlet = MockChannelOutlet()
    outlet.autoDeliver = false
    let channel = Channel(outlet: outlet)
    let writer = Buffer.createWriter(streamID: 0, channel: channel)
    let data = incompressible(20_000)
    var offset = 0
    while channel.isReadyToSend() {
      offset += try writer.write(data.subdata(in: offset..<data.count))
    }
    let held = outlet.heldHandles
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
      for handle in held { handle.markDelivered() }
    }

    try writer.close()

    let last = try XCTUnwrap(try messages(outlet).last)
    XCTAssertTrue(last.eof)
    XCTAssertEqual(last.data, Data())
  }

  // MARK: - Reader

  private func reader() -> (RawChannelReader, deliver: (Data, Bool) throws -> Void) {
    let sourceOutlet = MockChannelOutlet()
    let source = Channel(outlet: sourceOutlet)
    let channel = Channel(outlet: MockChannelOutlet())
    let reader = Buffer.createReader(streamID: 0, channel: channel)
    try? source.registerMessageType(StreamDataMessage.self, isSystemType: true)
    return (
      reader,
      { data, eof in
        try source.send(StreamDataMessage(streamID: 0, data: data, eof: eof))
        channel.receive(try XCTUnwrap(sourceOutlet.sentPackets.last))
      }
    )
  }

  func testReadReturnsWhatIsBufferedWhenFewerBytesThanAsked() throws {
    let (reader, deliver) = reader()
    try deliver(Data([1, 2, 3, 4, 5]), false)

    XCTAssertEqual(reader.read(10), Data([1, 2, 3, 4, 5]))
  }

  func testReadReturnsNilWhenEmptyBeforeTheEndOfTheStream() {
    let (reader, _) = reader()

    XCTAssertNil(reader.read(10))
  }

  func testReadReturnsEmptyDataAtTheEndOfTheStream() throws {
    let (reader, deliver) = reader()
    try deliver(Data(), true)

    XCTAssertEqual(reader.read(10), Data())
  }

  func testReadintoReturnsNilWhenEmptyBeforeTheEndOfTheStream() {
    let (reader, _) = reader()
    var buffer = [UInt8](repeating: 0, count: 8)

    XCTAssertNil(reader.readinto(&buffer))
  }

  func testReadintoReturnsZeroAtTheEndOfTheStream() throws {
    let (reader, deliver) = reader()
    try deliver(Data(), true)
    var buffer = [UInt8](repeating: 0, count: 8)

    XCTAssertEqual(reader.readinto(&buffer), 0)
  }
}
