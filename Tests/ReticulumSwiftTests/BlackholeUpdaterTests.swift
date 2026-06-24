import XCTest
@testable import ReticulumSwift

final class BlackholeUpdaterTests: XCTestCase {

    func testInitialStateIsStopped() {
        let updater = BlackholeUpdater()
        XCTAssertFalse(updater.isRunning)
    }

    func testUpdateIntervalConstant() {
        XCTAssertEqual(BlackholeUpdater.updateInterval, 3600, accuracy: 0.01)
    }

    func testJobIntervalConstant() {
        XCTAssertEqual(BlackholeUpdater.jobInterval, 60, accuracy: 0.01)
    }

    func testInitialWaitConstant() {
        XCTAssertEqual(BlackholeUpdater.initialWait, 20, accuracy: 0.01)
    }

    func testSourceTimeoutConstant() {
        XCTAssertEqual(BlackholeUpdater.sourceTimeout, 25, accuracy: 0.01)
    }

    func testStartSetsIsRunning() {
        let updater = BlackholeUpdater()
        updater.start()
        XCTAssertTrue(updater.isRunning)
        updater.stop()
    }

    func testStopClearsIsRunning() {
        let updater = BlackholeUpdater()
        updater.start()
        updater.stop()
        XCTAssertFalse(updater.isRunning)
    }

    func testStartIdempotent() {
        let updater = BlackholeUpdater()
        updater.start()
        updater.start()  // second start is a no-op
        XCTAssertTrue(updater.isRunning)
        updater.stop()
    }

    func testTickDoesNothingWithNoSources() {
        // When blackholeSources() returns [] tick() must not crash.
        // Reticulum.blackholeSources_ defaults to [] so no mutation needed.
        let updater = BlackholeUpdater()
        updater.tick()  // must not crash
    }

    func testTickIsIdempotentWithNoTransport() {
        // Calling tick() multiple times without a transport reference must not crash.
        let updater = BlackholeUpdater(transport: nil)
        updater.tick()
        updater.tick()
    }
}
