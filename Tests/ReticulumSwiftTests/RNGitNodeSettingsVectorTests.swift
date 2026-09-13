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

/// Settings an `rngit` node takes from its configuration file, as Python RNS 1.5.4 reads them.
///
/// Each configuration is read at two verbosities, since the file's log level is offset by the
/// verbosity the node was started with.
final class RNGitNodeSettingsVectorTests: XCTestCase {

  /// Settings holding the given fields over the node's own defaults.
  private static func expected(
    nodeName: String = "Anonymous Git Node", announceInterval: Int = 0,
    mirrorInterval: Int = 86400, statsEnabled: Bool = false, statsIgnored: [String] = [],
    statsPushIgnored: [String] = [], blockedIdentities: [String] = [], logLevel: Int? = nil,
    serveNomadNet: Bool = false, identityAliases: [String: String] = [:]
  ) -> RNGitNodeSettings {
    var settings = RNGitNodeSettings()
    settings.nodeName = nodeName
    settings.announceInterval = announceInterval
    settings.mirrorInterval = mirrorInterval
    settings.statsEnabled = statsEnabled
    settings.statsIgnored = Set(statsIgnored.compactMap { Data(pythonHex: $0) })
    settings.statsPushIgnored = Set(statsPushIgnored.compactMap { Data(pythonHex: $0) })
    settings.blockedIdentities = Set(blockedIdentities.compactMap { Data(pythonHex: $0) })
    settings.logLevel = logLevel
    settings.serveNomadNet = serveNomadNet
    settings.identityAliases = identityAliases
    return settings
  }

