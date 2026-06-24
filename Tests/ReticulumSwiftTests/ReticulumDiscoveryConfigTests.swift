import XCTest
@testable import ReticulumSwift

/// Tests for Reticulum config parsing of `discover_interfaces` and `blackhole_sources`,
/// and the wiring in Reticulum.Configuration for discoveryStampValidator.
///
/// Mirrors Python's config-handling in Reticulum.__init__ lines 560–582.
final class ReticulumDiscoveryConfigTests: XCTestCase {

    // MARK: - discover_interfaces parsing

    func testDiscoverInterfacesYes() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  discover_interfaces = Yes
""")
        XCTAssertTrue(cfg.reticulum.discoverInterfaces,
                      "discover_interfaces = Yes → true")
    }

    func testDiscoverInterfacesNo() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  discover_interfaces = No
""")
        XCTAssertFalse(cfg.reticulum.discoverInterfaces,
                       "discover_interfaces = No → false")
    }

    func testDiscoverInterfacesTrue() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  discover_interfaces = True
""")
        XCTAssertTrue(cfg.reticulum.discoverInterfaces)
    }

    func testDiscoverInterfacesFalse() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  discover_interfaces = False
""")
        XCTAssertFalse(cfg.reticulum.discoverInterfaces)
    }

    func testDiscoverInterfacesDefaultFalse() {
        let cfg = ReticulumConfig.parse("[reticulum]")
        XCTAssertFalse(cfg.reticulum.discoverInterfaces,
                       "discover_interfaces must default to false")
    }

    // MARK: - blackhole_sources parsing

    func testBlackholeSourcesSingle() {
        // 16-byte (32 hex char) truncated hash
        let hexHash = "521c87a83afb8f29e4455e77930b973b"
        let cfg = ReticulumConfig.parse("""
[reticulum]
  blackhole_sources = \(hexHash)
""")
        XCTAssertEqual(cfg.reticulum.blackholeSources.count, 1,
                       "Single blackhole_sources entry must parse to 1 element")
        XCTAssertEqual(cfg.reticulum.blackholeSources.first?.hexString,
                       hexHash, "Hex value must round-trip")
    }

    func testBlackholeSourcesMultiple() {
        let hash1 = "521c87a83afb8f29e4455e77930b973b"
        let hash2 = "a1b2c3d4e5f60708090a0b0c0d0e0f10"
        let cfg = ReticulumConfig.parse("""
[reticulum]
  blackhole_sources = \(hash1), \(hash2)
""")
        XCTAssertEqual(cfg.reticulum.blackholeSources.count, 2,
                       "Two comma-separated entries must parse to 2 elements")
    }

    func testBlackholeSourcesDefaultEmpty() {
        let cfg = ReticulumConfig.parse("[reticulum]")
        XCTAssertTrue(cfg.reticulum.blackholeSources.isEmpty,
                      "blackhole_sources must default to empty")
    }

    func testBlackholeSourcesSkipsInvalidHex() {
        let cfg = ReticulumConfig.parse("""
[reticulum]
  blackhole_sources = not-a-hash, 521c87a83afb8f29e4455e77930b973b
""")
        XCTAssertEqual(cfg.reticulum.blackholeSources.count, 1,
                       "Invalid hex must be silently skipped")
    }

    func testBlackholeSourcesSkipsWrongLength() {
        // 30 hex chars (15 bytes, not 16)
        let cfg = ReticulumConfig.parse("""
[reticulum]
  blackhole_sources = 521c87a83afb8f29e4455e77930b97
""")
        XCTAssertTrue(cfg.reticulum.blackholeSources.isEmpty,
                      "Wrong-length hash must be silently skipped")
    }

    // MARK: - Reticulum.Configuration discoveryStampValidator

    func testConfigurationDiscoveryStampValidatorDefaultNil() {
        let config = Reticulum.Configuration(
            storagePath: URL(fileURLWithPath: NSTemporaryDirectory()),
            shareInstance: false
        )
        XCTAssertNil(config.discoveryStampValidator,
                     "discoveryStampValidator must default to nil")
    }

    func testConfigurationDiscoveryStampValidatorCanBeSet() {
        var config = Reticulum.Configuration(
            storagePath: URL(fileURLWithPath: NSTemporaryDirectory()),
            shareInstance: false
        )
        config.discoveryStampValidator = AlwaysPassValidator26()
        XCTAssertNotNil(config.discoveryStampValidator)
    }
}

// MARK: - Helpers

private final class AlwaysPassValidator26: DiscoveryStampValidator {
    var stampSize: Int { 32 }
    func stampWorkblock(material: Data, expandRounds: Int) -> Data { Data(repeating: 0, count: 32) }
    func stampValue(workblock: Data, stamp: Data) -> Int { 255 }
    func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { true }
}
