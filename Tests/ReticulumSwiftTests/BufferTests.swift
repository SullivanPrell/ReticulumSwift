import XCTest
@testable import ReticulumSwift

final class BufferTests: XCTestCase {

    // MARK: - StreamDataMessage wire format (Python parity)

    func testStreamDataMessagePackNormal() throws {
        let msg = StreamDataMessage(streamID: 0x0003, data: Data([0xAA, 0xBB]), eof: false)
        let raw = try msg.pack()
        // Header: stream_id=3, no EOF, no compressed → 0x0003
        XCTAssertEqual(raw[0], 0x00)
        XCTAssertEqual(raw[1], 0x03)
        XCTAssertEqual(raw[2], 0xAA)
        XCTAssertEqual(raw[3], 0xBB)
        XCTAssertEqual(raw.count, 4)
    }

    func testStreamDataMessagePackEOF() throws {
        let msg = StreamDataMessage(streamID: 0x0001, data: Data(), eof: true)
        let raw = try msg.pack()
        // Header: stream_id=1 | EOF(0x8000) = 0x8001
        XCTAssertEqual(raw[0], 0x80)
        XCTAssertEqual(raw[1], 0x01)
        XCTAssertEqual(raw.count, 2)
    }

    func testStreamDataMessagePackStreamIDMax() throws {
        let msg = StreamDataMessage(streamID: StreamDataMessage.streamIDMax, data: Data(), eof: false)
        let raw = try msg.pack()
        // 0x3FFF → bytes 0x3F, 0xFF
        XCTAssertEqual(raw[0], 0x3F)
        XCTAssertEqual(raw[1], 0xFF)
    }

    func testStreamDataMessageUnpackRoundTrip() throws {
        let original = StreamDataMessage(streamID: 0x000A, data: Data("hello".utf8), eof: false)
        let packed = try original.pack()
        let decoded = StreamDataMessage()
        try decoded.unpack(packed)
        XCTAssertEqual(decoded.streamID, 0x000A)
        XCTAssertEqual(decoded.data, Data("hello".utf8))
        XCTAssertFalse(decoded.eof)
    }

    func testStreamDataMessageUnpackEOF() throws {
        // Raw: 0x8005 → streamID=5, eof=true
        let raw = Data([0x80, 0x05])
        let msg = StreamDataMessage()
        try msg.unpack(raw)
        XCTAssertEqual(msg.streamID, 0x0005)
        XCTAssertTrue(msg.eof)
        XCTAssertTrue(msg.data.isEmpty)
    }

    func testStreamDataMessageTypeID() {
        XCTAssertEqual(StreamDataMessage.typeID, 0xFF00)
    }

    // MARK: - RawChannelReader

