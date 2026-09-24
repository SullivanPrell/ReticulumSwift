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

/// A repository's statistics page, as Python RNS 1.5.4's `serve_stats_page` renders it.
///
/// Every page is the one the reference rendered with `time.time` pinned to `now` and `TZ=UTC`,
/// over group "proj" holding repository "demo", with how long the page took to generate
/// replaced by `{GEN_TIME}`.
final class RNGitStatsPageVectorTests: XCTestCase {

  /// The moment every page was rendered at: 2026-09-24 13:17 UTC.
  private static let now = Date(timeIntervalSince1970: 1_790_255_820)

  /// The identity a reader who has not identified is resolved as.
  private static let nullIdentityHash = Data(pythonHex: "d7db22f63b453c23bb0688dde565b7c1")!

  /// Counters spread across the window and before it, with every kind of event.
  private static let mixedCounters = RNGitRepositoryStatistics(
    view: ["2026-09-24": 3, "2026-09-20": 7, "2026-09-11": 7, "2026-06-01": 50],
    fetch: ["2026-09-23": 2, "2026-09-12": 1], push: ["2026-09-15": 1],
    download: ["2026-09-24": 1, "2026-09-22": 4],
    releaseDownload: ["2026-09-22": 2, "2026-09-19": 5])

  /// A handler over "proj"/"demo", everyone reading it and seeing its statistics unless
  /// `statsAllowed` is false.
  private static func handler(
    counters: RNGitRepositoryStatistics = RNGitRepositoryStatistics(), statsAllowed: Bool = true,
    blockNullIdentity: Bool = false
  ) -> RNGitPageHandler {
    var permissions = RNGitPermissionSet()
    permissions.read = [.everyone]
    if statsAllowed { permissions.stats = [.everyone] }
    let access = RNGitPageAccess(
      control: RNGitAccessControl(groups: [
        "proj": RNGitGroup(
          name: "proj", path: "/g/proj",
          repositories: [
            "demo": RNGitRepository(name: "demo", path: "/g/proj/demo", permissions: permissions)
          ],
          permissions: permissions)
      ]))
    var settings = RNGitNodeSettings()
    if blockNullIdentity { settings.blockedIdentities = [nullIdentityHash] }
    return RNGitPageHandler(
      access: access, runner: RNGitProcessRunner(),
      destinationHash: Data(repeating: 0x7A, count: 16),
      settings: settings,
      statistics: RNGitStatistics(
        groups: ["proj": RNGitGroupStatistics(repositories: ["demo": counters])]),
      templates: RNGitPageTemplates(
        directory: "/nonexistent/templates", nodeName: "A Node", version: "1.5.4"))
  }

  /// `page` with how long it took to generate replaced, as the recorded pages have it.
  private static func normalised(_ page: Data) -> String {
    let text = String(decoding: page, as: UTF8.self)
    return text.replacingOccurrences(
      of: #"Generated in [^`]*`f$"#, with: "Generated in {GEN_TIME}`f",
      options: .regularExpression)
  }

  private static func serve(
    _ handler: RNGitPageHandler, identityHash: Data? = nil, group: String = "proj",
    repository: String = "demo"
  ) -> String {
    let utc = TimeZone(identifier: "UTC")!
    return normalised(
      handler.serveStatsPage(
        identityHash: identityHash, groupName: group, repositoryName: repository, now: now,
        timeZone: utc))
  }

  func testInvalidRequestMatchesTheReference() {
    XCTAssertEqual(
      Self.serve(Self.handler(), group: ""), Self.invalidRequest.joined(separator: "\n"))
  }

  func testNoIdentityMatchesTheReference() {
    XCTAssertEqual(
      Self.serve(Self.handler(blockNullIdentity: true)), Self.noIdentity.joined(separator: "\n"))
  }

  func testNoStatsPermissionMatchesTheReference() {
    XCTAssertEqual(
      Self.serve(Self.handler(statsAllowed: false)),
      Self.noStatsPermission.joined(separator: "\n"))
  }

  func testUnknownRepositoryMatchesTheReference() {
    XCTAssertEqual(
      Self.serve(Self.handler(), repository: "nope"),
      Self.unknownRepository.joined(separator: "\n"))
  }

  func testNoActivityMatchesTheReference() {
    XCTAssertEqual(Self.serve(Self.handler()), Self.noActivity.joined(separator: "\n"))
  }

  /// A lone view charts, yet its points round down to none.
  func testOneViewTodayMatchesTheReference() {
    XCTAssertEqual(
      Self.serve(Self.handler(counters: RNGitRepositoryStatistics(view: ["2026-09-24": 1]))),
      Self.oneViewToday.joined(separator: "\n"))
  }

