//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

/// What the `git-remote-rns` helper brings up before it answers git.
///
/// The helper reads its own configuration, brings the stack up with its log in a file, and runs
/// ``RNGitRemoteHelper`` over a link to the node the URL names.
public struct RNGitHelperRuntime {

  /// The status a run that could not bring itself up exits with.
  public static let notReady: Int32 = 1

  /// The status a run that gave up part way exits with.
  public static let abortStatus: Int32 = 255

  /// Where the helper's output goes.
  public struct Streams {

    /// Where the helper answers git.
    public let standardOutput: RNGitClientOutput

    /// Where the helper writes what it is doing.
    public let standardError: RNGitClientOutput

    /// What git is telling the helper to do.
    public let standardInput: RNGitClientInput

    /// Creates the streams the helper runs against.
    public init(
      standardOutput: RNGitClientOutput, standardError: RNGitClientOutput,
      standardInput: RNGitClientInput
    ) {
      self.standardOutput = standardOutput
      self.standardError = standardError
      self.standardInput = standardInput
    }
  }

  /// Runs the helper over `arguments`, answering the status it exits with.
  ///
  /// `arguments` carries no program name, so git's `git-remote-rns origin rns://…` arrives as two
  /// entries.
  public static func run(
    arguments: [String], environment: [String: String], streams: Streams,
    workingDirectory: String = FileManager.default.currentDirectoryPath
  ) -> Int32 {
    let reading = RNGitHelperCommandLine.reading(arguments, environment: environment)
    if let code = reading.exitCode {
      streams.standardError.write(reading.standardError)
      return code
    }
    guard let setup = reading.setup else { return notReady }

    let directory = RNGitClientEnvironment.directory(given: setup.configDirectory)
    let settings: RNGitHelperSettings
    do {
      let configuration = try RNGitClientEnvironment.configuration(
        at: directory + "/" + RNGitClientEnvironment.configurationFileName, in: directory)
      settings = try RNGitHelperSettings(configuration: configuration)
    } catch {
      Reticulum.log(
        "Could not parse the configuration at " + directory + "/"
          + RNGitClientEnvironment.configurationFileName, level: .error)
      return notReady
    }

    let reticulum: Reticulum
    do {
      reticulum = try start(
        configurationDirectory: setup.rnsConfigDirectory,
        logFile: directory + "/" + RNGitClientEnvironment.logFileName,
        logLevel: settings.client.logLevel)
    } catch {
      streams.standardError.write("Failed to initialize Reticulum: \(error)\n")
      return notReady
    }

    let identity: Identity
    do {
      identity = try RNGitClientEnvironment.identity(
        at: directory + "/" + RNGitClientEnvironment.identityFileName, in: directory)
    } catch {
      Reticulum.log("Could not initialize client identity.", level: .error)
      return notReady
    }

    let temporary = NSTemporaryDirectory() + "/rngit-" + UUID().uuidString
    try? FileManager.default.createDirectory(
      atPath: temporary, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(atPath: temporary) }

    var helper = helper(
      setup: setup, settings: settings,
      transport: RNGitLinkTransport(
        reticulum: reticulum, identity: identity, directory: temporary),
      streams: streams, workingDirectory: workingDirectory)
    return run(&helper, streams: streams)
  }

  /// The helper `setup` and `settings` spell out, talking to the node over `transport`.
  static func helper(
    setup: RNGitHelperProgramSetup, settings: RNGitHelperSettings,
    transport: RNGitClientTransport, streams: Streams, workingDirectory: String
  ) -> RNGitRemoteHelper {
    RNGitRemoteHelper(
      url: setup.url, aliases: settings.client.destinationAliases,
      refBatchSize: settings.refBatchSize, workingDirectory: workingDirectory,
      transport: transport, stdout: streams.standardOutput, stderr: streams.standardError,
      input: streams.standardInput, runner: RNGitProcessRunner())
  }

  /// Runs `helper`, answering the status the run exits with.
  ///
  /// A run that gives up part way reports what it gave up over, where its failures go.
  static func run(_ helper: inout RNGitRemoteHelper, streams: Streams) -> Int32 {
    do {
      try helper.run()
    } catch let abort as RNGitClientAbort {
      streams.standardError.write(RNGitRemoteHelper.failurePrefix + abort.message + "\n")
      return abortStatus
    } catch {
      streams.standardError.write(
        RNGitRemoteHelper.failurePrefix + RNGitRemoteHelper.unknownReason + "\n")
      return abortStatus
    }
    return 0
  }

  /// The stack the helper runs on, with its log written to `logFile`.
  private static func start(
    configurationDirectory: String?, logFile: String, logLevel: Int?
  ) throws -> Reticulum {
    let configDir =
      configurationDirectory.map { DaemonBootstrap.expandTildeURL($0) }
      ?? DaemonBootstrap.homeDirectory().appendingPathComponent(".reticulum")
    let paths = DaemonBootstrap.Paths(configDir: configDir)
    try DaemonBootstrap.createStorageTree(paths)

    let sink = FileLogSink(fileURL: URL(fileURLWithPath: logFile))
    sink.install()
    if let logLevel, let level = Reticulum.LogLevel(rawValue: logLevel) {
      Reticulum.globalLogLevel = level
    }

    let reticulum = Reticulum.fromConfigDir(configDir)
    try reticulum.start()
    return reticulum
  }
}
