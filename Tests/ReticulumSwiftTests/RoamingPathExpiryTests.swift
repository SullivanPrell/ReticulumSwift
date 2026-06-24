import XCTest
@testable import ReticulumSwift

/// Tests for roaming-interface and access-point path expiry.
///
/// Python reference:
///   Transport.ROAMING_PATH_TIME = 60*60*6    (6 hours)
///   Transport.AP_PATH_TIME      = 60*60*24   (1 day)
///   Transport.PATHFINDER_E      = 7*24*60*60 (7 days)
///
/// Paths learned from a ROAMING-mode interface expire after 6 hours and paths
/// from an ACCESS_POINT-mode interface expire after 1 hour, instead of the
/// normal 7-day expiry. This matters for mobile nodes that move between
/// transport nodes frequently.
final class RoamingPathExpiryTests: XCTestCase {

    // MARK: - Constants

    func testRoamingPathExpiryIs6Hours() {
        XCTAssertEqual(Transport.roamingPathExpiry, 6 * 60 * 60,
                       "ROAMING_PATH_EXPIRY must be 6 hours (21600 seconds)")
    }

    func testApPathExpiryIs1Day() {
        XCTAssertEqual(Transport.apPathExpiry, 24 * 60 * 60,
                       "AP_PATH_TIME must be 1 day (86400 seconds), not 1 hour")
    }

    func testPathExpiryIs7Days() {
        XCTAssertEqual(Transport.pathExpiry, 7 * 24 * 60 * 60,
                       "PATHFINDER_E must be 7 days")
    }

    // MARK: - Roaming interface → short expiry

    final class ModeInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        var mode: InterfaceMode
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String, mode: InterfaceMode = .full) { self.name = name; self.mode = mode }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws {}
    }

    /// Inject a real announce on an interface and check the path expiry stored.
    private func injectAndGetExpiry(mode: InterfaceMode) throws -> TimeInterval {
        let transport = Transport()

        let iface = ModeInterface(name: "iface", mode: mode)
        transport.register(interface: iface)

        let id   = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["expiry"])
        let before = Date()
        let announce = try Announce.make(for: dest)
        // Inject directly via inbound handler
        iface.inboundHandler?(announce, iface)
        let after = Date()

        guard let entry = transport.paths[dest.hash] else {
            XCTFail("path must be recorded after announce")
            return 0
        }
        // Return seconds from "now" to expiry (clamped to nearest second)
        return entry.expires.timeIntervalSince(before.addingTimeInterval(
            after.timeIntervalSince(before) / 2
        ))
    }

    func testFullInterfacePathExpiresIn7Days() throws {
        let expiry = try injectAndGetExpiry(mode: .full)
        XCTAssertEqual(expiry, Transport.pathExpiry, accuracy: 2,
                       "FULL-mode interface paths must expire in 7 days")
    }

    func testRoamingInterfacePathExpiresIn6Hours() throws {
        let expiry = try injectAndGetExpiry(mode: .roaming)
        XCTAssertEqual(expiry, Transport.roamingPathExpiry, accuracy: 2,
                       "ROAMING-mode interface paths must expire in 6 hours")
    }

    func testGatewayInterfacePathExpiresIn7Days() throws {
        let expiry = try injectAndGetExpiry(mode: .gateway)
        XCTAssertEqual(expiry, Transport.pathExpiry, accuracy: 2,
                       "GATEWAY-mode interface paths must expire in 7 days")
    }

    func testAccessPointInterfacePathExpiresIn1Day() throws {
        let expiry = try injectAndGetExpiry(mode: .accessPoint)
        XCTAssertEqual(expiry, Transport.apPathExpiry, accuracy: 2,
                       "ACCESS_POINT-mode interface paths must expire in 1 day (AP_PATH_TIME)")
    }

    // MARK: - Roaming paths swept correctly

    func testRoamingPathSweptAfterShortExpiry() throws {
        let transport = Transport()
        let hash = Data(repeating: 0xAB, count: 16)

        // Directly restore a path with roaming-short expiry already elapsed.
        let shortExpiry = Transport.roamingPathExpiry
        let entry = Transport.PathEntry(
            destinationHash: hash,
            nextHopInterfaceName: "roam",
            hops: 1,
            lastHeard: Date().addingTimeInterval(-shortExpiry - 60),
            identityHash: Data(repeating: 0x01, count: 16),
            expires: Date().addingTimeInterval(-1)   // already expired
        )
        transport.restore(path: entry, forDestination: hash)
        XCTAssertTrue(transport.hasPath(to: hash))

        transport.sweepExpiredPaths()
        XCTAssertFalse(transport.hasPath(to: hash),
                       "expired roaming path must be swept from the path table")
    }

    func testNormalPathNotSweptAfterRoamingWindow() throws {
        let transport = Transport()
        let hash = Data(repeating: 0xCD, count: 16)

        // 7-day path that is only 6 hours old — should not be swept.
        let entry = Transport.PathEntry(
            destinationHash: hash,
            nextHopInterfaceName: "full",
            hops: 1,
            lastHeard: Date().addingTimeInterval(-Transport.roamingPathExpiry - 60),
            identityHash: Data(repeating: 0x02, count: 16)
            // expires = lastHeard + 7 days (default) → still in the future
        )
        transport.restore(path: entry, forDestination: hash)
        transport.sweepExpiredPaths()
        XCTAssertTrue(transport.hasPath(to: hash),
                      "normal 7-day path must not be swept after only 6 hours")
    }

    func testAccessPointPathSweptAfterShortExpiry() throws {
        let transport = Transport()
        let hash = Data(repeating: 0xEF, count: 16)

        // AP path with expiry already elapsed.
        let entry = Transport.PathEntry(
            destinationHash: hash,
            nextHopInterfaceName: "ap",
            hops: 1,
            lastHeard: Date().addingTimeInterval(-Transport.apPathExpiry - 60),
            identityHash: Data(repeating: 0x03, count: 16),
            expires: Date().addingTimeInterval(-1)   // already expired
        )
        transport.restore(path: entry, forDestination: hash)
        XCTAssertTrue(transport.hasPath(to: hash))

        transport.sweepExpiredPaths()
        XCTAssertFalse(transport.hasPath(to: hash),
                       "expired AP path must be swept from the path table")
    }

    func testNormalPathNotSweptAfterApWindow() throws {
        let transport = Transport()
        let hash = Data(repeating: 0x12, count: 16)

        // 7-day path that is only 1 day old — must not be swept.
        let entry = Transport.PathEntry(
            destinationHash: hash,
            nextHopInterfaceName: "full2",
            hops: 1,
            lastHeard: Date().addingTimeInterval(-Transport.apPathExpiry - 30),
            identityHash: Data(repeating: 0x04, count: 16)
            // default expires = now + 7 days
        )
        transport.restore(path: entry, forDestination: hash)
        transport.sweepExpiredPaths()
        XCTAssertTrue(transport.hasPath(to: hash),
                      "normal 7-day path must not be swept after only 1 day")
    }
}
