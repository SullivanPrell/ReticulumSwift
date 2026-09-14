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

/// Hands the user text in the editor they have, and reads back what they saved.
///
/// The editor is `$EDITOR`, or the first of `nano`, `vim` and `vi` the system can find.
public final class RNGitProcessEditor: RNGitClientEditor {

  /// The editors tried where the environment names none.
  public static let fallbacks = ["nano", "vim", "vi"]

  private let environment: [String: String]
  private let runner: RNGitCommandRunner

  /// Creates an editor resolved out of `environment`.
  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    runner: RNGitCommandRunner = RNGitProcessRunner()
  ) {
    self.environment = environment
    self.runner = runner
  }

  /// The editor to run, or the empty string where there is none to run.
  public func editor() -> String {
    if let named = environment["EDITOR"], !named.isEmpty { return named }
    for fallback in Self.fallbacks
    where runner.run("which", arguments: [fallback], in: nil)?.status == 0 {
      return fallback
    }
    return ""
  }

  /// Runs `editor` over the file at `path`, answering the code it came back with.
  public func run(_ editor: String, over path: String) -> Int32 {
    #if os(macOS)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [editor, path]
    do {
      try process.run()
      process.waitUntilExit()
      return process.terminationStatus
    } catch {
      return 1
    }
    #else
    return 1
    #endif
  }
}

/// What one `rngit` run comes to.
///
/// The run reads its command line, brings the stack up, and either serves repositories or asks a
/// node to do one thing and stops.
public enum RNGitRuntime {

  /// The status a run that could not bring itself up exits with.
  public static let notReady: Int32 = 1

  /// The status a run that gave up part way exits with.
  public static let abortStatus: Int32 = 1

  /// The status a run whose configuration will not parse exits with.
  public static let unreadableConfigurationStatus: Int32 = 255

  /// What a run says of an operation its subcommand does not take.
  public static let invalidOperation = "Invalid operation"

  /// The sink a run writes its log through, held for as long as the run lasts.
  private static var logSink: FileLogSink?

  /// Where a run's output goes.
  public struct Streams {

    /// Where the run says what it is doing.
    public let standardOutput: RNGitClientOutput

    /// Where the run says what went wrong.
    public let standardError: RNGitClientOutput

    /// What the user is typing.
    public let standardInput: RNGitClientInput

    /// Creates the streams the run works over.
    public init(
      standardOutput: RNGitClientOutput, standardError: RNGitClientOutput,
      standardInput: RNGitClientInput
    ) {
      self.standardOutput = standardOutput
      self.standardError = standardError
      self.standardInput = standardInput
    }
  }

