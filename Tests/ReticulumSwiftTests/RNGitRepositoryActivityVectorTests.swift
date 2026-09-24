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

/// A repository's activity over a statistics page's window, as Python RNS 1.5.4's
/// `repository_stats` totals it.
///
/// Every expectation is the figure the reference returned with `time.time` pinned to `now` and
/// `TZ` set to `timeZone`.
final class RNGitRepositoryActivityVectorTests: XCTestCase {

  /// One series as the reference returned it, with the days it counted nothing on left out.
  private struct Series {
    let nonZero: [Int: Int]
    let total: Int
    let peak: Int
    let peakDay: String?
  }

  /// One call to `repository_stats` and what it returned.
  private struct Vector {
    let name: String
    let now: TimeInterval
    let timeZone: String
    let lookbackDays: Int
    let counters: RNGitRepositoryStatistics
    let dateRange: String
    let views: Series
    let fetches: Series
    let pushes: Series
    let downloads: Series
    let releaseDownloads: Series
    let downloadsCombined: Series
    let activityScore: Int
    let actualDays: Int
    let activityLevel: RNGitRepositoryActivity.Level
  }

  private static let vectors: [Vector] = [
    Vector(
      name: "downloads only / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(download: ["2026-09-24": 6]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [13: 6], total: 6, peak: 6, peakDay: "2026-09-24"),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [13: 6], total: 6, peak: 6, peakDay: "2026-09-24"),
      activityScore: 1, actualDays: 14, activityLevel: .low),
    Vector(
      name: "downloads only / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(download: ["2026-09-24": 6]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [89: 6], total: 6, peak: 6, peakDay: "2026-09-24"),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [89: 6], total: 6, peak: 6, peakDay: "2026-09-24"),
      activityScore: 1, actualDays: 90, activityLevel: .low),
    Vector(
      name: "dst week / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(
        view: ["2027-03-13": 2, "2027-03-15": 4], fetch: ["2027-03-12": 1]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 1, activityLevel: .inactive),
    Vector(
      name: "dst week / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(
        view: ["2027-03-13": 2, "2027-03-15": 4], fetch: ["2027-03-12": 1]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 1, activityLevel: .inactive),
    Vector(
      name: "empty / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 14, activityLevel: .inactive),
    Vector(
      name: "empty / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 90, activityLevel: .inactive),
    Vector(
      name: "future day / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(fetch: ["2026-09-30": 4]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 1, activityLevel: .inactive),
    Vector(
      name: "future day / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(fetch: ["2026-09-30": 4]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 1, activityLevel: .inactive),
    Vector(
      name: "high / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(push: ["2026-09-24": 30]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [13: 30], total: 30, peak: 30, peakDay: "2026-09-24"),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 150, actualDays: 1, activityLevel: .high),
    Vector(
      name: "high / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(push: ["2026-09-24": 30]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [89: 30], total: 30, peak: 30, peakDay: "2026-09-24"),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 150, actualDays: 1, activityLevel: .high),
    Vector(
      name: "mixed window / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(
        view: ["2026-09-24": 3, "2026-09-20": 7, "2026-09-11": 7, "2026-06-01": 50],
        fetch: ["2026-09-23": 2, "2026-09-12": 1], push: ["2026-09-15": 1],
        download: ["2026-09-24": 1, "2026-09-22": 4],
        releaseDownload: ["2026-09-22": 2, "2026-09-19": 5]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [0: 7, 9: 7, 13: 3], total: 17, peak: 7, peakDay: "2026-09-11"),
      fetches: .init(nonZero: [1: 1, 12: 2], total: 3, peak: 2, peakDay: "2026-09-23"),
      pushes: .init(nonZero: [4: 1], total: 1, peak: 1, peakDay: "2026-09-15"),
      downloads: .init(nonZero: [11: 4, 13: 1], total: 5, peak: 4, peakDay: "2026-09-22"),
      releaseDownloads: .init(nonZero: [8: 5, 11: 2], total: 7, peak: 5, peakDay: "2026-09-19"),
      downloadsCombined: .init(
        nonZero: [8: 5, 11: 6, 13: 1], total: 12, peak: 6, peakDay: "2026-09-22"),
      activityScore: 16, actualDays: 14, activityLevel: .low),
    Vector(
      name: "mixed window / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(
        view: ["2026-09-24": 3, "2026-09-20": 7, "2026-09-11": 7, "2026-06-01": 50],
        fetch: ["2026-09-23": 2, "2026-09-12": 1], push: ["2026-09-15": 1],
        download: ["2026-09-24": 1, "2026-09-22": 4],
        releaseDownload: ["2026-09-22": 2, "2026-09-19": 5]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [76: 7, 85: 7, 89: 3], total: 17, peak: 7, peakDay: "2026-09-11"),
      fetches: .init(nonZero: [77: 1, 88: 2], total: 3, peak: 2, peakDay: "2026-09-23"),
      pushes: .init(nonZero: [80: 1], total: 1, peak: 1, peakDay: "2026-09-15"),
      downloads: .init(nonZero: [87: 4, 89: 1], total: 5, peak: 4, peakDay: "2026-09-22"),
      releaseDownloads: .init(nonZero: [84: 5, 87: 2], total: 7, peak: 5, peakDay: "2026-09-19"),
      downloadsCombined: .init(
        nonZero: [84: 5, 87: 6, 89: 1], total: 12, peak: 6, peakDay: "2026-09-22"),
      activityScore: 16, actualDays: 90, activityLevel: .low),
    Vector(
      name: "moderate / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(push: ["2026-09-24": 3, "2026-09-23": 3]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [12: 3, 13: 3], total: 6, peak: 3, peakDay: "2026-09-23"),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 30, actualDays: 2, activityLevel: .high),
    Vector(
      name: "moderate / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(push: ["2026-09-24": 3, "2026-09-23": 3]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [88: 3, 89: 3], total: 6, peak: 3, peakDay: "2026-09-23"),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 30, actualDays: 2, activityLevel: .high),
    Vector(
      name: "moderate daily / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(fetch: ["2026-09-23": 5]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [12: 5], total: 5, peak: 5, peakDay: "2026-09-23"),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 10, actualDays: 2, activityLevel: .moderate),
    Vector(
      name: "moderate daily / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(fetch: ["2026-09-23": 5]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [88: 5], total: 5, peak: 5, peakDay: "2026-09-23"),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 10, actualDays: 2, activityLevel: .moderate),
    Vector(
      name: "not a day / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(view: ["garbage": 3, "2026-09-24": 1]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [13: 1], total: 1, peak: 1, peakDay: "2026-09-24"),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 1, activityLevel: .low),
    Vector(
      name: "not a day / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(view: ["garbage": 3, "2026-09-24": 1]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [89: 1], total: 1, peak: 1, peakDay: "2026-09-24"),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 1, activityLevel: .low),
    Vector(
      name: "not a day first / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(view: ["-bad": 3, "2026-09-24": 1]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [13: 1], total: 1, peak: 1, peakDay: "2026-09-24"),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 14, activityLevel: .low),
    Vector(
      name: "not a day first / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(view: ["-bad": 3, "2026-09-24": 1]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [89: 1], total: 1, peak: 1, peakDay: "2026-09-24"),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 90, activityLevel: .low),
    Vector(
      name: "old activity only / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(view: ["2025-01-01": 9]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 14, activityLevel: .inactive),
    Vector(
      name: "old activity only / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(view: ["2025-01-01": 9]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 90, activityLevel: .inactive),
    Vector(
      name: "one view today / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(view: ["2026-09-24": 1]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [13: 1], total: 1, peak: 1, peakDay: "2026-09-24"),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 1, activityLevel: .low),
    Vector(
      name: "one view today / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(view: ["2026-09-24": 1]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [89: 1], total: 1, peak: 1, peakDay: "2026-09-24"),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 1, activityLevel: .low),
    Vector(
      name: "out of range day / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(view: ["2026-02-30": 3, "2026-09-24": 1]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [13: 1], total: 1, peak: 1, peakDay: "2026-09-24"),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 14, activityLevel: .low),
    Vector(
      name: "out of range day / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(view: ["2026-02-30": 3, "2026-09-24": 1]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [89: 1], total: 1, peak: 1, peakDay: "2026-09-24"),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 90, activityLevel: .low),
    Vector(
      name: "zero counts / 14 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 14,
      counters: RNGitRepositoryStatistics(view: ["2026-09-01": 0], push: ["2026-09-24": 2]),
      dateRange: "Sep 11 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [13: 2], total: 2, peak: 2, peakDay: "2026-09-24"),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 10, actualDays: 1, activityLevel: .high),
    Vector(
      name: "zero counts / 90 (UTC)", now: 1_790_255_820, timeZone: "UTC", lookbackDays: 90,
      counters: RNGitRepositoryStatistics(view: ["2026-09-01": 0], push: ["2026-09-24": 2]),
      dateRange: "Jun 27 - Sep 24",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [89: 2], total: 2, peak: 2, peakDay: "2026-09-24"),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 10, actualDays: 1, activityLevel: .high),
    Vector(
      name: "dst week / 14 (America/New_York)", now: 1_805_340_600, timeZone: "America/New_York",
      lookbackDays: 14,
      counters: RNGitRepositoryStatistics(
        view: ["2027-03-13": 2, "2027-03-15": 4], fetch: ["2027-03-12": 1]),
      dateRange: "Mar 04 - Mar 17",
      views: .init(nonZero: [9: 2, 11: 4], total: 6, peak: 4, peakDay: "2027-03-15"),
      fetches: .init(nonZero: [8: 1], total: 1, peak: 1, peakDay: "2027-03-12"),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 3, actualDays: 6, activityLevel: .low),
    Vector(
      name: "empty / 14 (America/New_York)", now: 1_805_340_600, timeZone: "America/New_York",
      lookbackDays: 14,
      counters: RNGitRepositoryStatistics(),
      dateRange: "Mar 04 - Mar 17",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 14, activityLevel: .inactive),
    Vector(
      name: "future day / 14 (America/New_York)", now: 1_805_340_600, timeZone: "America/New_York",
      lookbackDays: 14,
      counters: RNGitRepositoryStatistics(fetch: ["2026-09-30": 4]),
      dateRange: "Mar 04 - Mar 17",
      views: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      fetches: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      pushes: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      releaseDownloads: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      downloadsCombined: .init(nonZero: [:], total: 0, peak: 0, peakDay: nil),
      activityScore: 0, actualDays: 14, activityLevel: .inactive),
  ]

  /// Each vector's figures come out as the reference's did.
  func testRepositoryStatsMatchesTheReference() throws {
    for vector in Self.vectors {
      let timeZone = try XCTUnwrap(TimeZone(identifier: vector.timeZone), vector.name)
      let statistics = RNGitStatistics(
        groups: ["g": RNGitGroupStatistics(repositories: ["r": vector.counters])])
      let activity = statistics.repositoryStats(
        group: "g", repository: "r", lookbackDays: vector.lookbackDays,
        now: Date(timeIntervalSince1970: vector.now), timeZone: timeZone)

      XCTAssertEqual(activity.group, "g", vector.name)
      XCTAssertEqual(activity.repository, "r", vector.name)
      XCTAssertEqual(activity.lookbackDays, vector.lookbackDays, vector.name)
      XCTAssertEqual(activity.dateRange, vector.dateRange, vector.name)
      XCTAssertEqual(
        activity.timelineLabels, ["\(vector.lookbackDays) days ago", "Today"], vector.name)
      for (label, actual, expected) in [
        ("views", activity.views, vector.views),
        ("fetches", activity.fetches, vector.fetches),
        ("pushes", activity.pushes, vector.pushes),
        ("downloads", activity.downloads, vector.downloads),
        ("release downloads", activity.releaseDownloads, vector.releaseDownloads),
        ("downloads combined", activity.downloadsCombined, vector.downloadsCombined),
      ] {
        var daily = Array(repeating: 0, count: vector.lookbackDays)
        for (index, count) in expected.nonZero { daily[index] = count }
        let context = "\(vector.name): \(label)"
        XCTAssertEqual(actual.daily, daily, context)
        XCTAssertEqual(actual.total, expected.total, context)
        XCTAssertEqual(actual.peak, expected.peak, context)
        XCTAssertEqual(actual.peakDay, expected.peakDay, context)
      }
      XCTAssertEqual(activity.activityScore, vector.activityScore, vector.name)
      XCTAssertEqual(activity.actualDays, vector.actualDays, vector.name)
      XCTAssertEqual(activity.activityLevel, vector.activityLevel, vector.name)
    }
  }

  /// The window's days and their labels, in the zone the node runs in.
  func testDaysAndLabelsMatchTheReference() throws {
    let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
    let fortnight = RNGitStatistics().repositoryStats(
      group: "g", repository: "r", lookbackDays: 14,
      now: Date(timeIntervalSince1970: 1_790_255_820), timeZone: utc)
    XCTAssertEqual(fortnight.days, (11...24).map { String(format: "2026-09-%02d", $0) })
    XCTAssertEqual(fortnight.dayLabels, (11...24).map { String(format: "Sep %02d", $0) })

    let quarter = RNGitStatistics().repositoryStats(
      group: "g", repository: "r", lookbackDays: 90,
      now: Date(timeIntervalSince1970: 1_790_255_820), timeZone: utc)
    XCTAssertEqual(quarter.days.count, 90)
    XCTAssertEqual(quarter.days.first, "2026-06-27")
    XCTAssertEqual(quarter.days.last, "2026-09-24")
    XCTAssertEqual(quarter.dayLabels.first, "Jun 27")
    XCTAssertEqual(quarter.dayLabels.last, "Sep 24")

    // 23:30 on the Wednesday after New York moves its clocks forward, so every day before the
    // change falls an hour earlier on the clock.
    let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
    let acrossTheChange = RNGitStatistics().repositoryStats(
      group: "g", repository: "r", lookbackDays: 14,
      now: Date(timeIntervalSince1970: 1_805_340_600), timeZone: newYork)
    XCTAssertEqual(acrossTheChange.days, (4...17).map { String(format: "2027-03-%02d", $0) })
    XCTAssertEqual(acrossTheChange.dayLabels, (4...17).map { String(format: "Mar %02d", $0) })
  }
}
