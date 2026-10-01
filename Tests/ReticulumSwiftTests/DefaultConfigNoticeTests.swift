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

/// What a first run prints as it writes the default config, as Python's constructor prints it.
///
/// Python logs one notice before writing the default config and one after
/// (`Reticulum.py:341-344`). Every `rn*` tool brings its stack up through that constructor, so
/// Python's `rnstatus`, run where there's no config yet, prints both lines before its own
/// output. Python writes them to stdout in `RNS.log`'s format unless the program names another
/// destination.
final class DefaultConfigNoticeTests: XCTestCase {

  private var savedHandler: ((String, Reticulum.LogLevel) -> Void)?
  private var savedLevel = Reticulum.LogLevel.notice
  private var logged: [(String, Reticulum.LogLevel)] = []
  private var directory: URL!

  override func setUpWithError() throws {
    savedHandler = Reticulum.logHandler
    savedLevel = Reticulum.globalLogLevel
    Reticulum.globalLogLevel = .notice
    Reticulum.logHandler = { [unowned self] message, level in logged.append((message, level)) }
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("default-config-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    Reticulum.logHandler = savedHandler
    Reticulum.globalLogLevel = savedLevel
    try? FileManager.default.removeItem(at: directory)
  }

  private var creating: String {
    "Could not load config file, creating default configuration file..."
  }

  private func created(in configDir: URL) -> String {
    "Default config file created. Make any necessary changes in \(configDir.path)/config "
      + "and restart Reticulum if needed."
  }

  func testWritingTheDefaultConfigLogsPythonsTwoNotices() throws {
    let config = directory.appendingPathComponent("config")
    try Reticulum.createDefaultConfig(at: config)
    XCTAssertEqual(logged.map(\.0), [creating, created(in: directory)])
    XCTAssertEqual(logged.map(\.1), [.notice, .notice])
    XCTAssertEqual(
      try String(contentsOf: config, encoding: .utf8), RNSConfigTemplates.defaultConfigFile)
  }

  /// `start()` writes the default config through the same path.
  ///
  /// The config's directory here is a regular file, so the write fails before the default
  /// config, with its AutoInterface and shared instance, can come up.
  func testStartLogsTheFirstNoticeBeforeWritingTheDefaultConfig() throws {
    let blocker = directory.appendingPathComponent("blocker")
    try Data().write(to: blocker)
    let reticulum = Reticulum(
      configuration: Reticulum.Configuration(
        storagePath: directory.appendingPathComponent("storage"),
        configPath: blocker.appendingPathComponent("config"), shareInstance: false))
    XCTAssertThrowsError(try reticulum.start())
    XCTAssertEqual(logged.map(\.0), [creating])
  }

  /// `rnsd` and the tools built on `DaemonBootstrap` print the same two lines.
  func testTheDaemonBootstrapLogsTheSameNotices() throws {
    let paths = DaemonBootstrap.Paths(configDir: directory)
    let bootstrapped = try DaemonBootstrap.bootstrap(paths: paths, verbosity: nil)
    XCTAssertTrue(bootstrapped.createdDefaultConfig)
    XCTAssertEqual(logged.map(\.0), [creating, created(in: directory)])
  }

  /// The `rn*` tools log to stdout in Python's format unless the program set a destination.
  func testAttachingInstallsPythonsStdoutFormatWhereNoDestinationIsSet() throws {
    Reticulum.logHandler = nil
    InstanceConnection.installDefaultLogDestination()
    XCTAssertNotNil(Reticulum.logHandler)
  }

  func testAttachingLeavesADestinationTheProgramSet() throws {
    InstanceConnection.installDefaultLogDestination()
    Reticulum.log("kept")
    XCTAssertEqual(logged.map(\.0), ["kept"])
  }
}
