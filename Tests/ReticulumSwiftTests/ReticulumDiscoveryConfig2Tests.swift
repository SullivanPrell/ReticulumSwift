import XCTest
@testable import ReticulumSwift

/// Tests for the remaining discovery-related config options:
///   required_discovery_value, publish_blackhole,
///   interface_discovery_sources, autoconnect_discovered_interfaces.
///
/// Mirrors Python Reticulum.__init__ lines 567–596.
final class ReticulumDiscoveryConfig2Tests: XCTestCase {

    // MARK: - required_discovery_value

    func testRequiredDiscoveryValueParsed() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  required_discovery_value = 20
""")
        XCTAssertEqual(cfg.reticulum.requiredDiscoveryValue, 20)
    }

    func testRequiredDiscoveryValueZeroResetsToDefault() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  required_discovery_value = 0
""")
        // Python: if v > 0: set; else set to None. Swift maps None → nil.
        XCTAssertNil(cfg.reticulum.requiredDiscoveryValue,
                     "value 0 must set requiredDiscoveryValue to nil (Python: None)")
    }

    func testRequiredDiscoveryValueDefaultNil() {
        let cfg = ReticulumConfig.parse("[reticulum]")
        XCTAssertNil(cfg.reticulum.requiredDiscoveryValue,
                     "requiredDiscoveryValue must default to nil (use Reticulum.requiredDiscoveryValue() fallback)")
    }

    // MARK: - publish_blackhole

    func testPublishBlackholeYes() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  publish_blackhole = Yes
""")
        XCTAssertTrue(cfg.reticulum.publishBlackholeEnabled)
    }

    func testPublishBlackholeNo() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  publish_blackhole = No
""")
        XCTAssertFalse(cfg.reticulum.publishBlackholeEnabled)
    }

    func testPublishBlackholeDefaultFalse() {
        let cfg = ReticulumConfig.parse("[reticulum]")
        XCTAssertFalse(cfg.reticulum.publishBlackholeEnabled)
    }

    // MARK: - interface_discovery_sources

    func testInterfaceDiscoverySourcesSingle() {
        let hexHash = "521c87a83afb8f29e4455e77930b973b"
        let cfg = ReticulumConfig.parse("""
[reticulum]
  interface_discovery_sources = \(hexHash)
""")
        XCTAssertEqual(cfg.reticulum.interfaceDiscoverySources.count, 1)
        XCTAssertEqual(cfg.reticulum.interfaceDiscoverySources.first?.hexString, hexHash)
    }

    func testInterfaceDiscoverySourcesMultiple() {
        let hash1 = "521c87a83afb8f29e4455e77930b973b"
        let hash2 = "a1b2c3d4e5f60708090a0b0c0d0e0f10"
        let cfg = ReticulumConfig.parse("""
[reticulum]
  interface_discovery_sources = \(hash1), \(hash2)
""")
        XCTAssertEqual(cfg.reticulum.interfaceDiscoverySources.count, 2)
    }

    func testInterfaceDiscoverySourcesDefaultEmpty() {
        let cfg = ReticulumConfig.parse("[reticulum]")
        XCTAssertTrue(cfg.reticulum.interfaceDiscoverySources.isEmpty)
    }

    func testInterfaceDiscoverySourcesSkipsInvalid() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  interface_discovery_sources = not-valid, 521c87a83afb8f29e4455e77930b973b
""")
        XCTAssertEqual(cfg.reticulum.interfaceDiscoverySources.count, 1)
    }

    // MARK: - autoconnect_discovered_interfaces

    func testAutoconnectDiscoveredInterfacesPositive() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  autoconnect_discovered_interfaces = 5
""")
        XCTAssertEqual(cfg.reticulum.autoconnectDiscoveredInterfaces, 5)
    }

    func testAutoconnectDiscoveredInterfacesZeroIgnored() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  autoconnect_discovered_interfaces = 0
""")
        // Python: if v > 0: set (0 is ignored, default stays)
        XCTAssertEqual(cfg.reticulum.autoconnectDiscoveredInterfaces, 0,
                       "value 0 must not override default of 0")
    }

    func testAutoconnectDiscoveredInterfacesDefaultZero() {
        let cfg = ReticulumConfig.parse("[reticulum]")
        XCTAssertEqual(cfg.reticulum.autoconnectDiscoveredInterfaces, 0)
    }
}
