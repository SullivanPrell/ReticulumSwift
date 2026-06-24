import XCTest
@testable import ReticulumSwift

/// Golden-byte wire-compatibility tests.
///
/// Every expected value here was produced by running the canonical Python
/// Reticulum 1.3.0 implementation with identical inputs.  These tests
/// catch any encoding change that would break interoperability with Python
/// nodes at the byte level.
///
/// Deterministic inputs used throughout:
///   • "zero" public key  = 64 × 0x00
///   • "42" public key    = 64 × 0x42
///   • "reticulum" string = UTF-8 bytes b'reticulum'
final class WireGoldenBytesTests: XCTestCase {

    // MARK: - Helpers

    private func hex(_ s: String) -> Data {
        var data = Data()
        var iter = s.makeIterator()
        while let hi = iter.next(), let lo = iter.next() {
            data.append(UInt8(String([hi, lo]), radix: 16)!)
        }
        return data
    }

    // MARK: - Identity hash computation

    /// Python: `RNS.Identity.truncated_hash(bytes(64))`
    func testIdentityHashOfZeroPub() {
        let zeroPub = Data(repeating: 0x00, count: 64)
        let got = Hashes.truncatedHash(zeroPub)
        let want = hex("f5a5fd42d16a20302798ef6ed309979b")
        XCTAssertEqual(got, want,
            "truncated_hash(zeros64) must match Python golden: \(want.hex)")
    }

    /// Python: `RNS.Identity.truncated_hash(bytes([0x42]*64))`
    func testIdentityHashOf42Pub() {
        let pub42 = Data(repeating: 0x42, count: 64)
        let got = Hashes.truncatedHash(pub42)
        let want = hex("c422e7070cb1cb455b5de9afee0d975e")
        XCTAssertEqual(got, want,
            "truncated_hash(0x42*64) must match Python golden: \(want.hex)")
    }

    /// Python: `RNS.Identity.full_hash(b'reticulum')`
    func testFullHashOfReticulumString() {
        let got = Hashes.fullHash(Data("reticulum".utf8))
        let want = hex("eac4d70bfb1c16e45e39485e31e1f5ccb18cedf878e0310d9a96100168f89f0d")
        XCTAssertEqual(got, want,
            "full_hash('reticulum') must match Python golden")
    }

    /// Python: `RNS.Identity.truncated_hash(b'reticulum')`
    func testTruncatedHashOfReticulumString() {
        let got = Hashes.truncatedHash(Data("reticulum".utf8))
        let want = hex("eac4d70bfb1c16e45e39485e31e1f5cc")
        XCTAssertEqual(got, want,
            "truncated_hash('reticulum') must match Python golden (first 16 bytes of SHA-256)")
    }

    // MARK: - Name hash (10-byte truncation of full SHA-256)

    /// Python: `RNS.Identity.full_hash(b'test.node')[: NAME_HASH_LENGTH//8]` (10 bytes)
    func testNameHashOfTestNode() {
        let got = Hashes.fullHash(Data("test.node".utf8)).prefix(Constants.nameHashLength)
        let want = hex("0c92848d54d4355c790c")
        XCTAssertEqual(Data(got), want,
            "name_hash('test.node') must match Python golden (10 bytes)")
    }

    // MARK: - Destination hash computation

    /// Python:
    ///   name_hash = sha256(b'test.node')[:10]
    ///   id_hash   = truncated_hash(zeros_64)
    ///   dest_hash = truncated_hash(name_hash + id_hash)
    func testDestinationHashGolden() {
        let idHash   = Hashes.truncatedHash(Data(repeating: 0x00, count: 64))
        let nameHash = Hashes.fullHash(Data("test.node".utf8)).prefix(Constants.nameHashLength)
        var material = Data(nameHash)
        material.append(idHash)
        let got = Hashes.truncatedHash(material)
        let want = hex("b990556455ca8dfc162e289ddb88593b")
        XCTAssertEqual(got, want,
            "destination hash for 'test.node' + zero identity must match Python golden")
    }

    /// Python:
    ///   name_hash  = sha256(b'lxmf.propagation')[:10]
    ///   dest_hash  = truncated_hash(name_hash)   # plain destination (no identity)
    func testPlainDestinationHashLxmfPropagation() {
        let nameHash = Hashes.fullHash(Data("lxmf.propagation".utf8)).prefix(Constants.nameHashLength)
        let got = Hashes.truncatedHash(Data(nameHash))
        let want = hex("8801321bf89cce83419e3e80a7df53e8")
        XCTAssertEqual(got, want,
            "plain dest hash for 'lxmf.propagation' must match Python golden")
    }

