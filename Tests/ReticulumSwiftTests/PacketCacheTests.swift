import XCTest
@testable import ReticulumSwift

/// Tests for the disk-based announce packet cache.
///
/// Mirrors Python's `Transport.cache(packet, force_cache=True, packet_type="announce")`,
/// `Transport.get_cached_packet(hash, packet_type="announce")`, and
/// `Transport.clean_announce_cache()`.
///
/// The announce cache stores raw packet bytes indexed by packet hash so that
/// the path table can be fully restored across restarts.
final class PacketCacheTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-pkt-cache-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Basic round-trip

    func testCacheAndRetrieveAnnounce() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "cache", aspects: ["test"])
        let ann = try Announce.make(for: dest)
        let hash = Hashes.fullHash(try ann.hashablePart())

        try t.cacheAnnounce(ann)
        let retrieved = try t.getCachedAnnounce(hash: hash)

        XCTAssertNotNil(retrieved, "cached announce must be retrievable by its packet hash")
    }

    func testCachedPacketPreservesRawBytes() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "cache", aspects: ["raw"])
        let ann = try Announce.make(for: dest)
        let hash = Hashes.fullHash(try ann.hashablePart())
        let originalRaw = try ann.pack()

        try t.cacheAnnounce(ann)
        let retrieved = try XCTUnwrap(t.getCachedAnnounce(hash: hash))
        let retrievedRaw = try retrieved.pack()

        XCTAssertEqual(originalRaw, retrievedRaw,
            "cached and retrieved announce must have identical raw bytes")
    }

    // MARK: - Missing file returns nil

    func testGetCachedAnnounceReturnsNilForMissingHash() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        let fakeHash = Data(repeating: 0xDE, count: 32)
        let result = try t.getCachedAnnounce(hash: fakeHash)
        XCTAssertNil(result, "missing cache entry must return nil")
    }

    // MARK: - Announces directory created automatically

    func testCacheCreatesAnnouncesSubdirectory() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "cache", aspects: ["dir"])
        let ann = try Announce.make(for: dest)
        try t.cacheAnnounce(ann)

        let announcesDir = tmpDir.appendingPathComponent("announces")
        XCTAssertTrue(FileManager.default.fileExists(atPath: announcesDir.path),
            "caching an announce must create the 'announces' subdirectory")
    }

    // MARK: - cleanAnnounceCache removes stale entries

    func testCleanAnnounceCacheRemovesUnreferencedEntries() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        // Cache two announces — one will be referenced by a path, one will not.
        let id1 = Identity(); let id2 = Identity()
        let dest1 = try Destination(identity: id1, direction: .in, kind: .single,
                                    appName: "cache", aspects: ["keep"])
        let dest2 = try Destination(identity: id2, direction: .in, kind: .single,
                                    appName: "cache", aspects: ["drop"])
        let ann1 = try Announce.make(for: dest1)
        let ann2 = try Announce.make(for: dest2)
        let hash1 = Hashes.fullHash(try ann1.hashablePart())
        let hash2 = Hashes.fullHash(try ann2.hashablePart())

        try t.cacheAnnounce(ann1)
        try t.cacheAnnounce(ann2)

        // Add a path that references ann1's hash.
        let path = Transport.PathEntry(
            destinationHash: dest1.hash,
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: Date(),
            identityHash: id1.hash,
            cachedAnnounceHash: hash1
        )
        t.restore(path: path, forDestination: dest1.hash)

        // ann2 has no path → should be removed by clean.
        try t.cleanAnnounceCache()

        XCTAssertNotNil(try t.getCachedAnnounce(hash: hash1),
            "announce referenced by an active path must be retained")
        XCTAssertNil(try t.getCachedAnnounce(hash: hash2),
            "announce with no active path reference must be removed by clean")
    }

    // MARK: - Wired into announce handling

    func testAnnounceHandlingCachesPacketWhenCacheDirectorySet() throws {
        let t = Transport()
        t.cacheDirectory = tmpDir

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "cache", aspects: ["auto"])

        final class TestIface: Interface {
            var name = "cache-iface"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestIface()
        t.register(interface: iface)

        let ann = try Announce.make(for: dest)
        iface.inboundHandler?(try Packet.unpack(ann.pack()), iface)

        // The transport should have cached the announce on disk.
        let announcesDir = tmpDir.appendingPathComponent("announces")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: announcesDir.path)) ?? []
        XCTAssertFalse(files.isEmpty,
            "handling an announce must write it to the disk cache when cacheDirectory is set")
    }

    // MARK: - Reticulum lifecycle

    func testReticulumStartSetsCacheDirectory() throws {
        let dir = tmpDir.appendingPathComponent("rns-lifecycle")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storage = dir.appendingPathComponent("storage")
        let config = Reticulum.Configuration(storagePath: storage)

        let rns = try Reticulum(configuration: config)
        try rns.start()
        XCTAssertNotNil(rns.transport.cacheDirectory,
            "Reticulum.start() must configure transport.cacheDirectory")
        rns.stop()
    }
}
