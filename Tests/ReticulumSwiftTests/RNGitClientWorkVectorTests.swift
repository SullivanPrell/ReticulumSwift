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

/// The work commands an `rngit` client runs, measured against Python RNS 1.5.4.
final class RNGitClientWorkVectorTests: XCTestCase {

  private enum Command {
    case list(remote: String?, scope: String)
    case view(remote: String?, document: Int?, scope: String)
    case create(remote: String?, title: String?)
    case propose(remote: String?, title: String?)
    case edit(remote: String?, document: Int?, title: String?, scope: String)
    case delete(remote: String?, document: Int?, scope: String)
    case comment(remote: String?, document: Int?, scope: String)
    case complete(remote: String?, document: Int?)
    case activate(remote: String?, document: Int?)
    case permissions(remote: String?, document: Int?)
  }

  private enum Edits {
    case writes(String)
    case code(Int32)
    case none
  }

  private struct Request: Equatable {
    let path: String
    let fields: String
    let timeout: Double
  }

  private struct Sent {
    var awaitHash: String?
    var awaitTimeout: Double?
    var requests: [Request] = []
  }

  private struct Run {
    let name: String
    let command: Command
    let edits: Edits
    let typed: [String]
    let signs: Bool
    let hasPath: Bool
    let recalls: Bool
    let linkComesUp: Bool
    let answers: [RNGitRequestResult]
    let written: String
    let aborted: String?
    let sent: Sent?
    let tornDown: Bool
    let handed: [String]
    let suffixes: [String]
  }

  private static let privateKey =
    "3b1f5c9a7d2e4086b5c3a19f7e6d4c2b8a09f1e3d5c7b9a1f3e5d7c9b1a3f5e79c8b7a6f5e4d3c2b1a0f9e8d7c6b5a4938271605f4e3d2c1b0a9f8e7d6c5b4a3"

