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

/// What an `rngit` client makes of its configuration file and of a remote URL, as Python RNS
/// 1.5.4 makes it.
///
/// Every expectation is what the reference answered for the same configuration text, alias table
/// and URL.
final class RNGitClientVectorTests: XCTestCase {

  private struct Settings {
    let name: String
    let configuration: String
    let logLevel: Int?
    let aliases: [String: String]
  }

  private struct Resolved {
    let name: String
    let alias: String
    let aliases: [String: String]
    let answer: String
  }

  private enum Named {
    case repository(group: String, repository: String)
    case group(String)
    case destination
  }

  private struct Remote {
    let name: String
    let named: Named
    let url: String
    let aliases: [String: String]
    let destination: String?
    let message: String?
  }

  private static let settings: [Settings] = [
    Settings(
      name: "nothing configured", configuration: "",
      logLevel: nil, aliases: [:]),
    Settings(
      name: "log level taken", configuration: "[logging]\nloglevel = 4\n",
      logLevel: 4, aliases: [:]),
    Settings(
      name: "log level clamped low", configuration: "[logging]\nloglevel = -5\n",
      logLevel: -1, aliases: [:]),
    Settings(
      name: "log level clamped high", configuration: "[logging]\nloglevel = 99\n",
      logLevel: 8, aliases: [:]),
    Settings(
      name: "log level left out", configuration: "[logging]\n",
      logLevel: nil, aliases: [:]),
    Settings(
      name: "alias taken", configuration: "[aliases]\nbob = cccccccccccccccccccccccccccccccc\n",
      logLevel: nil, aliases: ["bob": "cccccccccccccccccccccccccccccccc"]),
    Settings(
      name: "alias lowercased",
      configuration: "[aliases]\nbob = CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC\n",
      logLevel: nil, aliases: ["bob": "cccccccccccccccccccccccccccccccc"]),
    Settings(
      name: "alias too short", configuration: "[aliases]\nbob = aabb\n",
      logLevel: nil, aliases: [:]),
    Settings(
      name: "alias not hexadecimal",
      configuration: "[aliases]\nbob = zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n",
      logLevel: nil, aliases: [:]),
    Settings(
      name: "alias reserved name",
      configuration: "[aliases]\nnobody = cccccccccccccccccccccccccccccccc\n",
      logLevel: nil, aliases: ["nobody": "cccccccccccccccccccccccccccccccc"]),
    Settings(
      name: "alias every reserved name",
      configuration:
        "[aliases]\nn = cccccccccccccccccccccccccccccccc\nnone = cccccccccccccccccccccccccccccccc\nnobody = cccccccccccccccccccccccccccccccc\na = cccccccccccccccccccccccccccccccc\nall = cccccccccccccccccccccccccccccccc\neveryone = cccccccccccccccccccccccccccccccc\n",
      logLevel: nil,
      aliases: [
        "a": "cccccccccccccccccccccccccccccccc", "all": "cccccccccccccccccccccccccccccccc",
        "everyone": "cccccccccccccccccccccccccccccccc", "n": "cccccccccccccccccccccccccccccccc",
        "nobody": "cccccccccccccccccccccccccccccccc", "none": "cccccccccccccccccccccccccccccccc",
      ]),
    Settings(
      name: "alias holding a list",
      configuration:
        "[aliases]\nbob = cccccccccccccccccccccccccccccccc, bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
      logLevel: nil, aliases: [:]),
    Settings(
      name: "alias opening a section",
      configuration: "[aliases]\n[[bob]]\nhash = cccccccccccccccccccccccccccccccc\n",
      logLevel: nil, aliases: [:]),
    Settings(
      name: "alias of spaces",
      configuration: "[aliases]\nbob = \"                                \"\n",
      logLevel: nil, aliases: [:]),
    Settings(
      name: "alias spaced short",
      configuration: "[aliases]\nbob = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  \"\n",
      logLevel: nil, aliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]),
    Settings(
      name: "two aliases taken",
      configuration:
        "[aliases]\nbob = cccccccccccccccccccccccccccccccc\nalice = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
      logLevel: nil,
      aliases: [
        "alice": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "bob": "cccccccccccccccccccccccccccccccc",
      ]),
    Settings(
      name: "aliases and log level",
      configuration: "[logging]\nloglevel = 2\n[aliases]\nbob = cccccccccccccccccccccccccccccccc\n",
      logLevel: 2, aliases: ["bob": "cccccccccccccccccccccccccccccccc"]),
    Settings(
      name: "other section passed over",
      configuration:
        "[client]\nref_batch_size = 100\n[aliases]\nbob = cccccccccccccccccccccccccccccccc\n",
      logLevel: nil, aliases: ["bob": "cccccccccccccccccccccccccccccccc"]),
  ]

  private static let resolved: [Resolved] = [
    Resolved(
      name: "spelled out hash", alias: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      aliases: [:], answer: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    Resolved(
      name: "known alias", alias: "bob",
      aliases: ["bob": "cccccccccccccccccccccccccccccccc"],
      answer: "cccccccccccccccccccccccccccccccc"),
    Resolved(
      name: "unknown alias", alias: "carol",
      aliases: ["bob": "cccccccccccccccccccccccccccccccc"], answer: "carol"),
    Resolved(
      name: "reserved name aliased", alias: "nobody",
      aliases: ["nobody": "cccccccccccccccccccccccccccccccc"],
      answer: "cccccccccccccccccccccccccccccccc"),
    Resolved(
      name: "reserved name unaliased", alias: "nobody",
      aliases: [:], answer: "nobody"),
    Resolved(
      name: "hash length of spaces", alias: "                                ",
      aliases: ["                                ": "cccccccccccccccccccccccccccccccc"],
      answer: "cccccccccccccccccccccccccccccccc"),
    Resolved(
      name: "uppercase hash", alias: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      aliases: [:], answer: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"),
    Resolved(
      name: "empty name", alias: "",
      aliases: ["": "cccccccccccccccccccccccccccccccc"], answer: "cccccccccccccccccccccccccccccccc"),
    Resolved(
      name: "short hexadecimal name", alias: "aabb",
      aliases: ["aabb": "cccccccccccccccccccccccccccccccc"],
      answer: "cccccccccccccccccccccccccccccccc"),
    Resolved(
      name: "long hexadecimal name", alias: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      aliases: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": "cccccccccccccccccccccccccccccccc"],
      answer: "cccccccccccccccccccccccccccccccc"),
  ]

  private static let remotes: [Remote] = [
    Remote(
      name: "repository url", named: Named.repository(group: "group", repository: "repo"),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "repository url uppercase scheme",
      named: Named.repository(group: "group", repository: "repo"),
      url: "RNS://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "repository url mixed scheme",
      named: Named.repository(group: "group", repository: "repo"),
      url: "Rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "repository url aliased", named: Named.repository(group: "group", repository: "repo"),
      url: "rns://bob/group/repo", aliases: ["bob": "cccccccccccccccccccccccccccccccc"],
      destination: "cccccccccccccccccccccccccccccccc", message: nil),
    Remote(
      name: "repository url wrong scheme", named: Named.repository(group: "", repository: ""),
      url: "http://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", aliases: [:],
      destination: nil, message: "Invalid protocol in remote URL"),
    Remote(
      name: "repository url no scheme", named: Named.repository(group: "", repository: ""),
      url: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", aliases: [:],
      destination: nil, message: "Invalid protocol in remote URL"),
    Remote(
      name: "repository url too few components", named: Named.repository(group: "", repository: ""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", aliases: [:],
      destination: nil, message: "Invalid number of URL components"),
    Remote(
      name: "repository url too many components",
      named: Named.repository(group: "", repository: ""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo/extra", aliases: [:],
      destination: nil, message: "Invalid number of URL components"),
    Remote(
      name: "repository url short hash", named: Named.repository(group: "", repository: ""),
      url: "rns://aabb/group/repo", aliases: [:],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "repository url unknown alias", named: Named.repository(group: "", repository: ""),
      url: "rns://bob/group/repo", aliases: [:],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "repository url bad digit", named: Named.repository(group: "", repository: ""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaz/group/repo", aliases: [:],
      destination: nil,
      message:
        "Invalid destination hash: non-hexadecimal number found in fromhex() arg at position 31"),
    Remote(
      name: "repository url spaced digit", named: Named.repository(group: "", repository: ""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa /group/repo", aliases: [:],
      destination: nil,
      message:
        "Invalid destination hash: non-hexadecimal number found in fromhex() arg at position 31"),
    Remote(
      name: "repository url uppercase hash",
      named: Named.repository(group: "group", repository: "repo"),
      url: "rns://AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/group/repo", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "repository url empty names", named: Named.repository(group: "", repository: ""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa//", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "group url", named: Named.group("group"),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "group url aliased", named: Named.group("group"),
      url: "rns://bob/group", aliases: ["bob": "cccccccccccccccccccccccccccccccc"],
      destination: "cccccccccccccccccccccccccccccccc", message: nil),
    Remote(
      name: "group url too few components", named: Named.group(""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", aliases: [:],
      destination: nil, message: "Invalid number of URL components"),
    Remote(
      name: "group url too many components", named: Named.group(""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", aliases: [:],
      destination: nil, message: "Invalid number of URL components"),
    Remote(
      name: "group url wrong scheme", named: Named.group(""),
      url: "git://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group", aliases: [:],
      destination: nil, message: "Invalid protocol in remote URL"),
    Remote(
      name: "group url short hash", named: Named.group(""),
      url: "rns://aabb/group", aliases: [:],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "group url empty name", named: Named.group(""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "destination url", named: Named.destination,
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "destination url aliased", named: Named.destination,
      url: "rns://bob", aliases: ["bob": "cccccccccccccccccccccccccccccccc"],
      destination: "cccccccccccccccccccccccccccccccc", message: nil),
    Remote(
      name: "destination url trailing components", named: Named.destination,
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "destination url nothing named", named: Named.destination,
      url: "rns://", aliases: [:],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "destination url wrong scheme", named: Named.destination,
      url: "rnss://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", aliases: [:],
      destination: nil, message: "Invalid protocol in remote URL"),
    Remote(
      name: "destination url short hash", named: Named.destination,
      url: "rns://aabb", aliases: [:],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "destination url bad digit", named: Named.destination,
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaz", aliases: [:],
      destination: nil,
      message:
        "Invalid destination hash: non-hexadecimal number found in fromhex() arg at position 31"),
    Remote(
      name: "repository url counted before length",
      named: Named.repository(group: "", repository: ""),
      url: "rns://aabb/group", aliases: [:],
      destination: nil, message: "Invalid number of URL components"),
    Remote(
      name: "repository url counted before digits",
      named: Named.repository(group: "", repository: ""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaz/group/repo/extra", aliases: [:],
      destination: nil, message: "Invalid number of URL components"),
    Remote(
      name: "repository url aliased to short hash",
      named: Named.repository(group: "", repository: ""),
      url: "rns://bob/group/repo", aliases: ["bob": "aabb"],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "repository url aliased to spaced hash",
      named: Named.repository(group: "", repository: ""),
      url: "rns://bob/group/repo", aliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "repository url aliased to bad digits",
      named: Named.repository(group: "", repository: ""),
      url: "rns://bob/group/repo", aliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaz"],
      destination: nil,
      message:
        "Invalid destination hash: non-hexadecimal number found in fromhex() arg at position 31"),
    Remote(
      name: "repository url alias keeps case", named: Named.repository(group: "", repository: ""),
      url: "RNS://BOB/group/repo", aliases: ["bob": "cccccccccccccccccccccccccccccccc"],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "repository url alias in second component",
      named: Named.repository(group: "bob", repository: "repo"),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/bob/repo",
      aliases: ["bob": "cccccccccccccccccccccccccccccccc"],
      destination: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "group url aliased to short hash", named: Named.group(""),
      url: "rns://bob/group", aliases: ["bob": "aabb"],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "destination url aliased to bad digits", named: Named.destination,
      url: "rns://bob", aliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaz"],
      destination: nil,
      message:
        "Invalid destination hash: non-hexadecimal number found in fromhex() arg at position 31"),
    Remote(
      name: "repository url long hash", named: Named.repository(group: "", repository: ""),
      url: "rns://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", aliases: [:],
      destination: nil, message: "Invalid destination hash length"),
    Remote(
      name: "repository url leading space", named: Named.repository(group: "", repository: ""),
      url: "rns:// aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/group/repo", aliases: [:],
      destination: nil,
      message:
        "Invalid destination hash: non-hexadecimal number found in fromhex() arg at position 32"),
    Remote(
      name: "repository url spaced pair",
      named: Named.repository(group: "group", repository: "repo"),
      url: "rns://aa aa aa aa aa aa aa aa aa aa aa/group/repo", aliases: [:],
      destination: "aaaaaaaaaaaaaaaaaaaaaa", message: nil),
    Remote(
      name: "repository url hexadecimal alias",
      named: Named.repository(group: "group", repository: "repo"),
      url: "rns://aabb/group/repo", aliases: ["aabb": "cccccccccccccccccccccccccccccccc"],
      destination: "cccccccccccccccccccccccccccccccc", message: nil),
  ]

  /// Every configuration is read into the same settings the reference read.
  func testSettingsMatchTheReference() throws {
    for vector in Self.settings {
      let configuration = try RNGitConfigFile.parse(vector.configuration)
      let read = try RNGitClientSettings(configuration: configuration)
      XCTAssertEqual(read.logLevel, vector.logLevel, vector.name)
      XCTAssertEqual(read.destinationAliases, vector.aliases, vector.name)
    }
  }

  /// Every name resolves to what the reference resolved it to.
  func testResolvedAliasesMatchTheReference() {
    for vector in Self.resolved {
      var settings = RNGitClientSettings()
      settings.destinationAliases = vector.aliases
      XCTAssertEqual(settings.resolving(vector.alias), vector.answer, vector.name)
    }
  }

  /// Every remote URL is read as the reference read it, down to the message it gave up with.
  func testRemoteURLsMatchTheReference() throws {
    for vector in Self.remotes {
      do {
        switch vector.named {
        case .repository(let group, let repository):
          let read = try RNGitRemoteURL.repository(vector.url, aliases: vector.aliases)
          XCTAssertEqual(read.destination.hexString, vector.destination, vector.name)
          XCTAssertEqual(read.group, group, vector.name)
          XCTAssertEqual(read.repository, repository, vector.name)
        case .group(let group):
          let read = try RNGitRemoteURL.group(vector.url, aliases: vector.aliases)
          XCTAssertEqual(read.destination.hexString, vector.destination, vector.name)
          XCTAssertEqual(read.group, group, vector.name)
        case .destination:
          let read = try RNGitRemoteURL.destination(vector.url, aliases: vector.aliases)
          XCTAssertEqual(read.hexString, vector.destination, vector.name)
        }
        XCTAssertNil(vector.message, vector.name)
      } catch let error as RNGitRemoteURLError {
        XCTAssertEqual(error.message, vector.message, vector.name)
      }
    }
  }
}
