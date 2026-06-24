import XCTest
@testable import ReticulumSwift

/// Tests for RNXApp constants.
/// Python reference: RNS/Utilities/rnx.py

final class RNXAppTests: XCTestCase {

    func testAppName() {
        // Python: APP_NAME = "rnx"
        XCTAssertEqual(RNXApp.appName, "rnx")
    }
}
