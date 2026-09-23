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

/// Where a node keeps its configuration, its log, its identity and its statistics.
///
/// A node reads a system-wide directory before the user's own, so one machine can serve
/// repositories for everyone on it.
public enum RNGitNodeEnvironment {

  /// The directory a node reads before any under the user's home.
  public static let systemDirectory = "/etc/rngit"

  /// What the log is called.
  public static let logFileName = "server_log"

  /// What the configuration file is called.
  public static let configurationFileName = "config"

  /// What the identity file is called.
  public static let identityFileName = "repositories_identity"

  /// What the statistics file is called.
  public static let statisticsFileName = "stats"

  /// The directory a node keeps its files in, where `given` names none.
  ///
  /// A node whose own configuration stands under `~/.config/rngit` keeps its files under
  /// `~/.rngit/reticulum`, so the client's files and the node's do not share a directory.
  public static func directory(
    given: String?, home: String = DaemonBootstrap.homeDirectory().path,
    isDirectory: (String) -> Bool = RNGitClientEnvironment.isDirectory,
    isFile: (String) -> Bool = RNGitClientEnvironment.isFile
  ) -> String {
    if let given { return given }
    if isDirectory(systemDirectory), isFile(systemDirectory + "/" + configurationFileName) {
      return systemDirectory
    }
    if isDirectory(home + "/.config/rngit"), isFile(home + "/.config/rngit/config") {
      return home + "/.rngit/reticulum"
    }
    return home + "/.rngit"
  }

  /// The configuration file a node writes where it finds none.
  public static let defaultConfiguration = """
    # This is the default rngit config file.
    # You will need to edit it to specify repository locations and
    # access permissions.

    [rngit]

    # Automatic announce interval in minutes.
    # 6 hours by default.

    announce_interval = 360

    # An optional name for this node, included
    # in announces.

    # node_name = Anonymous Git Node

    # You can enable collecting view, fetch and push statistics
    # which can be displayed on the stats pages of repositories.
    # Remember to set the "s" (stats) permission appropriately
    # for statistics to actually be viewable by anyone.

    # record_stats = no
    # stats_ignore_identities = 9710b86ba12c42d1d8f30f74fe509286
    # stats_push_ignore_identities = 5bffebe038654304dafcbe12cbcd0412

    # You can block specific identities from any interaction
    # with this node.

    # blocked_identities = d31aeea49873006f13b3415520666a4e

    # To make it easier to handle scrapers, crawlers, slopware
    # and other annoyances, you can block unidentified peers by
    # adding the null_ident hash to to blocked identities.

    # blocked_identities = d7db22f63b453c23bb0688dde565b7c1

    [repositories]

    # You can define multiple repository groups, each with a path
    # to the directory containing "repo_name.git" directories.

    internal = /path/to/directory/with/git/repositories
    public = /another/path/to/directory/with/git/repositories
    showcase = /another/path/to/directory/with/git/repositories

    # To add a short description to your repositories, you can
    # either place a "repo_name.description" file in the same
    # directory as the repository folder, or set it in the bare
    # repository with `git config repository.description`.

    # If you have mirrored repositories with the "rngit mirror"
    # command, you can configure the global mirroring interval
    # in hours.

    # mirror_interval = 24


    [aliases]

    # You can define aliases for commonly used identity hashes
    # in this section. Each line must be in the format
    # aliased_name = IDENTITY_HASH
    #
    # These hashes are used for the permissions system and
    # identity resolution. For rngit CLI client operations,
    # aliases must be defined in ~/.rngit/client_config.

    # alice = d09285e660cfe27cee6d9a0beb58b7e0
    # bob = ffcffb4e255e156e77f79b82c13086a6

    [access]

    # You can apply permissions for all repositories within
    # different repository collections like this:

    public = r:all, w:9710b86ba12c42d1d8f30f74fe509286
    internal = rw:9710b86ba12c42d1d8f30f74fe509286

    # By default, all repositories sourced from the con-
    # figured repository collection paths have no permissions
    # enabled, and will be neither readable nor writable.
    #
    # The following permissions are supported:
    #   r   = read       (clone, fetch, view)
    #   w   = write      (push, create and manage work documents)
    #   rw  = read/write
    #   c   = create     (create new repositories in group)
    #   s   = stats      (view repository statistics)
    #   rel = release    (create and manage releases)
    #   i   = interact   (comment on work documents)
    #   p   = propose    (propose new work documents)
    #   adm = admin      (full administrative access)
    #
    # To configure permissions per repository, you must create
    # an ".allowed" file matching the repository name. If the
    # repository is in a folder called "my_project.git", create
    # a "my_project.allowed" file next to it. This file must
    # contain a permission statement on each line in the form of
    # "r:IDENTITY_HASH", "w:IDENTITY_HASH" or "r:IDENTITY_HASH".
    # Instead of IDENTITY_HASH, you can also use "all" or "none".
    #
    # You can also make the allow-files executable, and have them
    # evaluate or source the permissions from somewhere else,
    # and then output the results to stdout.
    #
    # Additionally, you can create a "group.allowed" file in the
    # root of a repository group directory, which will apply to
    # all repositories within this group. The same syntax and
    # functionality applies here.


    [pages]
    # You can run a nomadnet-compatible page node to serve
    # repository information if required. Access permissions
    # will follow those configured per group and repository.
    #
    # The page server supports automatic markdown to micron
    # conversion for repository readmes and other files. If
    # you have the pygments Python module installed, syntax
    # highlighting will also be automatically applied.
    #
    # The page server is highly customizable, and you can
    # provide custom templates for each page type by placing
    # a corresponding "template_name.mu" file in the
    # ~/.rngit/templates directory. The supported template
    # names are "base", "front", "group", "repo", "tree",
    # "blob", "commits", "commit", "refs", "stats", "releases",
    # "release", "work" and "work_doc". You should include a
    # {PAGE_CONTENT} variable somewhere in your templates,
    # the rendered page content will be injected into this
    # variable.

    # serve_nomadnet = no

    # It is possible to disable Nerd Font icons and instead
    # use simpler (but more compatible) unicode icons.

    # unicode_icons = yes

    # You can configure whether the page server should try
    # to convert media files to WebP on the fly, for serving
    # to nomadnet clients. Enabled by default, but will
    # require an available encoding backend installed on
    # your system. Supported backends utilities are "magick",
    # "convert", "gm", "ffmpeg" and "avconv". If any one is
    # installed, rngit will auto-detect and use it, but you
    # can force a specific backend with the environment
    # variable RNGIT_MEDIA_BACKEND.

    # media_conversion = yes


    [logging]
    # Valid log levels are 0 through 8:
    #   0: Log only critical information
    #   1: Log errors and lower log levels
    #   2: Log warnings and lower log levels
    #   3: Log notices and lower log levels
    #   4: Log info and lower (this is the default)
    #   5: Verbose logging
    #   6: Debug logging
    #   7: Pathing logging
    #   8: Extreme logging

    loglevel = 4


    """

