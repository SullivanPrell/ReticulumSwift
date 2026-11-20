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

/// RNS 1.6.1's `link_cost` and `stamp_value` for `rngit` (`server.py:1980`, `:1994-1995`,
/// `:2066-2067`, `:2214-2215`; `pages.py:74`, `:142-143`, `:181-188`).
///
/// The quantized values are `floor(cost * 256 + 0.5) / 256` (`Stamps.py:915-935`).
final class RNS161RNGitLinkCostTests: XCTestCase {

  private struct Runner: RNGitCommandRunner {
    func run(_ executable: String, arguments: [String], in directory: String?)
      -> RNGitCommandOutput?
    {
      RNGitCommandOutput(status: 0, standardOutput: "", standardError: "")
    }
  }

  private func makeNode(_ configuration: String) throws -> RNGitNode {
    let directory = NSTemporaryDirectory() + "/rngit-link-cost-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(atPath: directory) }
    try configuration.write(
      toFile: directory + "/" + RNGitNodeEnvironment.configurationFileName, atomically: true,
      encoding: .utf8)
    return try RNGitNode(configDirectory: directory, runner: Runner())
  }

  private let stamps = StampSettings()

  func testTheRepositoriesDestinationDefaultsToALinkCostOf18() throws {
    let destination = try makeNode("").makeDestination()

    XCTAssertEqual(destination.getLinkCost(stamps), 18.0)
    XCTAssertEqual(destination.targetValue(stamps), stamps.destinationValue)
  }

  func testTheRngitSectionSetsAQuantizedLinkCostAndStampValue() throws {
    let node = try makeNode("[rngit]\nlink_cost = 20.3\nstamp_value = 30.1\n")
    let destination = try node.makeDestination()

    XCTAssertEqual(node.settings.linkCost, 20.30078125)
    XCTAssertEqual(node.settings.stampValue, 30.1015625)
    XCTAssertEqual(destination.getLinkCost(stamps), 20.30078125)
    XCTAssertEqual(destination.targetValue(stamps), 30.1015625)
  }

  /// `if self.stamp_value:` leaves a value of 0 unset.
  func testAZeroStampValueIsNotApplied() throws {
    let destination = try makeNode("[rngit]\nstamp_value = 0\n").makeDestination()

    XCTAssertEqual(destination.targetValue(stamps), stamps.destinationValue)
  }

  /// `as_float` raises for a value `float()` refuses.
  func testANonNumericLinkCostIsRefused() {
    XCTAssertThrowsError(try makeNode("[rngit]\nlink_cost = high\n")) {
      XCTAssertEqual($0 as? RNGitSettingsError, .notAFloat(key: "link_cost"))
    }
    XCTAssertThrowsError(try makeNode("[pages]\nstamp_value = high\n").pageSettings()) {
      XCTAssertEqual($0 as? RNGitSettingsError, .notAFloat(key: "stamp_value"))
    }
  }

  func testThePagesDestinationTakesThePagesSection() throws {
    let plain = try RNGitPageNode(owner: makeNode(""), version: "1.6.1")
    XCTAssertEqual(plain.destination.getLinkCost(stamps), 18.0)
    XCTAssertEqual(plain.destination.targetValue(stamps), stamps.destinationValue)

    let set = try RNGitPageNode(
      owner: makeNode("[rngit]\nlink_cost = 5\n[pages]\nlink_cost = 20.3\nstamp_value = 30.1\n"),
      version: "1.6.1")
    XCTAssertEqual(set.destination.getLinkCost(stamps), 20.30078125)
    XCTAssertEqual(set.destination.targetValue(stamps), 30.1015625)
  }

  func testTheShippedConfigurationDocumentsBothSettingsInBothSections() throws {
    let text = RNGitNodeEnvironment.defaultConfiguration
    XCTAssertEqual(text.components(separatedBy: "\n# link_cost = 18.0\n").count, 3)
    XCTAssertEqual(text.components(separatedBy: "\n# stamp_value = 25.0\n").count, 3)
  }
}

extension RNGitNode {
  fileprivate func pageSettings() throws -> RNGitPageNodeSettings {
    try RNGitPageNodeSettings(configuration: configuration)
  }
}
