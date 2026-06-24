import XCTest
@testable import ReticulumSwift

/// Tests for `Reticulum.log()` and log-level constants.
///
/// Python reference:
///   RNS.LOG_CRITICAL = 0
///   RNS.LOG_ERROR    = 1
///   RNS.LOG_WARNING  = 2
///   RNS.LOG_NOTICE   = 3
///   RNS.LOG_INFO     = 4
///   RNS.LOG_VERBOSE  = 5
///   RNS.LOG_DEBUG    = 6
///   RNS.LOG_EXTREME  = 7
///   RNS.log(msg, level=RNS.LOG_NOTICE)
final class ReticulumLogTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset to defaults before each test.
        Reticulum.globalLogLevel = .notice
        Reticulum.logHandler = nil
    }

    override func tearDown() {
        Reticulum.globalLogLevel = .notice
        Reticulum.logHandler = nil
        super.tearDown()
    }

    // MARK: - Log-level integer values

    func testLogCriticalRawValue() {
        XCTAssertEqual(Reticulum.logCritical.rawValue, 0)
    }
    func testLogErrorRawValue() {
        XCTAssertEqual(Reticulum.logError.rawValue, 1)
    }
    func testLogWarningRawValue() {
        XCTAssertEqual(Reticulum.logWarning.rawValue, 2)
    }
    func testLogNoticeRawValue() {
        XCTAssertEqual(Reticulum.logNotice.rawValue, 3)
    }
    func testLogInfoRawValue() {
        XCTAssertEqual(Reticulum.logInfo.rawValue, 4)
    }
    func testLogVerboseRawValue() {
        XCTAssertEqual(Reticulum.logVerbose.rawValue, 5)
    }
    func testLogDebugRawValue() {
        XCTAssertEqual(Reticulum.logDebug.rawValue, 6)
    }
    func testLogExtremeRawValue() {
        XCTAssertEqual(Reticulum.logExtreme.rawValue, 7)
    }

    // MARK: - Routing through logHandler

    func testLogHandlerReceivesMessage() {
        var received: (String, Reticulum.LogLevel)?
        Reticulum.globalLogLevel = .extreme   // allow all
        Reticulum.logHandler = { msg, lvl in received = (msg, lvl) }

        Reticulum.log("hello", level: .notice)

        XCTAssertEqual(received?.0, "hello")
        XCTAssertEqual(received?.1, .notice)
    }

    func testLogHandlerNotCalledWhenLevelBelowThreshold() {
        var called = false
        Reticulum.globalLogLevel = .error  // only critical and error pass
        Reticulum.logHandler = { _, _ in called = true }

        Reticulum.log("suppressed", level: .info)

        XCTAssertFalse(called, "message below threshold must not reach the handler")
    }

    func testLogHandlerCalledForCritical() {
        var called = false
        Reticulum.globalLogLevel = .notice
        Reticulum.logHandler = { _, _ in called = true }

        Reticulum.log("critical!", level: .critical)

        XCTAssertTrue(called, "CRITICAL is always above any notice-or-lower threshold")
    }

    func testDefaultLevelIsNotice() {
        // The default level used when no level is supplied must be .notice
        var received: Reticulum.LogLevel?
        Reticulum.globalLogLevel = .extreme
        Reticulum.logHandler = { _, lvl in received = lvl }

        Reticulum.log("no level specified")

        XCTAssertEqual(received, .notice,
                       "default log level must be .notice (mirrors Python LOG_NOTICE)")
    }

    // MARK: - Ordering

    func testLogLevelOrdering() {
        XCTAssertLessThan(Reticulum.logCritical, Reticulum.logError)
        XCTAssertLessThan(Reticulum.logError, Reticulum.logWarning)
        XCTAssertLessThan(Reticulum.logWarning, Reticulum.logNotice)
        XCTAssertLessThan(Reticulum.logNotice, Reticulum.logInfo)
        XCTAssertLessThan(Reticulum.logInfo, Reticulum.logVerbose)
        XCTAssertLessThan(Reticulum.logVerbose, Reticulum.logDebug)
        XCTAssertLessThan(Reticulum.logDebug, Reticulum.logExtreme)
    }
}

// MARK: - logtimestamps

final class ReticulumLogTimestampsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Reticulum.logTimestamps = true
    }

    override func tearDown() {
        Reticulum.logTimestamps = true
        super.tearDown()
    }

    func testDefaultLogTimestampsIsTrue() {
        XCTAssertTrue(Reticulum.logTimestamps,
                      "Python: RNS.logtimestamps = True by default")
    }

    func testConfigDefaultLogTimestampsIsTrue() {
        let cfg = ReticulumConfig.parse("")
        XCTAssertTrue(cfg.logging.logTimestamps)
    }

    func testConfigParsesLogTimestampsNo() {
        let cfg = ReticulumConfig.parse("[logging]\nlogtimestamps = No\n")
        XCTAssertFalse(cfg.logging.logTimestamps)
    }

    func testConfigParsesLogTimestampsFalse() {
        let cfg = ReticulumConfig.parse("[logging]\nlogtimestamps = False\n")
        XCTAssertFalse(cfg.logging.logTimestamps)
    }

    func testConfigParsesLogTimestampsYes() {
        let cfg = ReticulumConfig.parse("[logging]\nlogtimestamps = Yes\n")
        XCTAssertTrue(cfg.logging.logTimestamps)
    }

    func testLogTimestampsFlagCanBeSetFalse() {
        Reticulum.logTimestamps = false
        XCTAssertFalse(Reticulum.logTimestamps)
    }

    func testLogHandlerNotAffectedByTimestampFlag() {
        Reticulum.logTimestamps = false
        Reticulum.globalLogLevel = .extreme
        var received: String?
        Reticulum.logHandler = { msg, _ in received = msg }
        Reticulum.log("test message", level: .notice)
        XCTAssertEqual(received, "test message",
                       "logHandler receives raw message regardless of logTimestamps")
    }
}