  /// Each configuration with the settings the reference read from it at one verbosity.
  private static let files:
    [(name: String, text: String, verbosity: Int, settings: RNGitNodeSettings)] = [
      (
        "empty", "", 0,
        expected()
      ),
      (
        "empty", "", 2,
        expected()
      ),
      (
        "node name", "[rngit]\nnode_name = My Node\n", 0,
        expected(nodeName: "My Node")
      ),
      (
        "node name", "[rngit]\nnode_name = My Node\n", 2,
        expected(nodeName: "My Node")
      ),
      (
        "node name quoted", "[rngit]\nnode_name = \"My  Node\"\n", 0,
        expected(nodeName: "My  Node")
      ),
      (
        "node name quoted", "[rngit]\nnode_name = \"My  Node\"\n", 2,
        expected(nodeName: "My  Node")
      ),
      (
        "announce interval", "[rngit]\nannounce_interval = 30\n", 0,
        expected(announceInterval: 1800)
      ),
      (
        "announce interval", "[rngit]\nannounce_interval = 30\n", 2,
        expected(announceInterval: 1800)
      ),
      (
        "announce zero", "[rngit]\nannounce_interval = 0\n", 0,
        expected()
      ),
      (
        "announce zero", "[rngit]\nannounce_interval = 0\n", 2,
        expected()
      ),
      (
        "announce negative", "[rngit]\nannounce_interval = -5\n", 0,
        expected(announceInterval: -300)
      ),
      (
        "announce negative", "[rngit]\nannounce_interval = -5\n", 2,
        expected(announceInterval: -300)
      ),
      (
        "mirror interval", "[rngit]\nmirror_interval = 6\n", 0,
        expected(mirrorInterval: 21600)
      ),
      (
        "mirror interval", "[rngit]\nmirror_interval = 6\n", 2,
        expected(mirrorInterval: 21600)
      ),
      (
        "mirror zero", "[rngit]\nmirror_interval = 0\n", 0,
        expected(mirrorInterval: 0)
      ),
      (
        "mirror zero", "[rngit]\nmirror_interval = 0\n", 2,
        expected(mirrorInterval: 0)
      ),
      (
        "mirror negative", "[rngit]\nmirror_interval = -3\n", 0,
        expected(mirrorInterval: 0)
      ),
      (
        "mirror negative", "[rngit]\nmirror_interval = -3\n", 2,
        expected(mirrorInterval: 0)
      ),
      (
        "record stats on", "[rngit]\nrecord_stats = yes\n", 0,
        expected(statsEnabled: true)
      ),
      (
        "record stats on", "[rngit]\nrecord_stats = yes\n", 2,
        expected(statsEnabled: true)
      ),
      (
        "record stats off", "[rngit]\nrecord_stats = no\n", 0,
        expected()
      ),
      (
        "record stats off", "[rngit]\nrecord_stats = no\n", 2,
        expected()
      ),
      (
        "stats ignore one", "[rngit]\nstats_ignore_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
        0,
        expected(statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "stats ignore one", "[rngit]\nstats_ignore_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
        2,
        expected(statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "stats ignore list",
        "[rngit]\nstats_ignore_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        0,
        expected(
          statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
        )
      ),
      (
        "stats ignore list",
        "[rngit]\nstats_ignore_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        2,
        expected(
          statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
        )
      ),
      (
        "stats ignore short", "[rngit]\nstats_ignore_identities = aabb\n", 0,
        expected()
      ),
      (
        "stats ignore short", "[rngit]\nstats_ignore_identities = aabb\n", 2,
        expected()
      ),
      (
        "stats ignore bad", "[rngit]\nstats_ignore_identities = zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n",
        0,
        expected()
      ),
      (
        "stats ignore bad", "[rngit]\nstats_ignore_identities = zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n",
        2,
        expected()
      ),
      (
        "stats push ignore",
        "[rngit]\nstats_push_ignore_identities = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", 0,
        expected(statsPushIgnored: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"])
      ),
      (
        "stats push ignore",
        "[rngit]\nstats_push_ignore_identities = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", 2,
        expected(statsPushIgnored: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"])
      ),
      (
        "blocked one", "[rngit]\nblocked_identities = cccccccccccccccccccccccccccccccc\n", 0,
        expected(blockedIdentities: ["cccccccccccccccccccccccccccccccc"])
      ),
      (
        "blocked one", "[rngit]\nblocked_identities = cccccccccccccccccccccccccccccccc\n", 2,
        expected(blockedIdentities: ["cccccccccccccccccccccccccccccccc"])
      ),
      (
        "blocked list",
        "[rngit]\nblocked_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, cccccccccccccccccccccccccccccccc\n",
        0,
        expected(
          blockedIdentities: [
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "cccccccccccccccccccccccccccccccc",
          ]
        )
      ),
      (
        "blocked list",
        "[rngit]\nblocked_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, cccccccccccccccccccccccccccccccc\n",
        2,
        expected(
          blockedIdentities: [
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "cccccccccccccccccccccccccccccccc",
          ]
        )
      ),
      (
        "blocked duplicate",
        "[rngit]\nblocked_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
        0,
        expected(blockedIdentities: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "blocked duplicate",
        "[rngit]\nblocked_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n",
        2,
        expected(blockedIdentities: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "alias", "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 0,
        expected(identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "alias", "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 2,
        expected(identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "alias several",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nsue = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        0,
        expected(
          identityAliases: [
            "bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "sue": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          ]
        )
      ),
      (
        "alias several",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nsue = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        2,
        expected(
          identityAliases: [
            "bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "sue": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          ]
        )
      ),
      (
        "alias upper", "[aliases]\nbob = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n", 0,
        expected(identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "alias upper", "[aliases]\nbob = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n", 2,
        expected(identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "alias short", "[aliases]\nbob = aabb\n", 0,
        expected()
      ),
      (
        "alias short", "[aliases]\nbob = aabb\n", 2,
        expected()
      ),
      (
        "alias not hex", "[aliases]\nbob = zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n", 0,
        expected()
      ),
      (
        "alias not hex", "[aliases]\nbob = zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\n", 2,
        expected()
      ),
      (
        "alias spaces", "[aliases]\nbob =                                 \n", 0,
        expected()
      ),
      (
        "alias spaces", "[aliases]\nbob =                                 \n", 2,
        expected()
      ),
      (
        "alias reserved", "[aliases]\nall = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 0,
        expected()
      ),
      (
        "alias reserved", "[aliases]\nall = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 2,
        expected()
      ),
      (
        "alias reserved upper", "[aliases]\nALL = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 0,
        expected(identityAliases: ["ALL": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "alias reserved upper", "[aliases]\nALL = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 2,
        expected(identityAliases: ["ALL": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"])
      ),
      (
        "alias named like hash",
        "[aliases]\nbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 0,
        expected(
          identityAliases: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
      (
        "alias named like hash",
        "[aliases]\nbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 2,
        expected(
          identityAliases: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
      (
        "alias short keyword", "[aliases]\nn = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 0,
        expected()
      ),
      (
        "alias short keyword", "[aliases]\nn = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 2,
        expected()
      ),
      (
        "alias then blocked",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n[rngit]\nblocked_identities = bob\n", 0,
        expected(
          blockedIdentities: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
          identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
      (
        "alias then blocked",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n[rngit]\nblocked_identities = bob\n", 2,
        expected(
          blockedIdentities: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
          identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
      (
        "alias then stats",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n[rngit]\nstats_ignore_identities = bob, bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        0,
        expected(
          statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
          identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
      (
        "alias then stats",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n[rngit]\nstats_ignore_identities = bob, bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        2,
        expected(
          statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
          identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
      (
        "unknown alias target", "[rngit]\nblocked_identities = nobody\n", 0,
        expected()
      ),
      (
        "unknown alias target", "[rngit]\nblocked_identities = nobody\n", 2,
        expected()
      ),
      (
        "blocked keyword", "[rngit]\nblocked_identities = all\n", 0,
        expected()
      ),
      (
        "blocked keyword", "[rngit]\nblocked_identities = all\n", 2,
        expected()
      ),
      (
        "loglevel", "[logging]\nloglevel = 4\n", 0,
        expected(logLevel: 4)
      ),
      (
        "loglevel", "[logging]\nloglevel = 4\n", 2,
        expected(logLevel: 6)
      ),
      (
        "loglevel high", "[logging]\nloglevel = 99\n", 0,
        expected(logLevel: 8)
      ),
      (
        "loglevel high", "[logging]\nloglevel = 99\n", 2,
        expected(logLevel: 8)
      ),
      (
        "loglevel low", "[logging]\nloglevel = -99\n", 0,
        expected(logLevel: -1)
      ),
      (
        "loglevel low", "[logging]\nloglevel = -99\n", 2,
        expected(logLevel: -1)
      ),
      (
        "serve nomadnet", "[pages]\nserve_nomadnet = yes\n", 0,
        expected(serveNomadNet: true)
      ),
      (
        "serve nomadnet", "[pages]\nserve_nomadnet = yes\n", 2,
        expected(serveNomadNet: true)
      ),
      (
        "serve nomadnet off", "[pages]\nserve_nomadnet = no\n", 0,
        expected()
      ),
      (
        "serve nomadnet off", "[pages]\nserve_nomadnet = no\n", 2,
        expected()
      ),
      (
        "empty sections", "[rngit]\n[aliases]\n[logging]\n[pages]\n", 0,
        expected()
      ),
      (
        "empty sections", "[rngit]\n[aliases]\n[logging]\n[pages]\n", 2,
        expected()
      ),
      (
        "alias blank", "[aliases]\nbob = \"                                \"\n", 0,
        expected()
      ),
      (
        "alias blank", "[aliases]\nbob = \"                                \"\n", 2,
        expected()
      ),
      (
        "alias list value",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", 0,
        expected()
      ),
      (
        "alias list value",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n", 2,
        expected()
      ),
      (
        "node name empty", "[rngit]\nnode_name =\n", 0,
        expected(nodeName: "")
      ),
      (
        "node name empty", "[rngit]\nnode_name =\n", 2,
        expected(nodeName: "")
      ),
      (
        "stats ignore list value",
        "[rngit]\nstats_ignore_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, bob\n[aliases]\nbob = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        0,
        expected(
          statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
          identityAliases: ["bob": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
        )
      ),
      (
        "stats ignore list value",
        "[rngit]\nstats_ignore_identities = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, bob\n[aliases]\nbob = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        2,
        expected(
          statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
          identityAliases: ["bob": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
        )
      ),
      (
        "stats ignore blank",
        "[rngit]\nstats_ignore_identities = \"                                \"\n", 0,
        expected(statsIgnored: [""])
      ),
      (
        "stats ignore blank",
        "[rngit]\nstats_ignore_identities = \"                                \"\n", 2,
        expected(statsIgnored: [""])
      ),
      (
        "stats ignore spaced hex",
        "[rngit]\nstats_ignore_identities = \"aa bb cc dd ee ff 00 11 22 33 44\"\n", 0,
        expected(statsIgnored: ["aabbccddeeff0011223344"])
      ),
      (
        "stats ignore spaced hex",
        "[rngit]\nstats_ignore_identities = \"aa bb cc dd ee ff 00 11 22 33 44\"\n", 2,
        expected(statsIgnored: ["aabbccddeeff0011223344"])
      ),
      (
        "alias spaced hex", "[aliases]\nbob = \"aa bb cc dd ee ff 00 11 22 33 44\"\n", 0,
        expected(identityAliases: ["bob": "aabbccddeeff0011223344"])
      ),
      (
        "alias spaced hex", "[aliases]\nbob = \"aa bb cc dd ee ff 00 11 22 33 44\"\n", 2,
        expected(identityAliases: ["bob": "aabbccddeeff0011223344"])
      ),
      (
        "alias case differs",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nBOB = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        0,
        expected(
          identityAliases: [
            "bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "BOB": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          ]
        )
      ),
      (
        "alias case differs",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nBOB = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n",
        2,
        expected(
          identityAliases: [
            "bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "BOB": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          ]
        )
      ),
      (
        "alias unknown target", "[rngit]\nstats_ignore_identities = carol\n", 0,
        expected()
      ),
      (
        "alias unknown target", "[rngit]\nstats_ignore_identities = carol\n", 2,
        expected()
      ),
      (
        "alias after use",
        "[rngit]\nblocked_identities = bob\n[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 0,
        expected(
          blockedIdentities: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
          identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
      (
        "alias after use",
        "[rngit]\nblocked_identities = bob\n[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", 2,
        expected(
          blockedIdentities: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
          identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
      (
        "loglevel clamp high", "[logging]\nloglevel = 7\n", 0,
        expected(logLevel: 7)
      ),
      (
        "loglevel clamp high", "[logging]\nloglevel = 7\n", 2,
        expected(logLevel: 8)
      ),
      (
        "loglevel clamp low", "[logging]\nloglevel = -1\n", 0,
        expected(logLevel: -1)
      ),
      (
        "loglevel clamp low", "[logging]\nloglevel = -1\n", 2,
        expected(logLevel: 1)
      ),
      (
        "mirror large", "[rngit]\nmirror_interval = 100000\n", 0,
        expected(mirrorInterval: 360_000_000)
      ),
      (
        "mirror large", "[rngit]\nmirror_interval = 100000\n", 2,
        expected(mirrorInterval: 360_000_000)
      ),
      (
        "everything",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n[rngit]\nnode_name = Full\nannounce_interval = 15\nmirror_interval = 2\nrecord_stats = yes\nstats_ignore_identities = bob\nstats_push_ignore_identities = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\nblocked_identities = cccccccccccccccccccccccccccccccc\n[logging]\nloglevel = 6\n[pages]\nserve_nomadnet = yes\n",
        0,
        expected(
          nodeName: "Full",
          announceInterval: 900,
          mirrorInterval: 7200,
          statsEnabled: true,
          statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
          statsPushIgnored: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
          blockedIdentities: ["cccccccccccccccccccccccccccccccc"],
          logLevel: 6,
          serveNomadNet: true,
          identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
      (
        "everything",
        "[aliases]\nbob = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n[rngit]\nnode_name = Full\nannounce_interval = 15\nmirror_interval = 2\nrecord_stats = yes\nstats_ignore_identities = bob\nstats_push_ignore_identities = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\nblocked_identities = cccccccccccccccccccccccccccccccc\n[logging]\nloglevel = 6\n[pages]\nserve_nomadnet = yes\n",
        2,
        expected(
          nodeName: "Full",
          announceInterval: 900,
          mirrorInterval: 7200,
          statsEnabled: true,
          statsIgnored: ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],
          statsPushIgnored: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
          blockedIdentities: ["cccccccccccccccccccccccccccccccc"],
          logLevel: 8,
          serveNomadNet: true,
          identityAliases: ["bob": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
        )
      ),
    ]

  /// Each configuration the reference refused, having asked a value for the wrong type.
  private static let refused: [(name: String, text: String)] = [
    ("announce not integer", "[rngit]\nannounce_interval = soon\n"),
    ("mirror not integer", "[rngit]\nmirror_interval = never\n"),
    ("record stats not boolean", "[rngit]\nrecord_stats = maybe\n"),
    ("loglevel not integer", "[logging]\nloglevel = loud\n"),
    ("serve not boolean", "[pages]\nserve_nomadnet = perhaps\n"),
    ("announce empty", "[rngit]\nannounce_interval =\n"),
    ("mirror empty", "[rngit]\nmirror_interval =\n"),
    ("record stats empty", "[rngit]\nrecord_stats =\n"),
    ("loglevel empty", "[logging]\nloglevel =\n"),
    ("serve empty", "[pages]\nserve_nomadnet =\n"),
  ]

  /// Every configuration yields the settings the reference took from it.
  func testSettingsMatchTheReference() throws {
    for vector in Self.files {
      let configuration = try RNGitConfigFile.parse(vector.text)
      let settings = try RNGitNodeSettings(
        configuration: configuration, verbosity: vector.verbosity)
      XCTAssertEqual(settings, vector.settings, "\(vector.name) at \(vector.verbosity)")
    }
  }

  /// Every configuration the reference refused is refused here.
  func testRefusedSettingsMatchTheReference() throws {
    for vector in Self.refused {
      let configuration = try RNGitConfigFile.parse(vector.text)
      XCTAssertThrowsError(try RNGitNodeSettings(configuration: configuration), vector.name) {
        XCTAssertTrue($0 is RNGitSettingsError, vector.name)
      }
    }
  }
}
