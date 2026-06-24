import XCTest
@testable import ReticulumSwift

/// Tests for RNCopyApp constants.
/// Python reference: RNS/Utilities/rncp.py

final class RNCopyAppTests: XCTestCase {

    func testAppName() {
        // Python: APP_NAME = "rncp"
        XCTAssertEqual(RNCopyApp.appName, "rncp")
    }

    func testReqFetchNotAllowed() {
        // Python: REQ_FETCH_NOT_ALLOWED = 0xF0
        XCTAssertEqual(RNCopyApp.reqFetchNotAllowed, 0xF0)
    }
}
