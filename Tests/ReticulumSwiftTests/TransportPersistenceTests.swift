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

        let destHash = Data(repeating: 0xAA, count: 16)
        let idHash   = Data(repeating: 0xBB, count: 16)
        let entry = Transport.PathEntry(
            destinationHash: destHash,
            nextHopInterfaceName: "test0",
            hops: 2,
            lastHeard: Date(),
            identityHash: idHash
        )
        rns1.transport.restore(path: entry, forDestination: destHash)
        XCTAssertTrue(rns1.transport.hasPath(to: destHash))
        rns1.stop()

        // --- Second instance: path must survive ---
        let rns2 = Reticulum(configuration: .init(storagePath: dir))
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

        let hashes = (0..<5).map { Data(repeating: UInt8($0 + 1), count: 16) }
        for (i, h) in hashes.enumerated() {
            let e = Transport.PathEntry(
                destinationHash: h,
                nextHopInterfaceName: "iface\(i)",
                hops: UInt8(i + 1),
                lastHeard: Date(),
                identityHash: Data(repeating: UInt8(0x10 + i), count: 16)
            )
            rns1.transport.restore(path: e, forDestination: h)
        }
        rns1.stop()

        let rns2 = Reticulum(configuration: .init(storagePath: dir))
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

        let destHash = Data(repeating: 0xDD, count: 16)
        let pastDate = Date(timeIntervalSinceNow: -Transport.pathExpiry - 60)
        let entry = Transport.PathEntry(
            destinationHash: destHash,
            nextHopInterfaceName: "old0",
            hops: 1,
            lastHeard: pastDate,
            identityHash: Data(repeating: 0x01, count: 16),
            expires: Date(timeIntervalSinceNow: -1)  // already expired
        )
        rns1.transport.restore(path: entry, forDestination: destHash)
        rns1.stop()

        let rns2 = Reticulum(configuration: .init(storagePath: dir))
        try rns2.start()
        defer { rns2.stop() }

        // start() sweeps expired paths on load
        XCTAssertFalse(rns2.transport.hasPath(to: destHash),
                       "expired paths must not be present after restart")
    }
}
