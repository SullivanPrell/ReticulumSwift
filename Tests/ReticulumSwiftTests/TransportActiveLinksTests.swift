import XCTest
@testable import ReticulumSwift

/// Tests for Transport.activeLinks property.
/// Python reference: Transport.active_links list.

final class TransportActiveLinksTests: XCTestCase {

    func testActiveLinksPropertyExists() {
        let t = Transport()
        // Should be accessible and return an array.
        let links = t.activeLinks
        XCTAssertNotNil(links)
    }

    func testActiveLinksIsEmptyByDefault() {
        let t = Transport()
        XCTAssertTrue(t.activeLinks.isEmpty)
    }

    func testActiveLinksCountMatchesActiveStatus() {
        // getLinkCount() already exists and filters by .active
        // activeLinks should return the same set of links
        let t = Transport()
        XCTAssertEqual(t.activeLinks.count, t.getLinkCount())
    }
}