    func testRawChannelReaderReceivesData() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)

        let exp = expectation(description: "data available")
        let reader = Buffer.createReader(streamID: 0, channel: channel) { _ in exp.fulfill() }

        // Simulate a StreamDataMessage arriving on the channel.
        let msg = StreamDataMessage(streamID: 0, data: Data("hi".utf8), eof: false)
        let raw = try makeChannelEnvelope(msg: msg, seq: 0)
        channel.receive(raw)

        wait(for: [exp], timeout: 1.0)
        let bytes = reader.read(2)
        XCTAssertEqual(bytes, Data("hi".utf8))
        reader.close()
    }

    func testRawChannelReaderIgnoresOtherStreamIDs() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)

        let reader = Buffer.createReader(streamID: 5, channel: channel)

        // Deliver data on stream_id=3 (different).
        let msg = StreamDataMessage(streamID: 3, data: Data([0xFF]), eof: false)
        let raw = try makeChannelEnvelope(msg: msg, seq: 0)
        channel.receive(raw)

        let exp = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(reader.availableBytes, 0)
        reader.close()
    }

    func testRawChannelReaderEOFFlag() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        let reader = Buffer.createReader(streamID: 0, channel: channel)

        let eofMsg = StreamDataMessage(streamID: 0, data: Data(), eof: true)
        let raw = try makeChannelEnvelope(msg: eofMsg, seq: 0)
        channel.receive(raw)

        let exp = expectation(description: "eof")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(reader.atEOF)
        reader.close()
    }

    func testRawChannelReaderPartialRead() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        let reader = Buffer.createReader(streamID: 0, channel: channel)

        let msg = StreamDataMessage(streamID: 0, data: Data([1, 2, 3, 4, 5]), eof: false)
        let raw = try makeChannelEnvelope(msg: msg, seq: 0)
        channel.receive(raw)

        let exp = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(reader.availableBytes, 5)
        let first = reader.read(3)
        XCTAssertEqual(first, Data([1, 2, 3]))
        XCTAssertEqual(reader.availableBytes, 2)
        let rest = reader.read(2)
        XCTAssertEqual(rest, Data([4, 5]))
        XCTAssertEqual(reader.availableBytes, 0)
        reader.close()
    }

    // MARK: - RawChannelWriter

    func testRawChannelWriterSendsStreamDataMessage() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        let writer = Buffer.createWriter(streamID: 2, channel: channel)

        try writer.write(Data("test".utf8))

        XCTAssertEqual(outlet.sentPackets.count, 1)
        let raw = outlet.sentPackets[0]
        // Decode the channel envelope.
        let msgtype = UInt16(raw[0]) << 8 | UInt16(raw[1])
        XCTAssertEqual(msgtype, StreamDataMessage.typeID)
        // Stream header starts at offset 6.
        let streamHeader = UInt16(raw[6]) << 8 | UInt16(raw[7])
        let streamID = streamHeader & 0x3FFF
        let isEOF = (streamHeader & 0x8000) != 0
        XCTAssertEqual(streamID, 2)
        XCTAssertFalse(isEOF)
        XCTAssertEqual(raw.suffix(from: 8), Data("test".utf8))
    }

    func testRawChannelWriterClosesSendsEOF() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        let writer = Buffer.createWriter(streamID: 0, channel: channel)

        try writer.close()

        XCTAssertEqual(outlet.sentPackets.count, 1)
        let raw = outlet.sentPackets[0]
        let streamHeader = UInt16(raw[6]) << 8 | UInt16(raw[7])
        let isEOF = (streamHeader & 0x8000) != 0
        XCTAssertTrue(isEOF)
    }

    func testRawChannelWriterChunksLargeData() throws {
        let outlet = MockChannelOutlet()
        outlet.mockMDU = 30   // force chunking: mdu-6(ch header)-2(stream header)=22 bytes per chunk
        let channel = Channel(outlet: outlet)
        // Raise window so all chunks can go out.
        let writer = Buffer.createWriter(streamID: 0, channel: channel)

        // Write 50 bytes — needs 3 chunks at 22 bytes each (22+22+6=50).
        let data = Data(repeating: 0xCC, count: 50)
        try writer.write(data)

        XCTAssertGreaterThan(outlet.sentPackets.count, 1)
        // Reconstruct and verify all data.
        var recovered = Data()
        for raw in outlet.sentPackets {
            recovered.append(contentsOf: raw.dropFirst(8))
        }
        XCTAssertEqual(recovered, data)
    }

    // MARK: - Bidirectional buffer factory

    func testCreateBidirectionalBuffer() throws {
        let outlet = MockChannelOutlet()
        let channel = Channel(outlet: outlet)
        let (reader, _) = Buffer.createBidirectionalBuffer(
            receiveStreamID: 0, sendStreamID: 1, channel: channel)

        // Reader should subscribe; verify it picks up data.
        let exp = expectation(description: "data")
        reader.onDataAvailable = { _ in exp.fulfill() }

        let msg = StreamDataMessage(streamID: 0, data: Data([0x42]), eof: false)
        let raw = try makeChannelEnvelope(msg: msg, seq: 0)
        channel.receive(raw)

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(reader.availableBytes, 1)
        reader.close()
    }

    // MARK: - End-to-end Buffer over Link

    func testBufferRoundTripOverLink() throws {
        let pair = try makeEstablishedLinkPair()
        let aChannel = pair.initiator.getChannel()
        let bChannel = pair.responderLink.getChannel()

        let writer = Buffer.createWriter(streamID: 0, channel: aChannel)
        let received = expectation(description: "B got bytes")
        var gotBytes = Data()
        let reader = Buffer.createReader(streamID: 0, channel: bChannel)
        reader.onDataAvailable = { [weak reader] _ in
            while let b = reader?.read(1) {
                gotBytes.append(b)
                if gotBytes.count >= 5 { received.fulfill() }
            }
        }

        try writer.write(Data("hello".utf8))
        wait(for: [received], timeout: 1.0)
        XCTAssertEqual(gotBytes, Data("hello".utf8))
        reader.close()
    }

    // MARK: - Helpers

    func makeChannelEnvelope(msg: MessageBase, seq: UInt16) throws -> Data {
        let typeID = type(of: msg).typeID
        let body = try msg.pack()
        var out = Data(capacity: 6 + body.count)
        out.append(UInt8(typeID >> 8)); out.append(UInt8(typeID & 0xFF))
        out.append(UInt8(seq >> 8));   out.append(UInt8(seq & 0xFF))
        let len = UInt16(body.count)
        out.append(UInt8(len >> 8));   out.append(UInt8(len & 0xFF))
        out.append(body)
        return out
    }

    var aTransport: Transport!
    var bTransport: Transport!

    struct LinkPair {
        let initiator: Link
        let responderLink: Link
    }

    func makeEstablishedLinkPair() throws -> LinkPair {
        aTransport = Transport()
        bTransport = Transport()
        let bIdentity = Identity()
        let bDest = try Destination(
            identity: bIdentity, direction: .in, kind: .single,
            appName: "buffer", aspects: ["test"]
        )
        bTransport.ownerIdentity = bIdentity
        bTransport.register(destination: bDest)

        let aIface = BufferTestLoopback(name: "A")
        let bIface = BufferTestLoopback(name: "B")
        aIface.paired = bIface; bIface.paired = aIface
        aTransport.register(interface: aIface)
        bTransport.register(interface: bIface)

        let aE = expectation(description: "aE")
        let bE = expectation(description: "bE")
        aTransport.onLinkEstablished = { _ in aE.fulfill() }
        bTransport.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: aTransport)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bTransport.links[aLink.linkID!])
        return LinkPair(initiator: aLink, responderLink: bLink)
    }
}

private final class BufferTestLoopback: Interface {
    var name: String; var bitrate: Int = 0; var isOnline: Bool = true
    weak var paired: BufferTestLoopback?
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {
        let raw = try packet.pack(); let copy = try Packet.unpack(raw)
        paired?.inboundHandler?(copy, paired!)
    }
}
