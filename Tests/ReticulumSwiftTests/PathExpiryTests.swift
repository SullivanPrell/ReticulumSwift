import XCTest
@testable import ReticulumSwift

final class PathExpiryTests: XCTestCase {

    func testPathEntryIsExpiredAfterExpiry() {
        let now = Date()
        let entry = Transport.PathEntry(
            destinationHash: Data(repeating: 0x01, count: 16),
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: now.addingTimeInterval(-Transport.pathExpiry - 1),
            identityHash: Data(repeating: 0x02, count: 16),
            expires: now.addingTimeInterval(-1)
        )
        XCTAssertTrue(entry.isExpired)
    }

    func testPathEntryIsNotExpiredBeforeExpiry() {
        let entry = Transport.PathEntry(
            destinationHash: Data(repeating: 0x01, count: 16),
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: Date(),
            identityHash: Data(repeating: 0x02, count: 16)
        )
        XCTAssertFalse(entry.isExpired)
    }

    func testDefaultExpiryIsSevenDays() {
        let now = Date()
        let entry = Transport.PathEntry(
            destinationHash: Data(repeating: 0x01, count: 16),
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: now,
            identityHash: Data(repeating: 0x02, count: 16)
        )
        let delta = entry.expires.timeIntervalSince(now)
        XCTAssertEqual(delta, Transport.pathExpiry, accuracy: 1)
    }

    func testSweepExpiredPathsRemovesOldEntries() throws {
        let transport = Transport()
        let hash = Data(repeating: 0xAA, count: 16)
        let expired = Transport.PathEntry(
            destinationHash: hash,
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: Date().addingTimeInterval(-Transport.pathExpiry - 10),
            identityHash: Data(repeating: 0x01, count: 16),
            expires: Date().addingTimeInterval(-1)
        )
        transport.restore(path: expired, forDestination: hash)
        XCTAssertTrue(transport.hasPath(to: hash))

        transport.sweepExpiredPaths()
        XCTAssertFalse(transport.hasPath(to: hash))
    }

    func testSweepKeepsFreshPaths() throws {
        let transport = Transport()
        let hash = Data(repeating: 0xBB, count: 16)
        let fresh = Transport.PathEntry(
            destinationHash: hash,
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: Date(),
            identityHash: Data(repeating: 0x01, count: 16)
        )
        transport.restore(path: fresh, forDestination: hash)
        transport.sweepExpiredPaths()
        XCTAssertTrue(transport.hasPath(to: hash))
    }

    func testExpirePathRemovesSpecificDestination() throws {
        let transport = Transport()
        let hash = Data(repeating: 0xCC, count: 16)
        let entry = Transport.PathEntry(
            destinationHash: hash,
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: Date(),
            identityHash: Data(repeating: 0x01, count: 16)
        )
        transport.restore(path: entry, forDestination: hash)
        XCTAssertTrue(transport.hasPath(to: hash))
        transport.expirePath(for: hash)
        XCTAssertFalse(transport.hasPath(to: hash))
    }
}
