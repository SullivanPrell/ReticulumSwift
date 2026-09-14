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

/// What a `git-remote-rns` run brings up.
public struct RNGitHelperProgramSetup: Equatable, Sendable {

  /// Where the helper keeps its own configuration, or `nil` for the usual place.
  public var configDirectory: String?

  /// Where Reticulum keeps its configuration, or `nil` for the usual place.
  public var rnsConfigDirectory: String?

  /// What the URL git handed the helper names.
  public var url: RNGitHelperURL

  /// Creates a setup naming where the helper reads its configuration and what it is to reach.
  public init(configDirectory: String?, rnsConfigDirectory: String?, url: RNGitHelperURL) {
    self.configDirectory = configDirectory
    self.rnsConfigDirectory = rnsConfigDirectory
    self.url = url
  }
}

/// The command line `git-remote-rns` is given, which git writes rather than a person.
public enum RNGitHelperCommandLine {

  /// What one command line came to.
  public struct Reading: Equatable, Sendable {

    /// What the run wrote to its error stream.
    public var standardError = ""

    /// The status the run exits with, or `nil` where it carries on.
    public var exitCode: Int32?

    /// What the run brings up, or `nil` where it exits first.
    public var setup: RNGitHelperProgramSetup?
  }

  /// The name the helper is invoked under.
  public static let program = "git-remote-rns"

  /// Reads `arguments`, the remote's name and its URL, against `environment`.
  ///
  /// `arguments` excludes the program name, so git's `git-remote-rns origin rns://…` arrives as
  /// two entries.
  public static func reading(_ arguments: [String], environment: [String: String]) -> Reading {
    var reading = Reading()

    guard arguments.count >= 2 else {
      reading.standardError = "Usage: " + program + " <remote-name> <url>\n"
      reading.exitCode = 1
      return reading
    }

    let url: RNGitHelperURL
    do {
      url = try RNGitHelperURL.reading(arguments[1])
    } catch let error as RNGitHelperURLError {
      reading.standardError = error.message + "\n"
      reading.exitCode = 1
      return reading
    } catch {
      reading.standardError = "\(error)\n"
      reading.exitCode = 1
      return reading
    }

    reading.setup = RNGitHelperProgramSetup(
      configDirectory: environment["RNGIT_CONFIG"],
      rnsConfigDirectory: environment["RNS_CONFIG"], url: url)
    return reading
  }
}
