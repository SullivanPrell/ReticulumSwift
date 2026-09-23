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

/// What an `rngit` node does between requests.
///
/// A node wakes every ``jobsInterval`` seconds and runs whatever has come due: announcing itself,
/// writing its statistics out, syncing its mirrors, and letting go of links that are no longer up.
public enum RNGitNodeRuntime {

  /// Seconds a node sleeps between passes of its periodic jobs.
  public static let jobsInterval: TimeInterval = 5

  /// Seconds between writing the statistics out.
  public static let statisticsInterval: TimeInterval = 180

  /// Seconds between sweeping links that are no longer up.
  public static let linkCleanInterval: TimeInterval = 5

  /// Seconds between looking over the mirrors for one that has waited long enough.
  public static let syncCheckInterval: TimeInterval = 900

  /// What one pass of the periodic jobs runs.
  public struct Jobs: Equatable, Sendable {

    /// Whether the node announces itself.
    public var announce = false

    /// Whether the node writes its statistics out.
    public var persistStatistics = false

    /// Whether the node looks over its mirrors.
    public var syncMirrors = false

    /// Whether the node sweeps links that are no longer up.
    public var cleanLinks = false

    /// Creates a pass running the jobs named, and no others.
    public init(
      announce: Bool = false, persistStatistics: Bool = false, syncMirrors: Bool = false,
      cleanLinks: Bool = false
    ) {
      self.announce = announce
      self.persistStatistics = persistStatistics
      self.syncMirrors = syncMirrors
      self.cleanLinks = cleanLinks
    }
  }

  /// When each periodic job last ran, in seconds since the epoch.
  public struct Schedule: Equatable, Sendable {

    /// When the node last announced itself.
    public var announce: TimeInterval

    /// When the node last wrote its statistics out.
    public var statistics: TimeInterval

    /// When the node last looked over its mirrors.
    public var syncCheck: TimeInterval

    /// When the node last swept its links.
    public var linkClean: TimeInterval

    /// Creates a schedule holding when each job last ran.
    public init(
      announce: TimeInterval, statistics: TimeInterval, syncCheck: TimeInterval,
      linkClean: TimeInterval
    ) {
      self.announce = announce
      self.statistics = statistics
      self.syncCheck = syncCheck
      self.linkClean = linkClean
    }
  }

  /// A line a node writes about a request it took.
  public struct LogLine: Equatable, Sendable {

    /// What the line says.
    public let text: String

    /// How loudly it is said.
    public let level: Reticulum.LogLevel

    /// Creates a line saying `text` at `level`.
    public init(text: String, level: Reticulum.LogLevel) {
      self.text = text
      self.level = level
    }
  }

  /// The jobs `now` has come due for, given when each last ran.
  ///
  /// An announce interval of zero leaves the node announcing only when it is asked to, and a
  /// mirror interval of zero leaves its mirrors alone.
  public static func due(
    at now: TimeInterval, schedule: Schedule, settings: RNGitNodeSettings
  ) -> Jobs {
    Jobs(
      announce: settings.announceInterval != 0
        && now > schedule.announce + TimeInterval(settings.announceInterval),
      persistStatistics: now > schedule.statistics + statisticsInterval,
      syncMirrors: settings.mirrorInterval > 0 && now > schedule.syncCheck + syncCheckInterval,
      cleanLinks: now > schedule.linkClean + linkCleanInterval)
  }

  /// Whether a mirror last synced at `syncedAt` has waited longer than the interval allows.
  ///
  /// A mirror that has never synced counts as one synced at the epoch.
  public static func mirrorDue(
    syncedAt: Int?, at now: TimeInterval, settings: RNGitNodeSettings
  ) -> Bool {
    now > TimeInterval(syncedAt ?? 0) + TimeInterval(settings.mirrorInterval)
  }

  /// The line written about a request `identityHash` made.
  ///
  /// A request from a blocked identity says so, and is said quietly enough that a node under one
  /// does not fill its log with it.
  public static func requestLine(
    _ message: String, from identityHash: Data?, settings: RNGitNodeSettings
  ) -> LogLine {
    guard let identityHash, settings.blockedIdentities.contains(identityHash) else {
      return LogLine(text: message, level: .verbose)
    }
    return LogLine(text: "Blocked: " + message, level: .debug)
  }

  /// The links among `statuses` that are no longer up.
  public static func stale(among statuses: [Data: Link.Status]) -> Set<Data> {
    Set(statuses.filter { $0.value != .active }.keys)
  }
}
