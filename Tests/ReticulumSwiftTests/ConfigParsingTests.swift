import XCTest
@testable import ReticulumSwift

final class ConfigParsingTests: XCTestCase {

    func testParsesReticulumSection() {
        let text = """
[reticulum]
enable_transport = True
share_instance = No
"""
        let cfg = ReticulumConfig.parse(text)
        XCTAssertTrue(cfg.reticulum.enableTransport)
        XCTAssertFalse(cfg.reticulum.shareInstance)
    }

    func testParsesLoggingSection() {
        let text = """
[logging]
loglevel = 6
"""
        let cfg = ReticulumConfig.parse(text)
        XCTAssertEqual(cfg.logging.logLevel, 6)
    }

    func testParsesSingleInterface() {
        let text = """
[interfaces]

  [[My TCP]]
    type = TCPClientInterface
    target_host = testnet.reticulum.network
    target_port = 4242
    enabled = Yes
"""
        let cfg = ReticulumConfig.parse(text)
        XCTAssertEqual(cfg.interfaces.count, 1)
        let iface = cfg.interfaces[0]
        XCTAssertEqual(iface.name, "My TCP")
        XCTAssertEqual(iface.type, "TCPClientInterface")
        XCTAssertTrue(iface.enabled)
        XCTAssertEqual(iface["target_host"], "testnet.reticulum.network")
        XCTAssertEqual(iface.int("target_port"), 4242)
    }

    func testParsesMultipleInterfaces() {
        let text = """
[interfaces]

  [[TCP Out]]
    type = TCPClientInterface
    target_host = example.com
    target_port = 4242
    enabled = Yes

  [[Local UDP]]
    type = UDPInterface
    listen_port = 4545
    enabled = No
"""
        let cfg = ReticulumConfig.parse(text)
        XCTAssertEqual(cfg.interfaces.count, 2)
        XCTAssertEqual(cfg.interfaces[0].name, "TCP Out")
        XCTAssertEqual(cfg.interfaces[1].name, "Local UDP")
        XCTAssertFalse(cfg.interfaces[1].enabled)
    }

    func testIgnoresComments() {
        let text = """
# Top comment
[reticulum]
# Enable transport
enable_transport = True  # inline comment
"""
        let cfg = ReticulumConfig.parse(text)
        XCTAssertTrue(cfg.reticulum.enableTransport)
    }

    func testDefaultsForEmptyConfig() {
        let cfg = ReticulumConfig.parse("")
        XCTAssertFalse(cfg.reticulum.enableTransport)
        XCTAssertTrue(cfg.reticulum.shareInstance)
        XCTAssertEqual(cfg.logging.logLevel, 4)
        XCTAssertTrue(cfg.interfaces.isEmpty)
    }

    func testBoolVariants() {
        let variants = [
            ("yes", true), ("Yes", true), ("YES", true),
            ("no", false), ("No", false), ("NO", false),
            ("True", true), ("False", false),
            ("1", true), ("0", false),
        ]
        for (raw, expected) in variants {
            let text = "[reticulum]\nenable_transport = \(raw)\n"
            let cfg = ReticulumConfig.parse(text)
            XCTAssertEqual(cfg.reticulum.enableTransport, expected, "Failed for '\(raw)'")
        }
    }

    func testDefaultConfigTextIsValid() {
        let cfg = ReticulumConfig.parse(ReticulumConfig.defaultConfigText)
        // Default has one interface (AutoInterface).
        XCTAssertEqual(cfg.interfaces.count, 1)
        XCTAssertEqual(cfg.interfaces[0].type, "AutoInterface")
        XCTAssertFalse(cfg.reticulum.enableTransport)
        XCTAssertEqual(cfg.logging.logLevel, 4)
    }

    func testDisabledInterfaceIsParsed() {
        let text = """
[interfaces]
  [[Off]]
    type = UDPInterface
    enabled = No
"""
        let cfg = ReticulumConfig.parse(text)
        XCTAssertEqual(cfg.interfaces.count, 1)
        XCTAssertFalse(cfg.interfaces[0].enabled)
    }

    func testParsesAllowProbes() {
        let text = "[reticulum]\nallow_probes = True\n"
        let cfg = ReticulumConfig.parse(text)
        XCTAssertTrue(cfg.reticulum.allowProbes)
    }

    func testAllowProbesDefaultFalse() {
        let cfg = ReticulumConfig.parse("")
        XCTAssertFalse(cfg.reticulum.allowProbes)
    }

    func testParsesEnableRemoteManagement() {
        let text = "[reticulum]\nenable_remote_management = True\n"
        let cfg = ReticulumConfig.parse(text)
        XCTAssertTrue(cfg.reticulum.remoteManagementEnabled)
    }

    func testRemoteManagementDefaultFalse() {
        let cfg = ReticulumConfig.parse("")
        XCTAssertFalse(cfg.reticulum.remoteManagementEnabled)
    }

    func testParsesAllowProbesFalse() {
        let text = "[reticulum]\nallow_probes = False\n"
        let cfg = ReticulumConfig.parse(text)
        XCTAssertFalse(cfg.reticulum.allowProbes)
    }
}
