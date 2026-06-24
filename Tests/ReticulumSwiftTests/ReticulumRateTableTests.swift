import XCTest
@testable import ReticulumSwift

/// Tests for Reticulum.getRateTable() — mirrors Python's Reticulum.get_rate_table().
final class ReticulumRateTableTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-rt-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Reticulum.shared?.stop()
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func startReticulum() throws -> Reticulum {
        let cfg = Reticulum.Configuration(storagePath: tmpDir.appendingPathComponent("storage"))
        let rns = Reticulum(configuration: cfg)
        try rns.start()
        return rns
    }

    func testGetRateTableReturnsEmptyInitially() throws {
        let rns = try startReticulum()
        let table = rns.getRateTable()
        XCTAssertTrue(table.isEmpty, "Rate table must be empty before any announces")
    }

    func testGetRateTableReturnsEntryAfterRateLimitTracking() throws {
        let rns = try startReticulum()
        let destHash = Data(repeating: 0xAB, count: 16)

        // Inject a rate entry directly via the internal announce rate table.
        rns.transport.testInjectRateEntry(for: destHash, last: Date().timeIntervalSince1970)

        let table = rns.getRateTable()
        XCTAssertFalse(table.isEmpty, "Rate table must contain injected entry")
        XCTAssertTrue(table.contains(where: { $0.destinationHash == destHash }),
            "Rate table entry must match the injected destination hash")
    }

    func testGetRateTableEntryHasRequiredFields() throws {
        let rns = try startReticulum()
        let destHash = Data(repeating: 0xCD, count: 16)
        let now = Date().timeIntervalSince1970
        rns.transport.testInjectRateEntry(for: destHash, last: now)

        let table = rns.getRateTable()
        guard let entry = table.first(where: { $0.destinationHash == destHash }) else {
            XCTFail("Entry not found"); return
        }
        XCTAssertEqual(entry.last, now, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(entry.rateViolations, 0)
    }
}
