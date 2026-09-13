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

/// The permission commands an `rngit` client runs, measured against Python RNS 1.5.4.
final class RNGitClientPermissionVectorTests: XCTestCase {

  private enum Command {
    case group(remote: String?)
    case repository(remote: String?)
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
    let hasPath: Bool
    let recalls: Bool
    let linkComesUp: Bool
    let answers: [RNGitRequestResult]
    let written: String
    let aborted: String?
    let sent: Sent?
    let tornDown: Bool
    let handed: [String]
  }

  private static let runs: [Run] = [
    Run(
      name: "group, asked and did as asked",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group group\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "group, sent and did as asked",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group group\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and refused",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and refused",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and refused, saying why",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and refused, saying why",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and read nothing",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and read nothing",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and read nothing, saying why",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and read nothing, saying why",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and found nothing",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and found nothing",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and found nothing, saying what",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "034e6f20737563682067726f7570")!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such group",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and found nothing, saying what",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "034e6f20737563682067726f7570")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such group",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and failed",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and failed",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and failed, saying why",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f742072656164207065726d697373696f6e73")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read permissions",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and failed, saying why",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "ff636f756c64206e6f742072656164207065726d697373696f6e73")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read permissions",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and code of its own, saying why",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and code of its own, saying why",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and nothing at all",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and nothing at all",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and no answer",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and no answer",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and not bytes",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.file("/tmp/answer"), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, sent and not bytes",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .file("/tmp/answer"),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and answered nothing after the code",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group group\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "group, asked and answered permissions that stand",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group group\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, asked and answered a map naming no content",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0080")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group group\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "group, asked and answered a map naming content of no length",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "0081a7636f6e74656e74a0")!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group group\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "group, edited to no content",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes(""),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group group\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74a0",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, edited to content of one line",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("adm:cccc"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group group\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, edited to content of two lines",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("adm:cccc\nread:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group group\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8402a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3736574a7636f6e74656e74b661646d3a636363630a726561643a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, editor came back with code 1",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .code(1),
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, nothing to edit and editor came back with code 1",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .code(1),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEditor exited with error code 1\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "group, editor came back with code 127",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .code(127),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEditor exited with error code 127\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "group, nothing to edit and editor came back with code 127",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .code(127),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEditor exited with error code 127\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "group, editor was nowhere to be found",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .none,
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
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, nothing to edit and editor was nowhere to be found",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .none,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo editor found. Please set $EDITOR environment variable.\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields: "8302a567726f7570a96f7065726174696f6ea6677065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "group, no path to the remote",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "group, no identity recalled",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "group, link closed before it came up",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "group, no remote named",
      command: .group(remote: nil),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "group, remote named as nothing",
      command: .group(remote: ""),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "group, remote of the wrong protocol",
      command: .group(remote: "http://host/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "group, remote naming no hash",
      command: .group(remote: "rns://elsewhere/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "repository, asked and did as asked",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "repository, sent and did as asked",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and refused",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and refused",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and refused, saying why",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and refused, saying why",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and read nothing",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and read nothing",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and read nothing, saying why",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and read nothing, saying why",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and found nothing",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and found nothing",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and found nothing, saying what",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "034e6f20737563682067726f7570")!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such group",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and found nothing, saying what",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "034e6f20737563682067726f7570")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such group",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and failed",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and failed",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and failed, saying why",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "ff636f756c64206e6f742072656164207065726d697373696f6e73")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read permissions",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and failed, saying why",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "ff636f756c64206e6f742072656164207065726d697373696f6e73")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: could not read permissions",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and code of its own, saying why",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and code of its own, saying why",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and nothing at all",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and nothing at all",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and no answer",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and no answer",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and not bytes",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.file("/tmp/answer"), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, sent and not bytes",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .file("/tmp/answer"),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and answered nothing after the code",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "repository, asked and answered permissions that stand",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, asked and answered a map naming no content",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "0080")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "repository, asked and answered a map naming content of no length",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(Data(pythonHex: "0081a7636f6e74656e74a0")!), .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74ae616c6c6f773a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "repository, edited to no content",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes(""),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74a0",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, edited to content of one line",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("adm:cccc"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74a861646d3a63636363",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, edited to content of two lines",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("adm:cccc\nread:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rPermissions updated for group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0),
          Request(
            path: "/mgmt/perms",
            fields:
              "8400aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3736574a7636f6e74656e74b661646d3a636363630a726561643a65766572796f6e65",
            timeout: 120.0),
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, editor came back with code 1",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .code(1),
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, nothing to edit and editor came back with code 1",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .code(1),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEditor exited with error code 1\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "repository, editor came back with code 127",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .code(127),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [
        .bytes(
          Data(pythonHex: "0081a7636f6e74656e74b661646d3a626262620a726561643a65766572796f6e65")!),
        .bytes(Data(pythonHex: "00")!),
      ],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEditor exited with error code 127\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: ["adm:bbbb\nread:everyone"]),
    Run(
      name: "repository, nothing to edit and editor came back with code 127",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .code(127),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rEditor exited with error code 127\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: [
        "# No permissions are currently defined for this entity. Add them below, and save and exit when you are done."
      ]),
    Run(
      name: "repository, editor was nowhere to be found",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .none,
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
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, nothing to edit and editor was nowhere to be found",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .none,
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo editor found. Please set $EDITOR environment variable.\nEdit cancelled\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0,
        requests: [
          Request(
            path: "/mgmt/perms",
            fields:
              "8300aa67726f75702f7265706fa96f7065726174696f6ea6727065726d73a473746570a3676574",
            timeout: 120.0)
        ]),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, no path to the remote",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "repository, no identity recalled",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "repository, link closed before it came up",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "repository, no remote named",
      command: .repository(remote: nil),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "repository, remote named as nothing",
      command: .repository(remote: ""),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "No remote specified",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "repository, remote of the wrong protocol",
      command: .repository(remote: "http://host/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "repository, remote naming no hash",
      command: .repository(remote: "rns://elsewhere/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written: "",
      aborted: "Invalid destination hash length",
      sent: Sent(awaitHash: nil, awaitTimeout: nil, requests: []),
      tornDown: false,
      handed: []),
    Run(
      name: "group, remote of three components",
      command: .group(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: []),
    Run(
      name: "repository, remote of two components",
      command: .repository(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      edits: .writes("allow:everyone"),
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answers: [.bytes(Data(pythonHex: "00")!), .bytes(Data(pythonHex: "00")!)],
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, requests: []),
      tornDown: true,
      handed: []),
  ]

  /// Holds what the client wrote.
  private final class Recorder: RNGitClientOutput {
    var written = ""
    func write(_ text: String) { written += text }
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

    func request(_ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval)
      -> RNGitRequestResult
    {
      sent.requests.append(
        Request(path: path.rawValue, fields: MsgPack.encode(fields).hexString, timeout: timeout))
      return answers.isEmpty ? .bytes(Data([0])) : answers.removeFirst()
    }

    func teardown() { tornDown = true }
  }

  func testPermissionCommandsMatchTheReference() throws {
    for run in Self.runs {
      let output = Recorder()
      let transport = Stub(run)
      let editor = Scribe(run)
      let commands = RNGitClientCommands(
        transport: transport, output: output, editor: editor)

      var aborted: String?
      do {
        switch run.command {
        case .group(let remote): try commands.groupPermissions(remote: remote)
        case .repository(let remote): try commands.repositoryPermissions(remote: remote)
        }
      } catch let abort as RNGitClientAbort {
        aborted = abort.message
      }

      XCTAssertEqual(output.written, run.written, run.name)
      XCTAssertEqual(aborted, run.aborted, run.name)
      XCTAssertEqual(transport.sent.awaitHash, run.sent?.awaitHash, run.name)
      XCTAssertEqual(transport.sent.awaitTimeout, run.sent?.awaitTimeout, run.name)
      XCTAssertEqual(transport.sent.requests, run.sent?.requests ?? [], run.name)
      XCTAssertEqual(transport.tornDown, run.tornDown, run.name)
      XCTAssertEqual(editor.handed, run.handed, run.name)
      XCTAssertEqual(editor.suffixes, Array(repeating: ".txt", count: run.handed.count), run.name)
      XCTAssertEqual(editor.modes, Array(repeating: 0o600, count: run.handed.count), run.name)
      for path in editor.paths {
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), run.name)
      }
    }
  }

}
