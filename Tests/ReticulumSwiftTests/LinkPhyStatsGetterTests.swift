import XCTest
@testable import ReticulumSwift

/// Tests for Link PHY stats getter methods.
/// Mirrors Python's `Link.track_phy_stats()`, `Link.get_rssi()`, `Link.get_snr()`, `Link.get_q()`.
final class LinkPhyStatsGetterTests: XCTestCase {

    final class FakeInterface: Interface {
        var name: String = "fake"
        var bitrate: Int = 0
        var isOnline: Bool = true
        var rssi: Float? = nil
        var snr: Float? = nil
        var quality: Float? = nil
        var inboundHandler: ((Packet, any Interface) -> Void)?
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }

    private func makeLink() throws -> Link {
        let t = Transport()
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "test", aspects: ["phy"])
        t.ownerIdentity = identity
        t.register(destination: dest)
        let iface = FakeInterface()
        t.register(interface: iface)
        let link = try Link.initiate(destination: dest, transport: t)
        return link
    }

    // MARK: - When trackPhyStats is false (default)

    func testGetRssiReturnsNilWhenTrackingDisabled() throws {
        let link = try makeLink()
        XCTAssertFalse(link.trackPhyStats)
        XCTAssertNil(link.getRssi(), "getRssi() should return nil when trackPhyStats is false")
    }

    func testGetSnrReturnsNilWhenTrackingDisabled() throws {
        let link = try makeLink()
        XCTAssertNil(link.getSnr(), "getSnr() should return nil when trackPhyStats is false")
    }

    func testGetQReturnsNilWhenTrackingDisabled() throws {
        let link = try makeLink()
        XCTAssertNil(link.getQ(), "getQ() should return nil when trackPhyStats is false")
    }

    // MARK: - When trackPhyStats is true but no stats received yet

    func testGettersReturnNilWhenEnabledButNoStats() throws {
        let link = try makeLink()
        link.trackPhyStats = true
        XCTAssertNil(link.getRssi())
        XCTAssertNil(link.getSnr())
        XCTAssertNil(link.getQ())
    }

    // MARK: - When trackPhyStats is true and stats are available

    func testGetRssiReturnsValueWhenTracking() throws {
        let link = try makeLink()
        link.trackPhyStats = true
        link.testSetPhyStats(rssi: -72.5, snr: 8.2, quality: 90.0)
        let v = try XCTUnwrap(link.getRssi())
        XCTAssertEqual(v, -72.5, accuracy: 0.001)
    }

    func testGetSnrReturnsValueWhenTracking() throws {
        let link = try makeLink()
        link.trackPhyStats = true
        link.testSetPhyStats(rssi: -72.5, snr: 8.2, quality: 90.0)
        let v = try XCTUnwrap(link.getSnr())
        XCTAssertEqual(v, 8.2, accuracy: 0.001)
    }

    func testGetQReturnsValueWhenTracking() throws {
        let link = try makeLink()
        link.trackPhyStats = true
        link.testSetPhyStats(rssi: -72.5, snr: 8.2, quality: 90.0)
        let v = try XCTUnwrap(link.getQ())
        XCTAssertEqual(v, 90.0, accuracy: 0.001)
    }

    // MARK: - Disabling tracking hides previously-recorded values

    func testDisablingTrackingHidesValues() throws {
        let link = try makeLink()
        link.trackPhyStats = true
        link.testSetPhyStats(rssi: -72.5, snr: 8.2, quality: 90.0)
        XCTAssertNotNil(link.getRssi())
        link.trackPhyStats = false
        XCTAssertNil(link.getRssi(), "after disabling tracking, getRssi() should return nil again")
        XCTAssertNil(link.getSnr())
        XCTAssertNil(link.getQ())
    }
}
