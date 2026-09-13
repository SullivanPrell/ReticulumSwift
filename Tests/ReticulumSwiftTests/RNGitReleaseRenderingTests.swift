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

/// What an `rngit` client writes for the release answers that carry less than it reads for.
final class RNGitReleaseRenderingTests: XCTestCase {

  private let rendering = RNGitReleaseRendering(timeZone: TimeZone(identifier: "UTC")!)

  private func release(_ fields: [(String, MsgPack.Value)]) -> MsgPack.Value {
    .map(fields.map { (MsgPack.Value.string($0.0), $0.1) })
  }

  func testAReleaseWithNoNotesLeavesTheNotesColumnEmpty() {
    let listing = rendering.listing(
      .array([
        release([
          ("tag", .string("v1.0")), ("status", .string("draft")), ("created", .uint(0)),
          ("artifacts", .uint(0)), ("preview", .string("")),
        ])
      ]))

    XCTAssertEqual(
      listing,
      "Tag        Status     Created           Objs  Notes\n"
        + String(repeating: "-", count: 80) + "\n"
        + "v1.0       draft      unknown           0     \n")
  }

  func testAReleaseNamingNoPreviewLeavesTheNotesColumnEmpty() {
    let listing = rendering.listing(.array([release([("tag", .string("v1.0"))])]))

    XCTAssertEqual(
      listing?.hasSuffix("v1.0       unknown    unknown           0     \n"), true)
  }

  func testAListingNamingNoReleasesCarriesNone() {
    XCTAssertEqual(
      rendering.listing(release([("latest", .string("v1.0"))])),
      "No releases for this repository\n")
  }

  func testAListingNamingNoLatestNamesNone() {
    let listing = rendering.listing(
      release([("releases", .array([release([("tag", .string("v1.0"))])]))]))

    XCTAssertEqual(listing?.contains("The latest release is"), false)
  }

  func testAViewThatIsNoReleaseReadsAsTheTagAskedAfter() {
    XCTAssertEqual(
      rendering.view(.uint(7), target: "v1.0"),
      "Release : v1.0\nStatus  : unknown\nThanks  : 0\n\n")
  }

  func testATagAndAPreviewAreCutToTheirColumns() {
    let listing = rendering.listing(
      .array([
        release([
          ("tag", .string(String(repeating: "t", count: 24))),
          ("status", .string(String(repeating: "s", count: 24))),
          ("preview", .string(String(repeating: "p", count: 60))),
        ])
      ]))

    XCTAssertEqual(
      listing?.hasSuffix(
        String(repeating: "t", count: 10) + " " + String(repeating: "s", count: 9) + "  "
          + "unknown           0     " + String(repeating: "p", count: 34) + "\n"), true)
  }
}
