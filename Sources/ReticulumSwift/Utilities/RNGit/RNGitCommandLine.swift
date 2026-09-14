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

/// The subcommands `rngit` answers to.
public enum RNGitSubcommand: String, CaseIterable, Sendable {

  /// Run a repository node.
  case node

  /// Work with a repository's releases.
  case release

  /// Read and write the permissions on a group or a repository.
  case perms

  /// Work with a repository's work documents.
  case work

  /// Create a repository.
  case create

  /// Copy a repository to one of your own.
  case fork

  /// Bring a repository up to date with the node it came from.
  case sync

  /// Keep a repository following another one.
  case mirror
}

/// What one `rngit` run was asked to do.
///
/// A field the subcommand names nothing for is `nil`, so the subcommands that read it and the
/// ones that pass it over stay apart.
public struct RNGitTask: Equatable, Sendable {

  /// The subcommand that was named.
  public var command: RNGitSubcommand

  /// What the subcommand was asked to do, where it takes an operation.
  public var operation: String?

  /// The group or repository the operation runs against.
  public var remote: String?

  /// The repository a copy is taken from.
  public var source: String?

  /// The tag, the artifacts directory, or the repository a copy is written to.
  public var target: String?

  /// The identity a release is signed with, where it is not the release identity.
  public var signer: String?

  /// What a release package is called, where it is not the repository's name.
  public var name: String?

  /// Whether a release is built without being sent.
  public var noUpload: Bool?

  /// Whether a release is read from what stands locally, without fetching.
  public var offline: Bool?

  /// Which documents a listing reaches.
  public var scope: String?

  /// Which document the operation runs against.
  public var documentIdentifier: Int?

  /// What a document being written is called.
  public var title: String?

  /// Creates a task naming `command` and whatever else the subcommand reads.
  public init(
    command: RNGitSubcommand, operation: String? = nil, remote: String? = nil,
    source: String? = nil, target: String? = nil, signer: String? = nil, name: String? = nil,
    noUpload: Bool? = nil, offline: Bool? = nil, scope: String? = nil,
    documentIdentifier: Int? = nil, title: String? = nil
  ) {
    self.command = command
    self.operation = operation
    self.remote = remote
    self.source = source
    self.target = target
    self.signer = signer
    self.name = name
    self.noUpload = noUpload
    self.offline = offline
    self.scope = scope
    self.documentIdentifier = documentIdentifier
    self.title = title
  }
}

/// What an `rngit` run brings up.
public struct RNGitProgramSetup: Equatable, Sendable {

  /// Where `rngit` keeps its own configuration, or `nil` for the usual place.
  public var configDirectory: String?

  /// Where Reticulum keeps its configuration, or `nil` for the usual place.
  public var rnsConfigDirectory: String?

  /// How much more the run says.
  public var verbosity = 0

  /// How much less the run says.
  public var quietness = 0

  /// Whether the node runs as a service, which writes its log to a file.
  public var service: Bool?

  /// Whether the node drops into a shell once it is up.
  public var interactive: Bool?

  /// Whether the node prints what it is and stops.
  public var printIdentity: Bool?

  /// The identity the run acts as, or `nil` for the configured one.
  public var identity: String?

  /// The identity a release is signed with.
  public var signer: String?

  /// What the run was asked to do, or `nil` where it runs the node.
  public var task: RNGitTask?

  /// Creates a setup carrying nothing but the defaults.
  public init() {}
}

/// How `rngit` reads its command line.
///
/// The subcommand is the first word, and a first word that names none of them leaves the run
/// on the node subcommand with that word still standing, which the node's own reading refuses.
public enum RNGitCommandLine {

  /// What reading a command line came to.
  public struct Reading: Equatable, Sendable {

    /// What the reading wrote where the run's own output goes.
    public var standardOutput = ""

    /// What the reading wrote where the run's failures go.
    public var standardError = ""

    /// What the run stops with, where the reading takes it no further.
    public var exitCode: Int32?

    /// What the run brings up, or `nil` where the reading takes it no further.
    public var setup: RNGitProgramSetup?

    /// Creates an empty reading.
    public init() {}
  }

  /// What the program calls itself.
  public static let program = "rngit"

