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

/// The counters a node keeps for one repository, each keyed by `YYYY-MM-DD`.
///
/// Python: `STATS_INIT_REPO` (`server.py:4641`).
public struct RNGitRepositoryStatistics: Equatable, Sendable {

  /// Repository page views.
  public var view: [String: Int]

  /// Fetches served.
  public var fetch: [String: Int]

  /// Pushes accepted.
  public var push: [String: Int]

  /// Repository archive downloads.
  public var download: [String: Int]

  /// Release asset downloads.
  public var releaseDownload: [String: Int]

  /// Counters that are all empty.
  public init(
    view: [String: Int] = [:], fetch: [String: Int] = [:], push: [String: Int] = [:],
    download: [String: Int] = [:], releaseDownload: [String: Int] = [:]
  ) {
    self.view = view
    self.fetch = fetch
    self.push = push
    self.download = download
    self.releaseDownload = releaseDownload
  }
}

/// The counters a node keeps for one group.
///
/// Python: `STATS_INIT_GROUP` (`server.py:4642`).
public struct RNGitGroupStatistics: Equatable, Sendable {

  /// Group page views, by `YYYY-MM-DD`.
  public var view: [String: Int]

  /// Counters for the group's repositories, by repository name.
  public var repositories: [String: RNGitRepositoryStatistics]

  /// Counters that are all empty.
  public init(view: [String: Int] = [:], repositories: [String: RNGitRepositoryStatistics] = [:]) {
    self.view = view
    self.repositories = repositories
  }
}

/// Everything a node counts, as it holds the figures in memory and on disk.
///
/// Python: the node's `stats` dictionary (`server.py:2078`) and the seven `record_*`
/// methods that fill it (`server.py:4793-4907`).
///
/// Each group and repository carries its own counters. Python assigns the shared class
/// dictionaries `STATS_INIT_GROUP` and `STATS_INIT_REPO` rather than copies of them
/// (`server.py:4810`, `server.py:4828`), so every group it creates in one run is the same
/// dictionary and reports the same figures.
public struct RNGitStatistics: Equatable, Sendable {

  /// Front page views, by `YYYY-MM-DD`.
  ///
  /// Python: `stats["pages"]["front"]`, the only page `record_page_view` writes
  /// (`server.py:4798`).
  public var frontPageViews: [String: Int]

  /// Counters for the groups the node serves, by group name.
  public var groups: [String: RNGitGroupStatistics]

  /// Counters that are all empty.
  public init(
    frontPageViews: [String: Int] = [:], groups: [String: RNGitGroupStatistics] = [:]
  ) {
    self.frontPageViews = frontPageViews
    self.groups = groups
  }
}

// MARK: - Recording

extension RNGitStatistics {

  /// Counts one front page view on `day`.
  public mutating func recordPageView(on day: String) {
    frontPageViews[day, default: 0] += 1
  }

  /// Counts one view of the page for `group` on `day`.
  public mutating func recordGroupView(_ group: String, on day: String) {
    groups[group, default: RNGitGroupStatistics()].view[day, default: 0] += 1
  }

  /// Counts one view of the page for `repository` in `group` on `day`.
  public mutating func recordRepositoryView(
    _ group: String, _ repository: String, on day: String
  ) {
    increment(group, repository, on: day) { $0.view[day, default: 0] += 1 }
  }

  /// Counts one fetch from `repository` in `group` on `day`.
  public mutating func recordFetch(_ group: String, _ repository: String, on day: String) {
    increment(group, repository, on: day) { $0.fetch[day, default: 0] += 1 }
  }

  /// Counts one push to `repository` in `group` on `day`.
  public mutating func recordPush(_ group: String, _ repository: String, on day: String) {
    increment(group, repository, on: day) { $0.push[day, default: 0] += 1 }
  }

  /// Counts one archive download from `repository` in `group` on `day`.
  public mutating func recordDownload(_ group: String, _ repository: String, on day: String) {
    increment(group, repository, on: day) { $0.download[day, default: 0] += 1 }
  }

  /// Counts one release asset download from `repository` in `group` on `day`.
  public mutating func recordReleaseDownload(
    _ group: String, _ repository: String, on day: String
  ) {
    increment(group, repository, on: day) { $0.releaseDownload[day, default: 0] += 1 }
  }

  private mutating func increment(
    _ group: String, _ repository: String, on day: String,
    _ body: (inout RNGitRepositoryStatistics) -> Void
  ) {
    var record = groups[group] ?? RNGitGroupStatistics()
    var counters = record.repositories[repository] ?? RNGitRepositoryStatistics()
    body(&counters)
    record.repositories[repository] = counters
    groups[group] = record
  }
}

// MARK: - Coding

