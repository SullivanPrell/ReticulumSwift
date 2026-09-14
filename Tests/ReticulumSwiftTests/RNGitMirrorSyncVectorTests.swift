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
import XCTest

@testable import ReticulumSwift

/// The upstream synchronization a node performs, as Python RNS 1.5.4 performs it.
///
/// Each vector is what the reference's own routine answered, along with every command it
/// would have run, recorded through a stand-in for its `subprocess` module.
final class RNGitMirrorSyncVectorTests: XCTestCase {

  private struct Outcome {
    let status: Int32
    let standardOutput: String
    let standardError: String

    init(_ status: Int32, _ standardOutput: String, _ standardError: String) {
      self.status = status
      self.standardOutput = standardOutput
      self.standardError = standardError
    }
  }

  private struct Call: Equatable {
    let argv: [String]
    let directory: String?

    init(_ argv: [String], _ directory: String?) {
      self.argv = argv
      self.directory = directory
    }
  }

  /// Answers what the reference's `subprocess` was scripted to answer, logging every call.
  private final class ScriptedRunner: RNGitCommandRunner, @unchecked Sendable {
    let script: [Outcome?]
    var calls: [Call] = []

    init(_ script: [Outcome?]) { self.script = script }

    func run(_ executable: String, arguments: [String], in directory: String?)
      -> RNGitCommandOutput?
    {
      calls.append(Call([executable] + arguments, directory))
      let outcome =
        calls.count <= script.count ? script[calls.count - 1] : Outcome(0, "", "")
      guard let outcome else { return nil }
      return RNGitCommandOutput(
        status: outcome.status, standardOutput: outcome.standardOutput,
        standardError: outcome.standardError)
    }
  }

  private struct Vector {
    let name: String
    let source: String
    let script: [Outcome?]
    let answer: String
    let calls: [Call]
  }

