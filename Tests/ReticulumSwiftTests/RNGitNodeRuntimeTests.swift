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

/// What a node does on each pass of its periodic jobs, and what it writes about a request.
final class RNGitNodeRuntimeTests: XCTestCase {

  /// The five intervals match the reference's own numbers.
  func testTheIntervalsMatchTheReference() {
    XCTAssertEqual(RNGitNodeRuntime.jobsInterval, 5)
    XCTAssertEqual(RNGitNodeRuntime.statisticsInterval, 180)
    XCTAssertEqual(RNGitNodeRuntime.linkCleanInterval, 5)
    XCTAssertEqual(RNGitNodeRuntime.syncCheckInterval, 900)
  }

  /// A pass before anything is due does nothing.
  func testAPassBeforeAnythingIsDueDoesNothing() {
    var settings = RNGitNodeSettings()
    settings.announceInterval = 60
    let schedule = RNGitNodeRuntime.Schedule(
      announce: 1000, statistics: 1000, syncCheck: 1000, linkClean: 1000)

    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1001, schedule: schedule, settings: settings),
      RNGitNodeRuntime.Jobs())
  }

  /// Each job comes due once its own interval has passed, and not a moment before.
  func testEachJobComesDueOnceItsIntervalHasPassed() {
    var settings = RNGitNodeSettings()
    settings.announceInterval = 60
    let schedule = RNGitNodeRuntime.Schedule(
      announce: 1000, statistics: 1000, syncCheck: 1000, linkClean: 1000)

    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1005, schedule: schedule, settings: settings).cleanLinks, false)
    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1006, schedule: schedule, settings: settings).cleanLinks, true)

    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1060, schedule: schedule, settings: settings).announce, false)
    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1061, schedule: schedule, settings: settings).announce, true)

    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1180, schedule: schedule, settings: settings).persistStatistics,
      false)
    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1181, schedule: schedule, settings: settings).persistStatistics,
      true)

    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1900, schedule: schedule, settings: settings).syncMirrors, false)
    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1901, schedule: schedule, settings: settings).syncMirrors, true)
  }

  /// An announce interval of zero leaves the node announcing only when it is asked to.
  func testAnAnnounceIntervalOfZeroNeverComesDue() {
    var settings = RNGitNodeSettings()
    settings.announceInterval = 0
    let schedule = RNGitNodeRuntime.Schedule(
      announce: 0, statistics: .greatestFiniteMagnitude, syncCheck: .greatestFiniteMagnitude,
      linkClean: .greatestFiniteMagnitude)

    XCTAssertFalse(
      RNGitNodeRuntime.due(at: 1_000_000, schedule: schedule, settings: settings).announce)
  }

  /// A mirror interval of zero leaves mirrors alone, however long the check has waited.
  func testAMirrorIntervalOfZeroNeverComesDue() {
    var settings = RNGitNodeSettings()
    settings.mirrorInterval = 0
    let schedule = RNGitNodeRuntime.Schedule(
      announce: .greatestFiniteMagnitude, statistics: .greatestFiniteMagnitude, syncCheck: 0,
      linkClean: .greatestFiniteMagnitude)

    XCTAssertFalse(
      RNGitNodeRuntime.due(at: 1_000_000, schedule: schedule, settings: settings).syncMirrors)
  }

  /// A pass that everything is due for reports all four.
  func testAPassThatEverythingIsDueForReportsAllFour() {
    var settings = RNGitNodeSettings()
    settings.announceInterval = 60
    let schedule = RNGitNodeRuntime.Schedule(
      announce: 0, statistics: 0, syncCheck: 0, linkClean: 0)

    XCTAssertEqual(
      RNGitNodeRuntime.due(at: 1_000_000, schedule: schedule, settings: settings),
      RNGitNodeRuntime.Jobs(
        announce: true, persistStatistics: true, syncMirrors: true, cleanLinks: true))
  }

  /// A mirror comes due once its own last sync is further back than the interval.
  func testAMirrorComesDueOnceItsLastSyncIsFurtherBackThanTheInterval() {
    var settings = RNGitNodeSettings()
    settings.mirrorInterval = 3600

    XCTAssertFalse(RNGitNodeRuntime.mirrorDue(syncedAt: 1000, at: 4600, settings: settings))
    XCTAssertTrue(RNGitNodeRuntime.mirrorDue(syncedAt: 1000, at: 4601, settings: settings))
    XCTAssertTrue(RNGitNodeRuntime.mirrorDue(syncedAt: nil, at: 3601, settings: settings))
  }

  /// A request from a blocked identity is written as blocked, and at a quieter level.
  func testARequestFromABlockedIdentityIsWrittenAsBlocked() {
    let blocked = Data(repeating: 0xAA, count: 16)
    let settings = {
      var made = RNGitNodeSettings()
      made.blockedIdentities = [blocked]
      return made
    }()

    XCTAssertEqual(
      RNGitNodeRuntime.requestLine("List request from remote x", from: blocked, settings: settings),
      RNGitNodeRuntime.LogLine(text: "Blocked: List request from remote x", level: .debug))
    XCTAssertEqual(
      RNGitNodeRuntime.requestLine(
        "List request from remote x", from: Data(repeating: 0xBB, count: 16), settings: settings),
      RNGitNodeRuntime.LogLine(text: "List request from remote x", level: .verbose))
    XCTAssertEqual(
      RNGitNodeRuntime.requestLine("List request from nobody", from: nil, settings: settings),
      RNGitNodeRuntime.LogLine(text: "List request from nobody", level: .verbose))
  }

  /// Only the links that are no longer up are swept away.
  func testOnlyTheLinksThatAreNoLongerUpAreSweptAway() {
    let up = Data([0x01])
    let closed = Data([0x02])
    let pending = Data([0x03])

    XCTAssertEqual(
      RNGitNodeRuntime.stale(among: [up: .active, closed: .closed, pending: .pending]),
      [closed, pending])
    XCTAssertEqual(RNGitNodeRuntime.stale(among: [:]), [])
  }
}