extension RNGitStatistics {

  /// The statistics `data` carries, or empty ones if it is not a stats file.
  ///
  /// Keys the node does not write are dropped, as are counts that are not integers.
  public static func decoding(_ data: Data) -> RNGitStatistics {
    guard let value = try? MsgPack.decode(data), let root = value.asDictionary else {
      return RNGitStatistics()
    }
    var statistics = RNGitStatistics()
    statistics.frontPageViews = counts(root["pages"]?.asDictionary?["front"])
    for (name, record) in root["groups"]?.asDictionary ?? [:] {
      guard let fields = record.asDictionary else { continue }
      var group = RNGitGroupStatistics(view: counts(fields["view"]))
      for (repository, entry) in fields["repositories"]?.asDictionary ?? [:] {
        guard let counters = entry.asDictionary else { continue }
        group.repositories[repository] = RNGitRepositoryStatistics(
          view: counts(counters["view"]), fetch: counts(counters["fetch"]),
          push: counts(counters["push"]), download: counts(counters["download"]),
          releaseDownload: counts(counters["release_download"]))
      }
      statistics.groups[name] = group
    }
    return statistics
  }

  /// These statistics as a stats file's contents, with every key in sorted order.
  public func encoded() -> Data {
    var groupEntries: [(MsgPack.Value, MsgPack.Value)] = []
    for name in Self.sorted(Array(groups.keys)) {
      guard let group = groups[name] else { continue }
      var repositoryEntries: [(MsgPack.Value, MsgPack.Value)] = []
      for repository in Self.sorted(Array(group.repositories.keys)) {
        guard let counters = group.repositories[repository] else { continue }
        repositoryEntries.append(
          (
            .string(repository),
            .map([
              (.string("view"), Self.counted(counters.view)),
              (.string("fetch"), Self.counted(counters.fetch)),
              (.string("push"), Self.counted(counters.push)),
              (.string("download"), Self.counted(counters.download)),
              (.string("release_download"), Self.counted(counters.releaseDownload)),
            ])
          ))
      }
      groupEntries.append(
        (
          .string(name),
          .map([
            (.string("view"), Self.counted(group.view)),
            (.string("repositories"), .map(repositoryEntries)),
          ])
        ))
    }
    return MsgPack.encode(
      .map([
        (.string("pages"), .map([(.string("front"), Self.counted(frontPageViews))])),
        (.string("groups"), .map(groupEntries)),
      ]))
  }

  private static func counts(_ value: MsgPack.Value?) -> [String: Int] {
    var result: [String: Int] = [:]
    for (day, count) in value?.asDictionary ?? [:] {
      if let number = count.asInt { result[day] = number }
    }
    return result
  }

  private static func counted(_ counters: [String: Int]) -> MsgPack.Value {
    .map(sorted(Array(counters.keys)).map { (.string($0), .int(Int64(counters[$0] ?? 0))) })
  }

  /// `names` in the order Python's `sorted` puts them, which compares by code point.
  private static func sorted(_ names: [String]) -> [String] {
    names.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) { $0 < $1 } }
  }
}

// MARK: - Store

/// Why a stats file could not be written.
public enum RNGitStatsError: Error, Equatable, Sendable {

  /// The file could not be replaced.
  case notWritable(path: String)
}

/// The stats file a node keeps beside its configuration.
///
/// Python: `__load_stats` and `__persist_stats` (`server.py:2076-2095`).
public enum RNGitStatsStore {

  /// The statistics stored at `path`, creating the file with empty ones if it is missing.
  ///
  /// Answers empty statistics when the file cannot be read or does not decode, as Python
  /// does by setting `stats` before it opens the file (`server.py:2078`).
  public static func load(from path: String) -> RNGitStatistics {
    guard FileManager.default.fileExists(atPath: path) else {
      try? RNGitStatistics().encoded().write(to: URL(fileURLWithPath: path))
      return RNGitStatistics()
    }
    guard let data = FileManager.default.contents(atPath: path) else { return RNGitStatistics() }
    return RNGitStatistics.decoding(data)
  }

  /// Writes `statistics` to `path` through a temporary file, replacing what was there.
  public static func persist(_ statistics: RNGitStatistics, to path: String) throws {
    let temporaryPath = path + ".tmp"
    do {
      try statistics.encoded().write(to: URL(fileURLWithPath: temporaryPath))
    } catch {
      throw RNGitStatsError.notWritable(path: path)
    }
    guard rename(temporaryPath, path) == 0 else {
      throw RNGitStatsError.notWritable(path: path)
    }
  }

  /// The day `date` falls on where the node runs, as the counters key it.
  ///
  /// Python: `_get_day` (`server.py:4788-4791`).
  public static func day(at date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}
