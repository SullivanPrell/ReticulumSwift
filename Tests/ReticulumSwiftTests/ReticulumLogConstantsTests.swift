import XCTest
@testable import ReticulumSwift

/// Tests for log-destination constants and compactLogFmt flag.
/// Python references: RNS.LOG_STDOUT = 0x91, LOG_FILE = 0x92, LOG_CALLBACK = 0x93,
///                    LOG_MAXSIZE = 5*1024*1024, compact_log_fmt = False

final class ReticulumLogConstantsTests: XCTestCase {

    func testLogDestStdout() {
        XCTAssertEqual(Reticulum.logDestStdout, 0x91)
    }

    func testLogDestFile() {
        XCTAssertEqual(Reticulum.logDestFile, 0x92)
    }

    func testLogDestCallback() {
        XCTAssertEqual(Reticulum.logDestCallback, 0x93)
    }

    func testLogMaxSize() {
        XCTAssertEqual(Reticulum.logMaxSize, 5 * 1024 * 1024)
    }

    func testCompactLogFmtDefaultIsFalse() {
        // Python: compact_log_fmt = False
        XCTAssertFalse(Reticulum.compactLogFmt)
    }

    func testCompactLogFmtIsMutable() {
        let original = Reticulum.compactLogFmt
        Reticulum.compactLogFmt = !original
        XCTAssertEqual(Reticulum.compactLogFmt, !original)
        Reticulum.compactLogFmt = original  // restore
    }

    func testLogDestValuesAreDistinct() {
        let values = [Reticulum.logDestStdout, Reticulum.logDestFile, Reticulum.logDestCallback]
        XCTAssertEqual(Set(values).count, 3)
    }
}
