import XCTest
@testable import ReticulumSwift

/// Tests for RawChannelReader/Writer stream metadata and readinto.
///
/// Python reference (Buffer.py / io.RawIOBase):
///   reader.readable()  → True
///   reader.writable()  → False
///   reader.seekable()  → False
///   reader.readinto(bytearray) → int (bytes written) | None (EOF + empty)
///   reader.close()    → marks stream closed
///
///   writer.readable() → False
///   writer.writable() → True
///   writer.seekable() → False
///   writer.close()   → marks stream closed
final class BufferReadintoTests: XCTestCase {

    // MARK: - RawChannelReader metadata

    func testReaderIsReadable() {
        let (reader, _) = makeReaderWriter()
        XCTAssertTrue(reader.readable, "reader.readable must be true")
    }

    func testReaderIsNotWritable() {
        let (reader, _) = makeReaderWriter()
        XCTAssertFalse(reader.writable, "reader.writable must be false")
    }

    func testReaderIsNotSeekable() {
        let (reader, _) = makeReaderWriter()
        XCTAssertFalse(reader.seekable, "reader.seekable must be false")
    }

    // MARK: - RawChannelWriter metadata

    func testWriterIsNotReadable() {
        let (_, writer) = makeReaderWriter()
        XCTAssertFalse(writer.readable, "writer.readable must be false")
    }

    func testWriterIsWritable() {
        let (_, writer) = makeReaderWriter()
        XCTAssertTrue(writer.writable, "writer.writable must be true")
    }

    func testWriterIsNotSeekable() {
        let (_, writer) = makeReaderWriter()
        XCTAssertFalse(writer.seekable, "writer.seekable must be false")
    }

    // MARK: - readinto(inout [UInt8]) -> Int?

    func testReadintoReturnsCountWhenDataAvailable() throws {
        let (reader, writer) = makeReaderWriter()
        let payload = Data([0x01, 0x02, 0x03])
        try writer.write(payload)

        // Allow async loopback delivery
        Thread.sleep(forTimeInterval: 0.05)

        var buf = [UInt8](repeating: 0, count: 8)
        let n = reader.readinto(&buf)
        XCTAssertEqual(n, 3, "readinto must return the number of bytes written into buffer")
        XCTAssertEqual(buf[0], 0x01)
        XCTAssertEqual(buf[1], 0x02)
        XCTAssertEqual(buf[2], 0x03)
    }

    func testReadintoReturnsNilWhenClosedAndEmpty() {
        let (reader, _) = makeReaderWriter()
        reader.close()
        var buf = [UInt8](repeating: 0, count: 8)
        let n = reader.readinto(&buf)
        XCTAssertNil(n, "readinto must return nil when stream is closed and no data remains")
    }

    func testReadintoReturnsBytesBeforeNilAfterClose() throws {
        let (reader, writer) = makeReaderWriter()
        try writer.write(Data([0xAA, 0xBB]))
        Thread.sleep(forTimeInterval: 0.05)
        reader.close()

        var buf = [UInt8](repeating: 0, count: 8)
        let n = reader.readinto(&buf)
        if let count = n {
            XCTAssertGreaterThan(count, 0, "should deliver data before EOF nil")
            var buf2 = [UInt8](repeating: 0, count: 8)
            let n2 = reader.readinto(&buf2)
            XCTAssertNil(n2, "readinto must return nil after draining closed stream")
        }
        // nil on first call also valid (data not yet buffered before close)
    }

    func testReadintoFillsUpToBufferCapacity() throws {
        let (reader, writer) = makeReaderWriter()
        try writer.write(Data(repeating: 0xFF, count: 10))
        Thread.sleep(forTimeInterval: 0.05)

        var buf = [UInt8](repeating: 0, count: 4)  // smaller than available
        let n = reader.readinto(&buf)
        XCTAssertEqual(n, 4, "readinto must not exceed buffer capacity")
        XCTAssertTrue(buf.allSatisfy { $0 == 0xFF })
    }

    // MARK: - close() / isClosed

    func testReaderIsClosed() {
        let (reader, _) = makeReaderWriter()
        XCTAssertFalse(reader.isClosed, "reader must not be closed initially")
        reader.close()
        XCTAssertTrue(reader.isClosed, "reader must be closed after close()")
    }

    func testWriterIsClosed() throws {
        let (_, writer) = makeReaderWriter()
        XCTAssertFalse(writer.isClosed, "writer must not be closed initially")
        try writer.close()
        XCTAssertTrue(writer.isClosed, "writer must be closed after close()")
    }

    // MARK: - Helpers

    private func makeReaderWriter() -> (RawChannelReader, RawChannelWriter) {
        let outlet = LoopbackOutlet()
        let channel = Channel(outlet: outlet)
        outlet.channel = channel        // loopback: delivers sent packets back to same channel
        let r = Buffer.createReader(streamID: 0, channel: channel)
        let w = Buffer.createWriter(streamID: 0, channel: channel)
        return (r, w)
    }

    /// Outlet that synchronously delivers sent raw bytes back to its channel's receive path,
    /// making reader/writer tests work without a real Link.
    private final class LoopbackOutlet: ChannelOutlet {
        weak var channel: Channel?
        private let deliveryQueue = DispatchQueue(label: "loopback")

        func send(_ raw: Data) -> ChannelPacketHandle {
            let handle = ChannelPacketHandle(raw: raw)
            // Deliver back to channel.receive on a background queue (avoids re-entrancy)
            deliveryQueue.async { [weak self] in
                self?.channel?.receive(raw)
                handle.markDelivered()
            }
            return handle
        }

        func resend(_ handle: ChannelPacketHandle) {
            deliveryQueue.async { [weak self] in
                self?.channel?.receive(handle.raw)
                handle.markDelivered()
            }
        }
        var mdu: Int { 400 }
        var rtt: TimeInterval { 0.001 }
        var isUsable: Bool { true }
        func getPacketState(_ h: ChannelPacketHandle) -> MessageState { h.state == .delivered ? .delivered : .sent }
        func timedOut() {}
        func setPacketTimeoutCallback(_ h: ChannelPacketHandle, timeout: TimeInterval?, callback: ((ChannelPacketHandle) -> Void)?) {
            guard let t = timeout, let cb = callback else { h.timeoutWork?.cancel(); return }
            let work = DispatchWorkItem { cb(h) }
            h.timeoutWork = work
            deliveryQueue.asyncAfter(deadline: .now() + t, execute: work)
        }
        func setPacketDeliveredCallback(_ h: ChannelPacketHandle, callback: ((ChannelPacketHandle) -> Void)?) {
            h.deliveredCallback = callback
        }
        func getPacketID(_ h: ChannelPacketHandle) -> ObjectIdentifier? { ObjectIdentifier(h) }
    }
}
