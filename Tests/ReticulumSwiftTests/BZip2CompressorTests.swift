import XCTest
import CBZip2
@testable import ReticulumSwift

/// Tests for BZip2Compressor — wire-compatible bz2 round-trip,
/// correct StreamDataMessage compressed flag handling, and fallback
/// when no compressor is registered.
final class BZip2CompressorTests: XCTestCase {

    private let compressor = BZip2Compressor()

    // MARK: - BZip2Compressor basic round-trip

    func testCompressDecompressRoundTrip() throws {
        let original = Data("The quick brown fox jumps over the lazy dog".utf8)
        let compressed = try XCTUnwrap(compressor.compress(original),
                                       "compression must succeed")
        let restored   = try XCTUnwrap(compressor.decompress(compressed),
                                       "decompression must succeed")
        XCTAssertEqual(restored, original)
    }

    func testCompressReducesLargeRepetitiveData() {
        let original = Data(repeating: 0xAB, count: 10_000)
        let compressed = compressor.compress(original)
        XCTAssertNotNil(compressed, "bz2 must compress 10 KB of repeated data")
        XCTAssertLessThan(compressed!.count, original.count,
                          "compressed should be smaller than input for repetitive data")
    }

    func testCompressDecompressRoundTripLargeBinary() throws {
        var data = Data((0..<4096).map { UInt8($0 & 0xFF) })
        // Repeat to make it 64 KB to test buffer expansion in decompress().
        data = Data(repeating: 0, count: 65536)
        (0..<65536).forEach { data[$0] = UInt8($0 & 0xFF) }
        let compressed = try XCTUnwrap(compressor.compress(data))
        let restored   = try XCTUnwrap(compressor.decompress(compressed))
        XCTAssertEqual(restored, data)
    }

    func testDecompressFailsOnGarbage() {
        let garbage = Data([0xFF, 0xFE, 0x00, 0x01, 0x02, 0x03])
        XCTAssertNil(compressor.decompress(garbage),
                     "decompress must return nil on invalid bz2 data")
    }

    func testCompressEmptyData() {
        let result = compressor.compress(Data())
        // Empty input → empty output (no-op, not nil).
        XCTAssertEqual(result, Data())
    }

    func testDecompressEmptyData() {
        let result = compressor.decompress(Data())
        XCTAssertEqual(result, Data())
    }

    // MARK: - Bounded decompression (decompression bomb guard)

    /// Bounded decompress returns `.success` when the output fits within
    /// `maxLength`. Mirrors Python's `BZ2Decompressor.decompress(max_length=...)`
    /// happy path (RNS commit 09b0469f).
    func testBoundedDecompressSuccessWithinLimit() throws {
        let original = Data(repeating: 0xCD, count: 1024)
        let compressed = try XCTUnwrap(compressor.compress(original))
        let result = compressor.decompress(compressed, maxLength: 4096)
        XCTAssertEqual(result, .success(original))
    }

    /// Bounded decompress refuses output that exceeds the cap. This is the
    /// decompression-bomb guard: a tiny compressed blob expanding to
    /// hundreds of MB must NOT be allocated.
    func testBoundedDecompressRefusesBomb() throws {
        // 256 KB of zeros compresses to ~70 bytes but expands to 256 KB.
        let bomb = Data(repeating: 0, count: 256 * 1024)
        let compressed = try XCTUnwrap(compressor.compress(bomb))
        // Cap well below bomb size: must reject.
        let result = compressor.decompress(compressed, maxLength: 4096)
        XCTAssertEqual(result, .exceededMaxLength,
                       "bounded decompress must reject output > maxLength")
    }

    /// Bounded decompress reports `.error` for genuinely malformed bz2 data
    /// (distinct from the `.exceededMaxLength` bomb signal).
    func testBoundedDecompressErrorOnGarbage() {
        let garbage = Data([0xFF, 0xFE, 0x00, 0x01, 0x02, 0x03])
        let result = compressor.decompress(garbage, maxLength: 4096)
        XCTAssertEqual(result, .error)
    }

    // MARK: - StreamDataMessage compressed flag (wire format)

