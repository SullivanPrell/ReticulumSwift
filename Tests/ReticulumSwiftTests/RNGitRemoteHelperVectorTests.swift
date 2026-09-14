//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest

@testable import ReticulumSwift

/// The `git-remote-rns` helper, measured against Python RNS 1.5.4.
final class RNGitRemoteHelperVectorTests: XCTestCase {

  /// What a node answered one request with, or nothing where the request brought nothing back.
  private struct Answer {
    let body: String?
    let metadata: String?
  }

  /// What `git` answered one invocation with.
  private struct Command {
    let arguments: [String]
    let status: Int32
    let standardOutput: String
    let standardError: String
    let bundle: String?
  }

  /// One request the helper sent.
  private struct Request: Equatable {
    let path: String
    let fields: String
    let timeout: Double
  }

  /// The path the helper waited for, and how long it waited.
  private struct Awaited: Equatable {
    let hash: String
    let timeout: Double
  }

  /// One report a link made of a transfer still arriving.
  private struct Report {
    let fraction: Double
    let size: Int?
    let transferSize: Int?
    let at: Double
  }

  /// One run of the helper, and everything it did.
  private struct Run {
    let name: String
    let url: String
    let aliases: [String: String]
    let refBatchSize: Int
    let script: String
    let hasPath: Bool
    let recalls: Bool
    let linkComesUp: Bool
    let answers: [Answer]
    let commands: [Command]
    let reports: [[Report]]
    let bundle: String?
    let written: String
    let reported: String
    let requests: [Request]
    let ran: [[String]]
    let aborted: String?
    let failed: String?
    let references: [RNGitRemoteReference]
    let progress: Bool
    let awaited: Awaited?
    let tornDown: Bool
  }

  /// One value git reads back quoted.
  private struct Escape {
    let value: String
    let escaped: String
  }

  /// What the helper takes out of one configuration file.
  private struct Setting {
    let name: String
    let configuration: String
    let logLevel: Int?
    let refBatchSize: Int
    let aliases: [String: String]
  }

  /// What one URL git may hand the helper names, or why it names nothing.
  private struct Reading {
    let url: String
    let error: String?
    let destination: String?
    let group: String?
    let repository: String?
  }