  func testMixedActivityMatchesTheReference() {
    XCTAssertEqual(
      Self.serve(Self.handler(counters: Self.mixedCounters)), Self.mixed.joined(separator: "\n"))
  }

  /// The page for the invalid request case, one line per element.
  private static let invalidRequest: [String] =
    [
      "#!c=0",
      "> A Node",
      "",
      "",
      ">>Error",
      "",
      "Invalid request",
      "",
      "<",
      "-",
      "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
    ]

  /// The page for the no identity case, one line per element.
  private static let noIdentity: [String] =
    [
      "#!c=0",
      "> A Node",
      "",
      "",
      ">>No Identity",
      "",
      "This page requires identification, and none was received.",
      "",
      "<",
      "-",
      "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
    ]

  /// The page for the no stats permission case, one line per element.
  private static let noStatsPermission: [String] =
    [
      "#!c=0",
      "> A Node",
      "",
      ">>",
      "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / stats",
      "",
      ">>Error",
      "",
      "The requested repository was not found.",
      "",
      "<",
      "-",
      "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
    ]

  /// The page for the unknown repository case, one line per element.
  private static let unknownRepository: [String] =
    [
      "#!c=0",
      "> A Node",
      "",
      ">>",
      "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[nope`:/page/repo.mu`g=proj|r=nope]`! / stats",
      "",
      ">>Error",
      "",
      "The requested repository was not found.",
      "",
      "<",
      "-",
      "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
    ]

  /// The page for the no activity case, one line per element.
  private static let noActivity: [String] =
    [
      "#!c=0",
      "> A Node",
      "",
      ">>",
      "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / stats",
      "",
      ">>Stats for demo",
      "",
      "`FT10b981Fetches`f   :     0  total `F666  today:   0  peak:   0 ",
      "`f`FTB9A810Pushes`f    :     0  total `F666  today:   0  peak:   0 ",
      "`f`FT3b82f6Views`f     :     0  total `F666  today:   0  peak:   0 `f",
      "`FT7831E0Downloads`f :     0  total `F666  today:   0  peak:   0 `f",
      "`F0aaActivity`f  :     0 points",
      "",
      "`F666No activity`f over the last 90 days (Jun 27 - Sep 24)",
      "",
      "`*",
      "No development activity recorded for this repository in the selected time period.",
      "",
      "`*",
      "<",
      "-",
      "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
    ]

  /// The page for the one view today case, one line per element.
  private static let oneViewToday: [String] =
    [
      "#!c=0",
      "> A Node",
      "",
      ">>",
      "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / stats",
      "",
      ">>Stats for demo",
      "",
      "`FT10b981Fetches`f   :     0  total `F666  today:   0  peak:   0 ",
      "`f`FTB9A810Pushes`f    :     0  total `F666  today:   0  peak:   0 ",
      "`f`FT3b82f6Views`f     :     1  total `F666  today:   1  peak:   1 `f",
      "`FT7831E0Downloads`f :     0  total `F666  today:   0  peak:   0 `f",
      "`F0aaActivity`f  :     0 points",
      "",
      "`F66dLow activity`f over the last 1 days (Jun 27 - Sep 24)",
      "",
      ">>Views",
      "",
      "`FT3b82f6Peak: 1`f",
      "│                                                                                         `FT3b82f6`BT3b82f6▀`f`b",
      "│                                                                                         `FT3b82f6`BT3b82f6▀`f`b",
      "│                                                                                         `FT3b82f6`BT3a80f3▀`f`b",
      "│                                                                                         `FT377cec`BT3478e5▀`f`b",
      "│                                                                                         `FT3273de`BT2f6fd7▀`f`b",
      "│                                                                                         `FT2d6bd0`BT2a67c9▀`f`b",
      "│                                                                                         `FT2763c2`BT255fbb▀`f`b",
      "│                                                                                         `FT225ab4`BT2056ad▀`f`b",
      "│                                                                                         `FT1d52a6`BT1a4e9f▀`f`b",
      "│                                                                                         `FT184a98`BT154691▀`f`b",
      "└──────────────────────────────────────────────────────────────────────────────────────────┘",
      "`F66690 days ago `f                                                                    `F666       Today`f",
      "",
      "`*",
      "No development activity recorded for this repository in the selected time period.",
      "",
      "`*",
      "<",
      "-",
      "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
    ]

