import XCTest
@testable import ReticulumSwift

/// Tests for known destinations persistence.
/// Mirrors Python's `Identity.save_known_destinations()` / `Identity.load_known_destinations()`.
final class KnownDestinationsPersistenceTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() throws {
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["persist"])
        let appData = Data("hello known destinations".utf8)
        id.appData = appData

        let transport = Transport()
        transport.restore(identity: id, forDestination: dest.hash)

        let url = tmpDir.appendingPathComponent("known_destinations.json")
        try transport.saveKnownDestinations(to: url)

        // Load into a fresh transport
        let transport2 = Transport()
        try transport2.loadKnownDestinations(from: url)

        let recalled = transport2.recall(identity: dest.hash)
        XCTAssertNotNil(recalled, "should recall identity after load")
        XCTAssertEqual(recalled?.hash, id.hash, "recalled identity should match original")
        XCTAssertEqual(recalled?.appData, appData, "app data should be preserved")
    }

    func testLoadDoesNotOverwriteExistingEntry() throws {
        let id1 = Identity()
        let id2 = Identity()
        let destHash = Data(repeating: 0xAB, count: 16)

        let t = Transport()
        t.restore(identity: id1, forDestination: destHash)

        // Save id2 as if it was from a previous run
        let t2 = Transport()
        t2.restore(identity: id2, forDestination: destHash)
        let url = tmpDir.appendingPathComponent("known_destinations.json")
        try t2.saveKnownDestinations(to: url)

        // Load shouldn't overwrite the existing id1 entry
        try t.loadKnownDestinations(from: url)
        let recalled = t.recall(identity: destHash)
        XCTAssertEqual(recalled?.hash, id1.hash,
            "existing entry should not be overwritten on load")
    }

    func testSaveHandlesMultipleDestinations() throws {
        let t = Transport()
        var hashes: [Data] = []
        for i in 0..<5 {
            let id = Identity()
            let h = Hashes.truncatedHash(Data("dest\(i)".utf8))
            id.appData = Data("app\(i)".utf8)
            t.restore(identity: id, forDestination: h)
            hashes.append(h)
        }

        let url = tmpDir.appendingPathComponent("known_destinations.json")
        try t.saveKnownDestinations(to: url)

        let t2 = Transport()
        try t2.loadKnownDestinations(from: url)

        for (i, h) in hashes.enumerated() {
            XCTAssertNotNil(t2.recall(identity: h), "destination \(i) should be recalled")
            XCTAssertEqual(t2.recallAppData(forDestination: h), Data("app\(i)".utf8))
        }
    }
}
