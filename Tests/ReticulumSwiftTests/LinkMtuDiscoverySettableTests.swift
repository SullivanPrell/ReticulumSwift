import XCTest
@testable import ReticulumSwift

/// `bugs/025` / `bugs/030` — `Reticulum.linkMtuDiscoveryEnabled` was declared
/// `private(set)` and **nothing ever wrote it**, so Python's `link_mtu_discovery`
/// config option (`Reticulum.py:537-539`) had nowhere to be applied. Same shape as the
/// get-only interface attributes: adding the `[reticulum]` parser alone would not have
/// been enough.
final class LinkMtuDiscoverySettableTests: XCTestCase {

    override func tearDown() {
        Reticulum.linkMtuDiscoveryEnabled = true   // restore the Python default
        super.tearDown()
    }

    func testDefaultMatchesPython() {
        XCTAssertTrue(Reticulum.linkMtuDiscoveryEnabled,
                      "Python's LINK_MTU_DISCOVERY defaults to True")
        XCTAssertTrue(Reticulum.linkMtuDiscovery())
    }

    /// The write is the point: a config value of `link_mtu_discovery = no` must be applicable.
    func testCanBeDisabled() {
        Reticulum.linkMtuDiscoveryEnabled = false
        XCTAssertFalse(Reticulum.linkMtuDiscoveryEnabled,
                       "link_mtu_discovery must be settable — a config key with nowhere to be "
                       + "written cannot be honoured")
        XCTAssertFalse(Reticulum.linkMtuDiscovery(),
                       "the accessor Python calls must reflect the configured value")
    }
}
