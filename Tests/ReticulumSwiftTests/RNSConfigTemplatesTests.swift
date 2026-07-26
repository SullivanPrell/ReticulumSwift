import XCTest
@testable import ReticulumSwift

/// Byte-exactness of the two configuration templates Python ships.
///
/// Python reference: `RNS/Utilities/rnsd.py:90-583` (`__example_rns_config__`, printed by
/// `rnsd --exampleconfig`) and `RNS/Reticulum.py:1818+` (`__default_rns_config__`, written on
/// a first run). Both are ~15 KB and ~4 KB of prose that no reviewer can diff by eye, so the
/// SHA-256 assertions are the real guard — they were computed from the Python source with:
///
///     python3 -c "import re,hashlib; s=re.search(r\"__example_rns_config__ = '''(.*?)'''\",
///                 open('RNS/Utilities/rnsd.py').read(), re.S).group(1);
///                 print(len(s.encode()), hashlib.sha256(s.encode()).hexdigest())"
final class RNSConfigTemplatesTests: XCTestCase {

    private func sha256Hex(_ text: String) -> String {
        RNSUtilities.hexrep(Identity.fullHash(Data(text.utf8)), delimit: false)
    }

    // MARK: - __example_rns_config__

    func testExampleConfigByteLength() {
        XCTAssertEqual(RNSConfigTemplates.exampleConfig.utf8.count, 15663)
    }

    func testExampleConfigSHA256() {
        XCTAssertEqual(sha256Hex(RNSConfigTemplates.exampleConfig),
                       "78f08f25bbfe5cb15f22cdeec36c4b7476973bd8558f59e77faf8c118df2ca67")
    }

    func testExampleConfigNewlineCount() {
        XCTAssertEqual(RNSConfigTemplates.exampleConfig.filter { $0 == "\n" }.count, 518)
    }

    func testExampleConfigBoundaries() {
        XCTAssertTrue(RNSConfigTemplates.exampleConfig
            .hasPrefix("# This is an example Reticulum config file.\n"))
        // The literal ends with a blank line, so `print()` takes stdout to 15664 bytes.
        XCTAssertTrue(RNSConfigTemplates.exampleConfig
            .hasSuffix("    persistence = 200\n    slottime = 20\n\n"))
    }

    func testExampleConfigDocumentsTheRNS141GravityKeys() {
        // RNS 1.4.1 added four directives to `__example_rns_config__`. They are commented
        // out, so nothing parses them — the point is that a user copying this file as a
        // starting template sees the same options Python's users see.
        for key in ["default_gravity", "autoconnect_interface_mode",
                    "autoconnect_announces_to_internal", "autoconnect_interface_gravity"] {
            XCTAssertTrue(RNSConfigTemplates.exampleConfig.contains("# \(key) ="),
                          "example config does not document '\(key)'")
        }
    }

    func testReticulumExampleConfigIsTheTemplate() {
        // `rnsd --exampleconfig` prints `Reticulum.exampleConfig`; it must be the byte-exact blob.
        XCTAssertEqual(Reticulum.exampleConfig, RNSConfigTemplates.exampleConfig)
    }

    func testExampleConfigMentionsAllDocumentedKeys() {
        // All 23 verified present in the Python literal; 16 were absent from the abridged
        // Swift copy this replaced.
        let expected = [
            "rpc_key", "enable_remote_management", "remote_management_allowed",
            "network_identity", "discover_interfaces", "interface_discovery_sources",
            "autoconnect_discovered_interfaces", "required_discovery_value",
            "publish_blackhole", "blackhole_sources", "blackhole_update_interval",
            "static_transport_identity", "shared_instance_type", "shared_instance_port",
            "instance_control_port", "instance_name", "panic_on_interface_error",
            "respond_to_probes", "logtimestamps", "I2PInterface", "AX25KISSInterface",
            "RNodeInterface", "ble://",
        ]
        for key in expected {
            XCTAssertTrue(RNSConfigTemplates.exampleConfig.contains(key), "missing '\(key)'")
        }
    }