    func testStreamDataMessageCompressedFlagInHeader() throws {
        StreamDataMessage.compressor = BZip2Compressor()
        defer { StreamDataMessage.compressor = nil }

        let payload = Data(repeating: 0xCC, count: 500)
        let msg = StreamDataMessage(streamID: 3, data: payload, eof: false, compress: true)
        let raw = try msg.pack()

        // Bit 14 (0x4000) in the two-byte header must be set.
        let header = UInt16(raw[0]) << 8 | UInt16(raw[1])
        XCTAssertTrue((header & 0x4000) != 0, "compressed bit (0x4000) must be set")
        XCTAssertEqual(header & 0x3FFF, 3, "stream_id must be preserved")
        XCTAssertFalse((header & 0x8000) != 0, "EOF must be clear")
    }

    func testStreamDataMessageNoCompressionWithoutCompressor() throws {
        StreamDataMessage.compressor = nil
        let payload = Data(repeating: 0xDD, count: 500)
        let msg = StreamDataMessage(streamID: 1, data: payload, eof: false, compress: true)
        let raw = try msg.pack()

        let header = UInt16(raw[0]) << 8 | UInt16(raw[1])
        XCTAssertFalse((header & 0x4000) != 0, "compressed bit must be clear when no compressor")
        XCTAssertEqual(Data(raw.dropFirst(2)), payload, "payload must be unchanged")
    }

    func testStreamDataMessageCompressedRoundTrip() throws {
        StreamDataMessage.compressor = BZip2Compressor()
        defer { StreamDataMessage.compressor = nil }

        let original = Data(repeating: 0xEE, count: 1000)
        let sent = StreamDataMessage(streamID: 7, data: original, eof: false, compress: true)
        let raw  = try sent.pack()

        let recv = StreamDataMessage()
        try recv.unpack(raw)

        XCTAssertEqual(recv.streamID, 7)
        XCTAssertFalse(recv.eof)
        XCTAssertEqual(recv.data, original,
                       "unpack must transparently decompress when compressor is set")
    }

    func testStreamDataMessageReceiveCompressedWithoutDecompressor() throws {
        // Sender compresses…
        StreamDataMessage.compressor = BZip2Compressor()
        let original = Data(repeating: 0xBB, count: 1000)
        let sent = StreamDataMessage(streamID: 0, data: original, eof: false, compress: true)
        let raw  = try sent.pack()

        // … but receiver has no compressor injected.
        StreamDataMessage.compressor = nil

        let recv = StreamDataMessage()
        try recv.unpack(raw)

        // Without a decompressor the receiver gets raw (still-compressed) bytes.
        XCTAssertTrue(recv.isCompressed, "isCompressed flag must be set")
        XCTAssertNotEqual(recv.data, original,
                          "data must differ from original when no decompressor")
    }

    // MARK: - ResourceCompressor integration

    func testResourceCompressorIsNoOpByDefault() {
        let c = Resource.compressor
        let data = Data("test".utf8)
        XCTAssertNil(c.compress(data),
                     "default Resource.compressor (NoCompressor) must return nil")
        XCTAssertNil(c.decompress(data),
                     "default Resource.compressor (NoCompressor) must return nil on decompress")
    }

    func testResourceCompressorCanBeReplacedWithBZ2() {
        let saved = Resource.compressor
        defer { Resource.compressor = saved }

        Resource.compressor = BZip2Compressor()
        let data = Data(repeating: 0xAA, count: 2048)
        let compressed = Resource.compressor.compress(data)
        XCTAssertNotNil(compressed, "BZip2Compressor must compress via Resource.compressor")
        let restored = compressed.flatMap { Resource.compressor.decompress($0) }
        XCTAssertEqual(restored, data)
    }

    // MARK: - Python bz2 magic bytes verification

    /// Python bz2.compress produces output starting with `BZh` (0x42 0x5A 0x68).
    func testOutputStartsWithBZipMagicBytes() throws {
        let data = Data("Hello Reticulum".utf8)
        let compressed = try XCTUnwrap(compressor.compress(data))
        XCTAssertGreaterThanOrEqual(compressed.count, 3)
        XCTAssertEqual(compressed[0], 0x42, "bz2 magic byte 0: 'B'")
        XCTAssertEqual(compressed[1], 0x5A, "bz2 magic byte 1: 'Z'")
        XCTAssertEqual(compressed[2], 0x68, "bz2 magic byte 2: 'h'")
    }
}
