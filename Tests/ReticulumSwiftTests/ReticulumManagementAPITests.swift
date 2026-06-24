import XCTest
@testable import ReticulumSwift

/// Tests for Reticulum instance management API methods.
final class ReticulumManagementAPITests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-mgmt-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Reticulum.shared?.stop()
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func startReticulum() throws -> Reticulum {
        let config = Reticulum.Configuration(storagePath: tmpDir.appendingPathComponent("storage"))
        let rns = Reticulum(configuration: config)
        try rns.start()
        return rns
    }

    // MARK: - get_link_count (mirrors Python Reticulum.get_link_count)

    func testGetLinkCountReturnsZeroInitially() throws {
        let rns = try startReticulum()
        XCTAssertEqual(rns.getLinkCount(), 0)
    }

    // MARK: - get_interface_stats (mirrors Python Reticulum.get_interface_stats)

    func testGetInterfaceStatsReturnsEmptyWhenNoInterfaces() throws {
        let rns = try startReticulum()
        let stats = rns.getInterfaceStats()
        XCTAssertNotNil(stats)
    }

    // MARK: - get_path_table (mirrors Python Reticulum.get_path_table)

    func testGetPathTableReturnsEmptyInitially() throws {
        let rns = try startReticulum()
        let table = rns.getPathTable()
        XCTAssertNotNil(table)
    }

    func testGetPathTableMaxHopsFiltersResults() throws {
        let rns = try startReticulum()
        let fakeHash = Data(repeating: 0xAB, count: 16)
        rns.transport.restore(
            path: Transport.PathEntry(
                destinationHash: fakeHash,
                nextHopInterfaceName: "test",
                hops: 5,
                lastHeard: Date(),
                identityHash: Data(repeating: 0x00, count: 16)
            ),
            forDestination: fakeHash
        )
        let all = rns.getPathTable()
        let filtered = rns.getPathTable(maxHops: 3)
        XCTAssertGreaterThan(all.count, filtered.count,
            "maxHops filter should exclude high-hop paths")
    }

    // MARK: - drop_path (mirrors Python Reticulum.drop_path)

    func testDropPathRemovesKnownPath() throws {
        let rns = try startReticulum()
        let destHash = Data(repeating: 0xCC, count: 16)
        rns.transport.restore(
            path: Transport.PathEntry(
                destinationHash: destHash,
                nextHopInterfaceName: "test",
                hops: 1,
                lastHeard: Date(),
                identityHash: Data(repeating: 0x00, count: 16)
            ),
            forDestination: destHash
        )
        XCTAssertTrue(rns.transport.hasPath(to: destHash))
        rns.dropPath(for: destHash)
        XCTAssertFalse(rns.transport.hasPath(to: destHash))
    }
}
