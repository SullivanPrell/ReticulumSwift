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

extension RNGitPageHandler {

  /// The most of a release's first line of notes the releases page previews.
  public static let releasePreviewLength = 2048

  // MARK: - Releases page

  /// One repository's published releases, newest first, each with the first line of its notes
  /// and its creation day in `timeZone`—or nil where the reference raises and answers nothing.
  ///
  /// Mirrors `serve_releases_page` (`pages.py:1291-1355`). It raises on a published release
  /// with no notes to preview, since it takes the first of their lines without checking there
  /// is one. A repository with no releases at all is rendered through the `repo` template and
  /// counts no view.
  public mutating func serveReleasesPage(
    identityHash: Data?, groupName: String, repositoryName: String,
    timeZone: TimeZone = .current
  ) -> Data? {
    let startedAt = Date().timeIntervalSince1970

    guard !groupName.isEmpty, !repositoryName.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nInvalid request\n", startedAt: startedAt)
    }

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", template: RNGitPageTemplate.noIdentity.rawValue, startedAt: startedAt)
    }

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2)
          + "\nThe requested repository was not found.\n",
        startedAt: startedAt)
    }

    let navigation =
      ">>\n" + RNGitPageMicron.link("Node", RNGitPage.Path.index) + " / "
      + RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]) + " / "
      + RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)])
      + " / releases\n"

    let directory = RNGitReleaseStore.directory(forRepository: repository.path)
    guard let listing = RNGitReleaseStore.listing(directory), !listing.releases.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Releases", level: 2)
          + "\nNo releases available for this repository.\n",
        navigation: navigation, template: RNGitPageTemplate.repo.rawValue, startedAt: startedAt)
    }

    let published = listing.releases.compactMap(\.asDictionary).filter {
      $0["status"] == .string("published")
    }
    let rendering = RNGitReleaseRendering(timeZone: timeZone)
    let separator = RNGitPage.icon(.separator)

    var content = RNGitPageMicron.heading("Releases (\(published.count))", level: 2) + "\n"
    for release in published {
      let tag = release["tag"]?.pythonDescription ?? "unknown"
      let created = release["created"]?.asInt ?? 0
      let date = created != 0 ? rendering.dated(created, as: "yyyy-MM-dd") : "unknown"
      let artifacts = release["artifacts"]?.asInt ?? 0
      let format = release["format"]?.asString ?? "markdown"
      guard let firstLine = (release["preview"]?.asString ?? "").pythonLines.first else {
        return nil
      }
      var preview = firstLine.pythonPrefix(Self.releasePreviewLength)
      if firstLine.unicodeScalars.count > preview.unicodeScalars.count { preview += "\u{2026}" }

      let link = RNGitPageMicron.link(
        tag, RNGitPage.Path.release, [("g", groupName), ("r", repositoryName), ("t", tag)])
      let isLatest = listing.latest.map { release["tag"] == .string($0) } ?? false
      let latest = isLatest ? " \(separator) \(RNGitPage.Colour.okDim)`*Latest`*`f" : ""
      let counted = "`*\(artifacts) artifact\(artifacts != 1 ? "s" : "")`*"
      content += "\(link) \(RNGitPage.Colour.dim)\(date) \(separator) \(counted)\(latest)`f\n"
      if !preview.isEmpty {
        switch format {
        case "markdown": content += markdown.formatBlock(preview) + "\n"
        case "micron": content += preview + "\n"
        default: content += RNGitPageMicron.escape(preview) + "\n"
        }
      }
      content += "\n"
    }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    return templates.render(
      Self.rstripped(content) + "\n", navigation: navigation,
      template: RNGitPageTemplate.releases.rawValue, startedAt: startedAt)
  }

  // MARK: - Release page

  /// One published release: its thanks, creation moment in `timeZone`, notes and artifacts—or
  /// nil where the reference raises and answers nothing.
  ///
  /// Mirrors `serve_release_page` (`pages.py:1357-1459`). A `tag` of `latest` names the release
  /// the `latest` file names, or else the newest release whether published or not. The
  /// breadcrumb keeps the tag as it was asked for; everything below it names the one it
  /// resolved to. The reference raises when that resolution lands on a tag that is not a
  /// string. The release directory is joined as `os.path.join` joins it, so a tag opening with
  /// a separator stands on its own.
  public mutating func serveReleasePage(
    identityHash: Data?, groupName: String, repositoryName: String, tag requestedTag: String,
    thanksClicked: Bool = false, linkID: Data? = nil, timeZone: TimeZone = .current
  ) -> Data? {
    let startedAt = Date().timeIntervalSince1970

    guard !groupName.isEmpty, !repositoryName.isEmpty, !requestedTag.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nInvalid request\n", startedAt: startedAt)
    }

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", template: RNGitPageTemplate.noIdentity.rawValue, startedAt: startedAt)
    }

    guard
      let repository = access.repository(
        readableBy: identityHash, in: groupName, named: repositoryName)
    else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2)
          + "\nThe requested repository was not found.\n",
        startedAt: startedAt)
    }

    let navigation =
      ">>\n" + RNGitPageMicron.link("Node", RNGitPage.Path.index) + " / "
      + RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]) + " / "
      + RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)])
      + " / "
      + RNGitPageMicron.link(
        "releases", RNGitPage.Path.releases, [("g", groupName), ("r", repositoryName)])
      + " / " + requestedTag + "\n"

    func notFound(_ message: String) -> Data {
      templates.render(
        RNGitPageMicron.heading("Release Not Found", level: 2) + "\n" + message + "\n",
        navigation: navigation, startedAt: startedAt)
    }

    let releases = RNGitReleaseStore.directory(forRepository: repository.path)
    var tag = requestedTag
    if tag == "latest" {
      guard let listing = RNGitReleaseStore.listing(releases), !listing.releases.isEmpty else {
        return notFound("No releases exist.")
      }
      if let latest = listing.latest {
        tag = latest
      } else {
        guard let newest = listing.releases[0].asDictionary?["tag"]?.asString else { return nil }
        tag = newest
      }
    }

    let directory = RNGitReleaseHandler.joined(releases, tag)
    guard RNGitReleaseStore.isDirectory(directory) else {
      return notFound("The release \(tag) does not exist.")
    }
    guard let details = RNGitReleaseStore.details(directory, tag: tag)?.asDictionary else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nCould not load release data.\n",
        navigation: navigation, startedAt: startedAt)
    }
    guard details["status"] == .string("published") else {
      return notFound("The release \(tag) does not exist.")
    }

    let separator = RNGitPage.icon(.separator)
    let thanksCount = thanks.release(at: directory, thankedBy: thanksClicked ? linkID : nil)
    var content =
      RNGitPageMicron.requestLink(
        RNGitPage.icon(.heart) + " Thanks (\(thanksCount))", RNGitPage.Path.release,
        [("g", groupName), ("r", repositoryName), ("t", tag), ("thanks", "y")]) + "\n\n"

    let created = details["created"]?.asInt ?? 0
    let stamp =
      created != 0
      ? " \(separator) "
        + RNGitReleaseRendering(timeZone: timeZone).dated(created, as: "yyyy-MM-dd HH:mm:ss")
      : ""
    content += RNGitPageMicron.heading("Release \(tag)\(stamp)", level: 2) + "\n"

    let notes = details["notes"]?.asString ?? ""
    if !notes.isEmpty {
      switch details["notes_format"]?.asString ?? "text" {
      case "micron": content += notes + "\n"
      case "markdown": content += markdown.formatBlock(notes) + "\n"
      default: content += "`=" + notes + "`=\n"
      }
      content += "\n"
    }

    let artifacts = (details["artifacts"]?.asArray ?? []).compactMap(\.asDictionary)
    if artifacts.isEmpty {
      content += RNGitPageMicron.heading("Artifacts", level: 2)
      content += "\n`*No artifacts for this release`*\n"
    } else {
      content += RNGitPageMicron.heading("Artifacts (\(artifacts.count))", level: 2) + "\n"
      var byName: [String: [String: MsgPack.Value]] = [:]
      for artifact in artifacts { byName[artifact["name"]?.asString ?? "unknown"] = artifact }
      for name in RNGitPage.sorted(byName.keys) {
        let size = byName[name]?["size"]?.asInt ?? 0
        let measured = size != 0 ? RNSUtilities.prettysize(size) : "0 B"
        let fields = [("g", groupName), ("r", repositoryName), ("t", tag), ("a", name)]
        let named = RNGitPageMicron.requestLink(
          RNGitPage.icon(.file) + " " + RNGitPageMicron.escape(name), RNGitPage.Path.artifact,
          fields)
        let sized = RNGitPageMicron.requestLink("(\(measured))", RNGitPage.Path.artifact, fields)
        content += "\(named) \(RNGitPage.Colour.dim)\(sized)`f\n"
      }
    }

    viewSucceeded(group: groupName, repository: repositoryName, for: identityHash)

    return templates.render(
      content, navigation: navigation, template: RNGitPageTemplate.release.rawValue,
      startedAt: startedAt)
  }

  /// The converter release notes are written through, pointing links at the node's own pages.
  private var markdown: MarkdownToMicron {
    MarkdownToMicron(maxWidth: RNGitPage.maxRenderWidth, syntaxHighlighter: syntaxHighlighter)
  }
}
