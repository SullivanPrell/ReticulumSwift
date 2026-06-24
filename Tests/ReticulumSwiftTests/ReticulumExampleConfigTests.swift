import XCTest
@testable import ReticulumSwift

/// Tests for Reticulum.exampleConfig.
/// Python reference: rnsd.py __example_rns_config__ embedded string.

final class ReticulumExampleConfigTests: XCTestCase {

    func testExampleConfigIsNotEmpty() {
        XCTAssertFalse(Reticulum.exampleConfig.isEmpty)
    }

    func testExampleConfigContainsReticulumSection() {
        XCTAssertTrue(Reticulum.exampleConfig.contains("[reticulum]"),
                      "exampleConfig should contain '[reticulum]' section header")
    }

    func testExampleConfigContainsInterfacesSection() {
        XCTAssertTrue(Reticulum.exampleConfig.contains("[interfaces]"),
                      "exampleConfig should contain '[interfaces]' section header")
    }

    func testExampleConfigContainsAutoInterface() {
        XCTAssertTrue(Reticulum.exampleConfig.contains("AutoInterface"),
                      "exampleConfig should mention AutoInterface as a type")
    }

    func testExampleConfigContainsLoggingSection() {
        XCTAssertTrue(Reticulum.exampleConfig.contains("[logging]"),
                      "exampleConfig should contain '[logging]' section header")
    }

    func testExampleConfigMentionsEnableTransport() {
        XCTAssertTrue(Reticulum.exampleConfig.contains("enable_transport"),
                      "exampleConfig should mention 'enable_transport'")
    }
}
