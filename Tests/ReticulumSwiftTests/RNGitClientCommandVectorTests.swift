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

/// The commands an `rngit` client runs, measured against Python RNS 1.5.4.
final class RNGitClientCommandVectorTests: XCTestCase {

  private enum Command {
    case create(remote: String?)
    case fork(source: String?, target: String?)
    case mirror(source: String?, target: String?)
    case sync(remote: String?)
  }

  private struct Sent {
    var awaitHash: String?
    var awaitTimeout: Double?
    var path: String?
    var fields: String?
    var timeout: Double?
  }

  private struct Run {
    let name: String
    let command: Command
    let aliases: [String: String]
    let hasPath: Bool
    let recalls: Bool
    let linkComesUp: Bool
    let answer: RNGitRequestResult
    let written: String
    let aborted: String?
    let sent: Sent?
    let tornDown: Bool
  }

  private static let runs: [Run] = [
    Run(
      name: "create, did as asked",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRepository group/repo created\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, did as asked",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\nRepository forked to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, did as asked",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\nRepository mirrored to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, did as asked",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\nRepository synced\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, did as asked, carrying more",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "006578747261")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRepository group/repo created\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, did as asked, carrying more",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "006578747261")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\nRepository forked to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, did as asked, carrying more",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "006578747261")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\nRepository mirrored to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, did as asked, carrying more",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "006578747261")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\nRepository synced\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, refused",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "01")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Not allowed",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, refused",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "01")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "Not allowed",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, refused",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "01")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "Not allowed",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, refused",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "01")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "Not allowed",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, refused, saying why",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, refused, saying why",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, refused, saying why",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, refused, saying why",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, read nothing",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "02")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Invalid request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, read nothing",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "02")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "Invalid request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, read nothing",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "02")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "Invalid request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, read nothing",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "02")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "Invalid request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, read nothing, saying why",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Invalid request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, read nothing, saying why",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, read nothing, saying why",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, read nothing, saying why",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, found nothing",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "03")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Not found",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, found nothing",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "03")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "Not found",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, found nothing",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "03")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "Not found",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, found nothing",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "03")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "Not found",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, found nothing, saying what",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "034e6f2073756368207265706f7369746f7279")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Not found",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, found nothing, saying what",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "034e6f2073756368207265706f7369746f7279")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "No such repository",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, found nothing, saying what",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "034e6f2073756368207265706f7369746f7279")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "No such repository",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, found nothing, saying what",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "034e6f2073756368207265706f7369746f7279")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "No such repository",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, failed",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Unknown error",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, failed",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "Server error: Unknown error",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, failed",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "Server error: Unknown error",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, failed",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "Server error: Unknown error",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, failed, saying why",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff6769742065786974656420313238")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: git exited 128",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, failed, saying why",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff6769742065786974656420313238")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "Server error: git exited 128",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, failed, saying why",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff6769742065786974656420313238")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "Server error: git exited 128",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, failed, saying why",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff6769742065786974656420313238")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "Server error: git exited 128",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, code of its own",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Unknown error",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, code of its own",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "Server error: Unknown error",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, code of its own",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "Server error: Unknown error",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, code of its own",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "Server error: Unknown error",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, code of its own, saying why",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, code of its own, saying why",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "Server error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, code of its own, saying why",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "Server error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, code of its own, saying why",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "Server error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, refused in bytes that are not text",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "016162fffe6364")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "abcd",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, refused in bytes that are not text",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "016162fffe6364")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "abcd",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, refused in bytes that are not text",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "016162fffe6364")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "abcd",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, refused in bytes that are not text",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "016162fffe6364")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "abcd",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, nothing at all",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, nothing at all",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, nothing at all",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, nothing at all",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, no answer",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .none,
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, no answer",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .none,
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, no answer",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .none,
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, no answer",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .none,
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, not bytes",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .file("/tmp/answer"),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, not bytes",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .file("/tmp/answer"),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\n",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, not bytes",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .file("/tmp/answer"),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\n",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "sync, not bytes",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .file("/tmp/answer"),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is syncing repository...\n",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/sync",
        fields: "8100aa67726f75702f7265706f", timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, no path to the remote",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "create, no identity recalled",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "create, link closed before it came up",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Link establishment failed",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "fork, no path to the remote",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "fork, no identity recalled",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "fork, link closed before it came up",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Link establishment failed",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "mirror, no path to the remote",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "mirror, no identity recalled",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "mirror, link closed before it came up",
      command: .mirror(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Link establishment failed",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "sync, no path to the remote",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "sync, no identity recalled",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "sync, link closed before it came up",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Link establishment failed",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "create, no remote named",
      command: .create(remote: nil),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "create, remote of the wrong protocol",
      command: .create(remote: "http://host/g/r"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: nil,
      tornDown: false),
    Run(
      name: "create, remote of two components",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "create, remote of four components",
      command: .create(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/g/r/more"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "create, remote naming no hash",
      command: .create(remote: "rns://elsewhere/g/r"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid destination hash length",
      sent: nil,
      tornDown: false),
    Run(
      name: "create, remote under an alias",
      command: .create(remote: "rns://bob/group/repo"),
      aliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRepository group/repo created\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, no source named",
      command: .fork(source: nil, target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No source specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "fork, no target named",
      command: .fork(source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source", target: nil),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "fork, source under an alias",
      command: .fork(
        source: "rns://alice/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: ["alice": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\nRepository forked to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "fork, source that is not a remote URL",
      command: .fork(
        source: "/srv/git/source", target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\nRepository forked to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields: "8200aa67726f75702f7265706fa6736f75726365af2f7372762f6769742f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "fork, source of the wrong component count",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid number of URL components",
      sent: nil,
      tornDown: false),
    Run(
      name: "fork, target under an alias",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://bob/group/repo"),
      aliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\nRepository forked to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "mirror, no source named",
      command: .mirror(source: nil, target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No source specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "mirror, no target named",
      command: .mirror(source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source", target: nil),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "mirror, source that is not a remote URL",
      command: .mirror(
        source: "https://example.invalid/source.git",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is mirroring repository to group/repo...\nRepository mirrored to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/mirror",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d92268747470733a2f2f6578616d706c652e696e76616c69642f736f757263652e676974",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "create, remote named as nothing",
      command: .create(remote: ""),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "sync, remote named as nothing",
      command: .sync(remote: ""),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "fork, source named as nothing",
      command: .fork(source: "", target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No source specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "fork, target named as nothing",
      command: .fork(source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source", target: ""),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "mirror, source named as nothing",
      command: .mirror(source: "", target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No source specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "mirror, target named as nothing",
      command: .mirror(source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source", target: ""),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "create, remote under a protocol of mixed case",
      command: .create(remote: "RnS://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRepository group/repo created\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/create",
        fields: "8100aa67726f75702f7265706f", timeout: 120.0),
      tornDown: true),
    Run(
      name: "fork, source under a protocol of mixed case",
      command: .fork(
        source: "RNS://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\nRepository forked to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "fork, source naming a hash in capitals",
      command: .fork(
        source: "rns://BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRemote is forking repository to group/repo...\nRepository forked to group/repo\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/git/fork",
        fields:
          "8200aa67726f75702f7265706fa6736f75726365d933726e733a2f2f62626262626262626262626262626262626262626262626262626262626262622f6f746865722f736f75726365",
        timeout: 7200.0),
      tornDown: true),
    Run(
      name: "fork, source naming no group",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb//source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid source URL",
      sent: nil,
      tornDown: false),
    Run(
      name: "fork, source naming no repository",
      command: .fork(
        source: "rns://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/other/",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid source URL",
      sent: nil,
      tornDown: false),
    Run(
      name: "fork, source under an unknown name",
      command: .fork(
        source: "rns://elsewhere/other/source",
        target: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid destination hash length",
      sent: nil,
      tornDown: false),
    Run(
      name: "sync, no remote named",
      command: .sync(remote: nil),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "sync, remote of two components",
      command: .sync(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      aliases: [:],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
  ]

  private struct Answered {
    let name: String
    let response: String
    let body: String
  }

  private static let answered: [Answered] = [
    Answered(
      name: "nothing after the code",
      response: "00",
      body: ""),
    Answered(
      name: "one byte after the code",
      response: "002a",
      body: "2a"),
    Answered(
      name: "text after the code",
      response: "006c697374696e67",
      body: "6c697374696e67"),
    Answered(
      name: "a packed list after the code",
      response: "0090",
      body: "90"),
    Answered(
      name: "a packed map after the code",
      response: "0082a872656c656173657390a66c6174657374c0",
      body: "82a872656c656173657390a66c6174657374c0"),
    Answered(
      name: "bytes that are not text after the code",
      response: "00fffe0001",
      body: "fffe0001"),
  ]

  /// Holds what the client wrote.
  private final class Recorder: RNGitClientOutput {
    var written = ""
    func write(_ text: String) { written += text }
  }

  /// Answers a client the way one run says to, holding what it was asked.
  private final class Stub: RNGitClientTransport {
    private let run: Run
    var sent = Sent()
    var tornDown = false

    init(_ run: Run) { self.run = run }

    func mediumPathTimeout() -> TimeInterval { 1606 }

    func awaitPath(to destinationHash: Data, timeout: TimeInterval) -> Bool {
      sent.awaitHash = destinationHash.hexString
      sent.awaitTimeout = timeout
      return run.hasPath
    }

    func recallIdentity(for destinationHash: Data) -> Identity? {
      run.recalls ? Identity() : nil
    }

    func establishLink(to identity: Identity) -> Bool { run.linkComesUp }

    func request(_ path: RNGitRequestPath, _ fields: MsgPack.Value, timeout: TimeInterval)
      -> RNGitRequestResult
    {
      sent.path = path.rawValue
      sent.fields = MsgPack.encode(fields).hexString
      sent.timeout = timeout
      return run.answer
    }

    func teardown() { tornDown = true }
  }

  func testCommandsMatchTheReference() throws {
    for run in Self.runs {
      let output = Recorder()
      let transport = Stub(run)
      let commands = RNGitClientCommands(
        aliases: run.aliases, transport: transport, output: output)

      var aborted: String?
      do {
        switch run.command {
        case .create(let remote): try commands.createRepository(remote: remote)
        case .fork(let source, let target):
          try commands.forkRepository(source: source, target: target)
        case .mirror(let source, let target):
          try commands.mirrorRepository(source: source, target: target)
        case .sync(let remote): try commands.syncRepository(remote: remote)
        }
      } catch let abort as RNGitClientAbort {
        aborted = abort.message
      }

      XCTAssertEqual(output.written, run.written, run.name)
      XCTAssertEqual(aborted, run.aborted, run.name)
      XCTAssertEqual(transport.sent.awaitHash, run.sent?.awaitHash, run.name)
      XCTAssertEqual(transport.sent.awaitTimeout, run.sent?.awaitTimeout, run.name)
      XCTAssertEqual(transport.sent.path, run.sent?.path, run.name)
      XCTAssertEqual(transport.sent.fields, run.sent?.fields, run.name)
      XCTAssertEqual(transport.sent.timeout, run.sent?.timeout, run.name)
      XCTAssertEqual(transport.tornDown, run.tornDown, run.name)
    }
  }

  func testAnsweredBytesMatchTheReference() throws {
    let reading = RNGitResponseReading(other: .sent(prefix: "", fallback: ""))
    for answer in Self.answered {
      let result = RNGitRequestResult.bytes(Data(pythonHex: answer.response)!)
      XCTAssertEqual(
        reading.reading(result), .done(Data(pythonHex: answer.body)!), answer.name)
    }
  }

}
