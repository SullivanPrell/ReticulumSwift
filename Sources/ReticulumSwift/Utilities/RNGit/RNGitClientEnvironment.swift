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

/// Where a client keeps its configuration, its log and its identity.
///
/// The `rngit` client and the `git-remote-rns` helper keep the same three files in the same
/// place, and both fall back the same way where no directory is named.
public enum RNGitClientEnvironment {

  /// What the log is called.
  public static let logFileName = "client_log"

  /// What the configuration file is called.
  public static let configurationFileName = "client_config"

  /// What the identity file is called.
  public static let identityFileName = "client_identity"

  /// The directory a client keeps its files in, where `given` names none.
  ///
  /// A node's own configuration under `~/.config/rngit` moves the client's files aside, so the
  /// two do not share a directory.
  public static func directory(
    given: String?, home: String = DaemonBootstrap.homeDirectory().path,
    isDirectory: (String) -> Bool = Self.isDirectory,
    isFile: (String) -> Bool = Self.isFile
  ) -> String {
    if let given { return given }
    if isDirectory(home + "/.config/rngit"), isFile(home + "/.config/rngit/config") {
      return home + "/.rngit/reticulum"
    }
    return home + "/.rngit"
  }

  /// The configuration file a client writes where it finds none.
  public static let defaultConfiguration = """
    # This is the default rngit client config file.

    [client]

    # You can control the batch size of ref transfers
    # using the ref_batch_size directive:

    ref_batch_size = 25


    [aliases]

    # You can define aliases for commonly used destination
    # hashes in this section. Each line must be in the format
    # aliased_name = DESTINATION_HASH
    #
    # These hashes are used for resolving remote destinations.
    # For rngit node permissions and identity resolution,
    # aliases must be defined in ~/.rngit/config.

    # my_node = 063d38912bffc850af4a1b8a270a9d85
    # bobs_node = 714981d03e41deda0e4468cb274414cc


    [logging]
    # Valid log levels are 0 through 7:
    #   0: Log only critical information
    #   1: Log errors and lower log levels
    #   2: Log warnings and lower log levels
    #   3: Log notices and lower log levels
    #   4: Log info and lower (this is the default)
    #   5: Verbose logging
    #   6: Debug logging
    #   7: Extreme logging

    loglevel = 4

    """

  /// The configuration at `path`, writing the default one first where nothing is there.
  ///
  /// A file that will not parse throws, which is where a client stops.
  public static func configuration(at path: String, in directory: String) throws
    -> RNGitConfigSection
  {
    if !isFile(path) {
      try FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true)
      try defaultConfiguration.write(toFile: path, atomically: true, encoding: .utf8)
    }
    return try RNGitConfigFile.load(from: URL(fileURLWithPath: path))
  }

  /// The identity at `path`, generating and keeping one first where nothing is there.
  public static func identity(at path: String, in directory: String) throws -> Identity {
    let url = URL(fileURLWithPath: path)
    if isFile(path) {
      guard let recovered = Identity.fromFile(url) else {
        throw RNGitClientAbort("Could not initialize client identity")
      }
      return recovered
    }
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let made = Identity()
    guard (try? made.toFile(url)) == true else {
      throw RNGitClientAbort("Could not initialize client identity")
    }
    return made
  }

  /// Whether a directory stands at `path`.
  public static func isDirectory(_ path: String) -> Bool {
    var directory: ObjCBool = false
    let there = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
    return there && directory.boolValue
  }

  /// Whether a file that is no directory stands at `path`.
  public static func isFile(_ path: String) -> Bool {
    var directory: ObjCBool = false
    let there = FileManager.default.fileExists(atPath: path, isDirectory: &directory)
    return there && !directory.boolValue
  }
}
