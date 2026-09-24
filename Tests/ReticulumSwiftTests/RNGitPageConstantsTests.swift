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

/// What a page node is built around, as Python RNS 1.5.4 declares it.
final class RNGitPageConstantsTests: XCTestCase {

  /// Every page is served at the path the reference names it by.
  func testEveryPathMatchesTheReference() {
    XCTAssertEqual(RNGitPage.Path.index, "/page/index.mu")
    XCTAssertEqual(RNGitPage.Path.group, "/page/group.mu")
    XCTAssertEqual(RNGitPage.Path.repository, "/page/repo.mu")
    XCTAssertEqual(RNGitPage.Path.tree, "/page/tree.mu")
    XCTAssertEqual(RNGitPage.Path.blob, "/page/blob.mu")
    XCTAssertEqual(RNGitPage.Path.commits, "/page/commits.mu")
    XCTAssertEqual(RNGitPage.Path.commit, "/page/commit.mu")
    XCTAssertEqual(RNGitPage.Path.refs, "/page/refs.mu")
    XCTAssertEqual(RNGitPage.Path.stats, "/page/stats.mu")
    XCTAssertEqual(RNGitPage.Path.releases, "/page/releases.mu")
    XCTAssertEqual(RNGitPage.Path.release, "/page/release.mu")
    XCTAssertEqual(RNGitPage.Path.work, "/page/work.mu")
    XCTAssertEqual(RNGitPage.Path.workDocument, "/page/work_doc.mu")
    XCTAssertEqual(RNGitPage.Path.media, "/media")
    XCTAssertEqual(RNGitPage.Path.artifact, "/file/artifact")
    XCTAssertEqual(RNGitPage.Path.download, "/file/download")
    XCTAssertEqual(RNGitPage.Path.workDocumentFile, "/file/workdoc")
  }

  /// Every limit and name matches the reference.
  func testEveryLimitMatchesTheReference() {
    XCTAssertEqual(RNGitPage.appName, "nomadnetwork")
    XCTAssertEqual(RNGitPage.jobsInterval, 5)
    XCTAssertEqual(RNGitPage.linkCleanInterval, 60)
    XCTAssertEqual(RNGitPage.blobSizeLimit, 262144)
    XCTAssertEqual(RNGitPage.treeEntriesPerPage, 1000)
    XCTAssertEqual(RNGitPage.commitsPerPage, 100)
    XCTAssertEqual(RNGitPage.commandTimeout, 8)
    XCTAssertEqual(RNGitPage.maxRenderWidth, 100)
    XCTAssertEqual(RNGitPage.tabWidth, "   ")
    XCTAssertTrue(RNGitPage.showDiffByDefault)
    XCTAssertTrue(RNGitPage.useNerdFonts)
    XCTAssertEqual(RNGitPage.renderableExtensions, [".md", ".mu"])
    XCTAssertEqual(RNGitPage.renderDefault, [".md", ".mu"])
    XCTAssertEqual(
      RNGitPage.imageExtensions,
      [".webp", ".png", ".jpg", ".jpeg", ".gif", ".tiff", ".tif", ".bmp"])
  }

  /// Every colour matches the reference, markup and all.
  func testEveryColourMatchesTheReference() {
    XCTAssertEqual(RNGitPage.Colour.folder, "`Ffe6")
    XCTAssertEqual(RNGitPage.Colour.file, "`F66d")
    XCTAssertEqual(RNGitPage.Colour.dim, "`F666")
    XCTAssertEqual(RNGitPage.Colour.dimmer, "`F444")
    XCTAssertEqual(RNGitPage.Colour.okDim, "`FT537855")
    XCTAssertEqual(RNGitPage.Colour.diffAdded, "`F0a0")
    XCTAssertEqual(RNGitPage.Colour.diffRemoved, "`F900")
    XCTAssertEqual(RNGitPage.Colour.diffPosition, "`F0aa")
    XCTAssertEqual(RNGitPage.ChartColour.push, "B9A810")
    XCTAssertEqual(RNGitPage.ChartColour.pushGradient, "791212")
    XCTAssertEqual(RNGitPage.ChartColour.fetch, "10b981")
    XCTAssertEqual(RNGitPage.ChartColour.fetchGradient, "1c5e71")
    XCTAssertEqual(RNGitPage.ChartColour.view, "3b82f6")
    XCTAssertEqual(RNGitPage.ChartColour.viewGradient, "13428A")
    XCTAssertEqual(RNGitPage.ChartColour.download, "7831E0")
    XCTAssertEqual(RNGitPage.ChartColour.downloadGradient, "c5754d")
  }