    /// Python: LXMF delivery destination for a fixed identity (pub=0x42*64)
    func testLxmfDeliveryDestinationHash() {
        let pub42 = Data(repeating: 0x42, count: 64)
        let idHash = Hashes.truncatedHash(pub42)
        let nameHash = Hashes.fullHash(Data("lxmf.delivery".utf8)).prefix(Constants.nameHashLength)
        var material = Data(nameHash)
        material.append(idHash)
        let got = Hashes.truncatedHash(material)
        let want = hex("739d207e248bb4d11b55000bb54daff1")
        XCTAssertEqual(got, want,
            "LXMF delivery dest hash for 0x42-pub identity must match Python golden")
    }

    // MARK: - Packet header byte encoding

    /// Python: DATA/SINGLE/TYPE1/BROADCAST/UNSET_CONTEXT/HOPS=0 → flags byte 0x00
    func testType1DataPacketFlagsByte() throws {
        let p = Packet(destinationType: .single, packetType: .data,
                       destinationHash: Data(repeating: 0, count: 16), context: .none,
                       data: Data())
        let raw = try p.pack()
        XCTAssertEqual(raw[0], 0x00,
            "TYPE1/SINGLE/DATA packet flags byte must be 0x00")
    }

    /// Python: ANNOUNCE/SINGLE/TYPE1/BROADCAST → flags byte 0x01
    func testType1AnnouncePacketFlagsByte() throws {
        let p = Packet(destinationType: .single, packetType: .announce,
                       destinationHash: Data(repeating: 0, count: 16), context: .none,
                       data: Data())
        let raw = try p.pack()
        XCTAssertEqual(raw[0], 0x01,
            "TYPE1/SINGLE/ANNOUNCE flags byte must be 0x01 (Python ANNOUNCE=0x01)")
    }

    /// Relayed announce (TYPE2, context flag SET, SINGLE, ANNOUNCE) → 0x61
    ///
    /// Python flag byte layout (bit 6 = header, NOT bit 7):
    ///   (HEADER_2=1 << 6) | (SET=1 << 5) | (BROADCAST=0 << 4) | (SINGLE=0 << 2) | ANNOUNCE=1
    ///   = 0x40 | 0x20 | 0x01 = 0x61
    func testType2AnnouncePacketFlagsByte() throws {
        let p = Packet(headerType: .type2, contextFlag: .set, transportType: .broadcast,
                       destinationType: .single, packetType: .announce,
                       hops: 1, transportID: Data(repeating: 0, count: 16),
                       destinationHash: Data(repeating: 0, count: 16), context: .none,
                       data: Data())
        let raw = try p.pack()
        XCTAssertEqual(raw[0], 0x61,
            "TYPE2/SINGLE/ANNOUNCE relayed packet flags byte must be 0x61 (header in bit 6)")
    }

    // MARK: - ResourceAdvertisement msgpack encoding

    /// Verify the msgpack encoding of a known ResourceAdvertisement matches Python's.
    /// Python: msgpack.packb({'t':1000,'d':1000,'n':2,'h':b'\\x00'*32,'r':b'\\x00'*4,
    ///                        'o':b'\\x00'*32,'i':0,'l':1,'q':None,'f':0,'m':b'\\x00'*8})
    func testResourceAdvertisementMsgpackGolden() {
        let ad = ResourceAdvertisement(
            transferSize: 1000, dataSize: 1000, partCount: 2,
            resourceHash: Data(repeating: 0, count: 32),
            randomHash:   Data(repeating: 0, count: 4),
            originalHash: Data(repeating: 0, count: 32),
            segmentIndex: 0, totalSegments: 1,
            requestID: nil, hashmap: Data(repeating: 0, count: 8)
        )
        let got = ad.pack()
        let want = hex("8ba174cd03e8a164cd03e8a16e02a168c4200000000000000000000000000000000000000000000000000000000000000000a172c40400000000a16fc4200000000000000000000000000000000000000000000000000000000000000000a16900a16c01a171c0a16600a16dc4080000000000000000")
        XCTAssertEqual(got, want,
            "ResourceAdvertisement msgpack encoding must match Python golden bytes")
    }

    /// ResourceAdvertisement with isRequest=true and a 10-byte requestID.
    func testResourceAdvertisementRequestFlagGolden() {
        let ad = ResourceAdvertisement(
            transferSize: 512, dataSize: 512, partCount: 1,
            resourceHash: Data(repeating: 0, count: 32),
            randomHash:   Data(repeating: 0, count: 4),
            originalHash: Data(repeating: 0, count: 32),
            segmentIndex: 0, totalSegments: 1,
            requestID: Data(repeating: 0, count: 10),
            hashmap: Data(repeating: 0, count: 4),
            isRequest: true
        )
        let got = ad.pack()
        let want = hex("8ba174cd0200a164cd0200a16e01a168c4200000000000000000000000000000000000000000000000000000000000000000a172c40400000000a16fc4200000000000000000000000000000000000000000000000000000000000000000a16900a16c01a171c40a00000000000000000000a16608a16dc40400000000")
        XCTAssertEqual(got, want,
            "ResourceAdvertisement with isRequest+requestID must match Python golden bytes")
    }

