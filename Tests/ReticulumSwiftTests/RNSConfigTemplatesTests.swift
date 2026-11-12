//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest

@testable import ReticulumSwift

/// Byte-exactness of the two configuration templates Python ships.
///
/// Python reference: `RNS/Utilities/rnsd.py:90-692` (`__example_rns_config__`, printed by
/// `rnsd --exampleconfig`) and `RNS/Reticulum.py:1818+` (`__default_rns_config__`, written on
/// a first run). Both are ~15 KB and ~4 KB of prose that no reviewer can diff by eye, so the
/// SHA-256 assertions are the real guard—they were computed from the Python source with:
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
    XCTAssertEqual(RNSConfigTemplates.exampleConfig.utf8.count, 18342)
  }

  func testExampleConfigSHA256() {
    XCTAssertEqual(
      sha256Hex(RNSConfigTemplates.exampleConfig),
      "4c12061692e0d06cff9337b3e601ac6e4561a6bb486289a311fc6ae1c22d5875")
  }

  func testExampleConfigNewlineCount() {
    XCTAssertEqual(RNSConfigTemplates.exampleConfig.filter { $0 == "\n" }.count, 602)
  }

  func testExampleConfigBoundaries() {
    XCTAssertTrue(
      RNSConfigTemplates.exampleConfig
        .hasPrefix("# This is an example Reticulum config file.\n"))
    // The literal ends with a blank line, so `print()` takes stdout to 18343 bytes.
    XCTAssertTrue(
      RNSConfigTemplates.exampleConfig
        .hasSuffix("    persistence = 200\n    slottime = 20\n\n"))
  }

  func testExampleConfigDocumentsTheRNS141GravityKeys() {
    // RNS 1.4.1 added four directives to `__example_rns_config__`. They're commented
    // out, so nothing parses them—the point is that a user copying this file as a
    // starting template sees the same options Python's users see.
    for key in [
      "default_gravity", "autoconnect_interface_mode",
      "autoconnect_announces_to_internal", "autoconnect_interface_gravity",
    ] {
      XCTAssertTrue(
        RNSConfigTemplates.exampleConfig.contains("# \(key) ="),
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
    XCTAssertEqual(
      config.interfaces.map(\.name),
      [
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
    XCTAssertEqual(RNSConfigTemplates.defaultConfig.utf8.count, 4576)
    XCTAssertEqual(RNSConfigTemplates.defaultConfig.filter { $0 == "\n" }.count, 137)
  }

  func testDefaultConfigSHA256() {
    XCTAssertEqual(
      sha256Hex(RNSConfigTemplates.defaultConfig),
      "efc715b029497d8a9719fd270c988dd9ec8cd4d33822dda00ab9b8fc89754ff6")
  }

  func testDefaultConfigBoundaries() {
    XCTAssertTrue(
      RNSConfigTemplates.defaultConfig
        .hasPrefix("##########################################################\n# This is the default Reticulum config file.\n"))
    XCTAssertTrue(
      RNSConfigTemplates.defaultConfig
        .hasSuffix("  [[Default Interface]]\n    type = AutoInterface\n    enabled = Yes\n\n"))
    // Python's default config points the reader at the verbose one.
    XCTAssertTrue(RNSConfigTemplates.defaultConfig.contains("# rnsd --exampleconfig"))
  }

  func testReticulumConfigDefaultTextIsTheTemplate() {
    // What `InstanceConnection` parses when there's no config file to read.
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

  // MARK: - What a first run writes

  /// Python writes ConfigObj's serialisation of the literal (`Reticulum.py:1451-1456`).
  ///
  /// The digest is of RNS 1.6.0 writing `ConfigObj(__default_rns_config__)`, which matches
  /// the file its own first run leaves.
  func testDefaultConfigFileIsWhatPythonWritesOnAFirstRun() {
    XCTAssertEqual(RNSConfigTemplates.defaultConfigFile.utf8.count, 4661)
    XCTAssertEqual(RNSConfigTemplates.defaultConfigFile.filter { $0 == "\n" }.count, 136)
    XCTAssertEqual(
      sha256Hex(RNSConfigTemplates.defaultConfigFile),
      "73356fbad9fa0331caa82c12622e28cced39d7d37cbfd4692ce022dd8e7a60dd")
  }

  func testDefaultConfigFileParsesAsTheTemplateDoes() {
    let written = ReticulumConfig.parse(RNSConfigTemplates.defaultConfigFile)
    let template = ReticulumConfig.parse(RNSConfigTemplates.defaultConfig)
    XCTAssertEqual(written.interfaces.map(\.name), template.interfaces.map(\.name))
    XCTAssertEqual(written.interfaces.map(\.type), template.interfaces.map(\.type))
    XCTAssertEqual(written.interfaces.map(\.enabled), template.interfaces.map(\.enabled))
    XCTAssertEqual(written.reticulum.enableTransport, template.reticulum.enableTransport)
    XCTAssertEqual(written.reticulum.shareInstance, template.reticulum.shareInstance)
    XCTAssertEqual(written.reticulum.instanceName, template.reticulum.instanceName)
    XCTAssertEqual(written.logging.logLevel, template.logging.logLevel)
  }

  func testRespondToProbesAliasIsAccepted() {
    // The example config documents `respond_to_probes` (Python's own spelling,
    // Reticulum.py:550-552); this port previously read only `allow_probes`, so the
    // documented key was silently ignored.
    XCTAssertTrue(
      ReticulumConfig.parse("[reticulum]\nrespond_to_probes = yes\n")
        .reticulum.allowProbes)
    XCTAssertTrue(
      ReticulumConfig.parse("[reticulum]\nallow_probes = yes\n")
        .reticulum.allowProbes)
    XCTAssertFalse(
      ReticulumConfig.parse("[reticulum]\nrespond_to_probes = no\n")
        .reticulum.allowProbes)
  }

  func testTemplatesAreDistinct() {
    // Python keeps two separate literals; conflating them is the bug this replaced.
    XCTAssertNotEqual(RNSConfigTemplates.exampleConfig, RNSConfigTemplates.defaultConfig)
  }
}