  /// What `rngit` reads out of `arguments`, which carry no executable name.
  public static func reading(_ arguments: [String], version: String) -> Reading {
    var remaining = arguments
    var subcommand = RNGitSubcommand.node
    if let first = remaining.first, let named = RNGitSubcommand(rawValue: first) {
      subcommand = named
      remaining.removeFirst()
    }

    let parser = makeParser(for: subcommand)
    var reading = Reading()

    let parsed: ParsedArguments
    do {
      parsed = try parser.parse(remaining)
    } catch let error as ArgumentError {
      reading.standardError =
        usage(for: subcommand) + program + ": error: "
        + parser.message(for: error) + "\n"
      reading.exitCode = 2
      return reading
    } catch {
      reading.standardError = usage(for: subcommand) + program + ": error: \(error)\n"
      reading.exitCode = 2
      return reading
    }

    if parsed.wantsHelp {
      reading.standardOutput = help(for: subcommand)
      reading.exitCode = 0
      return reading
    }
    if parsed.flag("--version") {
      reading.standardOutput = program + " " + version + "\n"
      reading.exitCode = 0
      return reading
    }

    var setup = RNGitProgramSetup()
    setup.configDirectory = parsed.value("--config")
    setup.rnsConfigDirectory = parsed.value("--rnsconfig")
    setup.verbosity = parsed.count("--verbose")
    setup.quietness = parsed.count("--quiet")

    switch subcommand {
    case .node:
      guard parsed.positionals.isEmpty else {
        return leftover(parsed.positionals, subcommand, parser)
      }
      setup.service = parsed.flag("--service")
      setup.interactive = parsed.flag("--interactive")
      setup.printIdentity = parsed.flag("--print-identity")
      reading.setup = setup
      return reading

    case .create:
      guard let repository = parsed.positionals.first else {
        return missing("repository", subcommand, parser)
      }
      setup.identity = parsed.value("--identity")
      setup.task = RNGitTask(command: .create, operation: "create", remote: repository)

    case .release:
      let positionals = parsed.positionals
      if positionals.count < 2 { reading.standardOutput = help(for: subcommand) }
      setup.identity = parsed.value("--identity")
      setup.signer = parsed.value("--signer")
      setup.task = RNGitTask(
        command: .release, operation: positionals.count > 1 ? positionals[1] : nil,
        remote: positionals.first, target: positionals.count > 2 ? positionals[2] : nil,
        signer: parsed.value("--signer"), name: parsed.value("--name"),
        noUpload: parsed.flag("--local"), offline: parsed.flag("--offline"))

    case .perms:
      guard let given = parsed.positionals.first else {
        return missing("remote", subcommand, parser)
      }
      let remote = String(given.reversed().drop(while: { $0 == "/" }).reversed())
      let operation: String
      switch remote.components(separatedBy: "/").count {
      case 5: operation = "rperms"
      case 4: operation = "gperms"
      default:
        reading.standardOutput = help(for: subcommand) + "\nInvalid URL\n"
        reading.exitCode = 1
        return reading
      }
      setup.identity = parsed.value("--identity")
      setup.task = RNGitTask(command: .perms, operation: operation, remote: remote)

    case .work:
      let positionals = parsed.positionals
      if positionals.count < 2 { reading.standardOutput = help(for: subcommand) + "\n" }
      var identifier: Int?
      if let given = parsed.value("--id") {
        guard let read = Int(given) else {
          return invalid("--id", given, subcommand, parser)
        }
        identifier = read
      }
      setup.identity = parsed.value("--identity")
      setup.task = RNGitTask(
        command: .work, operation: positionals.count > 1 ? positionals[1] : nil,
        remote: positionals.first, scope: parsed.value("--scope"),
        documentIdentifier: identifier, title: parsed.value("--title"))

    case .fork, .mirror:
      let positionals = parsed.positionals
      guard !positionals.isEmpty else { return missing("source, target", subcommand, parser) }
      guard positionals.count > 1 else { return missing("target", subcommand, parser) }
      setup.identity = parsed.value("--identity")
      setup.task = RNGitTask(
        command: subcommand, operation: "fork", source: positionals[0], target: positionals[1])

    case .sync:
      guard let repository = parsed.positionals.first else {
        return missing("repository", subcommand, parser)
      }
      setup.identity = parsed.value("--identity")
      setup.task = RNGitTask(command: .sync, operation: "sync", remote: repository)
    }

    reading.setup = setup
    return reading
  }

  /// A reading that stops because a positional the subcommand needs was not given.
  private static func missing(
    _ name: String, _ subcommand: RNGitSubcommand, _ parser: ArgumentParser
  ) -> Reading {
    var reading = Reading()
    reading.standardError =
      usage(for: subcommand) + program + ": error: "
      + parser.message(for: .missingPositional(name)) + "\n"
    reading.exitCode = 2
    return reading
  }

  /// A reading that stops because words were given that the subcommand reads nothing from.
  private static func leftover(
    _ given: [String], _ subcommand: RNGitSubcommand, _ parser: ArgumentParser
  ) -> Reading {
    var reading = Reading()
    reading.standardError =
      usage(for: subcommand) + program + ": error: "
      + parser.message(for: .unrecognisedArguments(given)) + "\n"
    reading.exitCode = 2
    return reading
  }

  /// A reading that stops because a value the subcommand reads as a number is none.
  private static func invalid(
    _ option: String, _ given: String, _ subcommand: RNGitSubcommand, _ parser: ArgumentParser
  ) -> Reading {
    var reading = Reading()
    reading.standardError =
      usage(for: subcommand) + program + ": error: argument "
      + parser.spelling(for: option) + ": invalid int value: '" + given + "'\n"
    reading.exitCode = 2
    return reading
  }
}
