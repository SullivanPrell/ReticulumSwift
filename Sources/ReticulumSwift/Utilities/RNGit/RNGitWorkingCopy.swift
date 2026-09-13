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
/// Each runs one command and answers `false` for every failure, git's included.
public enum RNGitWorkingCopy {

  /// Whether `git` runs at all.
  public static func gitAvailable(runner: RNGitCommandRunner) -> Bool {
    succeeded(["--version"], in: nil, runner: runner) != nil
  }

  /// Whether `path` is a repository holding its own git directory.
  ///
  /// The test is that `--git-dir` answers `.`, so a repository with a working tree, which answers
  /// `.git`, is not one.
  public static func isGitRepository(_ path: String, runner: RNGitCommandRunner) -> Bool {
    succeeded(["rev-parse", "--git-dir"], in: path, runner: runner) == "."
  }

  /// Whether `path` is a bare repository.
  public static func isBareRepository(_ path: String, runner: RNGitCommandRunner) -> Bool {
    succeeded(["config", "--bool", "core.bare"], in: path, runner: runner) == "true"
  }

  /// The upstream `path` forks, or `nil` where it is not a fork.
  ///
  /// Answers the source even where the configured source is blank.
  public static func forkSource(of path: String, runner: RNGitCommandRunner) -> String? {
    upstreamSource(of: path, ofType: "fork", runner: runner)
  }

  /// The upstream `path` mirrors, or `nil` where it is not a mirror.
  public static func mirrorSource(of path: String, runner: RNGitCommandRunner) -> String? {
    upstreamSource(of: path, ofType: "mirror", runner: runner)
  }

  /// When `path` last synchronized with its upstream, or `nil` where it never recorded one.
  ///
  /// A blank or non-numeric setting is refused.
  public static func mirrorSynced(_ path: String, runner: RNGitCommandRunner) -> Int? {
    guard
      let text = succeeded(
        ["config", "repository.rngit.upstream.sync"], in: path,
        runner: runner)
    else { return nil }
    return RNGitConfigSection.integer(text)
  }

  /// Records `time` as the moment `path` last synchronized, answering whether git took it.
  public static func setMirrorSynced(
    _ path: String, at time: Int, runner: RNGitCommandRunner
  ) -> Bool {
    succeeded(
      ["config", "repository.rngit.upstream.sync", String(time)], in: path,
      runner: runner) != nil
  }

  /// When `path` last synchronized, taking a missing or unreadable setting as the epoch.
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

  /// Fetches every reference from `source` into the mirror at `path`, answering whether the
  /// mirror is now current.
  ///
  /// A failure to point HEAD at the upstream's default branch, and a failure to record the moment,
  /// both leave the mirror counted as synchronized.
  public static func syncMirror(
    _ path: String, from source: String, runner: RNGitCommandRunner, now: () -> Int
  ) -> Bool {
    guard !source.isEmpty else { return false }
    guard
      let fetched = runner.run("git", arguments: ["fetch", source, "+refs/*:refs/*"], in: path),
      fetched.status == 0
    else { return false }
    _ = updateHeadToSourceDefault(path, from: source, runner: runner)
    _ = setMirrorSynced(path, at: now(), runner: runner)
    return true
  }

  /// Fetches every reference from `source` into the fork at `path`, answering whether the
  /// fork is now current.
  ///
  /// Leaves HEAD where the fork's maintainer put it.
  public static func syncFork(
    _ path: String, from source: String, runner: RNGitCommandRunner, now: () -> Int
  ) -> Bool {
    guard !source.isEmpty else { return false }
    guard
      let fetched = runner.run("git", arguments: ["fetch", source, "+refs/*:refs/*"], in: path),
      fetched.status == 0
    else { return false }
    _ = setMirrorSynced(path, at: now(), runner: runner)
    return true
  }

  /// Points HEAD at `path` to the branch `source` defaults to, falling back to the first
  /// branch `path` holds.
  ///
  /// A first command that cannot run leaves the fallback to answer; every later one that cannot run
  /// abandons the attempt, which the mirror sync that called it goes on regardless of.
  public static func updateHeadToSourceDefault(
    _ path: String, from source: String, runner: RNGitCommandRunner
  ) -> Bool {
    var target = remoteDefaultBranch(of: source, runner: runner)
    if let branch = target {
      guard
        let checked = runner.run(
          "git", arguments: ["show-ref", "--verify", "--quiet", branch], in: path)
      else { return false }
      if checked.status != 0 { target = nil }
    }
    if target == nil {
      guard
        let listed = runner.run(
          "git",
          arguments: [
            "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1",
          ], in: path)
      else { return false }
      let first = listed.standardOutput.pythonStripped
      guard listed.status == 0, !first.isEmpty else { return false }
      target = "refs/heads/" + first
    }
    guard let branch = target,
      let written = runner.run("git", arguments: ["symbolic-ref", "HEAD", branch], in: path)
    else { return false }
    return written.status == 0
  }

  /// The branch `source` points HEAD at, or `nil` where it names none.
  private static func remoteDefaultBranch(
    of source: String, runner: RNGitCommandRunner
  ) -> String? {
    guard
      let listed = runner.run(
        "git", arguments: ["ls-remote", "--symref", source, "HEAD"], in: nil),
      listed.status == 0
    else { return nil }
    for line in listed.standardOutput.components(separatedBy: "\n")
    where line.hasPrefix("ref: refs/heads/") {
      let parts = line.components(separatedBy: "\t")
      guard parts.count >= 2, parts[1] == "HEAD" else { continue }
      return String(parts[0].dropFirst(5)).pythonStripped
    }
    return nil
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
