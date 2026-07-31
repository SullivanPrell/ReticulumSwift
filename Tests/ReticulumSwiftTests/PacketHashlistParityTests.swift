import XCTest
@testable import ReticulumSwift

/// `storage/packet_hashlist.raw` must be the file the reference writes.
///
/// `bugs/029` — the port writes `storage/packet_hashlist`, a JSON array of hex strings. The
/// reference writes the hashes themselves, concatenated with no framing at all
/// (`Transport.py:3314-3316`), and reads them back by fixed-width chunks until a short read ends
/// the file (`:242-251`).
///
/// This is the replay window. A Python daemon that starts on a directory whose hashlist it cannot
/// parse starts with an empty one, so every packet still in flight is accepted a second time.
final class PacketHashlistParityTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-hashlist-parity-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private var fileURL: URL {
        tmpDir.appendingPathComponent(StorageInventory.Entry.packetHashlist.components.last!)
    }

    /// `for packet_hash in Transport.packet_hashlist.copy(): file.write(packet_hash)` —
    /// `Transport.py:3315-3323`. No delimiters, no length prefix, no encoding.
    func testFileIsRawConcatenatedHashes() throws {
        let transport = Transport()
        let hashes = (0..<4).map { Data(repeating: UInt8($0 + 1), count: Constants.fullHashLength) }
        hashes.forEach { transport.testInsertPacketHash($0) }

        try transport.savePacketHashlist(to: fileURL)

        let raw = try Data(contentsOf: fileURL)
        XCTAssertEqual(raw.count, hashes.count * Constants.fullHashLength,
                       """
                       the file is exactly `n × HASHLENGTH//8` bytes — the hashes concatenated \
                       (Transport.py:3323). A JSON array of hex strings is more than four times \
                       that and parses to nothing on the reference's fixed-width read \
                       (:246-250).
                       """)

        // Order is a set's order on both sides, so compare as sets — but every 32-byte window
        // must be one of the hashes, which is the property the framing question turns on.
        var recovered: Set<Data> = []
        var cursor = raw.startIndex
        while raw.distance(from: cursor, to: raw.endIndex) >= Constants.fullHashLength {
            let next = raw.index(cursor, offsetBy: Constants.fullHashLength)
            recovered.insert(Data(raw[cursor..<next]))
            cursor = next
        }
        XCTAssertEqual(recovered, Set(hashes),
                       "each fixed-width chunk must be one of the stored hashes")
    }

    /// `packet_hash = file.read(hashlen); if len(packet_hash) == hashlen: add … else: done = True`
    /// (`Transport.py:246-250`) — a file whose length is not a multiple of the hash length gives
    /// up the trailing partial record and keeps everything before it.
    func testTrailingPartialRecordIsConsumed() throws {
        let whole = (0..<3).map { Data(repeating: UInt8($0 + 10), count: Constants.fullHashLength) }
        var raw = Data()
        whole.forEach { raw.append($0) }
        raw.append(Data(repeating: 0xEE, count: 7))   // torn write
        try raw.write(to: fileURL)

        let transport = Transport()
        try transport.loadPacketHashlist(from: fileURL)

        for hash in whole {
            XCTAssertTrue(transport.testContainsPacketHash(hash),
                          "every complete record before the tear must load")
        }
        XCTAssertFalse(transport.testContainsPacketHash(Data(repeating: 0xEE, count: 7)),
                       "the partial record ends the read; it is not stored as a short hash")
    }

    /// An empty hashlist is an empty file, not `[]`.
    func testEmptyHashlistIsAnEmptyFile() throws {
        let transport = Transport()
        try transport.savePacketHashlist(to: fileURL)
        XCTAssertEqual(try Data(contentsOf: fileURL).count, 0)
    }

    func testRoundTrip() throws {
        let transport = Transport()
        // Full 32-byte hashes, because that is what the live filter stores:
        // `Hashes.fullHash(packet.hashablePart())`, mirroring Python's `packet.packet_hash`.
        // `Hashes.randomHash()` is 16 bytes and would be a record the reference's fixed-width
        // read cannot even see.
        let hashes = (0..<8).map { _ in Hashes.fullHash(Hashes.randomHash()) }
        hashes.forEach { transport.testInsertPacketHash($0) }
        try transport.savePacketHashlist(to: fileURL)

        let revived = Transport()
        try revived.loadPacketHashlist(from: fileURL)
        for hash in hashes {
            XCTAssertTrue(revived.testContainsPacketHash(hash),
                          "the replay window must survive a restart")
        }
    }
}