  private static let mirrors: [Vector] = [
    Vector(
      name: "source empty",
      source: "",
      script: [],
      answer: "false",
      calls: []),
    Vector(
      name: "source blank",
      source: " ",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", " ", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", " ", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "fetched",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "fetch failed",
      source: "rns://source/repo",
      script: [Outcome(128, "", "fatal: no\n")],
      answer: "false",
      calls: [Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>")]),
    Vector(
      name: "fetch would not run",
      source: "rns://source/repo",
      script: [nil],
      answer: "false",
      calls: [Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>")]),
    Vector(
      name: "head update abandoned",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""), nil,
        Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "head update failed",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "sync time refused",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "sync time would not run",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), nil,
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
  ]

  private static let forks: [Vector] = [
    Vector(
      name: "source empty",
      source: "",
      script: [],
      answer: "false",
      calls: []),
    Vector(
      name: "source blank",
      source: " ",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", " ", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "fetched",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "fetch failed",
      source: "rns://source/repo",
      script: [Outcome(128, "", "fatal: no\n")],
      answer: "false",
      calls: [Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>")]),
    Vector(
      name: "fetch would not run",
      source: "rns://source/repo",
      script: [nil],
      answer: "false",
      calls: [Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>")]),
    Vector(
      name: "head update abandoned",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""), nil,
        Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "head update failed",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "sync time refused",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), Outcome(128, "", "fatal: no\n"),
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
    Vector(
      name: "sync time would not run",
      source: "rns://source/repo",
      script: [
        Outcome(0, "", ""), Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""), nil,
      ],
      answer: "true",
      calls: [
        Call(["git", "fetch", "rns://source/repo", "+refs/*:refs/*"], "<repo>"),
        Call(["git", "config", "repository.rngit.upstream.sync", "1700000000"], "<repo>"),
      ]),
  ]

  private static let heads: [Vector] = [
    Vector(
      name: "remote head taken",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""), Outcome(0, "", ""),
        Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
      ]),
    Vector(
      name: "remote head refused",
      source: "rns://source/repo",
      script: [Outcome(128, "", "fatal: no\n"), Outcome(0, "trunk\n", ""), Outcome(0, "", "")],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "remote head would not run",
      source: "rns://source/repo",
      script: [nil, Outcome(0, "trunk\n", ""), Outcome(0, "", "")],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "remote head without a tab",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\n", ""), Outcome(0, "trunk\n", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "remote head not for HEAD",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\tOTHER\n", ""), Outcome(0, "trunk\n", ""),
        Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "remote head not a branch",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/tags/v1\tHEAD\n", ""), Outcome(0, "trunk\n", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "remote head after another line",
      source: "rns://source/repo",
      script: [
        Outcome(0, "x\nref: refs/heads/one\tHEAD\nref: refs/heads/two\tHEAD\n", ""),
        Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/one"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/one"], "<repo>"),
      ]),
    Vector(
      name: "remote head with a third field",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\tHEAD\textra\n", ""), Outcome(0, "", ""),
        Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
      ]),
    Vector(
      name: "remote head padded",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main \t HEAD\n", ""), Outcome(0, "trunk\n", ""),
        Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "remote head trailing space",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main \tHEAD\n", ""), Outcome(0, "", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
      ]),
    Vector(
      name: "remote head carriage returned",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\tHEAD\r\n", ""), Outcome(0, "trunk\n", ""),
        Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "branch absent locally",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""), Outcome(128, "", "fatal: no\n"),
        Outcome(0, "trunk\n", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "branch check would not run",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""), nil, Outcome(0, "", ""),
        Outcome(0, "", ""),
      ],
      answer: "raised",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
      ]),
    Vector(
      name: "fallback empty",
      source: "rns://source/repo",
      script: [Outcome(128, "", "fatal: no\n"), Outcome(0, "  \n", ""), Outcome(0, "", "")],
      answer: "false",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
      ]),
    Vector(
      name: "fallback failed",
      source: "rns://source/repo",
      script: [Outcome(128, "", "fatal: no\n"), Outcome(128, "trunk\n", ""), Outcome(0, "", "")],
      answer: "false",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
      ]),
    Vector(
      name: "fallback would not run",
      source: "rns://source/repo",
      script: [Outcome(128, "", "fatal: no\n"), nil, Outcome(0, "", "")],
      answer: "false",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
      ]),
    Vector(
      name: "fallback padded",
      source: "rns://source/repo",
      script: [
        Outcome(128, "", "fatal: no\n"), Outcome(0, " \t trunk \r\n", ""), Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "fallback separator padded",
      source: "rns://source/repo",
      script: [
        Outcome(128, "", "fatal: no\n"), Outcome(0, "\u{1C}\u{1E} trunk \u{1F}", ""),
        Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(
          ["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "--count=1"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/trunk"], "<repo>"),
      ]),
    Vector(
      name: "head written",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""), Outcome(0, "", ""),
        Outcome(0, "", ""),
      ],
      answer: "true",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
      ]),
    Vector(
      name: "head refused",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""), Outcome(0, "", ""),
        Outcome(128, "", "fatal: no\n"),
      ],
      answer: "false",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
      ]),
    Vector(
      name: "head would not run",
      source: "rns://source/repo",
      script: [
        Outcome(0, "ref: refs/heads/main\tHEAD\n1111\tHEAD\n", ""), Outcome(0, "", ""), nil,
      ],
      answer: "false",
      calls: [
        Call(["git", "ls-remote", "--symref", "rns://source/repo", "HEAD"], nil),
        Call(["git", "show-ref", "--verify", "--quiet", "refs/heads/main"], "<repo>"),
        Call(["git", "symbolic-ref", "HEAD", "refs/heads/main"], "<repo>"),
      ]),
  ]

  private static let now = 1_700_000_000

  /// Every mirror is brought up to date the way the reference brings it.
  func testMirrorSyncsMatchTheReference() {
    for vector in Self.mirrors {
      check(vector) { path, runner in
        RNGitWorkingCopy.syncMirror(
          path, from: vector.source, runner: runner, now: { Self.now })
      }
    }
  }

  /// Every fork is brought up to date the way the reference brings it.
  func testForkSyncsMatchTheReference() {
    for vector in Self.forks {
      check(vector) { path, runner in
        RNGitWorkingCopy.syncFork(path, from: vector.source, runner: runner, now: { Self.now })
      }
    }
  }

  /// HEAD is pointed where the reference points it.
  func testHeadUpdatesMatchTheReference() {
    for vector in Self.heads {
      check(vector) { path, runner in
        RNGitWorkingCopy.updateHeadToSourceDefault(path, from: vector.source, runner: runner)
      }
    }
  }

  /// Runs `routine` against `vector` and compares its answer and its calls.
  ///
  /// The reference raises where a command after the first cannot run, which the routine
  /// that called it swallows; the port answers `false` and its caller ignores the answer
  /// the same way.
  private func check(
    _ vector: Vector, _ routine: (String, RNGitCommandRunner) -> Bool
  ) {
    let path = NSTemporaryDirectory() + "rngit-mirror-" + UUID().uuidString
    let runner = ScriptedRunner(vector.script)
    let answered = routine(path, runner)
    let expected = vector.answer == "raised" ? "false" : vector.answer
    XCTAssertEqual(String(answered), expected, vector.name)
    XCTAssertEqual(Self.normalised(runner.calls, at: path), vector.calls, vector.name)
  }

  /// The calls with the repository path replaced by the name the vectors use.
  private static func normalised(_ calls: [Call], at path: String) -> [Call] {
    calls.map { Call($0.argv, $0.directory == path ? "<repo>" : $0.directory) }
  }
}
