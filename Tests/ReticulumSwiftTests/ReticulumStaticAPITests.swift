import XCTest
@testable import ReticulumSwift

/// Tests for Reticulum static API methods from the API reference.
final class ReticulumStaticAPITests: XCTestCase {

    // MARK: - Methods from the epub API reference

    // Reticulum.remote_management_enabled()
    func testRemoteManagementEnabled() {
        let result = Reticulum.remoteManagementEnabled()
        XCTAssertFalse(result, "remote management should be disabled by default")
    }

    // Reticulum.required_discovery_value()
    func testRequiredDiscoveryValue() {
        let result = Reticulum.requiredDiscoveryValue()
        XCTAssertGreaterThanOrEqual(result, 0)
    }

    // Reticulum.publish_blackhole_enabled()
    func testPublishBlackholeEnabled() {
        XCTAssertFalse(Reticulum.publishBlackholeEnabled())
    }

    // Reticulum.blackhole_sources()
    func testBlackholeSources() {
        let sources = Reticulum.blackholeSources()
        XCTAssertNotNil(sources)  // empty list by default
    }

    // Reticulum.discovered_interfaces()
    func testDiscoveredInterfaces() {
        let ifaces = Reticulum.discoveredInterfaces()
        XCTAssertNotNil(ifaces)
    }

    // Reticulum.interface_discovery_sources()
    func testInterfaceDiscoverySources() {
        let sources = Reticulum.interfaceDiscoverySources()
        XCTAssertNotNil(sources)
    }

    // Already tested: get_instance, should_use_implicit_proof, transport_enabled, link_mtu_discovery
}