  private static let runs: [Run] = [
    Run(
      name: "capabilities",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "capabilities\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "list\nfetch\npush\noption\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "capabilities then batch",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "capabilities\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "list\nfetch\npush\noption\n\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "no commands",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "empty batch",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "two empty batches",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "unknown command",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "frobnicate\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: "Unknown Git command: frobnicate",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "unknown command with words",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetchery a b\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "stripped line",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "  capabilities  \n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "list\nfetch\npush\noption\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "blank line of spaces",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "   \n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress true",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress true\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress 1",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress 1\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress yes",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress yes\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress TRUE",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress TRUE\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress Yes",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress Yes\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress false",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress false\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress 0",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress 0\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress no",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress no\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress maybe",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress maybe\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress bare",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress spaced",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option   progress   true   and more\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option bare",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "unsupported\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option unknown",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option verbosity 2\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "unsupported\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option prefix run together",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "options progress true\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list empty",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list refs",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "0061616131313120726566732f68656164732f6d61696e0a62626232323220726566732f68656164732f6465760a63636333333320484541440a",
          metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "aaa111 refs/heads/main\nbbb222 refs/heads/dev\nccc333 HEAD\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [
        RNGitRemoteReference(name: "refs/heads/main", sha: "aaa111"),
        RNGitRemoteReference(name: "refs/heads/dev", sha: "bbb222"),
      ],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list for push",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list for-push\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "0061616131313120726566732f68656164732f6d61696e0a62626232323220726566732f68656164732f6465760a63636333333320484541440a",
          metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "aaa111 refs/heads/main\nbbb222 refs/heads/dev\nccc333 HEAD\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c3",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [
        RNGitRemoteReference(name: "refs/heads/main", sha: "aaa111"),
        RNGitRemoteReference(name: "refs/heads/dev", sha: "bbb222"),
      ],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list ragged",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "00202061616131313120726566732f68656164732f6d61696e20200a0a0a686561646c6573730a63636333333320484541440a646464343434206120620a",
          metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "  aaa111 refs/heads/main  \n\n\nheadless\nccc333 HEAD\nddd444 a b\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [
        RNGitRemoteReference(name: "refs/heads/main", sha: "aaa111"),
        RNGitRemoteReference(name: "a b", sha: "ddd444"),
      ],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list duplicate ref",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "0061616131313120726566732f68656164732f6d61696e0a62626232323220726566732f68656164732f6d61696e0a",
          metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "aaa111 refs/heads/main\nbbb222 refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [
        RNGitRemoteReference(name: "refs/heads/main", sha: "bbb222")
      ],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list refused",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "014e6f7420616c6c6f776564", metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: "Server refused list: Not allowed",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list refused empty",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "ff", metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: "Server refused list: ",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list empty response",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "", metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: "Invalid list response from server",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list request failed",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: nil, metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: "Request failed or timed out",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list twice",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n\nlist\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "0061616131313120726566732f68656164732f6d61696e0a62626232323220726566732f68656164732f6465760a63636333333320484541440a",
          metadata: nil),
        Answer(body: "00", metadata: nil),
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "aaa111 refs/heads/main\nbbb222 refs/heads/dev\nccc333 HEAD\n\n\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0),
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0),
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch one ref",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "bbb222\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739183a3736861a6616161313131a3726566af726566732f68656164732f6d61696ea468617665a6626262323232",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch ref already at sha",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch unresolvable ref",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 128, standardOutput: "",
          standardError: "unknown revision\n", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch duplicate",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\nfetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "bbb222\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739183a3736861a6616161313131a3726566af726566732f68656164732f6d61696ea468617665a6626262323232",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch two refs",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\nfetch bbb222 refs/heads/dev\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["rev-parse", "refs/heads/dev"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739282a3736861a6616161313131a3726566af726566732f68656164732f6d61696e82a3736861a6626262323232a3726566ae726566732f68656164732f646576",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["rev-parse", "refs/heads/dev"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch batched",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 2,
      script: "fetch a1 refs/heads/one\nfetch a2 refs/heads/two\nfetch a3 refs/heads/three\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100"),
        Answer(body: "<bundle>", metadata: "810100"),
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/one"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["rev-parse", "refs/heads/two"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["rev-parse", "refs/heads/three"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739282a3736861a26131a3726566ae726566732f68656164732f6f6e6582a3736861a26132a3726566ae726566732f68656164732f74776f",
          timeout: 7200.0),
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a26133a3726566b0726566732f68656164732f7468726565",
          timeout: 7200.0),
      ],
      ran: [
        ["rev-parse", "refs/heads/one"],
        ["rev-parse", "refs/heads/two"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
        ["rev-parse", "refs/heads/three"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch after list",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n\nfetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "0061616131313120726566732f68656164732f6d61696e0a62626232323220726566732f68656164732f6465760a63636333333320484541440a",
          metadata: nil),
        Answer(body: "<bundle>", metadata: "810100"),
      ],
      commands: [
        Command(
          arguments: ["cat-file", "-t", "aaa111"], status: 0, standardOutput: "", standardError: "",
          bundle: nil),
        Command(
          arguments: ["cat-file", "-t", "bbb222"], status: 1, standardOutput: "", standardError: "",
          bundle: nil),
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "ddd444\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "aaa111 refs/heads/main\nbbb222 refs/heads/dev\nccc333 HEAD\n\n\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0),
        Request(
          path: "/git/fetch",
          fields:
            "8300aa67726f75702f7265706fa4726566739183a3736861a6616161313131a3726566af726566732f68656164732f6d61696ea468617665a6646464343434a46861766591a6616161313131",
          timeout: 7200.0),
      ],
      ran: [
        ["cat-file", "-t", "aaa111"],
        ["cat-file", "-t", "bbb222"],
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [
        RNGitRemoteReference(name: "refs/heads/main", sha: "aaa111"),
        RNGitRemoteReference(name: "refs/heads/dev", sha: "bbb222"),
      ],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch empty bundle",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil)
      ],
      reports: [],
      bundle: nil,
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"]
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch refused",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "034e6f2073756368207265706f7369746f7279", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil)
      ],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"]
      ],
      aborted: "Fetch failed for batch: No such repository",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch no data",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil)
      ],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"]
      ],
      aborted: "No data in fetch response for batch",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch file without metadata",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil)
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"]
      ],
      aborted: "Invalid fetch response for batch",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch metadata without code",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "81a46e616d65a178")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil)
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"]
      ],
      aborted: "No result metadata on bundle response",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch metadata code set",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "8101ccff")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil)
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"]
      ],
      aborted: "Unknown remote state for batch ref fetch",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch verify fails",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
      ],
      aborted: "Bundle verification failed for batch",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch unbundle fails",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 2, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: "Bundle unbundle failed for batch: Non-zero return code",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch request failed",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: nil, metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil)
      ],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"]
      ],
      aborted: "Request failed or timed out",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch with progress",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress true\nfetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "--progress", "<bundle>"], status: 0,
          standardOutput: "", standardError: "Unbundling.\n", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c4542554e444c45",
      written: "ok\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\nTransferring: 100% (12 B).                       \nUnbundling.\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "--progress", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch cleared by push",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\npush refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "ok refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push one ref",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "ok refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push forced",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push +refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "ok refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c3a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push unresolvable",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/gone:refs/heads/gone\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/gone"], status: 128, standardOutput: "",
          standardError: "unknown revision\n", bundle: nil)
      ],
      reports: [],
      bundle: nil,
      written: "error refs/heads/gone \"Could not resolve local ref refs/heads/gone\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [
        ["rev-parse", "refs/heads/gone"]
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push empty bundle",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 128,
          standardOutput: "", standardError: "fatal: Refusing to create empty bundle.\n",
          bundle: nil),
      ],
      reports: [],
      bundle: nil,
      written: "ok refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8200aa67726f75702f7265706faa6f7065726174696f6e739184a6616374696f6eaa7570646174655f726566a3726566af726566732f68656164732f6d61696ea3736861a6616161313131a5666f726365c2",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push bundle failure",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 128,
          standardOutput: "", standardError: "fatal: bad object\n", bundle: nil),
      ],
      reports: [],
      bundle: nil,
      written: "error refs/heads/main \"Bundle creation failed\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push refused",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "014e6f7420616c6c6f7765643a20226d61696e222069732070726f7465637465640a09736565202f646f6373",
          metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written:
        "error refs/heads/main \"Not allowed: \\\"main\\\" is protected\\n\\tsee /docs\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push refused unicode",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "ff536572766572207361696420c3a9e298baf09f988001", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "error refs/heads/main \"Server said \\xe9\\x263a\\x1f600\\x01\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push no response",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "error refs/heads/main \"No response from server\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push after list",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n\npush refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "0061616131313120726566732f68656164732f6d61696e0a62626232323220726566732f68656164732f6465760a63636333333320484541440a",
          metadata: nil),
        Answer(body: "00", metadata: nil),
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["cat-file", "-t", "aaa111"], status: 0, standardOutput: "", standardError: "",
          bundle: nil),
        Command(
          arguments: ["cat-file", "-t", "bbb222"], status: 1, standardOutput: "", standardError: "",
          bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main", "^aaa111"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written:
        "aaa111 refs/heads/main\nbbb222 refs/heads/dev\nccc333 HEAD\n\n\nok refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0),
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0),
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["cat-file", "-t", "aaa111"],
        ["cat-file", "-t", "bbb222"],
        ["bundle", "create", "<push>", "refs/heads/main", "^aaa111"],
      ],
      aborted: nil,
      failed: nil,
      references: [
        RNGitRemoteReference(name: "refs/heads/main", sha: "aaa111"),
        RNGitRemoteReference(name: "refs/heads/dev", sha: "bbb222"),
      ],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push with progress",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress true\npush refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "--progress", "<push>", "refs/heads/main"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "ok\nok refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "--progress", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push bundle failure with progress",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress true\npush refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "--progress", "<push>", "refs/heads/main"], status: 128,
          standardOutput: "", standardError: "fatal: bad object\n", bundle: nil),
      ],
      reports: [],
      bundle: nil,
      written: "ok\nerror refs/heads/main \"Bundle creation failed\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\nfatal: bad object\n",
      requests: [],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "--progress", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push delete",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push :refs/heads/gone\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "ok refs/heads/gone\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/delete",
          fields: "8200aa67726f75702f7265706fa3726566af726566732f68656164732f676f6e65",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push delete refused",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push :refs/heads/gone\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "02496e76616c69642072657175657374", metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "error refs/heads/gone \"Invalid request\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/delete",
          fields: "8200aa67726f75702f7265706fa3726566af726566732f68656164732f676f6e65",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push delete no response",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push :refs/heads/gone\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "", metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "error refs/heads/gone \"No response from server\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/delete",
          fields: "8200aa67726f75702f7265706fa3726566af726566732f68656164732f676f6e65",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push two refs",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/a:refs/heads/a\npush :refs/heads/b\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil),
        Answer(body: "00", metadata: nil),
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/a"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/a"], status: 0, standardOutput: "",
          standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "ok refs/heads/a\nok refs/heads/b\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566ac726566732f68656164732f61aa72656d6f74655f726566ac726566732f68656164732f61a5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0),
        Request(
          path: "/git/delete",
          fields: "8200aa67726f75702f7265706fa3726566ac726566732f68656164732f62", timeout: 7200.0),
      ],
      ran: [
        ["rev-parse", "refs/heads/a"],
        ["bundle", "create", "<push>", "refs/heads/a"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push cleared by fetch",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\nfetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push empty bundle refused",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "014e6f7420616c6c6f776564", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 128,
          standardOutput: "", standardError: "EMPTY BUNDLE refused\n", bundle: nil),
      ],
      reports: [],
      bundle: nil,
      written: "error refs/heads/main \"Not allowed\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8200aa67726f75702f7265706faa6f7065726174696f6e739184a6616374696f6eaa7570646174655f726566a3726566af726566732f68656164732f6d61696ea3736861a6616161313131a5666f726365c2",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push empty bundle no response",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 128,
          standardOutput: "", standardError: "fatal: Refusing to create empty bundle.\n",
          bundle: nil),
      ],
      reports: [],
      bundle: nil,
      written: "error refs/heads/main \"No response from server\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8200aa67726f75702f7265706faa6f7065726174696f6e739184a6616374696f6eaa7570646174655f726566a3726566af726566732f68656164732f6d61696ea3736861a6616161313131a5666f726365c2",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push request failed",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: nil, metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: "Request failed or timed out",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "path fails",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "capabilities\n",
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported: "Requesting path...\n",
      requests: [],
      ran: [],
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: false),
    Run(
      name: "identity missing",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "capabilities\n",
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported: "Requesting path...\rPath resolved     ",
      requests: [],
      ran: [],
      aborted: "Could not recall remote identity. Is the server announcing?",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: false),
    Run(
      name: "link closed",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "capabilities\n",
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported: "Requesting path...\rPath resolved     \rEstablishing link...",
      requests: [],
      ran: [],
      aborted: "Failed to establish link",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "link silent",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "capabilities\n",
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported: "Requesting path...\rPath resolved     \rEstablishing link...",
      requests: [],
      ran: [],
      aborted: "Failed to establish link",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "bad hash",
      url: "rns://zzzz/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "capabilities\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported: "",
      requests: [],
      ran: [],
      aborted:
        "Invalid destination hash: non-hexadecimal number found in fromhex() arg at position 0",
      failed: nil,
      references: [],
      progress: false,
      awaited: nil,
      tornDown: false),
    Run(
      name: "empty hash",
      url: "rns:///group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "capabilities\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "list\nfetch\npush\noption\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "aliased destination",
      url: "rns://node/group/repo",
      aliases: ["node": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
      refBatchSize: 25,
      script: "capabilities\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "list\nfetch\npush\noption\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "nested repository name",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/sub/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [],
      reports: [],
      bundle: nil,
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200ae67726f75702f7375622f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch bare",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: "list index out of range",
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: false),
    Run(
      name: "fetch missing ref",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: "list index out of range",
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: false),
    Run(
      name: "push bare",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: "list index out of range",
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: false),
    Run(
      name: "push refspec without colon",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/main\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: "not enough values to unpack (expected 2, got 1)",
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: false),
    Run(
      name: "push refspec with two colons",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/a:refs/heads/b:refs/heads/c\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/a"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/a"], status: 0, standardOutput: "",
          standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "ok refs/heads/b:refs/heads/c\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566ac726566732f68656164732f61aa72656d6f74655f726566b9726566732f68656164732f623a726566732f68656164732f63a5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/a"],
        ["bundle", "create", "<push>", "refs/heads/a"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list repeated ref out of order",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "list\n\nfetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "0061616131313120726566732f68656164732f6d61696e0a62626232323220726566732f68656164732f6465760a63636333333320726566732f68656164732f6d61696e0a",
          metadata: nil),
        Answer(body: "<bundle>", metadata: "810100"),
      ],
      commands: [
        Command(
          arguments: ["cat-file", "-t", "ccc333"], status: 0, standardOutput: "", standardError: "",
          bundle: nil),
        Command(
          arguments: ["cat-file", "-t", "bbb222"], status: 0, standardOutput: "", standardError: "",
          bundle: nil),
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "ddd444\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "aaa111 refs/heads/main\nbbb222 refs/heads/dev\nccc333 refs/heads/main\n\n\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0),
        Request(
          path: "/git/fetch",
          fields:
            "8300aa67726f75702f7265706fa4726566739183a3736861a6616161313131a3726566af726566732f68656164732f6d61696ea468617665a6646464343434a46861766592a6636363333333a6626262323232",
          timeout: 7200.0),
      ],
      ran: [
        ["cat-file", "-t", "ccc333"],
        ["cat-file", "-t", "bbb222"],
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [
        RNGitRemoteReference(name: "refs/heads/main", sha: "ccc333"),
        RNGitRemoteReference(name: "refs/heads/dev", sha: "bbb222"),
      ],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "option progress prefix",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progressive true\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [],
      reports: [],
      bundle: nil,
      written: "unsupported\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch two batches one empty",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 1,
      script: "fetch a1 refs/heads/one\nfetch a2 refs/heads/two\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil),
        Answer(body: "<bundle>", metadata: "810100"),
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/one"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["rev-parse", "refs/heads/two"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a26131a3726566ae726566732f68656164732f6f6e65",
          timeout: 7200.0),
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a26132a3726566ae726566732f68656164732f74776f",
          timeout: 7200.0),
      ],
      ran: [
        ["rev-parse", "refs/heads/one"],
        ["rev-parse", "refs/heads/two"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch metadata empty map",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "0344656e696564", metadata: "80")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil)
      ],
      reports: [],
      bundle: nil,
      written: "",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"]
      ],
      aborted: "Fetch failed for batch: Denied",
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch unbundle noise",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "Unbundling objects.\n", bundle: nil),
      ],
      reports: [],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push forced unresolvable",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push +refs/heads/gone:refs/heads/gone\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/gone"], status: 128, standardOutput: "",
          standardError: "unknown revision\n", bundle: nil)
      ],
      reports: [],
      bundle: nil,
      written: "error refs/heads/gone \"Could not resolve local ref refs/heads/gone\"\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [],
      ran: [
        ["rev-parse", "refs/heads/gone"]
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push forced empty bundle",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push +refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/main"], status: 128,
          standardOutput: "", standardError: "fatal: Refusing to create empty bundle.\n",
          bundle: nil),
      ],
      reports: [],
      bundle: nil,
      written: "ok refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8200aa67726f75702f7265706faa6f7065726174696f6e739184a6616374696f6eaa7570646174655f726566a3726566af726566732f68656164732f6d61696ea3736861a6616161313131a5666f726365c3",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push renaming ref",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "push refs/heads/dev:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/dev"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "<push>", "refs/heads/dev"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [],
      bundle: nil,
      written: "ok refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566ae726566732f68656164732f646576aa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/dev"],
        ["bundle", "create", "<push>", "refs/heads/dev"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch reporting progress",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress true\nfetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "--progress", "<bundle>"], status: 0,
          standardOutput: "", standardError: "Unbundling.\n", bundle: nil),
      ],
      reports: [
        [
          Report(fraction: 0.0, size: 4096, transferSize: 4096, at: 0.0),
          Report(fraction: 0.25, size: 4096, transferSize: 4096, at: 0.7),
          Report(fraction: 0.5, size: 4096, transferSize: 4096, at: 2.0),
          Report(fraction: 1.0, size: 4096, transferSize: 4096, at: 3.5),
        ]
      ],
      bundle: "42554e444c4542554e444c45",
      written: "ok\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\nTransferring: 50.0% (2.05 KB/4.10 KB) 8.19 Kbps          \rTransferring: 100.0% (4.10 KB/4.10 KB) 10.92 Kbps          \rTransferring: 100% (12 B).                       \nUnbundling.\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "--progress", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "fetch reporting without progress",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "fetch aaa111 refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "<bundle>", metadata: "810100")
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 1, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "verify", "-q", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "unbundle", "<bundle>"], status: 0, standardOutput: "",
          standardError: "", bundle: nil),
      ],
      reports: [
        [
          Report(fraction: 0.0, size: 4096, transferSize: 4096, at: 0.0),
          Report(fraction: 0.25, size: 4096, transferSize: 4096, at: 0.7),
          Report(fraction: 0.5, size: 4096, transferSize: 4096, at: 2.0),
          Report(fraction: 1.0, size: 4096, transferSize: 4096, at: 3.5),
        ]
      ],
      bundle: "42554e444c45",
      written: "\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/fetch",
          fields:
            "8200aa67726f75702f7265706fa4726566739182a3736861a6616161313131a3726566af726566732f68656164732f6d61696e",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "verify", "-q", "<bundle>"],
        ["bundle", "unbundle", "<bundle>"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: false,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "push reporting progress",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress true\npush refs/heads/main:refs/heads/main\n\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(body: "00", metadata: nil)
      ],
      commands: [
        Command(
          arguments: ["rev-parse", "refs/heads/main"], status: 0, standardOutput: "aaa111\n",
          standardError: "", bundle: nil),
        Command(
          arguments: ["bundle", "create", "--progress", "<push>", "refs/heads/main"], status: 0,
          standardOutput: "", standardError: "", bundle: "50554b"),
      ],
      reports: [
        [
          Report(fraction: 0.0, size: 4096, transferSize: 4096, at: 0.0),
          Report(fraction: 0.25, size: 4096, transferSize: 4096, at: 0.7),
          Report(fraction: 0.5, size: 4096, transferSize: 4096, at: 2.0),
          Report(fraction: 1.0, size: 4096, transferSize: 4096, at: 3.5),
        ]
      ],
      bundle: nil,
      written: "ok\nok refs/heads/main\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\nTransferring: 50.0% (2.05 KB/4.10 KB) 8.19 Kbps          \rTransferring: 100.0% (4.10 KB/4.10 KB) 10.92 Kbps          \r",
      requests: [
        Request(
          path: "/git/push",
          fields:
            "8500aa67726f75702f7265706fa96c6f63616c5f726566af726566732f68656164732f6d61696eaa72656d6f74655f726566af726566732f68656164732f6d61696ea5666f726365c2a662756e646c65c40350554b",
          timeout: 7200.0)
      ],
      ran: [
        ["rev-parse", "refs/heads/main"],
        ["bundle", "create", "--progress", "<push>", "refs/heads/main"],
      ],
      aborted: nil,
      failed: nil,
      references: [],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list reporting without size",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress true\nlist\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "0061616131313120726566732f68656164732f6d61696e0a62626232323220726566732f68656164732f6465760a63636333333320484541440a",
          metadata: nil)
      ],
      commands: [],
      reports: [
        [
          Report(fraction: 0.0, size: nil, transferSize: nil, at: 0.0),
          Report(fraction: 0.5, size: nil, transferSize: nil, at: 2.0),
        ]
      ],
      bundle: nil,
      written: "ok\naaa111 refs/heads/main\nbbb222 refs/heads/dev\nccc333 HEAD\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [
        RNGitRemoteReference(name: "refs/heads/main", sha: "aaa111"),
        RNGitRemoteReference(name: "refs/heads/dev", sha: "bbb222"),
      ],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
    Run(
      name: "list reporting once",
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      aliases: [:],
      refBatchSize: 25,
      script: "option progress true\nlist\n",
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        Answer(
          body:
            "0061616131313120726566732f68656164732f6d61696e0a62626232323220726566732f68656164732f6465760a63636333333320484541440a",
          metadata: nil)
      ],
      commands: [],
      reports: [
        [Report(fraction: 0.4, size: 2048, transferSize: 2048, at: 0.0)]
      ],
      bundle: nil,
      written: "ok\naaa111 refs/heads/main\nbbb222 refs/heads/dev\nccc333 HEAD\n\n",
      reported:
        "Requesting path...\rPath resolved     \rEstablishing link...\rLink established with remote\n",
      requests: [
        Request(
          path: "/git/list", fields: "8200aa67726f75702f7265706fa8666f725f70757368c2",
          timeout: 7200.0)
      ],
      ran: [],
      aborted: nil,
      failed: nil,
      references: [
        RNGitRemoteReference(name: "refs/heads/main", sha: "aaa111"),
        RNGitRemoteReference(name: "refs/heads/dev", sha: "bbb222"),
      ],
      progress: true,
      awaited: Awaited(hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", timeout: 1606.0),
      tornDown: true),
  ]

  private static let readings: [Reading] = [
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", error: nil,
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: "group", repository: "repo"),
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/sub/repo", error: nil,
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: "group", repository: "sub/repo"),
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/sub/deeper/repo", error: nil,
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: "group", repository: "sub/deeper/repo"
    ),
    Reading(
      url: "rns:///group/repo", error: nil, destination: "", group: "group", repository: "repo"),
    Reading(
      url: "rns://node/group/repo", error: nil, destination: "node", group: "group",
      repository: "repo"),
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa//repo", error: nil,
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: "", repository: "repo"),
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/", error: nil,
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: "group", repository: ""),
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group",
      error: "Invalid URL format. Use rns://<hash>/<group>/<repo>",
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: "group", repository: nil),
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/",
      error: "Invalid URL format. Use rns://<hash>/<group>/<repo>",
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: "", repository: nil),
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      error: "Invalid URL format. Use rns://<hash>/<group>/<repo>",
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: nil, repository: nil),
    Reading(
      url: "rns://", error: "Invalid URL format. Use rns://<hash>/<group>/<repo>", destination: "",
      group: nil, repository: nil),
    Reading(url: "rns://a/b/c", error: nil, destination: "a", group: "b", repository: "c"),
    Reading(
      url: "RNS://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      error: "Invalid URL scheme. Must be rns://", destination: nil, group: nil, repository: nil),
    Reading(
      url: "Rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      error: "Invalid URL scheme. Must be rns://", destination: nil, group: nil, repository: nil),
    Reading(
      url: "https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo",
      error: "Invalid URL scheme. Must be rns://", destination: nil, group: nil, repository: nil),
    Reading(
      url: "", error: "Invalid URL scheme. Must be rns://", destination: nil, group: nil,
      repository: nil),
    Reading(
      url: "rns:/", error: "Invalid URL scheme. Must be rns://", destination: nil, group: nil,
      repository: nil),
    Reading(
      url: " rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/g/r",
      error: "Invalid URL scheme. Must be rns://", destination: nil, group: nil, repository: nil),
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo/", error: nil,
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: "group", repository: "repo/"),
    Reading(
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/re:po", error: nil,
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", group: "group", repository: "re:po"),
  ]

  private static let settings: [Setting] = [
    Setting(
      name: "nothing configured", configuration: "", logLevel: nil, refBatchSize: 25, aliases: [:]),
    Setting(
      name: "log level taken", configuration: "[logging]\nloglevel = 4\n", logLevel: 4,
      refBatchSize: 25, aliases: [:]),
    Setting(
      name: "log level clamped low", configuration: "[logging]\nloglevel = -5\n", logLevel: -1,
      refBatchSize: 25, aliases: [:]),
    Setting(
      name: "log level clamped high", configuration: "[logging]\nloglevel = 99\n", logLevel: 8,
      refBatchSize: 25, aliases: [:]),
    Setting(
      name: "batch size taken", configuration: "[client]\nref_batch_size = 100\n", logLevel: nil,
      refBatchSize: 100, aliases: [:]),
    Setting(
      name: "batch size clamped low", configuration: "[client]\nref_batch_size = -1\n",
      logLevel: nil, refBatchSize: 0, aliases: [:]),
    Setting(
      name: "batch size clamped high", configuration: "[client]\nref_batch_size = 4096\n",
      logLevel: nil, refBatchSize: 1024, aliases: [:]),
    Setting(
      name: "batch size of zero", configuration: "[client]\nref_batch_size = 0\n", logLevel: nil,
      refBatchSize: 0, aliases: [:]),
    Setting(
      name: "batch size left out", configuration: "[client]\n", logLevel: nil, refBatchSize: 25,
      aliases: [:]),
    Setting(
      name: "batch size at the ceiling", configuration: "[client]\nref_batch_size = 1024\n",
      logLevel: nil, refBatchSize: 1024, aliases: [:]),
    Setting(
      name: "alias taken", configuration: "[aliases]\nbob = cccccccccccccccccccccccccccccccc\n",
      logLevel: nil, refBatchSize: 25, aliases: ["bob": "cccccccccccccccccccccccccccccccc"]),
    Setting(
      name: "alias too short", configuration: "[aliases]\nbob = aabb\n", logLevel: nil,
      refBatchSize: 25, aliases: [:]),
    Setting(
      name: "everything configured",
      configuration:
        "[logging]\nloglevel = 2\n[client]\nref_batch_size = 7\n[aliases]\nbob = cccccccccccccccccccccccccccccccc\n",
      logLevel: 2, refBatchSize: 7, aliases: ["bob": "cccccccccccccccccccccccccccccccc"]),
  ]

  private static let escapes: [Escape] = [
    Escape(value: "", escaped: "\"\""),
    Escape(value: "plain", escaped: "\"plain\""),
    Escape(value: "with \"quotes\"", escaped: "\"with \\\"quotes\\\"\""),
    Escape(value: "back\\slash", escaped: "\"back\\\\slash\""),
    Escape(value: "line\nbreak", escaped: "\"line\\nbreak\""),
    Escape(value: "tab\there", escaped: "\"tab\\there\""),
    Escape(value: "carriage\rreturn", escaped: "\"carriage\\rreturn\""),
    Escape(value: "bell\u{07}", escaped: "\"bell\\x07\""),
    Escape(value: "null\u{00}byte", escaped: "\"null\\x00byte\""),
    Escape(value: "del\u{7f}", escaped: "\"del\\x7f\""),
    Escape(value: "highé", escaped: "\"high\\xe9\""),
    Escape(value: "snowman☃", escaped: "\"snowman\\x2603\""),
    Escape(value: "emoji😀", escaped: "\"emoji\\x1f600\""),
    Escape(value: "flag🇩🇪", escaped: "\"flag\\x1f1e9\\x1f1ea\""),
    Escape(value: "\u{1b}[31mred\u{1b}[0m", escaped: "\"\\x1b[31mred\\x1b[0m\""),
    Escape(value: " leading and trailing ", escaped: "\" leading and trailing \""),
    Escape(value: "~}|{", escaped: "\"~}|{\""),
  ]

  /// Holds what the helper wrote.
  private final class Recorder: RNGitClientOutput {
    var written = ""
    func write(_ text: String) { written += text }
  }

  /// Hands the helper the lines git sent it.
  private final class Script: RNGitClientInput {
    private var lines: [String]

    init(_ script: String) {
      lines = script.components(separatedBy: "\n")
      if lines.last == "" { lines.removeLast() }
    }

    func readLine() -> String? { lines.isEmpty ? nil : lines.removeFirst() }
  }

  /// What a run reads the time as while it runs.
  private final class Clock {

    /// Where the reference stood when it recorded every report.
    static let base: TimeInterval = 1_750_000_000

    var instant = Clock.base
  }

  /// Answers the helper the way one run says to, holding what it was asked.
  private final class Stub: RNGitClientTransport {
    private let vector: Run
    private let bundle: String?
    private let clock: Clock
    private var answers: [Answer]
    private var reports: [[Report]]
    var requests: [Request] = []
    var awaited: Awaited?
    var tornDown = false

    init(_ vector: Run, bundle: String?, clock: Clock) {
      self.vector = vector
      self.bundle = bundle
      self.clock = clock
      self.answers = vector.answers
      self.reports = vector.reports
    }

    func mediumPathTimeout() -> TimeInterval { 1606 }

    func awaitPath(to destinationHash: Data, timeout: TimeInterval) -> Bool {
      awaited = Awaited(hash: destinationHash.hexString, timeout: timeout)
      return vector.hasPath
    }

    func recallIdentity(for destinationHash: Data) -> Identity? {
      vector.recalls ? Identity() : nil
    }

    func establishLink(to identity: Identity) -> Bool { vector.linkComesUp }

    func request(
      _ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval,
      progress: ((RNGitTransferProgress) -> Void)?
    ) -> RNGitClientResponse {
      requests.append(
        Request(path: path.rawValue, fields: MsgPack.encode(fields).hexString, timeout: timeout))
      let reported = reports.isEmpty ? [] : reports.removeFirst()
      if let progress {
        for report in reported {
          clock.instant = Clock.base + report.at
          progress(
            RNGitTransferProgress(
              fraction: report.fraction, size: report.size, transferSize: report.transferSize))
        }
      }
      guard !answers.isEmpty else { return RNGitClientResponse(result: .none) }
      let answer = answers.removeFirst()
      guard let body = answer.body else { return RNGitClientResponse(result: .none) }
      let named = answer.metadata.flatMap { try? MsgPack.decode(Data(pythonHex: $0) ?? Data()) }
      guard body != "<bundle>" else {
        return RNGitClientResponse(result: .file(bundle ?? ""), metadata: named)
      }
      return RNGitClientResponse(
        result: .bytes(Data(pythonHex: body) ?? Data()), metadata: named)
    }

    func teardown() { tornDown = true }
  }

  /// Answers `git` the way one run says to, holding what it was asked.
  private final class Ledger: RNGitCommandRunner, @unchecked Sendable {
    private var commands: [Command]
    var ran: [[String]] = []
    var executables: Set<String> = []

    init(_ vector: Run) { commands = vector.commands }

    func run(_ executable: String, arguments: [String], in directory: String?)
      -> RNGitCommandOutput?
    {
      executables.insert(executable)
      ran.append(arguments.map(Self.named))
      guard !commands.isEmpty else {
        return RNGitCommandOutput(status: 0, standardOutput: "", standardError: "")
      }
      let command = commands.removeFirst()
      if let bundle = command.bundle, let written = Data(pythonHex: bundle) {
        for argument in arguments where argument.hasSuffix("/push.bundle") {
          try? written.write(to: URL(fileURLWithPath: argument))
        }
      }
      return RNGitCommandOutput(
        status: command.status, standardOutput: command.standardOutput,
        standardError: command.standardError)
    }

    /// `argument` with the paths a run cannot know standing under the names it recorded.
    private static func named(_ argument: String) -> String {
      if argument.hasSuffix("/fetched.bundle") { return "<bundle>" }
      if argument.hasSuffix("/push.bundle") { return "<push>" }
      return argument
    }
  }

  /// Every run does what the reference did, down to what it asked of the node and of `git`.
  func testEveryRunMatchesTheReference() throws {
    for run in Self.runs { try measure(run) }
  }

  /// Every URL is read the way the reference reads it.
  func testEveryURLMatchesTheReference() {
    for reading in Self.readings {
      guard let error = reading.error else {
        let read = try? RNGitHelperURL.reading(reading.url)
        XCTAssertEqual(read?.destination, reading.destination, reading.url)
        XCTAssertEqual(read?.group, reading.group, reading.url)
        XCTAssertEqual(read?.repository, reading.repository, reading.url)
        continue
      }
      XCTAssertThrowsError(try RNGitHelperURL.reading(reading.url), reading.url) { thrown in
        XCTAssertEqual((thrown as? RNGitHelperURLError)?.message, error, reading.url)
      }
    }
  }

  /// Every configuration is read the way the reference reads it.
  func testEverySettingMatchesTheReference() throws {
    for setting in Self.settings {
      let read = try RNGitHelperSettings(
        configuration: RNGitConfigFile.parse(setting.configuration))
      XCTAssertEqual(read.client.logLevel, setting.logLevel, setting.name)
      XCTAssertEqual(read.refBatchSize, setting.refBatchSize, setting.name)
      XCTAssertEqual(read.client.destinationAliases, setting.aliases, setting.name)
    }
  }

  /// Every value is written back the way the reference writes it.
  func testEveryEscapeMatchesTheReference() {
    for escape in Self.escapes {
      XCTAssertEqual(
        RNGitRemoteHelper.escapeForStdout(escape.value), escape.escaped,
        escape.value.debugDescription)
    }
  }

  /// Every canned `git` answer a run holds stands for one the reference ran.
  func testEveryRunNamesTheCommandsItAnswers() {
    for run in Self.runs {
      XCTAssertEqual(
        run.commands.map { $0.arguments }, Array(run.ran.prefix(run.commands.count)), run.name)
    }
  }

  /// Runs `run`, and measures everything it did against what the reference did.
  private func measure(_ run: Run) throws {
    let directory = NSTemporaryDirectory() + "/rngit-helper-" + UUID().uuidString
    try FileManager.default.createDirectory(
      atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }

    var bundle: String?
    if let carried = run.bundle {
      bundle = directory + "/fetched.bundle"
      try XCTUnwrap(Data(pythonHex: carried)).write(to: URL(fileURLWithPath: bundle ?? ""))
    }

    let stdout = Recorder()
    let stderr = Recorder()
    let clock = Clock()
    let transport = Stub(run, bundle: bundle, clock: clock)
    let ledger = Ledger(run)
    var helper = RNGitRemoteHelper(
      url: try RNGitHelperURL.reading(run.url), aliases: run.aliases,
      refBatchSize: run.refBatchSize, workingDirectory: directory,
      now: { Date(timeIntervalSince1970: clock.instant) }, transport: transport,
      stdout: stdout, stderr: stderr, input: Script(run.script), runner: ledger)

    var aborted: String?
    var failed: String?
    do {
      try helper.run()
    } catch let error as RNGitClientAbort {
      aborted = error.message
    } catch {
      failed = String(describing: error)
    }

    XCTAssertEqual(stdout.written, run.written, run.name)
    XCTAssertEqual(stderr.written, run.reported, run.name)
    XCTAssertEqual(aborted, run.aborted, run.name)
    XCTAssertEqual(failed, run.failed, run.name)
    XCTAssertEqual(transport.requests, run.requests, run.name)
    XCTAssertEqual(transport.awaited, run.awaited, run.name)
    XCTAssertEqual(transport.tornDown, run.tornDown, run.name)
    XCTAssertEqual(ledger.ran, run.ran, run.name)
    XCTAssertEqual(ledger.executables, run.ran.isEmpty ? [] : ["git"], run.name)
    XCTAssertEqual(helper.remoteReferences, run.references, run.name)
    XCTAssertEqual(helper.progressEnabled, run.progress, run.name)
  }
}
