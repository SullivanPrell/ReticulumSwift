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

/// The settings an `rngit` client takes from its own configuration file.
///
/// The defaults the initialiser sets stand where a section or key is left out. Unlike a node, a
/// client takes an alias under any name, including the names a permission line reserves.
public struct RNGitClientSettings: Equatable, Sendable {

  /// The log level the file asked for, already clamped, or `nil` where it asked for none.
  public var logLevel: Int?

  /// The destination hash each alias names, in lowercase hexadecimal.
  public var destinationAliases: [String: String] = [:]

  /// Creates the settings with every default in place.
  public init() {}

  /// Creates the settings `configuration` spells out.
  public init(configuration: RNGitConfigSection) throws {
    self.init()

    if let section = configuration.section("logging"), section.has("loglevel") {
      guard let level = section.int("loglevel") else {
        throw RNGitSettingsError.notAnInteger(key: "loglevel")
      }
      logLevel = max(Self.logNone, min(Self.logExtreme, level))
    }

    if let section = configuration.section("aliases") { readAliases(section) }
  }

  /// The destination hash `alias` names, or `alias` itself where it names none.
  public func resolving(_ alias: String) -> String {
    Self.resolving(alias, aliases: destinationAliases)
  }

  /// The destination hash `alias` names among `aliases`, or `alias` itself where it names none.
  ///
  /// A spelled-out hash is left alone, and so is a name nothing stands for.
  public static func resolving(_ alias: String, aliases: [String: String]) -> String {
    if alias.count == Identity.truncatedHashLength / 8 * 2, let hash = Data(pythonHex: alias),
      !hash.isEmpty
    {
      return alias
    }
    return aliases[alias] ?? alias
  }

  /// The lowest and highest log levels the file may ask for.
  private static let logNone = -1
  private static let logExtreme = 8

  private mutating func readAliases(_ section: RNGitConfigSection) {
    for alias in section.keys {
      guard let text = section.string(alias) else { continue }
      guard text.count == Identity.truncatedHashLength / 8 * 2, let hash = Data(pythonHex: text),
        !hash.isEmpty
      else { continue }
      destinationAliases[alias] = hash.hexString
    }
  }
}
