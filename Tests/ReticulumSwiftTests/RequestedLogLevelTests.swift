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

/// A level passed to the constructor wins over the config file's `loglevel`, which applies only
/// when the caller passes none (`Reticulum.py:310-316`, `:465`).
final class RequestedLogLevelTests: XCTestCase {

  private var savedLevel = Reticulum.LogLevel.notice
  private var directory: URL!

  override func setUpWithError() throws {
    savedLevel = Reticulum.globalLogLevel
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("requested-log-level-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    Reticulum.globalLogLevel = savedLevel
    try? FileManager.default.removeItem(at: directory)
  }

  /// Starts a stack whose config file sets `loglevel = 6`, nothing else.
  private func start(requesting level: Reticulum.LogLevel?) throws {
    let config = directory.appendingPathComponent("config")
    try "[reticulum]\n  share_instance = No\n\n[logging]\n  loglevel = 6\n\n[interfaces]\n"
      .write(to: config, atomically: true, encoding: .utf8)
    let storage = directory.appendingPathComponent("storage")
    let configuration =
      if let level {
        Reticulum.Configuration(
          storagePath: storage, configPath: config, shareInstance: false, logLevel: level)
      } else {
        Reticulum.Configuration(storagePath: storage, configPath: config, shareInstance: false)
      }
    let reticulum = Reticulum(configuration: configuration)
    try reticulum.start()
    reticulum.stop()
  }

  func testARequestedLevelWinsOverTheConfigFile() throws {
    Reticulum.globalLogLevel = .notice
    try start(requesting: .extreme)
    XCTAssertEqual(Reticulum.globalLogLevel, .extreme)
  }

  func testTheConfigFileAppliesWhenNoLevelIsRequested() throws {
    Reticulum.globalLogLevel = .notice
    try start(requesting: nil)
    XCTAssertEqual(Reticulum.globalLogLevel, .debug)
  }
}
