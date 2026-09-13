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

/// What `git` reports about one directory a node serves.
///
/// Python: the node's git helpers (`server.py:2709-2782`), each of which runs one command
/// with `check=True` and answers `False` for every failure, git's included.
public enum RNGitWorkingCopy {

  /// Whether `git` runs at all.
  ///
  /// Python: `_ensure_git` (`server.py:2709-2711`).
  public static func gitAvailable(runner: RNGitCommandRunner) -> Bool {
    succeeded(["--version"], in: nil, runner: runner) != nil
  }

  /// Whether `path` is a repository holding its own git directory.
  ///
  /// Python: `__is_git_repository` (`server.py:2713-2721`). The test is that `--git-dir`
  /// answers `.`, so a repository with a working tree, which answers `.git`, is not one.
  public static func isGitRepository(_ path: String, runner: RNGitCommandRunner) -> Bool {
    succeeded(["rev-parse", "--git-dir"], in: path, runner: runner) == "."
  }

  /// Whether `path` is a bare repository.
  ///
  /// Python: `__is_bare_repository` (`server.py:2723-2731`).
  public static func isBareRepository(_ path: String, runner: RNGitCommandRunner) -> Bool {
    succeeded(["config", "--bool", "core.bare"], in: path, runner: runner) == "true"
  }

  /// The upstream `path` forks, or `nil` where it is not a fork.
  ///
  /// Python: `__is_fork` (`server.py:2733-2745`), which answers the source even when the
  /// configured source is blank.
  public static func forkSource(of path: String, runner: RNGitCommandRunner) -> String? {
    upstreamSource(of: path, ofType: "fork", runner: runner)
  }

  /// The upstream `path` mirrors, or `nil` where it is not a mirror.
  ///
  /// Python: `__is_mirror` (`server.py:2747-2759`).
  public static func mirrorSource(of path: String, runner: RNGitCommandRunner) -> String? {
    upstreamSource(of: path, ofType: "mirror", runner: runner)
  }

  /// When `path` last synchronized with its upstream, or `nil` where it never recorded one.
  ///
  /// Python: `__mirror_synced` (`server.py:2761-2768`), whose `int()` refuses a blank or
  /// non-numeric setting.
  public static func mirrorSynced(_ path: String, runner: RNGitCommandRunner) -> Int? {
    guard
      let text = succeeded(
        ["config", "repository.rngit.upstream.sync"], in: path,
        runner: runner)
    else { return nil }
    return RNGitConfigSection.integer(text)
  }

  /// Records `time` as the moment `path` last synchronized, answering whether git took it.
  ///
  /// Python: `__set_mirror_synced` (`server.py:2770-2778`).
  public static func setMirrorSynced(
    _ path: String, at time: Int, runner: RNGitCommandRunner
  ) -> Bool {
    succeeded(
      ["config", "repository.rngit.upstream.sync", String(time)], in: path,
      runner: runner) != nil
  }

  /// When `path` last synchronized, taking a missing or unreadable setting as the epoch.
  ///
  /// Python: `last_upstream_sync` (`server.py:2780-2782`).
  public static func lastUpstreamSync(_ path: String, runner: RNGitCommandRunner) -> Int {
    mirrorSynced(path, runner: runner) ?? 0
  }

  private static func upstreamSource(
    of path: String, ofType type: String, runner: RNGitCommandRunner
  ) -> String? {
    guard succeeded(["config", "repository.rngit.type"], in: path, runner: runner) == type
    else { return nil }
    return succeeded(["config", "repository.rngit.upstream.source"], in: path, runner: runner)
  }

  /// What the command wrote, trimmed, or `nil` where git refused it or could not run.
  private static func succeeded(
    _ arguments: [String], in directory: String?, runner: RNGitCommandRunner
  ) -> String? {
    guard let output = runner.run("git", arguments: arguments, in: directory),
      output.status == 0
    else {
      return nil
    }
    return output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
