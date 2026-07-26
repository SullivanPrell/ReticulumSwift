import XCTest
@testable import ReticulumSwift

// MARK: - Process-global i2pd lifecycle rules
//
// `I2PDaemon` itself can't be unit-tested — starting it starts a real i2pd and
// stopping it terminates the process's crypto globals for good. The rule that
// keeps callers away from those two cliffs is factored out into
// `I2PDaemonPhase`, which is pure and testable.

final class I2PDaemonPhaseTests: XCTestCase {

    func testIdlePhaseAllowsStart() {
        XCTAssertNoThrow(try I2PDaemonPhase.idle.validateStart(),
                         "A fresh process may start i2pd")
    }

    func testRunningPhaseRefusesASecondDaemon() {
        XCTAssertThrowsError(try I2PDaemonPhase.running.validateStart(),
                             "i2pd's router is process-global; a second C_InitI2P would reconfigure the running one") { error in
            guard case I2PDaemonError.startFailed(let message) = error else {
                return XCTFail("Expected I2PDaemonError.startFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("already running"),
                          "The error should say a daemon is already running, got: \(message)")
        }
    }

    func testTerminatedPhaseRefusesReinitialisation() {
        XCTAssertThrowsError(try I2PDaemonPhase.terminated.validateStart(),
                             "C_TerminateI2P leaves i2pd's globals unusable; re-initialising them is undefined behaviour") { error in
            guard case I2PDaemonError.startFailed(let message) = error else {
                return XCTFail("Expected I2PDaemonError.startFailed, got \(error)")
            }
            // The message is user-visible via StackController's start log and
            // drives the "relaunch to apply" notice in RetiOS.
            XCTAssertTrue(message.contains("relaunch"),
                          "The error should tell the caller to relaunch, got: \(message)")
        }
    }
}