  /// Every icon is drawn as the reference draws it, in both fonts.
  func testEveryIconMatchesTheReferenceInBothFonts() {
    XCTAssertEqual(RNGitPage.icon(.separator, usingNerdFonts: true), "•")
    XCTAssertEqual(RNGitPage.icon(.separator, usingNerdFonts: false), "•")
    XCTAssertEqual(RNGitPage.icon(.folder, usingNerdFonts: true), "󰉖")
    XCTAssertEqual(RNGitPage.icon(.folder, usingNerdFonts: false), "🗀")
    XCTAssertEqual(RNGitPage.icon(.file, usingNerdFonts: true), "")
    XCTAssertEqual(RNGitPage.icon(.file, usingNerdFonts: false), "🗎")
    XCTAssertEqual(RNGitPage.icon(.branch, usingNerdFonts: true), "󰘬")
    XCTAssertEqual(RNGitPage.icon(.branch, usingNerdFonts: false), "⑃")
    XCTAssertEqual(RNGitPage.icon(.commits, usingNerdFonts: true), "󰋚")
    XCTAssertEqual(RNGitPage.icon(.commits, usingNerdFonts: false), "🖹")
    XCTAssertEqual(RNGitPage.icon(.tag, usingNerdFonts: true), "󰓼")
    XCTAssertEqual(RNGitPage.icon(.tag, usingNerdFonts: false), "⌆")
    XCTAssertEqual(RNGitPage.icon(.stats, usingNerdFonts: true), "")
    XCTAssertEqual(RNGitPage.icon(.stats, usingNerdFonts: false), "🗠")
    XCTAssertEqual(RNGitPage.icon(.heart, usingNerdFonts: true), "󰋑")
    XCTAssertEqual(RNGitPage.icon(.heart, usingNerdFonts: false), "♥")
    XCTAssertEqual(RNGitPage.icon(.package, usingNerdFonts: true), "󰏗")
    XCTAssertEqual(RNGitPage.icon(.package, usingNerdFonts: false), "◇")
    XCTAssertEqual(RNGitPage.icon(.work, usingNerdFonts: true), "󱌣")
    XCTAssertEqual(RNGitPage.icon(.work, usingNerdFonts: false), "☸")
  }

  /// The icons a page can draw are exactly the names the reference answers for.
  ///
  /// The reference answers an empty string for any other name, which a Swift case cannot be, so
  /// the guard is that the set of cases is the set of names.
  func testTheIconsAreExactlyTheNamesTheReferenceAnswersFor() {
    XCTAssertEqual(
      Set(RNGitPage.Icon.allCases.map(\.rawValue)),
      ["sep", "folder", "file", "branch", "commits", "tag", "stats", "heart", "package", "work"])
    for icon in RNGitPage.Icon.allCases {
      XCTAssertFalse(RNGitPage.icon(icon, usingNerdFonts: true).isEmpty, icon.rawValue)
      XCTAssertFalse(RNGitPage.icon(icon, usingNerdFonts: false).isEmpty, icon.rawValue)
    }
  }

  /// A handler draws the Nerd Font icons unless the node tells it otherwise.
  func testAHandlerDrawsNerdFontIconsUnlessToldOtherwise() {
    var handler = RNGitPageHandler(
      access: RNGitPageAccess(control: RNGitAccessControl(groups: [:])),
      runner: RNGitProcessRunner(), destinationHash: Data(count: 16),
      templates: RNGitPageTemplates(directory: "/nonexistent", nodeName: "", version: ""))
    XCTAssertEqual(handler.icon(.folder), RNGitPage.icon(.folder, usingNerdFonts: true))
    handler.useNerdFonts = false
    XCTAssertEqual(handler.icon(.folder), RNGitPage.icon(.folder, usingNerdFonts: false))
  }
}
