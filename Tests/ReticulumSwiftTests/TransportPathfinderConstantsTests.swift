import XCTest
@testable import ReticulumSwift

/// Tests verifying Transport path-finding constants match the Python reference.
///
/// Python reference (Transport.py):
///   Transport.PATHFINDER_M            = 128
///   Transport.PATHFINDER_R            = 1
///   Transport.PATHFINDER_G            = 5
///   Transport.PATHFINDER_RW           = 0.5
///   Transport.PATHFINDER_E            = 60*60*24*7  (7 days)
///   Transport.AP_PATH_TIME            = 60*60*24    (1 day)
///   Transport.ROAMING_PATH_TIME       = 60*60*6     (6 hours)
///   Transport.PATH_REQUEST_TIMEOUT    = 15
///   Transport.PATH_REQUEST_GRACE      = 0.4
///   Transport.PATH_REQUEST_RG         = 1.5
///   Transport.PATH_REQUEST_GATE_TIMEOUT = 120
///   Transport.PATH_REQUEST_MI         = 20
///   Transport.LOCAL_REBROADCASTS_MAX  = 2
final class TransportPathfinderConstantsTests: XCTestCase {

    func testPathfinderM() {
        XCTAssertEqual(Transport.pathfinderM, 128,
                       "PATHFINDER_M must be 128 (maximum hop limit)")
    }

    func testPathRequestRetries() {
        XCTAssertEqual(Transport.pathRequestRetries, 1,
                       "PATHFINDER_R must be 1 (retransmit retries)")
    }

    func testPathfinderG() {
        XCTAssertEqual(Transport.pathfinderG, 5,
                       "PATHFINDER_G must be 5 seconds (retry grace period)")
    }

    func testPathfinderRW() {
        XCTAssertEqual(Transport.pathfinderRW, 0.5, accuracy: 0.001,
                       "PATHFINDER_RW must be 0.5 (random rebroadcast window)")
    }

    func testPathRequestGrace() {
        XCTAssertEqual(Transport.pathRequestGrace, 0.4, accuracy: 0.001,
                       "PATH_REQUEST_GRACE must be 0.4 seconds")
    }

    func testPathRequestRG() {
        XCTAssertEqual(Transport.pathRequestRG, 1.5, accuracy: 0.001,
                       "PATH_REQUEST_RG must be 1.5 seconds (roaming extra grace)")
    }

    func testPathRequestTimeout() {
        XCTAssertEqual(Transport.pathRequestTimeout, 15,
                       "PATH_REQUEST_TIMEOUT must be 15 seconds")
    }

    func testPathRequestGateTimeout() {
        XCTAssertEqual(Transport.pathRequestGateTimeout, 120,
                       "PATH_REQUEST_GATE_TIMEOUT must be 120 seconds")
    }

    func testPathRequestMinInterval() {
        XCTAssertEqual(Transport.pathRequestMinInterval, 20,
                       "PATH_REQUEST_MI must be 20 seconds")
    }

    func testLocalRebroadcastsMax() {
        XCTAssertEqual(Transport.localRebroadcastsMax, 2,
                       "LOCAL_REBROADCASTS_MAX must be 2")
    }

    func testRoamingPathExpiry() {
        XCTAssertEqual(Transport.roamingPathExpiry, 6 * 60 * 60,
                       "ROAMING_PATH_TIME must be 6 hours")
    }

    func testApPathExpiry() {
        XCTAssertEqual(Transport.apPathExpiry, 24 * 60 * 60,
                       "AP_PATH_TIME must be 1 day (24 hours), not 1 hour")
    }

    func testPathExpiryIs7Days() {
        XCTAssertEqual(Transport.pathExpiry, 7 * 24 * 60 * 60,
                       "PATHFINDER_E must be 7 days")
    }

    /// The per-instance propagation limit must default to PATHFINDER_M.
    func testPropagationLimitDefaultsToPathfinderM() {
        let t = Transport()
        XCTAssertEqual(t.propagationLimit, UInt8(Transport.pathfinderM),
                       "propagationLimit must default to pathfinderM (128)")
    }
}
