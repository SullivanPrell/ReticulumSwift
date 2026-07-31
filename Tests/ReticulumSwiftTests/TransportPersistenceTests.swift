import XCTest
@testable import ReticulumSwift

/// Tests for the full Transport/Reticulum persistence cycle.
///
/// Python reference: Transport.persist_data() / Transport.save_path_table() /
///   Identity.save_known_destinations() / Transport.save_packet_hashlist()
///   all called from Transport.exit_handler and Reticulum.stop().
///
/// Swift: Reticulum.stop() saves paths + known destinations + packet hashlist;
///   Reticulum.start() restores all three.
final class TransportPersistenceTests: XCTestCase {

    private func makeTmpDir(tag: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RNSPersist-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Path table survives stop/start

    func testPathTableSurvivesRestart() throws {
        let dir = try makeTmpDir(tag: "paths")

        // --- First instance: register a path ---
        let rns1 = Reticulum(configuration: .init(storagePath: dir))
        try rns1.start()

        // A persisted path records its interface's hash and is dropped on load when nothing
        // matches (`bugs/027`, D6), so the same interface is registered on both runs — which is
        // what a real daemon does when it rebuilds interfaces from one config file.
        let iface1 = LoopbackInterface(name: "test0")
        rns1.transport.register(interface: iface1)

        // A real destination with its announce in the cache: the reference's entry references
        // that announce and discards any entry whose announce it cannot load
        // (`Transport.py:334-345`), so a synthetic destination hash is not a persistable path.
        let (destHash, _, _) = try installPersistablePath(on: rns1.transport,
                                                          through: iface1,
                                                          hops: 2,
                                                          aspect: "survives")
        XCTAssertTrue(rns1.transport.hasPath(to: destHash))
        rns1.stop()

        // --- Second instance: path must survive ---
        let rns2 = Reticulum(configuration: .init(storagePath: dir))
        rns2.transport.register(interface: LoopbackInterface(name: "test0"))
        try rns2.start()
        defer { rns2.stop() }

        XCTAssertTrue(rns2.transport.hasPath(to: destHash),
                      "path table must survive stop/start cycle")
        XCTAssertEqual(rns2.transport.hopsTo(destHash), 2,
                       "hop count must be preserved across restart")
    }

    func testMultiplePathsSurviveRestart() throws {
        let dir = try makeTmpDir(tag: "multipaths")
        let rns1 = Reticulum(configuration: .init(storagePath: dir))
        try rns1.start()

        let ifaces1 = (0..<5).map { LoopbackInterface(name: "iface\($0)") }
        ifaces1.forEach { rns1.transport.register(interface: $0) }
        let hashes = try (0..<5).map { i in
            try installPersistablePath(on: rns1.transport,
                                       through: ifaces1[i],
                                       hops: UInt8(i + 1),
                                       aspect: "multi\(i)").destinationHash
        }
        rns1.stop()

        let rns2 = Reticulum(configuration: .init(storagePath: dir))
        (0..<5).forEach { rns2.transport.register(interface: LoopbackInterface(name: "iface\($0)")) }
        try rns2.start()
        defer { rns2.stop() }

        for h in hashes {
            XCTAssertTrue(rns2.transport.hasPath(to: h),
                          "all paths must survive restart")
        }
    }

    // MARK: - Known destinations survive stop/start

    func testKnownDestinationsSurviveRestart() throws {
        let dir = try makeTmpDir(tag: "knowndest")
        let rns1 = Reticulum(configuration: .init(storagePath: dir))
        try rns1.start()

        let id = Identity()
        let destHash = Data(repeating: 0xCC, count: 16)
        rns1.transport.restore(identity: id, forDestination: destHash)
        XCTAssertNotNil(rns1.transport.recall(identity: destHash))
        rns1.stop()

        let rns2 = Reticulum(configuration: .init(storagePath: dir))
        try rns2.start()
        defer { rns2.stop() }

        let recalled = rns2.transport.recall(identity: destHash)
        XCTAssertNotNil(recalled, "known identity must survive stop/start cycle")
        XCTAssertEqual(recalled?.publicKeyBytes, id.publicKeyBytes,
                       "recalled identity must have same public key")
    }

    // MARK: - Packet hashlist survives stop/start

    func testPacketHashlistSurvivesRestart() throws {
        let dir = try makeTmpDir(tag: "hashlist")
        let rns1 = Reticulum(configuration: .init(storagePath: dir))
        try rns1.start()

        let fakeHash = Hashes.randomHash()
        rns1.transport.testInsertPacketHash(fakeHash)
        XCTAssertTrue(rns1.transport.testContainsPacketHash(fakeHash),
                      "hash must be present before stop")
        rns1.stop()

        let rns2 = Reticulum(configuration: .init(storagePath: dir))
        try rns2.start()
        defer { rns2.stop() }

        XCTAssertTrue(rns2.transport.testContainsPacketHash(fakeHash),
                      "packet hash must survive stop/start cycle")
    }

    // MARK: - Expired paths are NOT restored

    func testExpiredPathsNotRestoredOnStart() throws {
        let dir = try makeTmpDir(tag: "expired")
        let rns1 = Reticulum(configuration: .init(storagePath: dir))
        try rns1.start()

        // The interface is registered on **both** runs on purpose. Since `bugs/027` a path whose
        // stored interface hash resolves to nothing is dropped on load, so without this the
        // assertion below would pass for that reason instead of for expiry — the test would stop
        // testing what it is named for. A live path with the same setup is asserted alongside it
        // to keep that honest.
        let iface1 = LoopbackInterface(name: "old0")
        rns1.transport.register(interface: iface1)

        let pastDate = Date(timeIntervalSinceNow: -Transport.pathExpiry - 60)
        let (destHash, _, _) = try installPersistablePath(
            on: rns1.transport, through: iface1, aspect: "expired",
            lastHeard: pastDate,
            expires: Date(timeIntervalSinceNow: -1)  // already expired
        )
        let (liveHash, _, _) = try installPersistablePath(
            on: rns1.transport, through: iface1, aspect: "live")
        rns1.stop()

        let rns2 = Reticulum(configuration: .init(storagePath: dir))
        rns2.transport.register(interface: LoopbackInterface(name: "old0"))
        try rns2.start()
        defer { rns2.stop() }

        // start() sweeps expired paths on load
        XCTAssertFalse(rns2.transport.hasPath(to: destHash),
                       "expired paths must not be present after restart")
        XCTAssertTrue(rns2.transport.hasPath(to: liveHash),
                      "a live path through the same interface must survive — otherwise the "
                      + "assertion above proves only that nothing was restored at all")
    }
}
