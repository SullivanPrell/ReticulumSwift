import XCTest
@testable import ReticulumSwift

/// Tests for Transport packet hashlist persistence.
/// Mirrors Python's `Transport.save_packet_hashlist()` / loading in `__init__`.
///
/// Hashes here are the full 32 bytes the live filter stores —
/// `Hashes.fullHash(packet.hashablePart())`, mirroring Python's `packet.packet_hash`. They used
/// to be 16, a width no production path produces, and the port's hex-JSON codec round-tripped it
/// happily. The reference's file has no framing but the hash length (`Transport.py:3323`,
/// `:246-250`), so a wrong-width record is not a record at all — which is exactly why the format
/// and the width had to be fixed together (`bugs/029`).
final class PacketHashlistPersistenceTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-hashlist-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Round-trip

    func testSaveAndLoadRoundTrip() throws {
        let t = Transport()
        let hashes = (0..<10).map { _ in Hashes.fullHash(Hashes.randomHash()) }
        for h in hashes { t.testInsertPacketHash(h) }

        let url = tmpDir.appendingPathComponent(
            StorageInventory.Entry.packetHashlist.components.last!)
        try t.savePacketHashlist(to: url)

        let t2 = Transport()
        try t2.loadPacketHashlist(from: url)

        for h in hashes {
            XCTAssertTrue(t2.testContainsPacketHash(h), "loaded hashlist should contain \(h.hexString)")
        }
    }

    // MARK: - Duplicate rejection after load

    func testDuplicatePacketRejectedAfterLoad() throws {
        let t = Transport()
        let h = Hashes.fullHash(Hashes.randomHash())
        t.testInsertPacketHash(h)

        let url = tmpDir.appendingPathComponent(
            StorageInventory.Entry.packetHashlist.components.last!)
        try t.savePacketHashlist(to: url)

        let t2 = Transport()
        try t2.loadPacketHashlist(from: url)

        XCTAssertTrue(t2.testContainsPacketHash(h),
            "hash seen before save should be duplicate-rejected after load")
    }

    // MARK: - Missing file is a no-op

    func testLoadFromMissingFileIsNoop() throws {
        let t = Transport()
        let url = tmpDir.appendingPathComponent("nonexistent")
        // Should not throw; transport starts with empty hashlist.
        XCTAssertNoThrow(try t.loadPacketHashlist(from: url))
        let h = Data(repeating: 0xAB, count: Constants.fullHashLength)
        XCTAssertFalse(t.testContainsPacketHash(h))
    }

    // MARK: - Wired into Reticulum lifecycle

    func testReticulumStopSavesHashlistAndStartLoadsIt() throws {
        let dir = tmpDir.appendingPathComponent("rns-lifecycle")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = Reticulum.Configuration(storagePath: dir.appendingPathComponent("storage"))

        let rns = try Reticulum(configuration: config)
        try rns.start()

        // Insert a synthetic hash into transport's hashlist
        let h = Hashes.fullHash(Hashes.randomHash())
        rns.transport.testInsertPacketHash(h)
        rns.stop()

        // Verify the hashlist file was created
        let hashlistURL = StorageInventory.url(.packetHashlist, in: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: hashlistURL.path),
            "stop() should persist packet_hashlist file")

        // Start a fresh instance — hash should be seen as duplicate
        let rns2 = try Reticulum(configuration: config)
        try rns2.start()
        XCTAssertTrue(rns2.transport.testContainsPacketHash(h),
            "start() should restore packet_hashlist so seen hashes remain duplicates")
        rns2.stop()
    }
}
