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

/// The release commands an `rngit` client runs, measured against Python RNS 1.5.4.
final class RNGitClientReleaseVectorTests: XCTestCase {

  private enum Command {
    case list(remote: String?)
    case view(remote: String?, target: String?)
    case delete(remote: String?, target: String?)
    case latest(remote: String?, target: String?)
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
    let typed: [String]
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
      name: "list, did as asked",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo releases for this repository\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, did as asked",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Empty response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, did as asked",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: Release v1.0 deleted\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, did as asked",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: Release v1.0 set as latest\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, refused",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "01")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, refused",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "01")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, refused",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "01")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, refused",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "01")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, refused, saying why",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, refused, saying why",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, refused, saying why",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, refused, saying why",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "014e6f7420616c6c6f77656420666f7220796f75")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: Not allowed for you",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, read nothing",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "02")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, read nothing",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "02")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, read nothing",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "02")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, read nothing",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "02")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, read nothing, saying why",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, read nothing, saying why",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, read nothing, saying why",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, read nothing, saying why",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "024d616c666f726d65642072657175657374")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: Malformed request",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, found nothing",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "03")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, found nothing",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "03")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, found nothing",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "03")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, found nothing",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "03")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, found nothing, saying what",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "034e6f20737563682072656c65617365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: No such release",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, found nothing, saying what",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "034e6f20737563682072656c65617365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: No such release",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, found nothing, saying what",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "034e6f20737563682072656c65617365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: No such release",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, found nothing, saying what",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "034e6f20737563682072656c65617365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: No such release",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, failed",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, failed",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, failed",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, failed",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, failed, saying why",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff6769742065786974656420313238")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: git exited 128",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, failed, saying why",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff6769742065786974656420313238")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: git exited 128",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, failed, saying why",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff6769742065786974656420313238")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: git exited 128",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, failed, saying why",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "ff6769742065786974656420313238")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: git exited 128",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, code of its own",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, code of its own",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, code of its own",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, code of its own",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: ",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, code of its own, saying why",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, code of its own, saying why",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, code of its own, saying why",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, code of its own, saying why",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "7f736f6d657468696e6720656c7365")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: something else",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, refused in bytes that are not text",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "016162fffe6364")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Server error: abcd",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, refused in bytes that are not text",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "016162fffe6364")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Remote error: abcd",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, refused in bytes that are not text",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "016162fffe6364")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Remote error: abcd",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, refused in bytes that are not text",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "016162fffe6364")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Remote error: abcd",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, nothing at all",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, nothing at all",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, nothing at all",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, nothing at all",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, no answer",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .none,
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     ",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, no answer",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .none,
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     ",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, no answer",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .none,
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, no answer",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .none,
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "Request failed or timed out",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, not bytes",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .file("/tmp/answer"),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, not bytes",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .file("/tmp/answer"),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, not bytes",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .file("/tmp/answer"),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: ",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, not bytes",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .file("/tmp/answer"),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: ",
      aborted: "No response from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, no path to the remote",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "list, no identity recalled",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "list, link closed before it came up",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Link establishment failed",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "list, no remote named",
      command: .list(remote: nil),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "list, remote named as nothing",
      command: .list(remote: ""),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "list, remote of two components",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     ",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "list, remote of the wrong protocol",
      command: .list(remote: "http://host/g/r"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: nil,
      tornDown: false),
    Run(
      name: "view, no path to the remote",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "view, no identity recalled",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "view, link closed before it came up",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Link establishment failed",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "view, no remote named",
      command: .view(remote: nil, target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "view, remote named as nothing",
      command: .view(remote: "", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "view, remote of two components",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     ",
      aborted: "Invalid number of URL components",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "view, remote of the wrong protocol",
      command: .view(remote: "http://host/g/r", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: nil,
      tornDown: false),
    Run(
      name: "delete, no path to the remote",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "delete, no identity recalled",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "delete, link closed before it came up",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "delete, no remote named",
      command: .delete(remote: nil, target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "delete, remote named as nothing",
      command: .delete(remote: "", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "delete, remote of two components",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", target: "v1.0"),
      typed: ["y"],
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
      name: "delete, remote of the wrong protocol",
      command: .delete(remote: "http://host/g/r", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: nil,
      tornDown: false),
    Run(
      name: "latest, no path to the remote",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: false,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \n",
      aborted: "Could not resolve path to <aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa>",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "latest, no identity recalled",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: false,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      ",
      aborted: "Could not recall remote identity",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "latest, link closed before it came up",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: false,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "Requesting path... \rPath resolved      \rEstablishing link... ",
      aborted: "Failed to establish link",
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: false),
    Run(
      name: "latest, no remote named",
      command: .latest(remote: nil, target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "latest, remote named as nothing",
      command: .latest(remote: "", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No remote specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "latest, remote of two components",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", target: "v1.0"),
      typed: ["y"],
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
      name: "latest, remote of the wrong protocol",
      command: .latest(remote: "http://host/g/r", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "Invalid protocol in remote URL",
      sent: nil,
      tornDown: false),
    Run(
      name: "view, no target named",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: nil),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "view, target named as nothing",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: ""),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "delete, no target named",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: nil),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "delete, target named as nothing",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: ""),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "latest, no target named",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: nil),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "latest, target named as nothing",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: ""),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written: "",
      aborted: "No target specified",
      sent: nil,
      tornDown: false),
    Run(
      name: "list, answered with nothing after the code",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo releases for this repository\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with an empty list",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "0090")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo releases for this repository\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with one release",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "009185a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a961727469666163747303a770726576696577bf4669727374206c696e65206f66206e6f7465730a7365636f6e64206c696e65"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rTag        Status     Created           Objs  Notes\n--------------------------------------------------------------------------------\nv1.0       published  2025-09-04 15:33  3     First line of notes\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with three releases",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "009385a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a961727469666163747303a770726576696577bf4669727374206c696e65206f66206e6f7465730a7365636f6e64206c696e6585a3746167b876312e302e302d72656c656173652d63616e646964617465a6737461747573b1756e7075626c69736865642d6472616674a763726561746564ce6553f100a96172746966616374730ca770726576696577d93441207072657669657720746861742072756e732077656c6c20706173742074686520636f6c756d6e20697420697320676976656e85a3746167a476302e31a6737461747573a56472616674a76372656174656400a961727469666163747300a770726576696577a46f6e6c79"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rTag        Status     Created           Objs  Notes\n--------------------------------------------------------------------------------\nv1.0       published  2025-09-04 15:33  3     First line of notes\nv1.0.0-rel unpublish  2023-11-14 22:13  12    A preview that runs well past the \nv0.1       draft      unknown           0     only\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with a map naming no latest",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0082a872656c65617365739185a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a961727469666163747303a770726576696577bf4669727374206c696e65206f66206e6f7465730a7365636f6e64206c696e65a66c6174657374c0"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rTag        Status     Created           Objs  Notes\n--------------------------------------------------------------------------------\nv1.0       published  2025-09-04 15:33  3     First line of notes\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with a map naming a latest",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0082a872656c65617365739285a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a961727469666163747303a770726576696577bf4669727374206c696e65206f66206e6f7465730a7365636f6e64206c696e6585a3746167a476302e31a6737461747573a56472616674a76372656174656400a961727469666163747300a770726576696577a46f6e6c79a66c6174657374a476312e30"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rTag        Status     Created           Objs  Notes\n--------------------------------------------------------------------------------\nv1.0       published  2025-09-04 15:33  3     First line of notes\nv0.1       draft      unknown           0     only\n\nThe latest release is: v1.0\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with a map naming a latest and no releases",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "0082a872656c656173657390a66c6174657374a476312e30")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rNo releases for this repository\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with a map naming a latest of no length",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0082a872656c65617365739185a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a961727469666163747303a770726576696577bf4669727374206c696e65206f66206e6f7465730a7365636f6e64206c696e65a66c6174657374a0"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rTag        Status     Created           Objs  Notes\n--------------------------------------------------------------------------------\nv1.0       published  2025-09-04 15:33  3     First line of notes\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with a release naming nothing",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "009181a770726576696577a7756e6e616d6564")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rTag        Status     Created           Objs  Notes\n--------------------------------------------------------------------------------\nunknown    unknown    unknown           0     unnamed\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with a number",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "0007")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid release data format from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "list, answered with text",
      command: .list(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00a872656c6561736573")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \r",
      aborted: "Invalid release data format from remote",
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8200aa67726f75702f7265706fa96f7065726174696f6ea46c697374", timeout: 120.0),
      tornDown: true),
    Run(
      name: "view, answered with a full release",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0087a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a67468616e6b7307a56e6f746573bc52656c65617365206e6f7465730a6f7665722074776f206c696e6573ac6e6f7465735f666f726d6174a86d61726b646f776ea96172746966616374739282a46e616d65a8746f6f6c2e7a6970a473697a65ce0010000082a46e616d65a9656d7074792e62696ea473697a6500"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRelease : v1.0\nStatus  : published\nCreated : 2025-09-04 15:33:20\nThanks  : 7\n\nRelease Notes\n=============\n\nRelease notes\nover two lines\n\nArtifacts (2)\n=============\n - tool.zip (1.05 MB)\n - empty.bin (0 B)\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "view, answered with a release naming nothing",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "0080")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRelease : v1.0\nStatus  : unknown\nThanks  : 0\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "view, answered with a release created at no time",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0087a3746167a476312e30a6737461747573a97075626c6973686564a76372656174656400a67468616e6b7307a56e6f746573bc52656c65617365206e6f7465730a6f7665722074776f206c696e6573ac6e6f7465735f666f726d6174a86d61726b646f776ea96172746966616374739282a46e616d65a8746f6f6c2e7a6970a473697a65ce0010000082a46e616d65a9656d7074792e62696ea473697a6500"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRelease : v1.0\nStatus  : published\nThanks  : 7\n\nRelease Notes\n=============\n\nRelease notes\nover two lines\n\nArtifacts (2)\n=============\n - tool.zip (1.05 MB)\n - empty.bin (0 B)\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "view, answered with a release with no notes",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0087a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a67468616e6b7307a56e6f746573a0ac6e6f7465735f666f726d6174a86d61726b646f776ea96172746966616374739282a46e616d65a8746f6f6c2e7a6970a473697a65ce0010000082a46e616d65a9656d7074792e62696ea473697a6500"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRelease : v1.0\nStatus  : published\nCreated : 2025-09-04 15:33:20\nThanks  : 7\n\nArtifacts (2)\n=============\n - tool.zip (1.05 MB)\n - empty.bin (0 B)\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "view, answered with a release with no artifacts",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0087a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a67468616e6b7307a56e6f746573bc52656c65617365206e6f7465730a6f7665722074776f206c696e6573ac6e6f7465735f666f726d6174a86d61726b646f776ea961727469666163747390"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRelease : v1.0\nStatus  : published\nCreated : 2025-09-04 15:33:20\nThanks  : 7\n\nRelease Notes\n=============\n\nRelease notes\nover two lines\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "view, answered with a release with one artifact",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0087a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a67468616e6b7307a56e6f746573bc52656c65617365206e6f7465730a6f7665722074776f206c696e6573ac6e6f7465735f666f726d6174a86d61726b646f776ea96172746966616374739182a46e616d65aa6f6e652e7461722e677aa473697a65cd0bb8"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRelease : v1.0\nStatus  : published\nCreated : 2025-09-04 15:33:20\nThanks  : 7\n\nRelease Notes\n=============\n\nRelease notes\nover two lines\n\nArtifacts (1)\n=============\n - one.tar.gz (3.00 KB)\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "view, answered with a release with an unnamed artifact",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0087a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a67468616e6b7307a56e6f746573bc52656c65617365206e6f7465730a6f7665722074776f206c696e6573ac6e6f7465735f666f726d6174a86d61726b646f776ea96172746966616374739181a473697a650c"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRelease : v1.0\nStatus  : published\nCreated : 2025-09-04 15:33:20\nThanks  : 7\n\nRelease Notes\n=============\n\nRelease notes\nover two lines\n\nArtifacts (1)\n=============\n - unknown (12 B)\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "view, answered with a release with an artifact of no stated size",
      command: .view(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(
        Data(
          pythonHex:
            "0087a3746167a476312e30a6737461747573a97075626c6973686564a763726561746564ce68b9b140a67468616e6b7307a56e6f746573bc52656c65617365206e6f7465730a6f7665722074776f206c696e6573ac6e6f7465735f666f726d6174a86d61726b646f776ea96172746966616374739181a46e616d65ae756e6d656173757265642e62696e"
        )!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rRelease : v1.0\nStatus  : published\nCreated : 2025-09-04 15:33:20\nThanks  : 7\n\nRelease Notes\n=============\n\nRelease notes\nover two lines\n\nArtifacts (1)\n=============\n - unmeasured.bin (0 B)\n\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea476696577a3746167a476312e30",
        timeout: 300.0),
      tornDown: true),
    Run(
      name: "delete, answered yes",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: Release v1.0 deleted\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "delete, answered yes in capitals",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["Y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: Release v1.0 deleted\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "delete, answered yes with spaces around it",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["  y  "],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: Release v1.0 deleted\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea664656c657465a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "delete, answered no",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["n"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: Deletion cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "delete, answered nothing",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [""],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: Deletion cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "delete, answered something else",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["maybe"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: Deletion cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "delete, answered nothing at all",
      command: .delete(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to delete release v1.0? [y/N]: Deletion cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "latest, answered yes",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: Release v1.0 set as latest\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, answered yes in capitals",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["Y"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: Release v1.0 set as latest\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, answered yes with spaces around it",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["  y  "],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: Release v1.0 set as latest\n",
      aborted: nil,
      sent: Sent(
        awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0, path: "/mgmt/release",
        fields: "8300aa67726f75702f7265706fa96f7065726174696f6ea66c6174657374a3746167a476312e30",
        timeout: 120.0),
      tornDown: true),
    Run(
      name: "latest, answered no",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["n"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: Update cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "latest, answered nothing",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [""],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: Update cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "latest, answered something else",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: ["maybe"],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: Update cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
    Run(
      name: "latest, answered nothing at all",
      command: .latest(remote: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", target: "v1.0"),
      typed: [],
      hasPath: true,
      recalls: true,
      linkComesUp: true,
      answer: .bytes(Data(pythonHex: "00")!),
      written:
        "Requesting path... \rPath resolved      \rEstablishing link... \rLink established     \r                       \rAre you sure you want to set v1.0 as the latest release? [y/N]: Update cancelled\n",
      aborted: nil,
      sent: Sent(awaitHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", awaitTimeout: 1606.0),
      tornDown: true),
  ]

  /// Holds what the client wrote.
  private final class Recorder: RNGitClientOutput {
    var written = ""
    func write(_ text: String) { written += text }
  }

  /// Answers a client's prompts with the lines one run says were typed.
  private final class Typist: RNGitClientInput {
    private var lines: [String]
    init(_ lines: [String]) { self.lines = lines }
    func readLine() -> String? { lines.isEmpty ? nil : lines.removeFirst() }
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

  func testReleaseCommandsMatchTheReference() throws {
    for run in Self.runs {
      let output = Recorder()
      let transport = Stub(run)
      let commands = RNGitClientCommands(
        rendering: RNGitReleaseRendering(timeZone: TimeZone(identifier: "UTC")!),
        transport: transport, output: output, input: Typist(run.typed))

      var aborted: String?
      do {
        switch run.command {
        case .list(let remote): try commands.listReleases(remote: remote)
        case .view(let remote, let target):
          try commands.viewRelease(remote: remote, target: target)
        case .delete(let remote, let target):
          try commands.deleteRelease(remote: remote, target: target)
        case .latest(let remote, let target):
          try commands.latestRelease(remote: remote, target: target)
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

}
