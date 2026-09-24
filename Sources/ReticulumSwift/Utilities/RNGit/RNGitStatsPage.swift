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

  /// How many days a statistics page looks back across.
  public static let statsLookbackDays = 90

  // MARK: - Stats page

  /// One repository's counters over the last `statsLookbackDays` days ending on the day `now`
  /// falls on in `timeZone`, each charted, with a stack of all four when the repository scored
  /// any points.
  ///
  /// Mirrors `serve_stats_page` (`pages.py:1188-1289`), which counts no view. Its "Stats
  /// Unavailable" branch has no counterpart: the reference reaches it only when
  /// `repository_stats` refuses a reader the page has just let through, over the same
  /// permission.
  public func serveStatsPage(
    identityHash: Data?, groupName: String, repositoryName: String, now: Date = Date(),
    timeZone: TimeZone = .current
  ) -> Data {
    let startedAt = Date().timeIntervalSince1970

    guard !groupName.isEmpty, !repositoryName.isEmpty else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2) + "\nInvalid request\n", startedAt: startedAt)
    }

    if identityHash == nil, settings.blockedIdentities.contains(access.nullIdentityHash) {
      return templates.render(
        "", template: RNGitPageTemplate.noIdentity.rawValue, startedAt: startedAt)
    }

    let navigation =
      ">>\n" + RNGitPageMicron.link("Node", RNGitPage.Path.index) + " / "
      + RNGitPageMicron.link(groupName, RNGitPage.Path.group, [("g", groupName)]) + " / "
      + RNGitPageMicron.link(
        repositoryName, RNGitPage.Path.repository, [("g", groupName), ("r", repositoryName)])
      + " / stats\n"

    guard
      access.repository(readableBy: identityHash, in: groupName, named: repositoryName) != nil,
      access.allows(identityHash, group: groupName, repository: repositoryName, permission: .stats)
    else {
      return templates.render(
        RNGitPageMicron.heading("Error", level: 2)
          + "\nThe requested repository was not found.\n",
        navigation: navigation, startedAt: startedAt)
    }

    let stats = statistics.repositoryStats(
      group: groupName, repository: repositoryName, lookbackDays: Self.statsLookbackDays,
      now: now, timeZone: timeZone)
    let (levelColour, levelLabel) = Self.activityDisplay(stats.activityLevel)
    let dim = RNGitPage.Colour.dim

    func figures(_ series: RNGitRepositoryActivity.Series) -> String {
      Self.rightAligned(series.total, 5) + "  total " + dim + "  today: "
        + Self.rightAligned(series.daily.last ?? 0, 3) + "  peak: "
        + Self.rightAligned(series.peak, 3)
    }

    var content = RNGitPageMicron.heading("Stats for \(repositoryName)", level: 2)
    content += "\n`FT\(RNGitPage.ChartColour.fetch)Fetches`f   : \(figures(stats.fetches)) \n`f"
    content += "`FT\(RNGitPage.ChartColour.push)Pushes`f    : \(figures(stats.pushes)) \n`f"
    content += "`FT\(RNGitPage.ChartColour.view)Views`f     : \(figures(stats.views)) `f\n"
    content +=
      "`FT\(RNGitPage.ChartColour.download)Downloads`f : \(figures(stats.downloadsCombined)) `f\n"
    content += "`F0aaActivity`f  : \(Self.rightAligned(stats.activityScore, 5)) points\n\n"
    content +=
      "\(levelColour)\(levelLabel)`f over the last \(stats.actualDays) days (\(stats.dateRange))\n\n"

    let charts: [(String, RNGitRepositoryActivity.Series, String, String, Double?)] = [
      (
        "Fetches", stats.fetches, RNGitPage.ChartColour.fetch,
        RNGitPage.ChartColour.fetchGradient, nil
      ),
      (
        "Pushes", stats.pushes, RNGitPage.ChartColour.push, RNGitPage.ChartColour.pushGradient,
        nil
      ),
      ("Views", stats.views, RNGitPage.ChartColour.view, RNGitPage.ChartColour.viewGradient, nil),
      (
        "Downloads", stats.downloadsCombined, RNGitPage.ChartColour.download,
        RNGitPage.ChartColour.downloadGradient, 1.7
      ),
    ]
    for (title, series, colour, gradient, gradientFactor) in charts where series.total > 0 {
      content += RNGitPageMicron.heading(title, level: 2) + "\n"
      content += RNGitPageCharts.chart(
        series.daily, labels: stats.timelineLabels, colour: colour, secondaryColour: gradient,
        gradientFactor: gradientFactor)
      content += "\n"
    }

    if stats.activityScore > 0 {
      content += RNGitPageMicron.heading("Combined Activity", level: 2) + "\n"
      content += RNGitPageCharts.combined(
        views: stats.views.daily, fetches: stats.fetches.daily, pushes: stats.pushes.daily,
        downloads: stats.downloadsCombined.daily, labels: stats.timelineLabels)
    } else {
      content += RNGitPageMicron.italic(
        "\nNo development activity recorded for this repository in the selected time period.\n\n"
      )
    }

    return templates.render(
      content, navigation: navigation, template: RNGitPageTemplate.stats.rawValue,
      startedAt: startedAt)
  }

  /// The color and words a statistics page shows `level` in.
  private static func activityDisplay(_ level: RNGitRepositoryActivity.Level) -> (String, String) {
    switch level {
    case .inactive: return ("`F666", "No activity")
    case .low: return ("`F66d", "Low activity")
    case .moderate: return ("`Faa0", "Moderate activity")
    case .high: return ("`F0a0", "High activity")
    }
  }

  /// `value` right-aligned in `width` columns, as a `>width` format spec writes it.
  private static func rightAligned(_ value: Int, _ width: Int) -> String {
    let text = String(value)
    return String(repeating: " ", count: max(0, width - text.count)) + text
  }
}
