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

/// The charts a statistics page is drawn with, as Python RNS 1.5.4 draws them.
final class RNGitPageChartsTests: XCTestCase {

  /// The `halfblockDefault` chart is drawn as the reference draws it.
  func testChartHalfblockDefaultMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart(
        [0, 3, 7, 1, 12],
        labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"]),
      "`FT666666Peak: 12`f\n│    `FT666666`BT666666▀`f`b\n│    `FT666666`BT666666▀`f`b\n│    `FT666666`BT646464▀`f`b\n│    `FT606060`BT5c5c5c▀`f`b\n│  `FT545454▄`f `FT585858`BT545454▀`f`b\n│  `FT515151`BT4d4d4d▀`f`b `FT515151`BT4d4d4d▀`f`b\n│  `FT494949`BT454545▀`f`b `FT494949`BT454545▀`f`b\n│ `FT3d3d3d▄`f`FT414141`BT3d3d3d▀`f`b `FT414141`BT3d3d3d▀`f`b\n│ `FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b `FT393939`BT353535▀`f`b\n│ `FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT2d2d2d▄`f`FT313131`BT2d2d2d▀`f`b\n└─────┘\n`F6662026-01-01  `f`F666  2026-01-05`f\n"
    )
  }

  /// The `halfblockColoured` chart is drawn as the reference draws it.
  func testChartHalfblockColouredMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart(
        [0, 3, 7, 1, 12],
        labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"],
        colour: "10b981", height: 6),
      "`FT10b981Peak: 12`f\n│    `FT10b981`BT10b981▀`f`b\n│    `FT10b981`BT0fb67f▀`f`b\n│  `FT0d9e6e▄`f `FT0eaa77`BT0d9e6e▀`f`b\n│  `FT0c9366`BT0b875e▀`f`b `FT0c9366`BT0b875e▀`f`b\n│ `FT09704e▄`f`FT0a7b56`BT09704e▀`f`b `FT0a7b56`BT09704e▀`f`b\n│ `FT086446`BT07583e▀`f`b`FT086446`BT07583e▀`f`b`FT07583e▄`f`FT086446`BT07583e▀`f`b\n└─────┘\n`F6662026-01-01  `f`F666  2026-01-05`f\n"
    )
  }

  /// The `halfblockShortColour` chart is drawn as the reference draws it.
  func testChartHalfblockShortColourMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart(
        [0, 3, 7, 1, 12],
        labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"],
        colour: "fe6"),
      "`FTffee66Peak: 12`f\n│    `FTffee66`BTffee66▀`f`b\n│    `FTffee66`BTffee66▀`f`b\n│    `FTffee66`BTfbea64▀`f`b\n│    `FTf1e160`BTe8d85c▀`f`b\n│  `FTd4c654▄`f `FTdecf58`BTd4c654▀`f`b\n│  `FTcbbd51`BTc1b44d▀`f`b `FTcbbd51`BTc1b44d▀`f`b\n│  `FTb7ab49`BTaea245▀`f`b `FTb7ab49`BTaea245▀`f`b\n│ `FT9b903d▄`f`FTa49941`BT9b903d▀`f`b `FTa49941`BT9b903d▀`f`b\n│ `FT918739`BT877e35▀`f`b`FT918739`BT877e35▀`f`b `FT918739`BT877e35▀`f`b\n│ `FT7e7531`BT746c2d▀`f`b`FT7e7531`BT746c2d▀`f`b`FT746c2d▄`f`FT7e7531`BT746c2d▀`f`b\n└─────┘\n`F6662026-01-01  `f`F666  2026-01-05`f\n"
    )
  }

  /// The `halfblockSecondary` chart is drawn as the reference draws it.
  func testChartHalfblockSecondaryMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart(
        [0, 3, 7, 1, 12],
        labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"],
        colour: "3b82f6", height: 4, secondaryColour: "13428A"),
      "`FT3b82f6Peak: 12`f\n│    `FT3b82f6`BT3b82f6▀`f`b\n│    `FT3a80f3`BT3376e1▀`f`b\n│  `FT2d6bd0`BT2661be▀`f`b `FT2d6bd0`BT2661be▀`f`b\n│ `FT2056ad`BT194c9b▀`f`b`FT2056ad`BT194c9b▀`f`b`FT194c9b▄`f`FT2056ad`BT194c9b▀`f`b\n└─────┘\n`F6662026-01-01  `f`F666  2026-01-05`f\n"
    )
  }

  /// The `halfblockGradientFactor` chart is drawn as the reference draws it.
  func testChartHalfblockGradientFactorMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart(
        [0, 3, 7, 1, 12],
        labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"],
        colour: "B9A810", height: 5, gradientFactor: 2.5),
      "`FTB9A810Peak: 12`f\n│    `FTb9a810`BTb9a810▀`f`b\n│    `FTb9a810`BTb9a810▀`f`b\n│  `FTb9a810▄`f `FTb9a810`BTb9a810▀`f`b\n│  `FTb9a810`BT9e8f0d▀`f`b `FTb9a810`BT9e8f0d▀`f`b\n│ `FT83770b`BT685e08▀`f`b`FT83770b`BT685e08▀`f`b`FT685e08▄`f`FT83770b`BT685e08▀`f`b\n└─────┘\n`F6662026-01-01  `f`F666  2026-01-05`f\n"
    )
  }

  /// The `halfblockEmpty` chart is drawn as the reference draws it.
  func testChartHalfblockEmptyMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart(
        [], labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"]),
      "No data available\n")
  }

  /// The `halfblockAllZero` chart is drawn as the reference draws it.
  func testChartHalfblockAllZeroMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart([0, 0, 0], labels: ["2026-01-01", "2026-01-02", "2026-01-03"]),
      "No data available\n")
  }

  /// The `halfblockSinglePoint` chart is drawn as the reference draws it.
  func testChartHalfblockSinglePointMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart([5], labels: ["only"]),
      "`FT666666Peak: 5`f\n│`FT666666`BT666666▀`f`b\n│`FT666666`BT666666▀`f`b\n│`FT666666`BT646464▀`f`b\n│`FT606060`BT5c5c5c▀`f`b\n│`FT585858`BT545454▀`f`b\n│`FT515151`BT4d4d4d▀`f`b\n│`FT494949`BT454545▀`f`b\n│`FT414141`BT3d3d3d▀`f`b\n│`FT393939`BT353535▀`f`b\n│`FT313131`BT2d2d2d▀`f`b\n└─┘\n`F666only        `f`F666        only`f\n"
    )
  }

  /// The `halfblockLongLabels` chart is drawn as the reference draws it.
  func testChartHalfblockLongLabelsMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart(
        [0, 3, 7, 1, 12],
        labels: ["a-very-long-label-indeed", "b", "c", "d", "another-very-long-one"]),
      "`FT666666Peak: 12`f\n│    `FT666666`BT666666▀`f`b\n│    `FT666666`BT666666▀`f`b\n│    `FT666666`BT646464▀`f`b\n│    `FT606060`BT5c5c5c▀`f`b\n│  `FT545454▄`f `FT585858`BT545454▀`f`b\n│  `FT515151`BT4d4d4d▀`f`b `FT515151`BT4d4d4d▀`f`b\n│  `FT494949`BT454545▀`f`b `FT494949`BT454545▀`f`b\n│ `FT3d3d3d▄`f`FT414141`BT3d3d3d▀`f`b `FT414141`BT3d3d3d▀`f`b\n│ `FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b `FT393939`BT353535▀`f`b\n│ `FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT2d2d2d▄`f`FT313131`BT2d2d2d▀`f`b\n└─────┘\n`F666a-very-long-`f`F666another-very`f\n"
    )
  }

  /// The `fullblockDefault` chart is drawn as the reference draws it.
  func testChartFullblockDefaultMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.fullBlock(
        [0, 3, 7, 1, 12],
        labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"]),
      "`F666Peak: 12`f\n│    `F666█`f\n│    `F666█`f\n│    `F666▓`f\n│    `F666▓`f\n│  `F666▒`f `F666▒`f\n│  `F666▒`f `F666▒`f\n│  `F666▒`f `F666▒`f\n│ `F666░`f`F666░`f `F666░`f\n│ `F666░`f`F666░`f `F666░`f\n│ `F666░`f`F666░`f`F666░`f`F666░`f\n└─────┘\n`F6662026-01-01  `f`F666  2026-01-05`f\n"
    )
  }

  /// The `fullblockColoured` chart is drawn as the reference draws it.
  func testChartFullblockColouredMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.fullBlock(
        [0, 3, 7, 1, 12],
        labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"],
        colour: "0a0", height: 8),
      "`F0a0Peak: 12`f\n│    `F0a0█`f\n│    `F0a0█`f\n│    `F0a0▓`f\n│  `F0a0▓`f `F0a0▓`f\n│  `F0a0▒`f `F0a0▒`f\n│  `F0a0▒`f `F0a0▒`f\n│ `F0a0░`f`F0a0░`f `F0a0░`f\n│ `F0a0░`f`F0a0░`f`F0a0░`f`F0a0░`f\n└─────┘\n`F6662026-01-01  `f`F666  2026-01-05`f\n"
    )
  }

  /// The `fullblockEmpty` chart is drawn as the reference draws it.
  func testChartFullblockEmptyMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.fullBlock([0, 0], labels: ["2026-01-01", "2026-01-02"]),
      "No data available\n")
  }

  /// The `fullblockSinglePoint` chart is drawn as the reference draws it.
  func testChartFullblockSinglePointMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.fullBlock([3], labels: ["one"]),
      "`F666Peak: 3`f\n│`F666█`f\n│`F666█`f\n│`F666▓`f\n│`F666▓`f\n│`F666▒`f\n│`F666▒`f\n│`F666▒`f\n│`F666░`f\n│`F666░`f\n│`F666░`f\n└─┘\n`F666one         `f`F666         one`f\n"
    )
  }

  /// The `default` stacked chart is drawn as the reference draws it.
  func testCombinedDefaultMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(
        views: [4, 0, 9], fetches: [1, 2, 3], pushes: [7, 5, 0], downloads: [2, 2, 2],
        labels: ["a", "b", "c"]),
      "`FTa0920d`BTa0920d██`f`b Pushes  `FT0da070`BT0da070██`f`b Fetches  `FT3371d6`BT3371d6██`f`b Views  `FT682ac2`BT682ac2██`f`b Downloads\n\n│`FT682ac2`BT3371d6▀`f`b`FT682ac2`BT682ac2█`f`b`FT682ac2`BT3371d6▀`f`b\n│`FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b`FT3371d6`BT3371d6█`f`b\n│`FT3371d6`BT0da070▀`f`b`FT0da070`BTa0920d▀`f`b`FT3371d6`BT3371d6█`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT3371d6`BT3371d6█`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT3371d6`BT0da070▀`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT0da070`BT0da070█`f`b\n└───┘\n`F666a   c`f\n"
    )
  }

  /// The `taller` stacked chart is drawn as the reference draws it.
  func testCombinedTallerMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(
        views: [4, 0, 9], fetches: [1, 2, 3], pushes: [7, 5, 0], downloads: [2, 2, 2],
        labels: ["a", "b", "c"], height: 10),
      "`FTa0920d`BTa0920d██`f`b Pushes  `FT0da070`BT0da070██`f`b Fetches  `FT3371d6`BT3371d6██`f`b Views  `FT682ac2`BT682ac2██`f`b Downloads\n\n│`FT682ac2`BT682ac2█`f`b`FT682ac2`BT682ac2█`f`b`FT682ac2`BT682ac2█`f`b\n│`FT3371d6`BT3371d6█`f`b`FT682ac2`BT682ac2█`f`b`FT3371d6`BT3371d6█`f`b\n│`FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b`FT3371d6`BT3371d6█`f`b\n│`FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b`FT3371d6`BT3371d6█`f`b\n│`FT0da070`BT0da070█`f`b`FTa0920d`BTa0920d█`f`b`FT3371d6`BT3371d6█`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT3371d6`BT3371d6█`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT3371d6`BT3371d6█`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT3371d6`BT0da070▀`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT0da070`BT0da070█`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT0da070`BT0da070█`f`b\n└───┘\n`F666a   c`f\n"
    )
  }

  /// The `dimmed` stacked chart is drawn as the reference draws it.
  func testCombinedDimmedMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(
        views: [4, 0, 9], fetches: [1, 2, 3], pushes: [7, 5, 0], downloads: [2, 2, 2],
        labels: ["a", "b", "c"], dim: 0.5),
      "`FT5c5408`BT5c5408██`f`b Pushes  `FT085c40`BT085c40██`f`b Fetches  `FT1d417b`BT1d417b██`f`b Views  `FT3c1870`BT3c1870██`f`b Downloads\n\n│`FT3c1870`BT1d417b▀`f`b`FT3c1870`BT3c1870█`f`b`FT3c1870`BT1d417b▀`f`b\n│`FT1d417b`BT1d417b█`f`b`FT085c40`BT085c40█`f`b`FT1d417b`BT1d417b█`f`b\n│`FT1d417b`BT085c40▀`f`b`FT085c40`BT5c5408▀`f`b`FT1d417b`BT1d417b█`f`b\n│`FT5c5408`BT5c5408█`f`b`FT5c5408`BT5c5408█`f`b`FT1d417b`BT1d417b█`f`b\n│`FT5c5408`BT5c5408█`f`b`FT5c5408`BT5c5408█`f`b`FT1d417b`BT085c40▀`f`b\n│`FT5c5408`BT5c5408█`f`b`FT5c5408`BT5c5408█`f`b`FT085c40`BT085c40█`f`b\n└───┘\n`F666a   c`f\n"
    )
  }

  /// The `noLabels` stacked chart is drawn as the reference draws it.
  func testCombinedNoLabelsMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(
        views: [4, 0, 9], fetches: [1, 2, 3], pushes: [7, 5, 0], downloads: [2, 2, 2], labels: []),
      "`FTa0920d`BTa0920d██`f`b Pushes  `FT0da070`BT0da070██`f`b Fetches  `FT3371d6`BT3371d6██`f`b Views  `FT682ac2`BT682ac2██`f`b Downloads\n\n│`FT682ac2`BT3371d6▀`f`b`FT682ac2`BT682ac2█`f`b`FT682ac2`BT3371d6▀`f`b\n│`FT3371d6`BT3371d6█`f`b`FT0da070`BT0da070█`f`b`FT3371d6`BT3371d6█`f`b\n│`FT3371d6`BT0da070▀`f`b`FT0da070`BTa0920d▀`f`b`FT3371d6`BT3371d6█`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT3371d6`BT3371d6█`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT3371d6`BT0da070▀`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b`FT0da070`BT0da070█`f`b\n└───┘\n"
    )
  }

  /// The `noViews` stacked chart is drawn as the reference draws it.
  func testCombinedNoViewsMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(views: [], fetches: [1], pushes: [1], downloads: [1], labels: ["a"]),
      "No data available\n")
  }

  /// The `emptyFetches` stacked chart is drawn as the reference draws it.
  func testCombinedEmptyFetchesMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(views: [1], fetches: [], pushes: [1], downloads: [1], labels: ["a"]),
      "No data available\n")
  }

  /// The `allZeroColumn` stacked chart is drawn as the reference draws it.
  func testCombinedAllZeroColumnMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(
        views: [0, 1], fetches: [0, 1], pushes: [0, 1], downloads: [0, 1], labels: ["a", "b"]),
      "`FTa0920d`BTa0920d██`f`b Pushes  `FT0da070`BT0da070██`f`b Fetches  `FT3371d6`BT3371d6██`f`b Views  `FT682ac2`BT682ac2██`f`b Downloads\n\n│ `FT682ac2`BT682ac2█`f`b\n│ `FT682ac2`BT3371d6▀`f`b\n│ `FT3371d6`BT3371d6█`f`b\n│ `FT0da070`BT0da070█`f`b\n│ `FT0da070`BTa0920d▀`f`b\n│ `FTa0920d`BTa0920d█`f`b\n└──┘\n`F666a  b`f\n"
    )
  }

  /// The `chosenColours` stacked chart is drawn as the reference draws it.
  func testCombinedChosenColoursMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(
        views: [4, 0, 9], fetches: [1, 2, 3], pushes: [7, 5, 0], downloads: [2, 2, 2],
        labels: ["a", "b", "c"],
        colours: [.views: "f00", .fetches: "0f0", .pushes: "00f", .downloads: "ff0"]),
      "`FT0000dd`BT0000dd██`f`b Pushes  `FT00dd00`BT00dd00██`f`b Fetches  `FTdd0000`BTdd0000██`f`b Views  `FTdddd00`BTdddd00██`f`b Downloads\n\n│`FTdddd00`BTdd0000▀`f`b`FTdddd00`BTdddd00█`f`b`FTdddd00`BTdd0000▀`f`b\n│`FTdd0000`BTdd0000█`f`b`FT00dd00`BT00dd00█`f`b`FTdd0000`BTdd0000█`f`b\n│`FTdd0000`BT00dd00▀`f`b`FT00dd00`BT0000dd▀`f`b`FTdd0000`BTdd0000█`f`b\n│`FT0000dd`BT0000dd█`f`b`FT0000dd`BT0000dd█`f`b`FTdd0000`BTdd0000█`f`b\n│`FT0000dd`BT0000dd█`f`b`FT0000dd`BT0000dd█`f`b`FTdd0000`BT00dd00▀`f`b\n│`FT0000dd`BT0000dd█`f`b`FT0000dd`BT0000dd█`f`b`FT00dd00`BT00dd00█`f`b\n└───┘\n`F666a   c`f\n"
    )
  }

  /// The `longLabels` stacked chart is drawn as the reference draws it.
  func testCombinedLongLabelsMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(
        views: [1, 2], fetches: [1, 2], pushes: [1, 2], downloads: [1, 2],
        labels: ["a-very-long-label-x", "another-long-label-y"]),
      "`FTa0920d`BTa0920d██`f`b Pushes  `FT0da070`BT0da070██`f`b Fetches  `FT3371d6`BT3371d6██`f`b Views  `FT682ac2`BT682ac2██`f`b Downloads\n\n│`FT682ac2`BT682ac2█`f`b`FT682ac2`BT682ac2█`f`b\n│`FT682ac2`BT3371d6▀`f`b`FT682ac2`BT3371d6▀`f`b\n│`FT3371d6`BT3371d6█`f`b`FT3371d6`BT3371d6█`f`b\n│`FT0da070`BT0da070█`f`b`FT0da070`BT0da070█`f`b\n│`FT0da070`BTa0920d▀`f`b`FT0da070`BTa0920d▀`f`b\n│`FTa0920d`BTa0920d█`f`b`FTa0920d`BTa0920d█`f`b\n└──┘\n`F666a-very-long-another-long`f\n"
    )
  }

  /// The `fullblockTallEnoughToShade` chart is drawn as the reference draws it.
  func testChartFullblockTallEnoughToShadeMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.fullBlock(
        [0, 3, 7, 1, 12],
        labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"], height: 20),
      "`F666Peak: 12`f\n│    `F666█`f\n│    `F666█`f\n│    `F666█`f\n│    `F666▓`f\n│    `F666▓`f\n│    `F666▓`f\n│    `F666▓`f\n│    `F666▓`f\n│  `F666▒`f `F666▒`f\n│  `F666▒`f `F666▒`f\n│  `F666▒`f `F666▒`f\n│  `F666▒`f `F666▒`f\n│  `F666▒`f `F666▒`f\n│  `F666░`f `F666░`f\n│  `F666░`f `F666░`f\n│ `F666░`f`F666░`f `F666░`f\n│ `F666░`f`F666░`f `F666░`f\n│ `F666░`f`F666░`f `F666░`f\n│ `F666░`f`F666░`f`F666░`f`F666░`f\n│ `F666░`f`F666░`f`F666░`f`F666░`f\n└─────┘\n`F6662026-01-01  `f`F666  2026-01-05`f\n"
    )
  }

  /// The `halfblockZeroGradientFactor` chart is drawn as the reference draws it.
  func testChartHalfblockZeroGradientFactorMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart(
        [0, 3, 7, 1, 12],
        labels: ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04", "2026-01-05"],
        gradientFactor: 0),
      "`FT666666Peak: 12`f\n│    `FT666666`BT666666▀`f`b\n│    `FT666666`BT666666▀`f`b\n│    `FT666666`BT646464▀`f`b\n│    `FT606060`BT5c5c5c▀`f`b\n│  `FT545454▄`f `FT585858`BT545454▀`f`b\n│  `FT515151`BT4d4d4d▀`f`b `FT515151`BT4d4d4d▀`f`b\n│  `FT494949`BT454545▀`f`b `FT494949`BT454545▀`f`b\n│ `FT3d3d3d▄`f`FT414141`BT3d3d3d▀`f`b `FT414141`BT3d3d3d▀`f`b\n│ `FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b `FT393939`BT353535▀`f`b\n│ `FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT2d2d2d▄`f`FT313131`BT2d2d2d▀`f`b\n└─────┘\n`F6662026-01-01  `f`F666  2026-01-05`f\n"
    )
  }

  /// The `halfblockWiderThanItsLabels` chart is drawn as the reference draws it.
  func testChartHalfblockWiderThanItsLabelsMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.chart(
        [
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
          26, 27, 28, 29, 30,
        ],
        labels: [
          "d01", "d02", "d03", "d04", "d05", "d06", "d07", "d08", "d09", "d10", "d11", "d12", "d13",
          "d14", "d15", "d16", "d17", "d18", "d19", "d20", "d21", "d22", "d23", "d24", "d25", "d26",
          "d27", "d28", "d29", "d30",
        ]),
      "`FT666666Peak: 30`f\n│                            `FT666666▄`f`FT666666`BT666666▀`f`b\n│                         `FT666666▄`f`FT666666`BT666666▀`f`b`FT666666`BT666666▀`f`b`FT666666`BT666666▀`f`b`FT666666`BT666666▀`f`b\n│                      `FT646464▄`f`FT666666`BT646464▀`f`b`FT666666`BT646464▀`f`b`FT666666`BT646464▀`f`b`FT666666`BT646464▀`f`b`FT666666`BT646464▀`f`b`FT666666`BT646464▀`f`b`FT666666`BT646464▀`f`b\n│                   `FT5c5c5c▄`f`FT606060`BT5c5c5c▀`f`b`FT606060`BT5c5c5c▀`f`b`FT606060`BT5c5c5c▀`f`b`FT606060`BT5c5c5c▀`f`b`FT606060`BT5c5c5c▀`f`b`FT606060`BT5c5c5c▀`f`b`FT606060`BT5c5c5c▀`f`b`FT606060`BT5c5c5c▀`f`b`FT606060`BT5c5c5c▀`f`b`FT606060`BT5c5c5c▀`f`b\n│                `FT545454▄`f`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b`FT585858`BT545454▀`f`b\n│             `FT4d4d4d▄`f`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b`FT515151`BT4d4d4d▀`f`b\n│          `FT454545▄`f`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b`FT494949`BT454545▀`f`b\n│       `FT3d3d3d▄`f`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b`FT414141`BT3d3d3d▀`f`b\n│    `FT353535▄`f`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b`FT393939`BT353535▀`f`b\n│`FT2d2d2d▄`f`FT2d2d2d▄`f`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b`FT313131`BT2d2d2d▀`f`b\n└──────────────────────────────┘\n`F666d01         `f        `F666         d30`f\n"
    )
  }

  /// The `fullblockWiderThanItsLabels` chart is drawn as the reference draws it.
  func testChartFullblockWiderThanItsLabelsMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.fullBlock(
        [
          1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,
          26, 27, 28, 29, 30,
        ],
        labels: [
          "d01", "d02", "d03", "d04", "d05", "d06", "d07", "d08", "d09", "d10", "d11", "d12", "d13",
          "d14", "d15", "d16", "d17", "d18", "d19", "d20", "d21", "d22", "d23", "d24", "d25", "d26",
          "d27", "d28", "d29", "d30",
        ]),
      "`F666Peak: 30`f\n│                           `F666█`f`F666█`f`F666█`f\n│                        `F666█`f`F666█`f`F666█`f`F666█`f`F666█`f`F666█`f\n│                     `F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f\n│                  `F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f`F666▓`f\n│               `F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f\n│            `F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f\n│         `F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f`F666▒`f\n│      `F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f\n│   `F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f\n│`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f`F666░`f\n└──────────────────────────────┘\n`F666d01         `f        `F666         d30`f\n"
    )
  }

  /// The `brightenedPastItsColour` stacked chart is drawn as the reference draws it.
  func testCombinedBrightenedPastItsColourMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageCharts.combined(
        views: [4, 0, 9], fetches: [1, 2, 3], pushes: [7, 5, 0], downloads: [2, 2, 2],
        labels: ["a", "b", "c"], dim: 1.5),
      "`FTb9a810`BTb9a810██`f`b Pushes  `FT10b981`BT10b981██`f`b Fetches  `FT3b82f6`BT3b82f6██`f`b Views  `FT7831e0`BT7831e0██`f`b Downloads\n\n│`FT7831e0`BT3b82f6▀`f`b`FT7831e0`BT7831e0█`f`b`FT7831e0`BT3b82f6▀`f`b\n│`FT3b82f6`BT3b82f6█`f`b`FT10b981`BT10b981█`f`b`FT3b82f6`BT3b82f6█`f`b\n│`FT3b82f6`BT10b981▀`f`b`FT10b981`BTb9a810▀`f`b`FT3b82f6`BT3b82f6█`f`b\n│`FTb9a810`BTb9a810█`f`b`FTb9a810`BTb9a810█`f`b`FT3b82f6`BT3b82f6█`f`b\n│`FTb9a810`BTb9a810█`f`b`FTb9a810`BTb9a810█`f`b`FT3b82f6`BT10b981▀`f`b\n│`FTb9a810`BTb9a810█`f`b`FTb9a810`BTb9a810█`f`b`FT10b981`BT10b981█`f`b\n└───┘\n`F666a   c`f\n"
    )
  }
}