  /// Runs `arguments`, answering the status the run exits with.
  ///
  /// `arguments` carries no program name, so `rngit node --service` arrives as two entries.
  public static func run(
    arguments: [String], version: String, streams: Streams,
    workingDirectory: String = FileManager.default.currentDirectoryPath,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Int32 {
    let reading = RNGitCommandLine.reading(arguments, version: version)
    streams.standardOutput.write(reading.standardOutput)
    if let code = reading.exitCode {
      streams.standardError.write(reading.standardError)
      return code
    }
    guard let setup = reading.setup else { return notReady }

    if setup.printIdentity == true {
      return printIdentity(setup, streams: streams)
    }

    let stack: Reticulum
    do {
      stack = try start(setup)
    } catch {
      streams.standardError.write("Failed to initialize Reticulum: \(error)\n")
      return notReady
    }

    guard let task = setup.task else { return serve(setup, on: stack, streams: streams) }
    return ask(
      task, setup, on: stack, streams: streams, workingDirectory: workingDirectory,
      environment: environment)
  }

  // MARK: - The node

  /// Prints what the node is and stops, without bringing the stack up.
  ///
  /// A node that does not come up far enough to say what it is stops the run where a node that
  /// does not come up at all stops it.
  static func printIdentity(_ setup: RNGitProgramSetup, streams: Streams) -> Int32 {
    do {
      let node = try RNGitNode(
        configDirectory: setup.configDirectory, verbosity: setup.verbosity - setup.quietness)
      let client = try RNGitNodeEnvironment.identity(
        at: node.directory + "/" + RNGitClientEnvironment.identityFileName, in: node.directory)
      let lines = RNGitNodeEnvironment.identityLines(
        node: node.identity, client: client, servingPages: node.settings.serveNomadNet)
      streams.standardOutput.write(lines.joined(separator: "\n") + "\n")
      return 0
    } catch let abort as RNGitClientAbort {
      Reticulum.log(abort.message, level: .error)
      return RNGitNode.notReadyStatus
    } catch {
      Reticulum.log("\(error)", level: .error)
      return RNGitNode.notReadyStatus
    }
  }

  /// Serves repositories until the run is stopped.
  static func serve(_ setup: RNGitProgramSetup, on stack: Reticulum, streams: Streams) -> Int32 {
    Reticulum.log("Starting Reticulum Git Node...", level: .notice)
    let node: RNGitNode
    do {
      node = try RNGitNode(
        configDirectory: setup.configDirectory, verbosity: setup.verbosity - setup.quietness)
    } catch let abort as RNGitClientAbort {
      Reticulum.log(abort.message, level: .error)
      return RNGitNode.notReadyStatus
    } catch {
      Reticulum.log("\(error)", level: .error)
      return RNGitNode.notReadyStatus
    }
    guard node.ready else { return RNGitNode.notReadyStatus }

    let destination: Destination
    do {
      destination = try node.makeDestination()
    } catch {
      Reticulum.log("Could not create the repositories destination: \(error)", level: .error)
      return RNGitNode.notReadyStatus
    }
    if let level = node.settings.logLevel.flatMap(Reticulum.LogLevel.init(rawValue:)) {
      Reticulum.globalLogLevel = level
    }
    if setup.service == true {
      let sink = FileLogSink(fileURL: URL(fileURLWithPath: node.logPath))
      sink.install()
      logSink = sink
    }

    stack.transport.register(destination: destination)
    node.attach(to: destination)
    Reticulum.log(
      "Reticulum Git Node listening on " + RNSUtilities.prettyhexrep(destination.hash),
      level: .notice)

    while true {
      Thread.sleep(forTimeInterval: RNGitNodeRuntime.jobsInterval)
      node.runDueJobs(at: Date().timeIntervalSince1970)
    }
  }

  // MARK: - The client

  /// Asks a node to do one thing, answering the status the run exits with.
  static func ask(
    _ task: RNGitTask, _ setup: RNGitProgramSetup, on stack: Reticulum, streams: Streams,
    workingDirectory: String, environment: [String: String]
  ) -> Int32 {
    let directory = RNGitClientEnvironment.directory(given: setup.configDirectory)
    let settings: RNGitClientSettings
    do {
      let configuration = try RNGitClientEnvironment.configuration(
        at: directory + "/" + RNGitClientEnvironment.configurationFileName, in: directory)
      settings = try RNGitClientSettings(configuration: configuration)
    } catch {
      return unreadableConfiguration(at: directory)
    }

    let identity: Identity
    do {
      identity = try RNGitClientEnvironment.identity(
        at: setup.identity ?? directory + "/" + RNGitClientEnvironment.identityFileName,
        in: directory)
    } catch {
      Reticulum.log("Could not initialize client identity", level: .error)
      return notReady
    }

    let temporary = NSTemporaryDirectory() + "/rngit-" + UUID().uuidString
    try? FileManager.default.createDirectory(
      atPath: temporary, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(atPath: temporary) }

    let commands = RNGitClientCommands(
      aliases: settings.destinationAliases, identity: identity,
      workingDirectory: workingDirectory,
      transport: RNGitLinkTransport(
        reticulum: stack, identity: identity, directory: temporary),
      output: streams.standardOutput, input: streams.standardInput,
      editor: RNGitProcessEditor(environment: environment), runner: RNGitProcessRunner())

    do {
      return try dispatch(task, through: commands, output: streams.standardOutput)
    } catch {
      return gaveUp(over: error, saying: streams.standardOutput)
    }
  }

  /// The status a run whose configuration at `directory` will not parse stops with.
  ///
  /// A configuration a run cannot read is where it stops, rather than something it works
  /// around, so the status is the one a node that did not come up stops on.
  static func unreadableConfiguration(at directory: String) -> Int32 {
    Reticulum.log(
      "Could not parse the configuration at " + directory + "/"
        + RNGitClientEnvironment.configurationFileName, level: .error)
    Reticulum.log("Check your configuration file for errors!", level: .error)
    return unreadableConfigurationStatus
  }

  /// The status a run that gave up over `error` stops with, having said what it gave up over.
  ///
  /// A failure the client has already reported on carries no message of its own, so nothing more
  /// is written for it.
  static func gaveUp(over error: Error, saying output: RNGitClientOutput) -> Int32 {
    switch error {
    case let abort as RNGitClientAbort: output.write(abort.message + "\n")
    case is RNGitClientFailure: break
    default: output.write("\(error)\n")
    }
    return abortStatus
  }

  /// Runs what `task` names through `commands`, answering the status the run exits with.
  static func dispatch(
    _ task: RNGitTask, through commands: RNGitClientCommands, output: RNGitClientOutput
  ) throws -> Int32 {
    let scope = task.scope ?? "active"
    switch task.command {
    case .create:
      try commands.createRepository(remote: task.remote)

    case .fork:
      try commands.forkRepository(source: task.source, target: task.target)

    case .mirror:
      try commands.mirrorRepository(source: task.source, target: task.target)

    case .sync:
      try commands.syncRepository(remote: task.remote)

    case .release:
      switch task.operation {
      case "list": try commands.listReleases(remote: task.remote)
      case "view": try commands.viewRelease(remote: task.remote, target: task.target)
      case "fetch":
        try commands.fetchRelease(
          remote: task.remote, target: task.target, signer: task.signer,
          offline: task.offline ?? false)
      case "verify":
        try commands.fetchRelease(
          remote: task.remote, target: task.target, signer: task.signer, offline: true)
      case "create":
        try commands.createRelease(
          remote: task.remote, target: task.target, signer: task.signer, name: task.name,
          noUpload: task.noUpload ?? false)
      case "delete": try commands.deleteRelease(remote: task.remote, target: task.target)
      case "latest": try commands.latestRelease(remote: task.remote, target: task.target)
      default: return refuse(output)
      }

    case .perms:
      switch task.operation {
      case "gperms": try commands.groupPermissions(remote: task.remote)
      case "rperms": try commands.repositoryPermissions(remote: task.remote)
      default: return refuse(output)
      }

    case .work:
      switch task.operation {
      case "list": try commands.listWork(remote: task.remote, scope: scope)
      case "view":
        try commands.viewWork(remote: task.remote, document: task.documentIdentifier, scope: scope)
      case "create": try commands.createWork(remote: task.remote, title: task.title)
      case "propose": try commands.proposeWork(remote: task.remote, title: task.title)
      case "edit":
        try commands.editWork(
          remote: task.remote, document: task.documentIdentifier, title: task.title, scope: scope)
      case "delete":
        try commands.deleteWork(
          remote: task.remote, document: task.documentIdentifier, scope: scope)
      case "update":
        try commands.commentWork(
          remote: task.remote, document: task.documentIdentifier, scope: scope)
      case "complete":
        try commands.completeWork(remote: task.remote, document: task.documentIdentifier)
      case "activate":
        try commands.activateWork(remote: task.remote, document: task.documentIdentifier)
      case "perms":
        try commands.workPermissions(remote: task.remote, document: task.documentIdentifier)
      default: return refuse(output)
      }

    case .node:
      return notReady
    }
    return 0
  }

  /// Says the operation is none of the subcommand's, and stops.
  static func refuse(_ output: RNGitClientOutput) -> Int32 {
    output.write(invalidOperation + "\n")
    return 1
  }

  /// The stack the run works over.
  ///
  /// A run kept as a service writes its log to a file and takes the log level the configuration
  /// holds, where any other run writes to standard output and takes the level the command line
  /// asked for on top of it.
  private static func start(_ setup: RNGitProgramSetup) throws -> Reticulum {
    let configDir =
      setup.rnsConfigDirectory.map { DaemonBootstrap.expandTildeURL($0) }
      ?? DaemonBootstrap.homeDirectory().appendingPathComponent(".reticulum")
    let paths = DaemonBootstrap.Paths(configDir: configDir)

    if setup.service == true {
      let sink = FileLogSink(fileURL: paths.logFile)
      sink.install()
      logSink = sink
    } else {
      FileLogSink.installStdoutHandler()
    }
    Reticulum.globalLogLevel = .notice

    let bootstrapped = try DaemonBootstrap.bootstrap(
      paths: paths,
      verbosity: setup.service == true ? nil : setup.verbosity - setup.quietness)

    let reticulum = Reticulum.fromConfigDir(configDir)
    try reticulum.start()
    Reticulum.globalLogLevel = bootstrapped.logLevel
    return reticulum
  }
}
