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

/// How an `rngit` client writes out what a node said about releases.
public struct RNGitReleaseRendering: Sendable {

  /// The time zone the client dates a release in.
  public var timeZone: TimeZone

  /// Creates the rendering, which dates a release in `timeZone`.
  public init(timeZone: TimeZone = .current) {
    self.timeZone = timeZone
  }

  /// The table the releases `value` holds read as, or `nil` where it holds no releases at all.
  public func listing(_ value: MsgPack.Value) -> String? {
    var releases: [MsgPack.Value]
    var latest: String?

    if let items = value.asArray {
      releases = items
    } else if let fields = value.asDictionary {
      releases = fields["releases"]?.asArray ?? []
      latest = fields["latest"]?.asString
    } else {
      return nil
    }

    guard !releases.isEmpty else { return "No releases for this repository\n" }

    var text =
      "Tag".pythonPadded(10) + " " + "Status".pythonPadded(10) + " "
      + "Created".pythonPadded(17) + " " + "Objs".pythonPadded(5) + " Notes\n"
    text += String(repeating: "-", count: 80) + "\n"

    for release in releases {
      let fields = release.asDictionary ?? [:]
      let tag = (fields["tag"]?.asString ?? Self.unknown).pythonPrefix(10)
      let status = (fields["status"]?.asString ?? Self.unknown).pythonPrefix(9)
      let created = fields["created"]?.asInt ?? 0
      let when = created == 0 ? Self.unknown : dated(created, as: "yyyy-MM-dd HH:mm")
      let objects = String(fields["artifacts"]?.asInt ?? 0)
      let preview = (fields["preview"]?.asString ?? "").pythonLines.first ?? ""
      text +=
        tag.pythonPadded(10) + " " + status.pythonPadded(10) + " " + when.pythonPadded(17) + " "
        + objects.pythonPadded(5) + " " + preview.pythonPrefix(34) + "\n"
    }

    if let latest, !latest.isEmpty { text += "\nThe latest release is: \(latest)\n" }
    return text
  }

  /// The release `value` holds read as, where the client asked after `target`.
  public func view(_ value: MsgPack.Value, target: String) -> String {
    let fields = value.asDictionary ?? [:]

    var text = "Release : \(fields["tag"]?.asString ?? target)\n"
    text += "Status  : \(fields["status"]?.asString ?? Self.unknown)\n"
    let created = fields["created"]?.asInt ?? 0
    if created != 0 { text += "Created : \(dated(created, as: "yyyy-MM-dd HH:mm:ss"))\n" }
    text += "Thanks  : \(fields["thanks"]?.asInt ?? 0)\n"

    let notes = fields["notes"]?.asString ?? ""
    if !notes.isEmpty { text += "\nRelease Notes\n=============\n\n\(notes)\n" }

    let artifacts = fields["artifacts"]?.asArray ?? []
    if !artifacts.isEmpty {
      let heading = "Artifacts (\(artifacts.count))"
      text += "\n" + heading + "\n" + String(repeating: "=", count: heading.count) + "\n"
      for artifact in artifacts {
        let named = artifact.asDictionary ?? [:]
        let measured = RNSUtilities.prettysize(named["size"]?.asInt ?? 0)
        text += " - \(named["name"]?.asString ?? Self.unknown) (\(measured))\n"
      }
    }

    return text + "\n"
  }

  /// The instant `seconds` names, written the way a manifest carries it.
  public func stamped(_ seconds: Int) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
  }

  /// What the client writes where a release names no tag, status, time or artifact.
  private static let unknown = "unknown"

  /// `seconds` since the epoch written out in `format`.
  func dated(_ seconds: Int, as format: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
  }
}

extension String {

  /// The first `count` characters Python would take off the front of this string.
  func pythonPrefix(_ count: Int) -> String {
    String(String.UnicodeScalarView(unicodeScalars.prefix(count)))
  }

  /// This string with spaces added on the right until it is `width` characters wide.
  func pythonPadded(_ width: Int) -> String {
    let length = unicodeScalars.count
    return length >= width ? self : self + String(repeating: " ", count: width - length)
  }
}
