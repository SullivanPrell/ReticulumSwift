import XCTest
@testable import ReticulumSwift

/// What a daemon does when the state it finds is not state it can use.
///
/// The reference's answer is always the same: start with that structure empty, log it, continue
/// (`Identity.py:238-240`, `Transport.py:243`, `:357-359`). `bugs/029` adopts it verbatim,
/// including for the port's *own* earlier formats — a reader for those would be
/// implementation-specific code on the exact seam this capability exists to make
/// implementation-independent, and the reference has no counterpart to it. The old files are
/// orphans: not read, not deleted, documented as safe to remove.
final class StorageStartupTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-startup-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: - Pre-parity files

    /// A directory holding only the port's pre-`029` files starts clean, and leaves them exactly
    /// as it found them.
    ///
    /// Two halves, and both matter. Starting empty is the reference's behaviour on a file it does
    /// not find. Leaving the bytes alone is the decision: a converting reader would be a
    /// divergence of its own, and silently deleting an operator's file to tidy up is worse than
    /// either.
    func testPreParityFilesAreLeftUntouched() throws {
        // The shapes the port actually wrote before this change.
        let legacy: [String: Data] = [
            "paths.json": Data("""
                {"entries":[{"destinationHashHex":"aabbccddeeff00112233445566778899",\
                "hops":2,"identityHashHex":"00112233445566778899aabbccddeeff",\
                "identityPublicKeyHex":"","lastHeard":"2026-07-01T00:00:00Z",\
                "nextHopInterfaceName":"eth0"}]}
                """.utf8),
            "known_destinations.json": Data("""
                {"aabbccddeeff00112233445566778899":\
                {"publicKey":"00","timestamp":1751328000.0}}
                """.utf8),
            "packet_hashlist": Data(#"["aabb","ccdd"]"#.utf8),
        ]
        XCTAssertEqual(Set(legacy.keys), Set(StorageInventory.preParityOrphans),
                       "the fixture must cover exactly the names the inventory calls orphans, "
                       + "or this test stops tracking the decision it exists for")
        for (name, contents) in legacy {
            try contents.write(to: dir.appendingPathComponent(name))
        }

        let rns = Reticulum(configuration: .init(storagePath: dir))
        rns.transport.register(interface: LoopbackInterface(name: "eth0"))
        XCTAssertNoThrow(try rns.start(), "a pre-parity directory must not prevent start")

        XCTAssertTrue(rns.transport.paths.isEmpty,
                      """
                      the path table starts empty: `paths.json` is not one of the reference's \
                      files, so nothing looks for it. Reading it would be Swift-only code on the \
                      seam this change exists to make implementation-independent (bugs/029, \
                      proposal).
                      """)
        XCTAssertNil(rns.transport.recall(identity: Data(hex: "aabbccddeeff00112233445566778899")!),
                     "known destinations start empty for the same reason")
        XCTAssertFalse(rns.transport.testContainsPacketHash(Data(hex: "aabb")!),
                       "and so does the replay hashlist")

        rns.stop()

        for (name, contents) in legacy {
            XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(name)), contents,
                           """
                           `\(name)` must be byte-identical after a clean shutdown. It is an \
                           orphan: not read, and not deleted either — removing an operator's \
                           file to tidy up is a decision this change did not make.
                           """)
        }
    }

    /// And the reference's files are written beside them, so the two sets coexist.
    func testReferenceFilesAreWrittenBesideTheOrphans() throws {
        try Data(#"["aabb"]"#.utf8).write(to: dir.appendingPathComponent("packet_hashlist"))

        let rns = Reticulum(configuration: .init(storagePath: dir))
        try rns.start()
        rns.transport.testInsertPacketHash(Hashes.fullHash(Hashes.randomHash()))
        rns.stop()

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: StorageInventory.url(.packetHashlist, storage: dir).path),
            "the reference's `packet_hashlist.raw` is written regardless of the orphan beside it")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("packet_hashlist").path),
            "and the orphan is still there")
    }

    // MARK: - Damaged files

    /// `except Exception … "Could not load destination table from storage"` and continue
    /// (`Transport.py:357-359`) — a truncated table costs the path table, not the daemon.
    func testTruncatedTableDoesNotPreventStart() throws {
        // A well-formed table, then cut mid-entry.
        let seed = Reticulum(configuration: .init(storagePath: dir))
        try seed.start()
        let iface = LoopbackInterface(name: "trunc0")
        seed.transport.register(interface: iface)
        try installPersistablePath(on: seed.transport, through: iface, aspect: "truncated")
        seed.stop()

        let tableURL = StorageInventory.url(.destinationTable, storage: dir)
        let whole = try Data(contentsOf: tableURL)
        XCTAssertGreaterThan(whole.count, 20, "the seed must have written a real table")
        try whole.prefix(whole.count / 2).write(to: tableURL)

        let rns = Reticulum(configuration: .init(storagePath: dir))
        rns.transport.register(interface: LoopbackInterface(name: "trunc0"))
        XCTAssertNoThrow(try rns.start(),
                         "the reference logs the failure and carries on (Transport.py:357-359); "
                         + "a daemon that will not start because of one damaged table cannot be "
                         + "recovered without deleting files by hand")
        defer { rns.stop() }
        XCTAssertTrue(rns.transport.paths.isEmpty, "and starts with an empty path table")
    }

    /// The same for the tunnel table (`Transport.py:406-407`), which is read in the same block.
    func testTruncatedTunnelTableDoesNotPreventStart() throws {
        try Data([0x93, 0xC4, 0x10]).write(to: StorageInventory.url(.tunnels, storage: dir))

        let rns = Reticulum(configuration: .init(storagePath: dir))
        XCTAssertNoThrow(try rns.start())
        defer { rns.stop() }
        XCTAssertTrue(rns.transport.tunnels.isEmpty)
    }

    /// And for known destinations (`Identity.py:236-239`, "file will be recreated on exit").
    func testUnreadableKnownDestinationsDoesNotPreventStart() throws {
        try Data("not msgpack at all".utf8)
            .write(to: StorageInventory.url(.knownDestinations, storage: dir))

        let rns = Reticulum(configuration: .init(storagePath: dir))
        XCTAssertNoThrow(try rns.start())
        defer { rns.stop() }
        XCTAssertNil(rns.transport.recall(identity: Data(repeating: 0xAA, count: 16)))
    }
}
