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

/// Why a configuration file's value could not be read as the setting it names.
///
/// Applying a configuration does not catch this.
public enum RNGitSettingsError: Error, Equatable, Sendable {

  /// A setting read as an integer whose value does not name one.
  case notAnInteger(key: String)

  /// A setting read as a boolean whose value names neither.
  case notABoolean(key: String)

  /// A setting read as a path whose value holds more than one, or opens a section.
  case notAPath(key: String)
}

/// The settings an `rngit` node takes from its configuration file.
///
/// The defaults the initialiser sets stand where a section or key is left out, and the aliases are
/// read before the sections that use them.
public struct RNGitNodeSettings: Equatable, Sendable {

  /// The name the node announces itself under.
  public var nodeName = "Anonymous Git Node"

  /// Seconds between announces, or zero to announce only at startup.
  public var announceInterval = 0

  /// Seconds between mirror synchronizations, or zero to leave mirrors alone.
  public var mirrorInterval = 24 * 60 * 60

  /// Whether the node records page and repository statistics.
  public var statsEnabled = false

  /// Identities whose requests the node leaves out of its statistics.
  public var statsIgnored: Set<Data> = []

  /// Identities whose pushes the node leaves out of its statistics.
  public var statsPushIgnored: Set<Data> = []

  /// Identities the node refuses outright.
  public var blockedIdentities: Set<Data> = []

  /// The log level the file asked for, already clamped, or `nil` where it asked for none.
  public var logLevel: Int?

  /// Whether the node also serves its repositories as Nomad Network pages.
  public var serveNomadNet = false

  /// The identity hash each alias names, in lowercase hexadecimal.
  public var identityAliases: [String: String] = [:]

  /// Creates the settings with every default in place.
  public init() {}

  /// Creates the settings `configuration` spells out, with `verbosity` added to its log level.
  public init(configuration: RNGitConfigSection, verbosity: Int = 0) throws {
    self.init()

    if let section = configuration.section("aliases") { readAliases(section) }
    if let section = configuration.section("rngit") { try readNode(section) }

    if let section = configuration.section("logging"), section.has("loglevel") {
      guard let level = section.int("loglevel") else {
        throw RNGitSettingsError.notAnInteger(key: "loglevel")
      }
      logLevel = max(Self.logNone, min(Self.logExtreme, level + verbosity))
    }

    if let section = configuration.section("pages"), section.has("serve_nomadnet") {
      guard let serve = section.bool("serve_nomadnet") else {
        throw RNGitSettingsError.notABoolean(key: "serve_nomadnet")
      }
      if serve { serveNomadNet = true }
    }
  }

  /// The identity hash `alias` names, or `alias` itself where it names none.
  public func resolving(_ alias: String) -> String {
    RNGitPermissionSet.resolvingAlias(alias, aliases: identityAliases)
  }

  /// The names an alias may not take, which `__apply_config` compares without folding case.
  ///
  /// Tested without lowercasing, unlike the test ``RNGitPermissionSet/resolvingAlias(_:aliases:)``
  /// makes against the same list.
  private static let reservedNames = ["n", "none", "nobody", "a", "all", "everyone"]

  /// The lowest and highest log levels the file may ask for.
  private static let logNone = -1
  private static let logExtreme = 8

  private mutating func readAliases(_ section: RNGitConfigSection) {
    for alias in section.keys {
      guard let text = section.string(alias) else { continue }
      guard text.count == Identity.truncatedHashLength / 8 * 2, let hash = Data(pythonHex: text),
        !hash.isEmpty
      else { continue }
      guard !Self.reservedNames.contains(alias) else { continue }
      identityAliases[alias] = hash.map { String(format: "%02x", $0) }.joined()
    }
  }

  private mutating func readNode(_ section: RNGitConfigSection) throws {
    if let name = section.string("node_name") { nodeName = name }

    if section.has("announce_interval") {
      guard let minutes = section.int("announce_interval") else {
        throw RNGitSettingsError.notAnInteger(key: "announce_interval")
      }
      announceInterval = minutes * 60
    }

    if section.has("mirror_interval") {
      guard let hours = section.int("mirror_interval") else {
        throw RNGitSettingsError.notAnInteger(key: "mirror_interval")
      }
      mirrorInterval = max(hours * 60 * 60, 0)
    }

    if section.has("record_stats") {
      guard let enabled = section.bool("record_stats") else {
        throw RNGitSettingsError.notABoolean(key: "record_stats")
      }
      statsEnabled = enabled
    }

    statsIgnored = hashes(section, "stats_ignore_identities")
    statsPushIgnored = hashes(section, "stats_push_ignore_identities")
    blockedIdentities = hashes(section, "blocked_identities")
  }

  private func hashes(_ section: RNGitConfigSection, _ key: String) -> Set<Data> {
    guard let entries = section.list(key) else { return [] }
    var found: Set<Data> = []
    for entry in entries {
      let resolved = resolving(entry)
      guard resolved.count == Reticulum.truncatedHashLength / 8 * 2,
        let hash = Data(pythonHex: resolved)
      else { continue }
      found.insert(hash)
    }
    return found
  }
}
