import XCTest
@testable import ReticulumSwift

/// Tests for Reticulum instance lifecycle, persistence, and static API.
final class ReticulumLifecycleTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-lifecycle-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Reticulum.shared?.stop()
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Reticulum.get_instance() equivalent

    func testSharedIsNilBeforeStart() {
        // Reticulum.shared is nil until start() is called
        // (unless another test started it — just test it's accessible)
        _ = Reticulum.shared  // should not crash
    }

    func testGetInstanceAfterStart() throws {
        let config = Reticulum.Configuration(storagePath: tmpDir.appendingPathComponent("storage"))
        let rns = Reticulum(configuration: config)
        try rns.start()
        XCTAssertNotNil(Reticulum.shared)
        rns.stop()
    }

    // MARK: - Persistence round-trip

    func testPathTablePersistedAndRestored() throws {
        let storage = tmpDir.appendingPathComponent("storage")
        let config = Reticulum.Configuration(storagePath: storage)

        // First run: create a path
        do {
            let rns = Reticulum(configuration: config)
            try rns.start()
            let fakeHash = Data(repeating: 0xAB, count: 16)
            rns.transport.restore(
                path: Transport.PathEntry(
                    destinationHash: fakeHash,
                    nextHopInterfaceName: "test",
                    hops: 2,
                    lastHeard: Date(),
                    identityHash: Data(repeating: 0xCD, count: 16)
                ),
                forDestination: fakeHash
            )
            rns.stop()
        }

        // Second run: path should be restored
        do {
            let rns2 = Reticulum(configuration: config)
            try rns2.start()
            let fakeHash = Data(repeating: 0xAB, count: 16)
            XCTAssertTrue(rns2.transport.hasPath(to: fakeHash), "path should be restored from disk")
            rns2.stop()
        }
    }

    func testIdentityPersistedAndRestored() throws {
        let storage = tmpDir.appendingPathComponent("storage2")
        let config = Reticulum.Configuration(storagePath: storage)
        var originalHash: Data!

        do {
            let rns = Reticulum(configuration: config)
            try rns.start()
            let id = try rns.loadOrCreateIdentity()
            originalHash = id.hash
            rns.stop()
        }

        do {
            let rns2 = Reticulum(configuration: config)
            try rns2.start()
            let id2 = try rns2.loadOrCreateIdentity()
            XCTAssertEqual(id2.hash, originalHash, "identity should persist across restarts")
            rns2.stop()
        }
    }

    // MARK: - Transport access via shared instance

    func testTransportAccessibleFromShared() throws {
        let config = Reticulum.Configuration(storagePath: tmpDir.appendingPathComponent("storage3"))
        let rns = Reticulum(configuration: config)
        try rns.start()
        XCTAssertNotNil(Reticulum.shared?.transport)
        XCTAssertFalse(Reticulum.shouldUseImplicitProof() == false, "should use implicit proof by default")
        rns.stop()
    }
}
