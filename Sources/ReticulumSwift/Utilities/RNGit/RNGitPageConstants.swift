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

/// The paths, limits and colours a page node is built around.
public enum RNGitPage {

  /// The app name a page node serves on.
  public static let appName = "nomadnetwork"

  /// The aspect a page node serves on.
  public static let aspect = "node"

  /// How often the page node's periodic work runs, in seconds.
  public static let jobsInterval: TimeInterval = 5

  /// How often links that are no longer up are swept, in seconds.
  public static let linkCleanInterval: TimeInterval = 60

  /// The pages a node serves, each at the path a link names it by.
  public enum Path {

    /// The node's own front page.
    public static let index = "/page/index.mu"
    /// One repository group.
    public static let group = "/page/group.mu"
    /// One repository.
    public static let repository = "/page/repo.mu"
    /// One directory inside a repository.
    public static let tree = "/page/tree.mu"
    /// One file inside a repository.
    public static let blob = "/page/blob.mu"
    /// A repository's commits.
    public static let commits = "/page/commits.mu"
    /// One commit.
    public static let commit = "/page/commit.mu"
    /// A repository's branches and tags.
    public static let refs = "/page/refs.mu"
    /// What a repository has been counted doing.
    public static let stats = "/page/stats.mu"
    /// A repository's releases.
    public static let releases = "/page/releases.mu"
    /// One release.
    public static let release = "/page/release.mu"
    /// A repository's work documents.
    public static let work = "/page/work.mu"
    /// One work document.
    public static let workDocument = "/page/work_doc.mu"
    /// An image, converted for the reader.
    public static let media = "/media"
    /// A release artifact.
    public static let artifact = "/file/artifact"
    /// A file out of a repository.
    public static let download = "/file/download"
    /// A file attached to a work document.
    public static let workDocumentFile = "/file/workdoc"
  }

  /// The largest file a page renders rather than offering as a download.
  public static let blobSizeLimit = 256 * 1024

  /// How many directory entries one tree page holds.
  public static let treeEntriesPerPage = 1000

  /// How many commits one commits page holds.
  public static let commitsPerPage = 100

  /// Whether a commit page carries its diff.
  public static let showDiffByDefault = true

  /// How long one `git` call is given, in seconds.
  public static let commandTimeout: TimeInterval = 8

  /// The width a page is rendered to.
  public static let maxRenderWidth = 100

  /// Whether the icons a page draws are the ones a Nerd Font carries.
  public static let useNerdFonts = true

  /// What a tab is drawn as, which is three spaces and no more.
  public static let tabWidth = "   "

  /// The files a page renders rather than shows as text.
  public static let renderableExtensions = [".md", ".mu"]

  /// The files a page renders unless the reader asks for the source.
  public static let renderDefault = [".md", ".mu"]

  /// The files a page offers as an image.
  public static let imageExtensions = [
    ".webp", ".png", ".jpg", ".jpeg", ".gif", ".tiff", ".tif", ".bmp",
  ]

  /// The colours a page draws with.
  public enum Colour {

    /// A directory.
    public static let folder = "`Ffe6"
    /// A file.
    public static let file = "`F66d"
    /// Text that is there but not the point.
    public static let dim = "`F666"
    /// Text that is dimmer still.
    public static let dimmer = "`F444"
    /// Something that came off.
    public static let okDim = "`FT537855"
    /// A line a diff added.
    public static let diffAdded = "`F0a0"
    /// A line a diff removed.
    public static let diffRemoved = "`F900"
    /// A diff's position marker.
    public static let diffPosition = "`F0aa"
  }

  /// The colours a chart is drawn in, each with the colour its gradient runs to.
  public enum ChartColour {

    /// Pushes, and what they run to.
    public static let push = "B9A810"
    /// The colour a push bar's gradient runs to.
    public static let pushGradient = "791212"
    /// Fetches.
    public static let fetch = "10b981"
    /// The colour a fetch bar's gradient runs to.
    public static let fetchGradient = "1c5e71"
    /// Views.
    public static let view = "3b82f6"
    /// The colour a view bar's gradient runs to.
    public static let viewGradient = "13428A"
    /// Downloads.
    public static let download = "7831E0"
    /// The colour a download bar's gradient runs to.
    public static let downloadGradient = "c5754d"
  }

  /// What a page draws for each thing it names.
  public enum Icon: String, CaseIterable, Sendable {

    /// Between one thing and the next.
    case separator = "sep"
    /// A directory.
    case folder
    /// A file.
    case file
    /// A branch.
    case branch
    /// A commit history.
    case commits
    /// A tag.
    case tag
    /// Statistics.
    case stats
    /// Thanks.
    case heart
    /// A release.
    case package
    /// A work document.
    case work
  }

  /// The icons a Nerd Font carries.
  static let nerdFontIcons: [Icon: String] = [
    .separator: "•", .folder: "\u{F0256}", .file: "\u{F0F6}", .branch: "\u{F062C}",
    .commits: "\u{F02DA}", .tag: "\u{F04FC}", .stats: "\u{F201}", .heart: "\u{F02D1}",
    .package: "\u{F03D7}", .work: "\u{F1323}",
  ]

  /// The icons every font carries.
  static let unicodeIcons: [Icon: String] = [
    .separator: "•", .folder: "🗀", .file: "🗎", .branch: "⑃", .commits: "🖹", .tag: "⌆",
    .stats: "🗠", .heart: "♥", .package: "◇", .work: "☸",
  ]

  /// What `icon` is drawn as.
  ///
  /// Takes no default: a node chooses its icons once, so a page asks the handler serving it
  /// rather than reading ``useNerdFonts`` itself.
  public static func icon(_ icon: Icon, usingNerdFonts: Bool) -> String {
    (usingNerdFonts ? nerdFontIcons : unicodeIcons)[icon] ?? ""
  }

  /// `names`, in the order Python's `sorted()` puts them.
  ///
  /// Swift's default `String` comparison is Unicode-aware and can disagree with Python's, which
  /// orders by code point, so a page that sorts a list for display sorts it this way instead.
  static func sorted(_ names: some Sequence<String>) -> [String] {
    names.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) { $0 < $1 } }
  }
}