  private static let runs: [Run] = [
    Run(
      name: "list, one active document",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    A title                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, documents in every scope",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "all"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c657465649185a2696402a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a870726f706f7365649185a2696403a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    A title                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n\nCompleted documents\n====================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n2    A title                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n\nProposed documents\n===================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n3    A title                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a3616c6c",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, nothing at all",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo active work documents found.\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, nothing at all in every scope",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "all"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo work documents found.\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a3616c6c",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, an empty listing",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "0083a661637469766590a9636f6d706c6574656490a870726f706f73656490")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo active work documents found.\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, an empty listing in every scope",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "all"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "0083a661637469766590a9636f6d706c6574656490a870726f706f73656490")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo work documents found.\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a3616c6c",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a scope the node names nothing under",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "stalled"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo stalled work documents found.\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a77374616c6c6564",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a scope written in two code points that print as one",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "🇦🇹"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a661637469766590a9636f6d706c6574656490a870726f706f73656490a8f09f87a6f09f87b99185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\n🇦🇹 documents\n=============\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    A title                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a8f09f87a6f09f87b9",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, completed documents",
      command: .list(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "completed"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a661637469766590a9636f6d706c657465649185a2696409a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nCompleted documents\n====================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n9    A title                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a9636f6d706c65746564",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, proposed documents",
      command: .list(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "proposed"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a661637469766590a9636f6d706c6574656490a870726f706f7365649185a2696404a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nProposed documents\n===================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n4    A title                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a870726f706f736564",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a document naming nothing",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "0083a66163746976659180a9636f6d706c6574656490a870726f706f73656490")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n?    Untitled                       …                 unknown            0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a title of twenty-nine characters",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65bd7474747474747474747474747474747474747474747474747474747474a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    ttttttttttttttttttttttttttttt  bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a title of thirty characters",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65be747474747474747474747474747474747474747474747474747474747474a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    ttttttttttttttttttttttttttttt… bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a title of forty characters",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65d92874747474747474747474747474747474747474747474747474747474747474747474747474747474a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    ttttttttttttttttttttttttttttt… bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, an author of no length",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72a0a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    A title                        …                 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, an author of ten characters",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72aa63636363636363636363a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    A title                        cccccccccc…       2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a document created at no time",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a76372656174656400a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    A title                        bbbbbbbbbbbbbbbb… unknown            0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a document carrying comments",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e74730ca9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    A title                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   12\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, several documents",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659385a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e74730085a2696402a57469746c65a7416e6f74686572a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e74730085a269641ea57469746c65a741207468697264a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r\nActive documents\n=================\n\nID   Title                          Author            Created            Comments\n--------------------------------------------------------------------------------\n1    A title                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n2    Another                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n30   A third                        bbbbbbbbbbbbbbbb… 2025-09-04 15:33   0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node refused",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node refused, saying why",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node read nothing",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node read nothing, saying why",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node found nothing",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node found nothing, saying what",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node failed",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node failed, saying why",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node a code of its own, saying why",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node nothing at all",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, the node no answer",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     ",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea46c697374a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document signed by its author",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : <039da95c7a04620318d94346e34924c9>\nSignature : Valid\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document whose signature does not hold",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c44000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Not valid\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document signed over other content",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c440528bb79baa1081a9f74abb090755f504eed68ab5304a6da1db81819633e0ba6f5e5668ebf51e47487b2d437d7b92ea66fd4a05cf7f0e6dea45bc449516369003a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Not valid\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a signature of the wrong length",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c43f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a signature one byte too long",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a signature that is no bytes",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265a96e6f74206279746573a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, no signature at all",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746186a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a key of the wrong length",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c4200000000000000000000000000000000000000000000000000000000000000000a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a key one byte too long",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c4410000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a key that is no bytes",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479a96e6f74206279746573a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, no key at all",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746186a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document carrying updates",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e74739284a2696401a6617574686f72d9206363636363636363636363636363636363636363636363636363636363636363a763726561746564ce68b9b4c4a7636f6e74656e74aa416e207570646174652e84a2696402a6617574686f72d9206363636363636363636363636363636363636363636363636363636363636363a763726561746564ce68b9b4c4a7636f6e74656e74a941207365636f6e642e"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : <039da95c7a04620318d94346e34924c9>\nSignature : Valid\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 2\n\n# Heading\n\nBody of the document.\n\nUpdates\n=======\n\n#1 by cccccccccccccccccccccccccccccccc at 2025-09-04 15:48:20\n-------------------------------------------------------------\nAn update.\n\n#2 by cccccccccccccccccccccccccccccccc at 2025-09-04 15:48:20\n-------------------------------------------------------------\nA second.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document of no content",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c440754bc890ad0c4da1a7e318b8b57bdfe71f7da2cc3c1272f6c0df0a4e0eca7729493ea4c63ce29e16e48394a868cd5a7f33901b89b507c3fedcd4d2d042b4f708a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74a0a8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : <039da95c7a04620318d94346e34924c9>\nSignature : Valid\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document naming no scope of its own",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "completed"
      ),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : <039da95c7a04620318d94346e34924c9>\nSignature : Valid\nStatus    : Completed\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a9636f6d706c65746564",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, nothing after the code",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Empty response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node refused",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node refused, saying why",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node read nothing",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node read nothing, saying why",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node found nothing",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node found nothing, saying what",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node failed",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node failed, saying why",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node a code of its own, saying why",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node nothing at all",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the node no answer",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     ",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "create, the node named what it made",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0082a573636f7065a6616374697665a2696405")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document created as active #5\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node named nothing",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document created\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node named no scope",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0081a2696405")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error creating work document: 'scope'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node named no identifier",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0081a573636f7065a6616374697665")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error creating work document: 'id'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the user wrote nothing",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes(""),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rCreation cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the user wrote only space",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("  \n \n"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rCreation cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the editor came back with code 1",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .code(1),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEditor exited with error code 1\nCreation cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, there was no editor to run",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .none,
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo editor found. Please set $EDITOR environment variable.\nCreation cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "create, no title named",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: nil),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written: "",
      aborted: "No title specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "create, a title of no length",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: ""),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written: "",
      aborted: "No title specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "create, the node refused",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node refused, saying why",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node read nothing",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node read nothing, saying why",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node found nothing",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node found nothing, saying what",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node failed",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node failed, saying why",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node a code of its own, saying why",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node nothing at all",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, the node no answer",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea6637265617465a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node named what it made",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0082a573636f7065a6616374697665a2696405")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document created as active #5\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node named nothing",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document proposed\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node named no scope",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0081a2696405")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error creating work document: 'scope'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node named no identifier",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0081a573636f7065a6616374697665")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error creating work document: 'id'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the user wrote nothing",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes(""),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rProposal cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the user wrote only space",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("  \n \n"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rProposal cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the editor came back with code 1",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .code(1),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEditor exited with error code 1\nProposal cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, there was no editor to run",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .none,
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo editor found. Please set $EDITOR environment variable.\nProposal cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, no title named",
      command: .propose(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: nil),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written: "",
      aborted: "No title specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, a title of no length",
      command: .propose(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: ""),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written: "",
      aborted: "No title specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, the node refused",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node refused, saying why",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node read nothing",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node read nothing, saying why",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node found nothing",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node found nothing, saying what",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node failed",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node failed, saying why",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node a code of its own, saying why",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node nothing at all",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, the node no answer",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea770726f706f7365a57469746c65a741207469746c65a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776ea97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "create, nothing to sign with",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: false,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error creating work document: 'NoneType' object has no attribute 'sign'",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "propose, nothing to sign with",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: false,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error creating work document: 'NoneType' object has no attribute 'sign'",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [
        "# Remove this line and enter your document content. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "edit, the user rewrote the document",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document active #3 updated\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, a title of its own",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3,
        title: "A new title", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document active #3 updated\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65ab41206e6577207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the user wrote nothing",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes(""),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, there was no editor to run",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .none,
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo editor found. Please set $EDITOR environment variable.\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, nothing after the code",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error editing work document: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, a document naming no content",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "0081a46d65746181a57469746c65a741207469746c65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error editing work document: 'content'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node refused when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node refused when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "01")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node refused, saying why when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node refused, saying why when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node read nothing when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node read nothing when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "02")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node read nothing, saying why when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node read nothing, saying why when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node found nothing when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node found nothing when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "03")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node found nothing, saying what when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node found nothing, saying what when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node failed when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node failed when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "ff")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node failed, saying why when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node failed, saying why when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node a code of its own, saying why when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node a code of its own, saying why when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node nothing at all when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node nothing at all when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, the node no answer when asked",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none, .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the node no answer when sent",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .none,
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "edit, nothing to sign with",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: false,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error editing work document: 'NoneType' object has no attribute 'sign'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "delete, the user agreed",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: Work document active #3 deleted\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the user agreed in capitals",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["Y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: Work document active #3 deleted\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the user agreed with space around it",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [" y \n"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: Work document active #3 deleted\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the user refused",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["n"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: Deletion cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the user typed nothing",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [""],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: Deletion cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the user typed something else",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["yes"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: Deletion cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, there was nothing to read",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: Deletion cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, a document in another scope",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "proposed"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete proposed work document #3? [y/N]: Work document proposed #3 deleted\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a870726f706f736564",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node refused",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node refused, saying why",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node read nothing",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node read nothing, saying why",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node found nothing",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node found nothing, saying what",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node failed",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node failed, saying why",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node a code of its own, saying why",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node nothing at all",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the node no answer",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #3? [y/N]: ",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, the node named the update",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0081a2696407")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rUpdate #7 added to active document #3\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node named nothing",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rUpdate added\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node named no identifier",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0080")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error adding comment: 'id'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the user wrote nothing",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes(""),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rUpdate cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, there was no editor to run",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .none,
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo editor found. Please set $EDITOR environment variable.\nUpdate cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, a document in another scope",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "completed"
      ),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0081a2696407")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rUpdate #7 added to completed document #3\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a9636f6d706c65746564a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node refused",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node refused, saying why",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node read nothing",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node read nothing, saying why",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node found nothing",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node found nothing, saying what",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node failed",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node failed, saying why",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node a code of its own, saying why",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node nothing at all",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "comment, the node no answer",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696403a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "complete, the node named the document",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0081a2696403")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document #3 completed\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node named nothing",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document completed\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node named no identifier",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0080")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error completing work document: 'id'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node refused",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node refused, saying why",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node read nothing",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node read nothing, saying why",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node found nothing",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node found nothing, saying what",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node failed",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node failed, saying why",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node a code of its own, saying why",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node nothing at all",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the node no answer",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node named the document",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0081a2696403")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document #3 activated\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node named nothing",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document activated\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node named no identifier",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0080")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error activating work document: 'id'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node refused",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node refused, saying why",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node read nothing",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node read nothing, saying why",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node found nothing",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node found nothing, saying what",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node failed",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node failed, saying why",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node a code of its own, saying why",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node nothing at all",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the node no answer",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696403",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the user rewrote what stands",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for work document #3\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, nothing stands yet",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for work document #3\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ],
      suffixes: [".txt"]),
    Run(
      name: "permissions, a map naming no content",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0080")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for work document #3\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ],
      suffixes: [".txt"]),
    Run(
      name: "permissions, there was no editor to run",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .none,
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo editor found. Please set $EDITOR environment variable.\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the editor came back with code 1",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .code(1),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEditor exited with error code 1\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node refused when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "01")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node refused when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "01")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node refused, saying why when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node refused, saying why when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node read nothing when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "02")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node read nothing when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "02")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node read nothing, saying why when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node read nothing, saying why when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node found nothing when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "03")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node found nothing when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "03")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node found nothing, saying what when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node found nothing, saying what when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "034e6f207375636820646f63756d656e74")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node failed when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "ff")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node failed when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "ff")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node failed, saying why when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node failed, saying why when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "ff636f756c64206e6f7420726561642074686520646f63756d656e74")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read the document",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node a code of its own, saying why when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node a code of its own, saying why when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node nothing at all when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node nothing at all when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "permissions, the node no answer when asked",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.none, .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the node no answer when sent",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("adm:cccc"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .none,
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696403a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "list, no path to the remote",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "list, no identity recalled",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a link that closed before it came up",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Link establishment failed",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "list, no remote named",
      command: .list(remote: nil, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a remote of no length",
      command: .list(remote: "", scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a remote of another protocol",
      command: .list(remote: "http://host/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a remote naming no hash",
      command: .list(remote: "rns://elsewhere/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a remote naming no repository",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c65a741207469746c65a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     ",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, no path to the remote",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "view, no identity recalled",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a link that closed before it came up",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Link establishment failed",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "view, no remote named",
      command: .view(remote: nil, document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a remote of no length",
      command: .view(remote: "", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a remote of another protocol",
      command: .view(remote: "http://host/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a remote naming no hash",
      command: .view(remote: "rns://elsewhere/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a remote naming no repository",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     ",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, no document named",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: nil, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written: "",
      aborted: "No document ID specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "view, the document named zero",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 0, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : <039da95c7a04620318d94346e34924c9>\nSignature : Valid\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n# Heading\n\nBody of the document.\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696400a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "create, no path to the remote",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "create, no identity recalled",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "create, a link that closed before it came up",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "create, no remote named",
      command: .create(remote: nil, title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "create, a remote of no length",
      command: .create(remote: "", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "create, a remote of another protocol",
      command: .create(remote: "http://host/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "create, a remote naming no hash",
      command: .create(remote: "rns://elsewhere/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "create, a remote naming no repository",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, no path to the remote",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, no identity recalled",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, a link that closed before it came up",
      command: .propose(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, no remote named",
      command: .propose(remote: nil, title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, a remote of no length",
      command: .propose(remote: "", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, a remote of another protocol",
      command: .propose(remote: "http://host/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, a remote naming no hash",
      command: .propose(remote: "rns://elsewhere/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "propose, a remote naming no repository",
      command: .propose(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", title: "A title"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, no path to the remote",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, no identity recalled",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, a link that closed before it came up",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, no remote named",
      command: .edit(remote: nil, document: 3, title: nil, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, a remote of no length",
      command: .edit(remote: "", document: 3, title: nil, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, a remote of another protocol",
      command: .edit(remote: "http://host/group/repo", document: 3, title: nil, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, a remote naming no hash",
      command: .edit(
        remote: "rns://elsewhere/group/repo", document: 3, title: nil, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, a remote naming no repository",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, no document named",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: nil, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "No document ID specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, the document named zero",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 0, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c4409d823900bcdf2aae5c986bbf02d38a41152f297b1fcc9e3a2feb6829fffbca19f9eeec25f4023a4d7061c987fb3901df231b5904359061fd3c78cf3d12a76d05a86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7a7636f6e74656e74d920232048656164696e670a0a426f6479206f662074686520646f63756d656e742ea8636f6d6d656e747390"
          )!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document active #0 updated\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696400a573636f7065a6616374697665",
            timeout: 600.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8700aa67726f75702f7265706fa96f7065726174696f6ea465646974a6646f635f696400a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a57469746c65a741207469746c65a97369676e6174757265c440b36b9a488c6eb29bc1746674cb55bd0961577b627eefede75d3ee036b0d67ae30502f0ad02ed76069c4ac19389eb0fa272a826f417eb56ffa454a07cc8460002",
            timeout: 600.0),
        ]),
      tornDown: true,
      handed: ["# Heading\n\nBody of the document."],
      suffixes: [".md"]),
    Run(
      name: "delete, no path to the remote",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, no identity recalled",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, a link that closed before it came up",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, no remote named",
      command: .delete(remote: nil, document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, a remote of no length",
      command: .delete(remote: "", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, a remote of another protocol",
      command: .delete(remote: "http://host/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, a remote naming no hash",
      command: .delete(remote: "rns://elsewhere/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, a remote naming no repository",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, no document named",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: nil, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No document ID specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "delete, the document named zero",
      command: .delete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 0, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete active work document #0? [y/N]: Work document active #0 deleted\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a6646f635f696400a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, no path to the remote",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, no identity recalled",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, a link that closed before it came up",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, no remote named",
      command: .comment(remote: nil, document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, a remote of no length",
      command: .comment(remote: "", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, a remote of another protocol",
      command: .comment(remote: "http://host/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, a remote naming no hash",
      command: .comment(remote: "rns://elsewhere/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, a remote naming no repository",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, no document named",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: nil, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No document ID specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "comment, the document named zero",
      command: .comment(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 0, scope: "active"),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rUpdate added\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8600aa67726f75702f7265706fa96f7065726174696f6ea7636f6d6d656e74a6646f635f696400a573636f7065a6616374697665a7636f6e74656e74af5772697474656e20636f6e74656e74a6666f726d6174a86d61726b646f776e",
            timeout: 600.0)
        ]),
      tornDown: true,
      handed: [
        "# Remove this line and enter your update. Save and exit when done, or save an empty document to abort abort."
      ],
      suffixes: [".md"]),
    Run(
      name: "complete, no path to the remote",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, no identity recalled",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, a link that closed before it came up",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, no remote named",
      command: .complete(remote: nil, document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, a remote of no length",
      command: .complete(remote: "", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, a remote of another protocol",
      command: .complete(remote: "http://host/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, a remote naming no hash",
      command: .complete(remote: "rns://elsewhere/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, a remote naming no repository",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, no document named",
      command: .complete(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: nil),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No document ID specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "complete, the document named zero",
      command: .complete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 0),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document completed\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea8636f6d706c657465a6646f635f696400",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, no path to the remote",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, no identity recalled",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, a link that closed before it came up",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, no remote named",
      command: .activate(remote: nil, document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, a remote of no length",
      command: .activate(remote: "", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, a remote of another protocol",
      command: .activate(remote: "http://host/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, a remote naming no hash",
      command: .activate(remote: "rns://elsewhere/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, a remote naming no repository",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, no document named",
      command: .activate(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: nil),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No document ID specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "activate, the document named zero",
      command: .activate(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 0),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rWork document activated\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea86163746976617465a6646f635f696400",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, no path to the remote",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, no identity recalled",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, a link that closed before it came up",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, no remote named",
      command: .permissions(remote: nil, document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, a remote of no length",
      command: .permissions(remote: "", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, a remote of another protocol",
      command: .permissions(remote: "http://host/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, a remote naming no hash",
      command: .permissions(remote: "rns://elsewhere/group/repo", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, a remote naming no repository",
      command: .permissions(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", document: 3),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, no document named",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: nil),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written: "",
      aborted: "No document ID specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: [],
      suffixes: []),
    Run(
      name: "permissions, the document named zero",
      command: .permissions(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 0),
      edits: .writes("Written content"),
      typed: ["y"],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for work document #0\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696400a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/work",
            fields:
              "8500aa67726f75702f7265706fa96f7065726174696f6ea57065726d73a6646f635f696400a473746570a3736574a7636f6e74656e74af5772697474656e20636f6e74656e74",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"],
      suffixes: [".txt"]),
    Run(
      name: "view, a document naming no author",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a2696403a46d65746184a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea7636f6e74656e74a163"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error viewing work document: 'author'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document naming no title",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a2696403a46d65746184a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea7636f6e74656e74a163"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error viewing work document: 'title'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document naming no created",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a2696403a46d65746184a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea7636f6e74656e74a163"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\n",
      aborted: "Error viewing work document: 'created'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document naming no edited",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a2696403a46d65746184a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6666f726d6174a86d61726b646f776ea7636f6e74656e74a163"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\n",
      aborted: "Error viewing work document: 'edited'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document naming no format",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a2696403a46d65746184a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a7636f6e74656e74a163"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\n",
      aborted: "Error viewing work document: 'format'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document naming no meta",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0082a2696403a7636f6e74656e74a163")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error viewing work document: 'meta'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document naming no identifier",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0082a46d65746185a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea7636f6e74656e74a163"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Error viewing work document: 'id'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, content that is no text",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a2696403a46d65746185a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea7636f6e74656e7407"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n7\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document naming no content",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0082a2696403a46d65746185a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776e"
          )!)
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rA title (#3)\n============\nAuthor    : bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb (not locally validated)\nSignature : Document not signed\nStatus    : Active\nCreated   : 2025-09-04 15:33:20\nEdited    : 2025-09-04 15:43:20\nFormat    : markdown\nUpdates   : 0\n\n",
      aborted: "Error viewing work document: 'content'",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/work",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea476696577a6646f635f696403a573636f7065a6616374697665",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [],
      suffixes: []),
  ]

  private static let malformed: [Run] = [
    Run(
      name: "list, a listing that is no map",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0007")!)],
      written: "",
      aborted: nil,
      sent: nil,
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a document that is no map",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "0083a66163746976659107a9636f6d706c6574656490a870726f706f73656490")!)
      ],
      written: "",
      aborted: nil,
      sent: nil,
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "list, a title that is no text",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a66163746976659185a2696401a57469746c6507a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a763726561746564ce68b9b140a8636f6d6d656e747300a9636f6d706c6574656490a870726f706f73656490"
          )!)
      ],
      written: "",
      aborted: nil,
      sent: nil,
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, a document that is no map",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0007")!)],
      written: "",
      aborted: nil,
      sent: nil,
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "edit, a document that is no map",
      command: .edit(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, title: nil,
        scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0007")!), .bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: nil,
      sent: nil,
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "create, the node named what is no map",
      command: .create(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", title: "A title"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0007")!)],
      written: "",
      aborted: nil,
      sent: nil,
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, updates that are no list",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0084a2696403a46d65746185a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea7636f6e74656e74a163a8636f6d6d656e7473a46e6f6e65"
          )!)
      ],
      written: "",
      aborted: nil,
      sent: nil,
      tornDown: true,
      handed: [],
      suffixes: []),
    Run(
      name: "view, content that is no text under a signature",
      command: .view(
        remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", document: 3, scope: "active"),
      edits: .writes("Written content"),
      typed: [],
      signs: true,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(
            pythonHex:
              "0083a2696403a7636f6e74656e7407a46d65746187a6617574686f72d9206262626262626262626262626262626262626262626262626262626262626262a57469746c65a741207469746c65a763726561746564ce68b9b140a6656469746564ce68b9b398a6666f726d6174a86d61726b646f776ea97369676e6174757265c440977d277d48db96794471bf71ee551b75d8dbbf7218f46ea92ec0af12e585f0e651d702017a4fdb2cd9371789fa10b264323090d022939053344ec72ce88d7f0ca86964656e74697479c44069efaca886c2e8fbc23f395b04095c20ab5897d0c5a52a682e0fb65cc9fa072029874879008795f7bccdb52e5323513bb928042b01bc8ed2dbf4fade0f68cfb7"
          )!)
      ],
      written: "",
      aborted: nil,
      sent: nil,
      tornDown: true,
      handed: [],
      suffixes: []),
  ]

  /// Holds what the client wrote.
  private final class Recorder: RNGitClientOutput {
    var written = ""
    func write(_ text: String) { written += text }
  }

  /// Answers every prompt with what the user typed.
  private final class Typist: RNGitClientInput {
    private var lines: [String]
    init(_ lines: [String]) { self.lines = lines }
    func readLine() -> String? { lines.isEmpty ? nil : lines.removeFirst() }
  }

  /// Stands in for the user's editor, holding what it was handed.
  private final class Scribe: RNGitClientEditor {
    private let vector: Run
    var handed: [String] = []
    var suffixes: [String] = []
    var modes: [Int] = []
    var paths: [String] = []

    init(_ vector: Run) { self.vector = vector }

    func editor() -> String {
      if case .none = vector.edits { return "" }
      return "editor-under-test"
    }

    func run(_ editor: String, over path: String) -> Int32 {
      handed.append((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
      suffixes.append("." + (path as NSString).pathExtension)
      let attributes = try? FileManager.default.attributesOfItem(atPath: path)
      modes.append((attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0)
      paths.append(path)
      switch vector.edits {
      case .writes(let text):
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        return 0
      case .code(let code): return code
      case .none: return 0
      }
    }
  }

  /// Answers a client the way one run says to, holding what it was asked.
  private final class Stub: RNGitClientTransport {
    private var answers: [RNGitRequestResult]
    private let vector: Run
    var sent = Sent()
    var tornDown = false

    init(_ vector: Run) {
      self.vector = vector
      self.answers = vector.answers
    }

    func mediumPathTimeout() -> TimeInterval { 1606 }

    func awaitPath(to destinationHash: Data, timeout: TimeInterval) -> Bool {
      sent.awaitHash = destinationHash.hexString
      sent.awaitTimeout = timeout
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
      sent.requests.append(
        Request(path: path.rawValue, fields: MsgPack.encode(fields).hexString, timeout: timeout))
      return RNGitClientResponse(
        result: answers.isEmpty ? .bytes(Data([0])) : answers.removeFirst())
    }

    func teardown() { tornDown = true }
  }

  /// `value` with every signature it carries blanked.
  ///
  /// Ed25519 signing is randomised here, so a recorded signature can never be reproduced, while
  /// everything it covers can be.
  private static func blinded(_ value: MsgPack.Value) -> MsgPack.Value {
    switch value {
    case .bytes(let data):
      return data.count == Constants.signatureLength ? .bytes(Data(count: data.count)) : value
    case .array(let items): return .array(items.map(blinded))
    case .map(let entries): return .map(entries.map { (blinded($0.0), blinded($0.1)) })
    default: return value
    }
  }

  /// `request` with every signature its fields carry blanked.
  private static func blinded(_ request: Request) -> Request {
    let fields = (try? MsgPack.decode(Data(pythonHex: request.fields) ?? Data())) ?? .nil
    return Request(
      path: request.path, fields: MsgPack.encode(blinded(fields)).hexString,
      timeout: request.timeout)
  }

  /// Runs `command` against `commands`.
  private static func run(_ command: Command, on commands: RNGitClientCommands) throws {
    switch command {
    case .list(let remote, let scope): try commands.listWork(remote: remote, scope: scope)
    case .view(let remote, let document, let scope):
      try commands.viewWork(remote: remote, document: document, scope: scope)
    case .create(let remote, let title):
      try commands.createWork(remote: remote, title: title)
    case .propose(let remote, let title):
      try commands.proposeWork(remote: remote, title: title)
    case .edit(let remote, let document, let title, let scope):
      try commands.editWork(remote: remote, document: document, title: title, scope: scope)
    case .delete(let remote, let document, let scope):
      try commands.deleteWork(remote: remote, document: document, scope: scope)
    case .comment(let remote, let document, let scope):
      try commands.commentWork(remote: remote, document: document, scope: scope)
    case .complete(let remote, let document):
      try commands.completeWork(remote: remote, document: document)
    case .activate(let remote, let document):
      try commands.activateWork(remote: remote, document: document)
    case .permissions(let remote, let document):
      try commands.workPermissions(remote: remote, document: document)
    }
  }

  /// Runs `run` and measures everything it left behind against what was recorded.
  private func measure(_ run: Run) throws {
    let identity = try XCTUnwrap(Identity.fromBytes(Data(pythonHex: Self.privateKey)!))
    let output = Recorder()
    let transport = Stub(run)
    let editor = Scribe(run)
    let typist = Typist(run.typed)
    let commands = RNGitClientCommands(
      rendering: RNGitReleaseRendering(timeZone: TimeZone(identifier: "UTC")!),
      identity: run.signs ? identity : nil, transport: transport, output: output,
      input: typist, editor: editor)

    var aborted: String?
    do {
      try Self.run(run.command, on: commands)
    } catch let abort as RNGitClientAbort {
      aborted = abort.message
    }

    XCTAssertEqual(output.written, run.written, run.name)
    XCTAssertEqual(aborted, run.aborted, run.name)
    XCTAssertEqual(transport.sent.awaitHash, run.sent?.awaitHash, run.name)
    XCTAssertEqual(transport.sent.awaitTimeout, run.sent?.awaitTimeout, run.name)
    XCTAssertEqual(
      transport.sent.requests.map(Self.blinded), (run.sent?.requests ?? []).map(Self.blinded),
      run.name)
    XCTAssertEqual(transport.tornDown, run.tornDown, run.name)
    XCTAssertEqual(editor.handed, run.handed, run.name)
    XCTAssertEqual(editor.suffixes, run.suffixes, run.name)
    XCTAssertEqual(editor.modes, Array(repeating: 0o600, count: run.handed.count), run.name)
    for path in editor.paths {
      XCTAssertFalse(FileManager.default.fileExists(atPath: path), run.name)
    }
  }

  func testWorkCommandsMatchTheReference() throws {
    for run in Self.runs { try measure(run) }
  }

  /// A node answer holding the wrong kind of value where a map or text belongs.
  ///
  /// Python RNS 1.5.4 reads these answers without checking them and raises out of the
  /// interpreter, so the text it prints names CPython's own types and is no contract. These
  /// runs are held apart from the recorded ones for that reason, and what is measured over
  /// them is that the client refuses the answer, says something, and closes the link.
  func testAnUnreadableAnswerIsRefused() throws {
    for run in Self.malformed {
      let output = Recorder()
      let transport = Stub(run)
      let commands = RNGitClientCommands(
        rendering: RNGitReleaseRendering(timeZone: TimeZone(identifier: "UTC")!),
        identity: try XCTUnwrap(Identity.fromBytes(Data(pythonHex: Self.privateKey)!)),
        transport: transport, output: output, input: Typist(run.typed), editor: Scribe(run))

      var aborted: String?
      do {
        try Self.run(run.command, on: commands)
      } catch let abort as RNGitClientAbort {
        aborted = abort.message
      }

      XCTAssertEqual(aborted?.isEmpty, false, run.name)
      XCTAssertTrue(transport.tornDown, run.name)
    }
  }

}