    func testExampleConfigLogLevelLegendSaysZeroThroughEight() {
        // Python: "# Valid log levels are 0 through 8:". The abridged Swift copy said 7.
        XCTAssertTrue(RNSConfigTemplates.exampleConfig.contains("0 through 8"))
        XCTAssertFalse(RNSConfigTemplates.exampleConfig.contains("0 through 7"))
    }

    func testExampleConfigRoundTripsThroughParser() {
        let config = ReticulumConfig.parse(RNSConfigTemplates.exampleConfig)
        XCTAssertEqual(config.interfaces.map(\.name), [
            "Default Interface",
            "UDP Interface",
            "TCP Server Interface",
            "TCP Client Interface",
            "I2P",
            "RNode LoRa Interface",
            "Packet Radio KISS Interface",
            "Packet Radio AX.25 KISS Interface",
        ])
        // Python: only `[[Default Interface]]` carries `enabled = yes`.
        XCTAssertEqual(config.interfaces.filter(\.enabled).map(\.name), ["Default Interface"])
        XCTAssertEqual(config.logging.logLevel, 4)
        XCTAssertFalse(config.reticulum.enableTransport)
        XCTAssertTrue(config.reticulum.shareInstance)
    }

    // MARK: - __default_rns_config__

    func testDefaultConfigByteLength() {
        XCTAssertEqual(RNSConfigTemplates.defaultConfig.utf8.count, 3950)
        XCTAssertEqual(RNSConfigTemplates.defaultConfig.filter { $0 == "\n" }.count, 120)
    }

    func testDefaultConfigSHA256() {
        XCTAssertEqual(sha256Hex(RNSConfigTemplates.defaultConfig),
                       "9b811134dd64a46a49ec2af3fe0d7293aa94bcc8c547c44b42f0eb38eef92e42")
    }

    func testDefaultConfigBoundaries() {
        XCTAssertTrue(RNSConfigTemplates.defaultConfig
            .hasPrefix("# This is the default Reticulum config file.\n"))
        XCTAssertTrue(RNSConfigTemplates.defaultConfig
            .hasSuffix("  [[Default Interface]]\n    type = AutoInterface\n    enabled = Yes\n\n"))
        // Python's default config points the reader at the verbose one.
        XCTAssertTrue(RNSConfigTemplates.defaultConfig.contains("# rnsd --exampleconfig"))
    }

    func testReticulumConfigDefaultTextIsTheTemplate() {
        // This is what `Reticulum.start()` and the daemons write on a first run.
        XCTAssertEqual(ReticulumConfig.defaultConfigText, RNSConfigTemplates.defaultConfig)
    }

    func testDefaultConfigRoundTripsThroughParser() {
        let config = ReticulumConfig.parse(RNSConfigTemplates.defaultConfig)
        XCTAssertEqual(config.interfaces.count, 1)
        XCTAssertEqual(config.interfaces[0].name, "Default Interface")
        XCTAssertEqual(config.interfaces[0].type, "AutoInterface")
        XCTAssertTrue(config.interfaces[0].enabled)
        XCTAssertFalse(config.reticulum.enableTransport)
        XCTAssertTrue(config.reticulum.shareInstance)
        XCTAssertEqual(config.logging.logLevel, 4)
    }

    func testRespondToProbesAliasIsAccepted() {
        // The example config documents `respond_to_probes` (Python's own spelling,
        // Reticulum.py:550-552); this port previously read only `allow_probes`, so the
        // documented key was silently ignored.
        XCTAssertTrue(ReticulumConfig.parse("[reticulum]\nrespond_to_probes = yes\n")
            .reticulum.allowProbes)
        XCTAssertTrue(ReticulumConfig.parse("[reticulum]\nallow_probes = yes\n")
            .reticulum.allowProbes)
        XCTAssertFalse(ReticulumConfig.parse("[reticulum]\nrespond_to_probes = no\n")
            .reticulum.allowProbes)
    }

    func testTemplatesAreDistinct() {
        // Python keeps two separate literals; conflating them is the bug this replaced.
        XCTAssertNotEqual(RNSConfigTemplates.exampleConfig, RNSConfigTemplates.defaultConfig)
    }
}
