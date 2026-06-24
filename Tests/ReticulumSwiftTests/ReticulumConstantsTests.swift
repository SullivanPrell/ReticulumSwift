import XCTest
@testable import ReticulumSwift

/// Tests for Python-parity class-level constants on `Reticulum`.
///
/// Python reference (Reticulum.py):
///   Reticulum.ANNOUNCE_CAP              = 2          (raw %, not fraction)
///   Reticulum.MAX_QUEUED_ANNOUNCES      = 16384
///   Reticulum.GRACIOUS_PERSIST_INTERVAL = 60*5  = 300 s
///   Reticulum.PERSIST_INTERVAL          = 60*60*12   (already existed)
///   AnnounceQueue internal cap          = ANNOUNCE_CAP / 100.0 = 0.02
///   Reticulum.drop_announce_queues()    wraps Transport.drop_announce_queues()
final class ReticulumConstantsTests: XCTestCase {

    // MARK: - ANNOUNCE_CAP

    func testAnnounceCap() {
        XCTAssertEqual(Reticulum.announceCap, 2,
                       "ANNOUNCE_CAP must be 2 (raw percentage, not decimal fraction)")
    }

    func testAnnounceCapNormalisedIs0_02() {
        // Python uses: announce_cap = Reticulum.ANNOUNCE_CAP / 100.0  → 0.02
        XCTAssertEqual(Double(Reticulum.announceCap) / 100.0, 0.02, accuracy: 0.0001)
    }

    func testAnnounceQueueCapDerivesFromReticulumConstant() {
        // AnnounceQueue.announceCap must equal ANNOUNCE_CAP / 100.0
        XCTAssertEqual(AnnounceQueue.announceCap,
                       Double(Reticulum.announceCap) / 100.0,
                       accuracy: 0.0001,
                       "AnnounceQueue.announceCap must equal Reticulum.announceCap / 100.0")
    }

    // MARK: - MAX_QUEUED_ANNOUNCES

    func testMaxQueuedAnnounces() {
        XCTAssertEqual(Reticulum.maxQueuedAnnounces, 16384,
                       "MAX_QUEUED_ANNOUNCES must be 16384")
    }

    // MARK: - GRACIOUS_PERSIST_INTERVAL

    func testGraciousPersistInterval() {
        XCTAssertEqual(Reticulum.graciousPersistInterval, 300,
                       "GRACIOUS_PERSIST_INTERVAL must be 300 s (60*5)")
    }

    func testGraciousPersistIntervalShorterThanPersistInterval() {
        XCTAssertLessThan(Reticulum.graciousPersistInterval, Reticulum.persistInterval,
                          "gracious interval must be shorter than the full persist interval")
    }

    func testPersistIntervalRegressionGuard() {
        // PERSIST_INTERVAL = 60*60*12 — already existed, must not regress
        XCTAssertEqual(Reticulum.persistInterval, 43200,
                       "PERSIST_INTERVAL must remain 43200 s (12 hours)")
    }

    // MARK: - dropAnnounceQueues() on Transport

    func testTransportDropAnnounceQueuesEmptiesQueues() {
        let t = Transport()
        t.testInjectAnnounceQueue(interfaceName: "fake0")
        XCTAssertTrue(t.hasAnnounceQueue(for: "fake0"), "queue must exist before drop")

        t.dropAnnounceQueues()

        XCTAssertFalse(t.hasAnnounceQueue(for: "fake0"),
                       "queue must be gone after dropAnnounceQueues()")
    }

    func testTransportDropAnnounceQueuesIdempotent() {
        let t = Transport()
        t.dropAnnounceQueues()
        t.dropAnnounceQueues() // must not crash on empty queues
    }

    // MARK: - Reticulum.dropAnnounceQueues() wrapper

    func testReticulumDropAnnounceQueuesReturnsTrue() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RNSConstTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let rns = Reticulum(configuration: .init(storagePath: tmpDir))
        try rns.start()
        defer { rns.stop() }

        XCTAssertTrue(rns.dropAnnounceQueues(),
                      "dropAnnounceQueues() must return true")
    }

    func testReticulumDropAnnounceQueuesForwardsToTransport() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RNSConstTest2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let rns = Reticulum(configuration: .init(storagePath: tmpDir))
        try rns.start()
        defer { rns.stop() }

        rns.transport.testInjectAnnounceQueue(interfaceName: "fake1")
        XCTAssertTrue(rns.transport.hasAnnounceQueue(for: "fake1"))

        _ = rns.dropAnnounceQueues()

        XCTAssertFalse(rns.transport.hasAnnounceQueue(for: "fake1"),
                       "Reticulum.dropAnnounceQueues() must delegate to transport")
    }
}
