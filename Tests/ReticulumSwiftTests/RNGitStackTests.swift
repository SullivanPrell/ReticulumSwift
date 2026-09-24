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

/// The stack `rngit` and `git-remote-rns` work over.
///
/// Both programs build it with `RNS.Reticulum(configdir=...)` (`server.py:67`,
/// `client.py:152`), which joins the shared instance where one is running and otherwise brings
/// up the interfaces the configuration names.
final class RNGitStackTests: XCTestCase {

  private var directories: [URL] = []
  private var stacks: [Reticulum] = []
  private var instances: [InstanceConnection] = []
  private var savedHandler: ((String, Reticulum.LogLevel) -> Void)?
  private var savedLevel = Reticulum.globalLogLevel

  override func setUp() {
    super.setUp()
    savedHandler = Reticulum.logHandler
    savedLevel = Reticulum.globalLogLevel
  }

  override func tearDown() {
    for stack in stacks { stack.stop() }
    stacks = []
    for instance in instances { instance.stop() }
    instances = []
    for directory in directories { try? FileManager.default.removeItem(at: directory) }
    directories = []
    Reticulum.logHandler = savedHandler
    Reticulum.globalLogLevel = savedLevel
    super.tearDown()
  }

  /// A Reticulum configuration directory naming one UDP interface, with its ports away from
  /// the usual 37428 and 37429.
  private func configurationDirectory(sharingTheInstance share: Bool) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rngit-stack-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    directories.append(directory)

    let base = Int.random(in: 41_000...48_000)
    let text = """
      [reticulum]
      enable_transport = False
      share_instance = \(share ? "Yes" : "No")
      shared_instance_port = \(base)
      instance_control_port = \(base + 1)

      [logging]
      loglevel = 1

      [interfaces]
        [[Test UDP]]
          type = UDPInterface
          enabled = Yes
          listen_ip = 127.0.0.1
          listen_port = \(base + 2)
          forward_ip = 127.0.0.1
          forward_port = \(base + 2)
      """
    try text.write(
      to: directory.appendingPathComponent("config"), atomically: true, encoding: .utf8)
    return directory
  }

  /// The stack `rngit` works over with the Reticulum configuration at `directory`.
  private func nodeStack(_ directory: URL) throws -> Reticulum {
    var setup = RNGitProgramSetup()
    setup.rnsConfigDirectory = directory.path
    let stack = try RNGitRuntime.start(setup)
    stacks.append(stack)
    return stack
  }

  /// The stack `git-remote-rns` works over with the Reticulum configuration at `directory`.
  private func helperStack(_ directory: URL) throws -> Reticulum {
    let stack = try RNGitHelperRuntime.start(
      configurationDirectory: directory.path,
      logFile: directory.appendingPathComponent("helper-log").path, logLevel: nil)
    stacks.append(stack)
    return stack
  }

  /// The shared instance the configuration at `directory` names, already running.
  private func runningInstance(_ directory: URL) throws {
    instances.append(
      try InstanceConnection.attach(configDirectory: directory, synthesizeInterfaces: false))
  }

  func testTheNodeBringsUpTheInterfacesItsConfigurationNames() throws {
    let stack = try nodeStack(try configurationDirectory(sharingTheInstance: false))
    XCTAssertEqual(stack.transport.interfaces.filter { $0 is UDPInterface }.count, 1)
  }

  func testTheNodeJoinsTheSharedInstanceThatIsRunning() throws {
    let directory = try configurationDirectory(sharingTheInstance: true)
    try runningInstance(directory)
    let stack = try nodeStack(directory)
    XCTAssertTrue(stack.transport.isConnectedToSharedInstance)
    XCTAssertEqual(stack.transport.interfaces.filter { $0 is LocalInterface }.count, 1)
    XCTAssertEqual(stack.transport.interfaces.filter { $0 is UDPInterface }.count, 0)
  }

  func testTheNodeBecomesTheSharedInstanceWhereNoneIsRunning() throws {
    let stack = try nodeStack(try configurationDirectory(sharingTheInstance: true))
    XCTAssertFalse(stack.transport.isConnectedToSharedInstance)
    XCTAssertEqual(stack.transport.interfaces.filter { $0 is PosixTCPServer }.count, 1)
    XCTAssertEqual(stack.transport.interfaces.filter { $0 is UDPInterface }.count, 1)
  }

  func testTheHelperBringsUpTheInterfacesItsConfigurationNames() throws {
    let stack = try helperStack(try configurationDirectory(sharingTheInstance: false))
    XCTAssertEqual(stack.transport.interfaces.filter { $0 is UDPInterface }.count, 1)
  }

  func testTheHelperJoinsTheSharedInstanceThatIsRunning() throws {
    let directory = try configurationDirectory(sharingTheInstance: true)
    try runningInstance(directory)
    let stack = try helperStack(directory)
    XCTAssertTrue(stack.transport.isConnectedToSharedInstance)
    XCTAssertEqual(stack.transport.interfaces.filter { $0 is LocalInterface }.count, 1)
    XCTAssertEqual(stack.transport.interfaces.filter { $0 is UDPInterface }.count, 0)
  }

  /// The helper writes its log to the file it is given for as long as the run lasts.
  func testTheHelperKeepsWritingItsLog() throws {
    let directory = try configurationDirectory(sharingTheInstance: false)
    _ = try helperStack(directory)
    Reticulum.globalLogLevel = .notice
    Reticulum.log("still written", level: .notice)
    let log = try String(
      contentsOf: directory.appendingPathComponent("helper-log"), encoding: .utf8)
    XCTAssertTrue(log.contains("still written"))
  }
}
