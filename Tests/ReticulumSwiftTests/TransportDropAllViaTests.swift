import XCTest
@testable import ReticulumSwift

/// Tests for Transport.dropAllPaths(via:) returning a count and
/// Reticulum.dropAllVia(_:) management API.
/// Mirrors Python's Reticulum.drop_all_via(transport_hash).
final class TransportDropAllViaTests: XCTestCase {

    private func makeTransport() -> Transport {
        let t = Transport()
        return t
    }

    private func injectPath(
        into t: Transport,
        destinationHash: Data,
        nextHopTransportID: Data?
    ) {
        t.restore(
            path: Transport.PathEntry(
                destinationHash: destinationHash,
                nextHopInterfaceName: "test",
                hops: 1,
                lastHeard: Date(),
                identityHash: Data(repeating: 0x00, count: 16),
                nextHopTransportID: nextHopTransportID
            ),
            forDestination: destinationHash
        )
    }

    // MARK: - dropAllPaths returns count

    func testDropAllPathsViaReturnsZeroWhenNoMatch() {
        let t = makeTransport()
        let transportID = Data(repeating: 0xAA, count: 16)
        let otherID = Data(repeating: 0xBB, count: 16)
        let destHash = Data(repeating: 0x01, count: 16)
        injectPath(into: t, destinationHash: destHash, nextHopTransportID: otherID)

        let dropped = t.dropAllPaths(via: transportID)
        XCTAssertEqual(dropped, 0)
        XCTAssertTrue(t.hasPath(to: destHash), "Unmatched path must survive")
    }

    func testDropAllPathsViaReturnsCountOfDroppedPaths() {
        let t = makeTransport()
        let transportID = Data(repeating: 0xAA, count: 16)
        let dest1 = Data(repeating: 0x01, count: 16)
        let dest2 = Data(repeating: 0x02, count: 16)
        let dest3 = Data(repeating: 0x03, count: 16)

        injectPath(into: t, destinationHash: dest1, nextHopTransportID: transportID)
        injectPath(into: t, destinationHash: dest2, nextHopTransportID: transportID)
        injectPath(into: t, destinationHash: dest3, nextHopTransportID: nil) // no transport ID

        let dropped = t.dropAllPaths(via: transportID)
        XCTAssertEqual(dropped, 2)
        XCTAssertFalse(t.hasPath(to: dest1))
        XCTAssertFalse(t.hasPath(to: dest2))
        XCTAssertTrue(t.hasPath(to: dest3), "Path without transport ID must survive")
    }

    func testDropAllPathsViaDropsOnlyMatchingTransport() {
        let t = makeTransport()
        let transportA = Data(repeating: 0xAA, count: 16)
        let transportB = Data(repeating: 0xBB, count: 16)
        let dest1 = Data(repeating: 0x01, count: 16)
        let dest2 = Data(repeating: 0x02, count: 16)

        injectPath(into: t, destinationHash: dest1, nextHopTransportID: transportA)
        injectPath(into: t, destinationHash: dest2, nextHopTransportID: transportB)

        let dropped = t.dropAllPaths(via: transportA)
        XCTAssertEqual(dropped, 1)
        XCTAssertFalse(t.hasPath(to: dest1))
        XCTAssertTrue(t.hasPath(to: dest2))
    }

    // MARK: - Reticulum.dropAllVia

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-dav-\(UUID().uuidString)")
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

    func testReticulumDropAllViaReturnsCountAndRemovesPaths() throws {
        let rns = try startReticulum()
        let transportID = Data(repeating: 0xCC, count: 16)
        let dest1 = Data(repeating: 0x10, count: 16)
        let dest2 = Data(repeating: 0x11, count: 16)

        rns.transport.restore(
            path: Transport.PathEntry(
                destinationHash: dest1, nextHopInterfaceName: "t",
                hops: 2, lastHeard: Date(),
                identityHash: Data(repeating: 0x00, count: 16),
                nextHopTransportID: transportID
            ),
            forDestination: dest1
        )
        rns.transport.restore(
            path: Transport.PathEntry(
                destinationHash: dest2, nextHopInterfaceName: "t",
                hops: 1, lastHeard: Date(),
                identityHash: Data(repeating: 0x00, count: 16),
                nextHopTransportID: transportID
            ),
            forDestination: dest2
        )

        let dropped = rns.dropAllVia(transportHash: transportID)
        XCTAssertEqual(dropped, 2)
        XCTAssertFalse(rns.transport.hasPath(to: dest1))
        XCTAssertFalse(rns.transport.hasPath(to: dest2))
    }
}