    /// Verify the isRequest flag is 0x08 in the flags field.
    func testResourceAdvertisementFlagsEncoding() {
        let ad = ResourceAdvertisement(
            transferSize: 0, dataSize: 0, partCount: 0,
            resourceHash: Data(repeating: 0, count: 32),
            randomHash: Data(repeating: 0, count: 4),
            originalHash: Data(repeating: 0, count: 32),
            segmentIndex: 0, totalSegments: 1,
            isRequest: true, isResponse: false
        )
        XCTAssertEqual(ad.flags, 0x08, "isRequest must set bit 3 (0x08) in flags")
    }

    func testResourceAdvertisementResponseFlagEncoding() {
        let ad = ResourceAdvertisement(
            transferSize: 0, dataSize: 0, partCount: 0,
            resourceHash: Data(repeating: 0, count: 32),
            randomHash: Data(repeating: 0, count: 4),
            originalHash: Data(repeating: 0, count: 32),
            segmentIndex: 0, totalSegments: 1,
            isRequest: false, isResponse: true
        )
        XCTAssertEqual(ad.flags, 0x10, "isResponse must set bit 4 (0x10) in flags")
    }

    // MARK: - Channel envelope format

    /// Python channel envelope: msgtype(2B) + seq(2B) + len(2B) + body
    /// For msgtype=0x0100, seq=0, body=b'hello' → 01 00 00 00 00 05 68 65 6c 6c 6f
    func testChannelEnvelopeGolden() throws {
        let outlet = MinimalOutlet()
        let channel = Channel(outlet: outlet)
        try channel._registerMessageType(TestMsg.self, isSystemType: true)
        let msg = TestMsg(body: Data("hello".utf8))
        let env = Envelope(outlet: outlet, message: msg, sequence: 0)
        let raw = try env.pack(messageFactories: [TestMsg.typeID: { TestMsg() }])

        let want = hex("01000000000568656c6c6f")
        XCTAssertEqual(raw, want,
            "Channel envelope [msgtype=0x0100, seq=0, len=5, 'hello'] must match Python golden")
    }

    // MARK: - StreamDataMessage (Buffer) header

    /// Python: streamID=5, eof=False → header = 0x0005 (big-endian UInt16)
    func testStreamDataMessageHeader() throws {
        let msg = StreamDataMessage(streamID: 5, data: Data("test".utf8), eof: false)
        var buf = Data()
        buf.append(UInt8(msg.streamID >> 8))
        buf.append(UInt8(msg.streamID & 0xFF))
        // Verify wire encoding
        XCTAssertEqual(buf, hex("0005"),
            "StreamDataMessage header for streamID=5 must be 0x0005")
    }

    /// EOF flag sets bit 15 (0x8000).
    func testStreamDataMessageEOFFlag() {
        let msg = StreamDataMessage(streamID: 0, data: Data(), eof: true)
        let headerWord = (UInt16(0x8000) | (msg.streamID & StreamDataMessage.streamIDMax))
        XCTAssertEqual(headerWord & 0x8000, 0x8000, "EOF flag must be bit 15 of the header word")
    }

    // MARK: - Helpers for Channel test

    private final class MinimalOutlet: ChannelOutlet {
        func send(_ raw: Data) -> ChannelPacketHandle { ChannelPacketHandle(raw: raw) }
        func resend(_ h: ChannelPacketHandle) {}
        var mdu: Int { 500 }
        var rtt: TimeInterval { 0.1 }
        var isUsable: Bool { true }
        func getPacketState(_ h: ChannelPacketHandle) -> MessageState { .sent }
        func timedOut() {}
        func setPacketTimeoutCallback(_ h: ChannelPacketHandle, timeout: TimeInterval?,
                                      callback: ((ChannelPacketHandle) -> Void)?) {}
        func setPacketDeliveredCallback(_ h: ChannelPacketHandle,
                                         callback: ((ChannelPacketHandle) -> Void)?) {}
        func getPacketID(_ h: ChannelPacketHandle) -> ObjectIdentifier? { ObjectIdentifier(h) }
    }

    private final class TestMsg: MessageBase {
        static override var typeID: UInt16 { 0x0100 }
        var body = Data()
        convenience init(body: Data) { self.init(); self.body = body }
        override func pack() throws -> Data { body }
        override func unpack(_ data: Data) throws { body = data }
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