  /// The page for the mixed case, one line per element.
  private static let mixed: [String] =
    [
      "#!c=0",
      "> A Node",
      "",
      ">>",
      "`!`[Node`:/page/index.mu]`! / `!`[proj`:/page/group.mu`g=proj]`! / `!`[demo`:/page/repo.mu`g=proj|r=demo]`! / stats",
      "",
      ">>Stats for demo",
      "",
      "`FT10b981Fetches`f   :     3  total `F666  today:   0  peak:   2 ",
      "`f`FTB9A810Pushes`f    :     1  total `F666  today:   0  peak:   1 ",
      "`f`FT3b82f6Views`f     :    17  total `F666  today:   3  peak:   7 `f",
      "`FT7831E0Downloads`f :    12  total `F666  today:   1  peak:   6 `f",
      "`F0aaActivity`f  :    16 points",
      "",
      "`F66dLow activity`f over the last 90 days (Jun 27 - Sep 24)",
      "",
      ">>Fetches",
      "",
      "`FT10b981Peak: 2`f",
      "│                                                                                        `FT10b981`BT10b981▀`f`b ",
      "│                                                                                        `FT10b981`BT10b981▀`f`b ",
      "│                                                                                        `FT10b981`BT10b680▀`f`b ",
      "│                                                                                        `FT11b07f`BT11aa7e▀`f`b ",
      "│                                                                                        `FT12a47d`BT139f7c▀`f`b ",
      "│                                                                             `FT14997b`BT14937a▀`f`b          `FT14997b`BT14937a▀`f`b ",
      "│                                                                             `FT158d79`BT168778▀`f`b          `FT158d79`BT168778▀`f`b ",
      "│                                                                             `FT178177`BT187b76▀`f`b          `FT178177`BT187b76▀`f`b ",
      "│                                                                             `FT187575`BT196f74▀`f`b          `FT187575`BT196f74▀`f`b ",
      "│                                                                             `FT1a6973`BT1b6372▀`f`b          `FT1a6973`BT1b6372▀`f`b ",
      "└──────────────────────────────────────────────────────────────────────────────────────────┘",
      "`F66690 days ago `f                                                                    `F666       Today`f",
      "",
      ">>Pushes",
      "",
      "`FTB9A810Peak: 1`f",
      "│                                                                                `FTb9a810`BTb9a810▀`f`b         ",
      "│                                                                                `FTb9a810`BTb9a810▀`f`b         ",
      "│                                                                                `FTb9a810`BTb7a410▀`f`b         ",
      "│                                                                                `FTb39a10`BTaf9010▀`f`b         ",
      "│                                                                                `FTaa8710`BTa67d10▀`f`b         ",
      "│                                                                                `FTa27310`BT9e6910▀`f`b         ",
      "│                                                                                `FT9a6010`BT965611▀`f`b         ",
      "│                                                                                `FT914c11`BT8d4211▀`f`b         ",
      "│                                                                                `FT893911`BT852f11▀`f`b         ",
      "│                                                                                `FT812511`BT7d1b11▀`f`b         ",
      "└──────────────────────────────────────────────────────────────────────────────────────────┘",
      "`F66690 days ago `f                                                                    `F666       Today`f",
      "",
      ">>Views",
      "",
      "`FT3b82f6Peak: 7`f",
      "│                                                                            `FT3b82f6`BT3b82f6▀`f`b        `FT3b82f6`BT3b82f6▀`f`b    ",
      "│                                                                            `FT3b82f6`BT3b82f6▀`f`b        `FT3b82f6`BT3b82f6▀`f`b    ",
      "│                                                                            `FT3b82f6`BT3a80f3▀`f`b        `FT3b82f6`BT3a80f3▀`f`b    ",
      "│                                                                            `FT377cec`BT3478e5▀`f`b        `FT377cec`BT3478e5▀`f`b    ",
      "│                                                                            `FT3273de`BT2f6fd7▀`f`b        `FT3273de`BT2f6fd7▀`f`b    ",
      "│                                                                            `FT2d6bd0`BT2a67c9▀`f`b        `FT2d6bd0`BT2a67c9▀`f`b    ",
      "│                                                                            `FT2763c2`BT255fbb▀`f`b        `FT2763c2`BT255fbb▀`f`b   `FT2763c2`BT255fbb▀`f`b",
      "│                                                                            `FT225ab4`BT2056ad▀`f`b        `FT225ab4`BT2056ad▀`f`b   `FT225ab4`BT2056ad▀`f`b",
      "│                                                                            `FT1d52a6`BT1a4e9f▀`f`b        `FT1d52a6`BT1a4e9f▀`f`b   `FT1d52a6`BT1a4e9f▀`f`b",
      "│                                                                            `FT184a98`BT154691▀`f`b        `FT184a98`BT154691▀`f`b   `FT184a98`BT154691▀`f`b",
      "└──────────────────────────────────────────────────────────────────────────────────────────┘",
      "`F66690 days ago `f                                                                    `F666       Today`f",
      "",
      ">>Downloads",
      "",
      "`FT7831E0Peak: 6`f",
      "│                                                                                       `FT7831e0`BT7831e0▀`f`b  ",
      "│                                                                                       `FT7831e0`BT7831e0▀`f`b  ",
      "│                                                                                    `FT7831e0`BT7831e0▀`f`b  `FT7831e0`BT7831e0▀`f`b  ",
      "│                                                                                    `FT7831e0`BT7831e0▀`f`b  `FT7831e0`BT7831e0▀`f`b  ",
      "│                                                                                    `FT7831e0`BT7d35d6▀`f`b  `FT7831e0`BT7d35d6▀`f`b  ",
      "│                                                                                    `FT833bc9`BT8a40bd▀`f`b  `FT833bc9`BT8a40bd▀`f`b  ",
      "│                                                                                    `FT9046b0`BT974ca4▀`f`b  `FT9046b0`BT974ca4▀`f`b  ",
      "│                                                                                    `FT9d5297`BTa4588b▀`f`b  `FT9d5297`BTa4588b▀`f`b  ",
      "│                                                                                    `FTaa5d7e`BTb16372▀`f`b  `FTaa5d7e`BTb16372▀`f`b `FTb16372▄`f",
      "│                                                                                    `FTb76965`BTbe6f59▀`f`b  `FTb76965`BTbe6f59▀`f`b `FTb76965`BTbe6f59▀`f`b",
      "└──────────────────────────────────────────────────────────────────────────────────────────┘",
      "`F66690 days ago `f                                                                    `F666       Today`f",
      "",
      ">>Combined Activity",
      "",
      "`FTa0920d`BTa0920d██`f`b Pushes  `FT0da070`BT0da070██`f`b Fetches  `FT3371d6`BT3371d6██`f`b Views  `FT682ac2`BT682ac2██`f`b Downloads",
      "",
      "│                                                                            `FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b  `FTa0920d`BTa0920d█`f`b   `FT682ac2`BT682ac2█`f`b`FT3371d6`BT3371d6█`f`b `FT682ac2`BT682ac2█`f`b`FT0da070`BT0da070█`f`b`FT682ac2`BT682ac2█`f`b",
      "│                                                                            `FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b  `FTa0920d`BTa0920d█`f`b   `FT682ac2`BT682ac2█`f`b`FT3371d6`BT3371d6█`f`b `FT682ac2`BT682ac2█`f`b`FT0da070`BT0da070█`f`b`FT682ac2`BT3371d6▀`f`b",
      "│                                                                            `FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b  `FTa0920d`BTa0920d█`f`b   `FT682ac2`BT682ac2█`f`b`FT3371d6`BT3371d6█`f`b `FT682ac2`BT682ac2█`f`b`FT0da070`BT0da070█`f`b`FT3371d6`BT3371d6█`f`b",
      "│                                                                            `FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b  `FTa0920d`BTa0920d█`f`b   `FT682ac2`BT682ac2█`f`b`FT3371d6`BT3371d6█`f`b `FT682ac2`BT682ac2█`f`b`FT0da070`BT0da070█`f`b`FT3371d6`BT3371d6█`f`b",
      "│                                                                            `FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b  `FTa0920d`BTa0920d█`f`b   `FT682ac2`BT682ac2█`f`b`FT3371d6`BT3371d6█`f`b `FT682ac2`BT682ac2█`f`b`FT0da070`BT0da070█`f`b`FT3371d6`BT3371d6█`f`b",
      "│                                                                            `FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b  `FTa0920d`BTa0920d█`f`b   `FT682ac2`BT682ac2█`f`b`FT3371d6`BT3371d6█`f`b `FT682ac2`BT682ac2█`f`b`FT0da070`BT0da070█`f`b`FT3371d6`BT3371d6█`f`b",
      "└──────────────────────────────────────────────────────────────────────────────────────────┘",
      "`F66690 days ago                                                                            Today`f",
      "",
      "<",
      "-",
      "`a`F666`[Served by rngit 1.5.4`:/page/index.mu] - Generated in {GEN_TIME}`f",
    ]
}
