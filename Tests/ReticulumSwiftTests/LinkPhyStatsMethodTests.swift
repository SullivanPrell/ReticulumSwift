import XCTest
@testable import ReticulumSwift

/// Tests for `Link.trackPhyStats(_:Bool)` — the explicit method form that
/// mirrors Python's `Link.track_phy_stats(track: bool)`.
final class LinkPhyStatsMethodTests: XCTestCase {

    // MARK: - Helpers

    final class FakeInterface: Interface {
        var name: String = "fake-phy-method"
        var bitrate: Int = 0
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }

    private func makeLink() throws -> Link {
        let t = Transport()
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["phymethod"])
        t.ownerIdentity = id
        t.register(destination: dest)
        t.register(interface: FakeInterface())
        return try Link.initiate(destination: dest, transport: t)
    }

    // MARK: - trackPhyStats(Bool) method form

    func testTrackPhyStatsEnablesTracking() throws {
        let link = try makeLink()
        XCTAssertFalse(link.trackPhyStats, "tracking must be disabled by default")
        link.trackPhyStats(true)
        XCTAssertTrue(link.trackPhyStats,
                      "trackPhyStats(true) must enable stat tracking")
    }

    func testTrackPhyStatsDisablesTracking() throws {
        let link = try makeLink()
        link.trackPhyStats(true)
        link.trackPhyStats(false)
        XCTAssertFalse(link.trackPhyStats,
                       "trackPhyStats(false) must disable stat tracking")
    }

    func testTrackPhyStatsIsIdempotent() throws {
        let link = try makeLink()
        link.trackPhyStats(true)
        link.trackPhyStats(true)
        XCTAssertTrue(link.trackPhyStats)
    }

    func testGetRssiNilWhenNotTracking() throws {
        let link = try makeLink()
        link.trackPhyStats(false)
        XCTAssertNil(link.getRssi(), "getRssi() must be nil when PHY tracking is disabled")
    }

    func testGetSnrNilWhenNotTracking() throws {
        let link = try makeLink()
        XCTAssertNil(link.getSnr(), "getSnr() must be nil when PHY tracking is disabled")
    }

    func testGetQNilWhenNotTracking() throws {
        let link = try makeLink()
        XCTAssertNil(link.getQ(), "getQ() must be nil when PHY tracking is disabled")
    }

    func testMethodAndPropertyAgree() throws {
        let link = try makeLink()
        link.trackPhyStats(true)
        XCTAssertEqual(link.trackPhyStats, true,
                       "method form and property must stay in sync")
        link.trackPhyStats(false)
        XCTAssertEqual(link.trackPhyStats, false)
    }
}
