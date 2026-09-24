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

/// One repository's counters over the days a statistics page looks back across, as
/// `repository_stats` totals them (`server.py:4644-4760`).
public struct RNGitRepositoryActivity: Equatable, Sendable {

  /// One counter over the window.
  public struct Series: Equatable, Sendable {

    /// The count for each day, oldest first.
    public var daily: [Int]

    /// The sum of `daily`.
    public var total: Int

    /// The largest count in `daily`, or zero when every day is.
    public var peak: Int

    /// The first day `peak` was counted on, or nil when every day counted zero.
    public var peakDay: String?
  }

  /// How busy a repository has been, by the points it scores each day.
  public enum Level: String, Equatable, Sendable {

    /// No points.
    case inactive
    /// Fewer than three points a day.
    case low
    /// Fewer than ten points a day.
    case moderate
    /// Ten points a day or more.
    case high
  }

  /// The group the repository is in.
  public let group: String

  /// The repository's name.
  public let repository: String

  /// How many days the window covers, ending today.
  public let lookbackDays: Int

  /// The first and last of `dayLabels`, joined.
  public let dateRange: String

  /// Each day in the window as `YYYY-MM-DD`, oldest first.
  public let days: [String]

  /// Each day in the window as a month and day, such as `Sep 04`.
  public let dayLabels: [String]

  /// What a chart's first and last bar are labelled.
  public let timelineLabels: [String]

  /// Repository page views.
  public let views: Series

  /// Fetches served.
  public let fetches: Series

  /// Pushes accepted.
  public let pushes: Series

  /// Repository archive downloads.
  public let downloads: Series

  /// Release asset downloads.
  public let releaseDownloads: Series

  /// Archive and release asset downloads together.
  public let downloadsCombined: Series

  /// The window's points, a fifth of one for each view or download, two for each fetch, and
  /// five for each push, rounded down.
  public let activityScore: Int

  /// The days the points are spread over: from the first day anything was viewed, fetched or
  /// pushed—inside the window or not—to today, and never more than `lookbackDays`.
  public let actualDays: Int

  /// How busy the repository has been, by its points over `actualDays`.
  public let activityLevel: Level
}

extension RNGitStatistics {

  /// A repository's counters over a window of days ending today.
  ///
  /// The window is the `lookbackDays` days ending on the day `now` falls on in `timeZone`.
  /// Whether the reader may see these figures is the caller's to decide; the reference checks
  /// `PERM_STATS` before counting.
  ///
  /// - Precondition: `lookbackDays` is at least one.
  public func repositoryStats(
    group: String, repository: String, lookbackDays: Int = 14, now: Date = Date(),
    timeZone: TimeZone = .current
  ) -> RNGitRepositoryActivity {
    precondition(lookbackDays > 0, "a window of no days has no range")
    let daySeconds = 86_400.0
    let dayFormatter = Self.formatter("yyyy-MM-dd", timeZone)
    let labelFormatter = Self.formatter("MMM dd", timeZone)

    var days: [String] = []
    var dayLabels: [String] = []
    for offset in stride(from: lookbackDays - 1, through: 0, by: -1) {
      let day = now.addingTimeInterval(-Double(offset) * daySeconds)
      days.append(dayFormatter.string(from: day))
      dayLabels.append(labelFormatter.string(from: day))
    }

    let counters = groups[group]?.repositories[repository] ?? RNGitRepositoryStatistics()
    let views = Self.series(days) { counters.view[$0] ?? 0 }
    let fetches = Self.series(days) { counters.fetch[$0] ?? 0 }
    let pushes = Self.series(days) { counters.push[$0] ?? 0 }
    let downloads = Self.series(days) { counters.download[$0] ?? 0 }
    let releaseDownloads = Self.series(days) { counters.releaseDownload[$0] ?? 0 }
    let downloadsCombined = Self.series(days) {
      (counters.download[$0] ?? 0) + (counters.releaseDownload[$0] ?? 0)
    }

    let viewTotal = views.total + downloads.total + releaseDownloads.total
    let totalScore =
      Double(viewTotal) * 0.2 + Double(fetches.total) * 2.0 + Double(pushes.total) * 5

    var actualDays = lookbackDays
    let activeDays = [counters.view, counters.fetch, counters.push].flatMap { series in
      series.filter { $0.value > 0 }.map(\.key)
    }
    if let earliest = activeDays.min(by: Self.precedes),
      let midnight = Self.midnight(of: earliest, in: timeZone)
    {
      let span = now.timeIntervalSince1970 - midnight.timeIntervalSince1970
      actualDays = max(1, Int((span / daySeconds).rounded(.down)) + 1)
    }
    actualDays = min(actualDays, lookbackDays)

    let dailyScore = totalScore / Double(actualDays)
    let level: RNGitRepositoryActivity.Level
    if dailyScore == 0 {
      level = .inactive
    } else if dailyScore < 3 {
      level = .low
    } else if dailyScore < 10 {
      level = .moderate
    } else {
      level = .high
    }

    return RNGitRepositoryActivity(
      group: group, repository: repository, lookbackDays: lookbackDays,
      dateRange: "\(dayLabels[0]) - \(dayLabels[dayLabels.count - 1])", days: days,
      dayLabels: dayLabels, timelineLabels: ["\(lookbackDays) days ago", "Today"],
      views: views, fetches: fetches, pushes: pushes, downloads: downloads,
      releaseDownloads: releaseDownloads, downloadsCombined: downloadsCombined,
      activityScore: Int(totalScore), actualDays: actualDays, activityLevel: level)
  }

  /// The count `count` gives each of `days`, with its total and the first day it peaked on.
  private static func series(_ days: [String], _ count: (String) -> Int)
    -> RNGitRepositoryActivity.Series
  {
    var series = RNGitRepositoryActivity.Series(daily: [], total: 0, peak: 0, peakDay: nil)
    for day in days {
      let value = count(day)
      series.daily.append(value)
      series.total += value
      if value > series.peak {
        series.peak = value
        series.peakDay = day
      }
    }
    return series
  }

  /// Whether `lhs` sorts before `rhs` as Python compares strings, by code point.
  private static func precedes(_ lhs: String, _ rhs: String) -> Bool {
    lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars) { $0 < $1 }
  }

  /// The start of the day `day` names in `timeZone`, or nil when `day` is not one that
  /// `time.strptime(day, "%Y-%m-%d")` reads.
  ///
  /// The pattern is the one `_strptime` builds for that format: four digits of year, then a
  /// month and a day each with or without a leading zero, the day also after a space, and
  /// nothing left over. A day past the end of its month does not read either.
  private static func midnight(of day: String, in timeZone: TimeZone) -> Date? {
    let pattern = #"^(\d{4})-(1[0-2]|0[1-9]|[1-9])-(3[01]|[12]\d|0[1-9]|[1-9]| [1-9])$"#
    guard let match = day.range(of: pattern, options: .regularExpression),
      match == day.startIndex..<day.endIndex
    else { return nil }
    let fields = day.split(separator: "-", maxSplits: 2).map {
      Int($0.trimmingCharacters(in: .whitespaces))
    }
    guard fields.count == 3, let year = fields[0], let month = fields[1],
      let dayOfMonth = fields[2],
      year >= 1
    else { return nil }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = DateComponents(year: year, month: month, day: dayOfMonth)
    guard let date = calendar.date(from: components),
      calendar.component(.day, from: date) == dayOfMonth
    else { return nil }
    return date
  }

  /// A formatter writing `format` in `timeZone`, in English whatever the host's language.
  private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    return formatter
  }
}