  /// The aspect a node serves Nomad Network pages on, alongside its repositories.
  public static let pagesFullName = "nomadnetwork.node"

  /// The four lines a node prints when it is asked what it is.
  ///
  /// A node serving no pages prints the first three. The labels are padded to one width so the
  /// colons line up.
  public static func identityLines(
    node: Identity, client: Identity, servingPages: Bool
  ) -> [String] {
    let repositories = Destination.hash(
      identity: node, appName: RNGitDestination.appName, aspects: [RNGitDestination.aspect])
    var lines = [
      "Git Peer Identity         : " + RNSUtilities.prettyhexrep(client.hash),
      "Repository Node Identity  : " + RNSUtilities.prettyhexrep(node.hash),
      "Repositories Destination  : " + RNSUtilities.prettyhexrep(repositories),
    ]
    guard servingPages else { return lines }
    let pages = Destination.hash(fromFullName: pagesFullName, identity: node)
    lines.append("Nomad Network Destination : " + RNSUtilities.prettyhexrep(pages))
    return lines
  }

  /// The configuration at `path`, writing the default one first where nothing is there.
  ///
  /// A file that will not parse throws, which is where a node stops.
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

  /// The repositories identity at `path`, generating and keeping one first where nothing is
  /// there.
  public static func identity(at path: String, in directory: String) throws -> Identity {
    let url = URL(fileURLWithPath: path)
    if isFile(path) {
      guard let recovered = Identity.fromFile(url) else {
        throw RNGitClientAbort("Could not initialize repositories identity")
      }
      return recovered
    }
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let made = Identity()
    guard (try? made.toFile(url)) == true else {
      throw RNGitClientAbort("Could not initialize repositories identity")
    }
    return made
  }

  /// Whether a directory stands at `path`.
  static func isDirectory(_ path: String) -> Bool {
    RNGitClientEnvironment.isDirectory(path)
  }

  /// Whether a file that is no directory stands at `path`.
  static func isFile(_ path: String) -> Bool {
    RNGitClientEnvironment.isFile(path)
  }
}
