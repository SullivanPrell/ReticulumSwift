import XCTest
@testable import ReticulumSwift

/// Tests for Destination class-level ratchet constants.
/// Python: Destination.RATCHET_COUNT = 512, Destination.RATCHET_INTERVAL = 30*60
final class DestinationRatchetConstantsTests: XCTestCase {

    func testRatchetCountConstant() {
        // Python: Destination.RATCHET_COUNT = 512
        XCTAssertEqual(Destination.ratchetCount, 512)
    }

    func testRatchetIntervalConstant() {
        // Python: Destination.RATCHET_INTERVAL = 30*60 = 1800
        XCTAssertEqual(Destination.ratchetInterval, 1800)
    }

    func testDefaultRetainedRatchetsConstantValue() throws {
        // Python: Destination.RATCHET_COUNT = 512
        // Swift: Identity.ratchetHistoryDepth defaults to 8 (practical limit for mobile)
        // But the class constant must be 512 for API parity
        XCTAssertEqual(Destination.ratchetCount, 512)
    }

    func testDefaultRatchetIntervalConstantValue() throws {
        // Python: Destination.RATCHET_INTERVAL = 1800 (30 minutes)
        XCTAssertEqual(Destination.ratchetInterval, 1800)
    }
}
