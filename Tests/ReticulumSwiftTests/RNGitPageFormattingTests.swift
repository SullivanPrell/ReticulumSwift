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

/// How a page writes sizes, times, tabs and diffs, as Python RNS 1.5.4 writes them.
final class RNGitPageFormattingTests: XCTestCase {

  /// The moment the relative times were recorded against.
  private static let recordedAt: TimeInterval = 1_700_000_000

  /// Every recorded size reads as the reference wrote it.
  func testEverySizeMatchesTheReference() {
    XCTAssertEqual(RNGitPageFormatting.size(0), "0 B")
    XCTAssertEqual(RNGitPageFormatting.size(1), "1 B")
    XCTAssertEqual(RNGitPageFormatting.size(999), "999 B")
    XCTAssertEqual(RNGitPageFormatting.size(1000), "1.00 KB")
    XCTAssertEqual(RNGitPageFormatting.size(1023), "1.02 KB")
    XCTAssertEqual(RNGitPageFormatting.size(1024), "1.02 KB")
    XCTAssertEqual(RNGitPageFormatting.size(1025), "1.02 KB")
    XCTAssertEqual(RNGitPageFormatting.size(262144), "262.14 KB")
    XCTAssertEqual(RNGitPageFormatting.size(1_048_576), "1.05 MB")
    XCTAssertEqual(RNGitPageFormatting.size(1_500_000), "1.50 MB")
    XCTAssertEqual(RNGitPageFormatting.size(1_073_741_824), "1.07 GB")
    XCTAssertEqual(RNGitPageFormatting.size(999_999_999_999), "1000.00 GB")
  }

  /// Every recorded elapsed time reads as the reference wrote it.
  func testEveryRelativeTimeMatchesTheReference() {
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 0, now: Self.recordedAt),
      "just now")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 1, now: Self.recordedAt),
      "just now")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 59, now: Self.recordedAt),
      "just now")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 60, now: Self.recordedAt),
      "1 minute ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 61, now: Self.recordedAt),
      "1 minute ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 119, now: Self.recordedAt),
      "1 minute ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 120, now: Self.recordedAt),
      "2 minutes ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 3599, now: Self.recordedAt),
      "59 minutes ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 3600, now: Self.recordedAt),
      "1 hour ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 3601, now: Self.recordedAt),
      "1 hour ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 7200, now: Self.recordedAt),
      "2 hours ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 86399, now: Self.recordedAt),
      "23 hours ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 86400, now: Self.recordedAt),
      "1 day ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 86401, now: Self.recordedAt),
      "1 day ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 172800, now: Self.recordedAt),
      "2 days ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 604799, now: Self.recordedAt),
      "6 days ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 604800, now: Self.recordedAt),
      "1 week ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 1_209_600, now: Self.recordedAt),
      "2 weeks ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 2_591_999, now: Self.recordedAt),
      "4 weeks ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 2_592_000, now: Self.recordedAt),
      "1 month ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 5_184_000, now: Self.recordedAt),
      "2 months ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 31_535_999, now: Self.recordedAt),
      "12 months ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 31_536_000, now: Self.recordedAt),
      "1 year ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 63_072_000, now: Self.recordedAt),
      "2 years ago")
    XCTAssertEqual(
      RNGitPageFormatting.relativeTime(Self.recordedAt - 315_360_000, now: Self.recordedAt),
      "10 years ago")
  }

  /// Every recorded moment reads as the reference wrote it.
  ///
  /// The reference reads a timestamp in the node's own time zone, so the recording was taken in
  /// a fixed one and the port is handed the same.
  func testEveryAbsoluteTimeMatchesTheReference() throws {
    let recorded = try XCTUnwrap(TimeZone(identifier: "UTC"))
    XCTAssertEqual(
      RNGitPageFormatting.absoluteTime(0, in: recorded), "1970-01-01 00:00:00")
    XCTAssertEqual(
      RNGitPageFormatting.absoluteTime(1, in: recorded), "1970-01-01 00:00:01")
    XCTAssertEqual(
      RNGitPageFormatting.absoluteTime(1_700_000_000, in: recorded), "2023-11-14 22:13:20")
    XCTAssertEqual(
      RNGitPageFormatting.absoluteTime(1_000_000_000, in: recorded), "2001-09-09 01:46:40")
    XCTAssertEqual(
      RNGitPageFormatting.absoluteTime(2_000_000_000, in: recorded), "2033-05-18 03:33:20")
    XCTAssertEqual(
      RNGitPageFormatting.absoluteTime(1_234_567_890, in: recorded), "2009-02-13 23:31:30")
  }

  /// A moment is read in the time zone it is handed, not the one the machine is set to.
  func testAMomentIsReadInTheTimeZoneItIsHanded() throws {
    let east = try XCTUnwrap(TimeZone(secondsFromGMT: 3600))
    let west = try XCTUnwrap(TimeZone(secondsFromGMT: -3600))
    XCTAssertEqual(RNGitPageFormatting.absoluteTime(0, in: east), "1970-01-01 01:00:00")
    XCTAssertEqual(RNGitPageFormatting.absoluteTime(0, in: west), "1969-12-31 23:00:00")
  }

  /// Every recorded tab reads as the reference wrote it.
  func testEveryTabMatchesTheReference() {
    XCTAssertEqual(RNGitPageFormatting.tabs("a\tb"), "a   b")
    XCTAssertEqual(RNGitPageFormatting.tabs("\t"), "   ")
    XCTAssertEqual(RNGitPageFormatting.tabs("no tabs"), "no tabs")
    XCTAssertEqual(RNGitPageFormatting.tabs(""), "")
    XCTAssertEqual(RNGitPageFormatting.tabs("a\t\tb"), "a      b")
    XCTAssertNil(RNGitPageFormatting.tabs(nil))
  }

  /// The recorded diff reads as the reference wrote it.
  func testTheRecordedDiffMatchesTheReference() {
    XCTAssertEqual(RNGitPageFormatting.diff(Self.diffSource), Self.formattedDiff)
  }

  /// The recorded diff reads as the reference wrote it as a commit message.
  func testTheRecordedCommitMatchesTheReference() {
    XCTAssertEqual(RNGitPageFormatting.commit(Self.diffSource), Self.formattedCommit)
  }

  /// A file's header is separated from the last file by a blank line.
  func testEachFileInADiffIsSeparatedFromTheLast() {
    let two = "diff --git a/x b/x\ndiff --git a/y b/y"
    XCTAssertEqual(
      RNGitPageFormatting.diff(two).components(separatedBy: "\n").filter(\.isEmpty).count, 2)
  }

  /// The diff the reference was recorded reading.
  private static let diffSource =
    "diff --git a/a.txt b/a.txt\nindex 1111111..2222222 100644\n--- a/a.txt\n+++ b/a.txt\n@@ -1,3 +1,4 @@\n alpha\n-beta\n+BETA\n gamma\n+delta\ndiff --git a/b.txt b/b.txt\ndeleted file mode 100644\nindex 1111111..2222222\n--- a/b.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-x `tick`\ndiff --git a/c.txt b/c.txt\nnew file mode 100644\nindex 1111111..2222222\n--- /dev/null\n+++ b/c.txt\n@@ -0,0 +1 @@\n+back\\slash\n"

  /// What the reference wrote that diff as.
  private static let formattedDiff =
    "\n`F666diff --git a/a.txt b/a.txt`f\n`F666index 1111111..2222222 100644`f\n\\--- a/a.txt\n+++ b/a.txt\n`F0aa@@ -1,3 +1,4 @@`f\n alpha\n`F900-beta`f\n`F0a0+BETA`f\n gamma\n`F0a0+delta`f\n\n`F666diff --git a/b.txt b/b.txt`f\n`F666deleted file mode 100644`f\n`F666index 1111111..2222222`f\n\\--- a/b.txt\n+++ /dev/null\n`F0aa@@ -1 +0,0 @@`f\n`F900-x \\`tick\\``f\n\n`F666diff --git a/c.txt b/c.txt`f\n`F666new file mode 100644`f\n`F666index 1111111..2222222`f\n\\--- /dev/null\n+++ b/c.txt\n`F0aa@@ -0,0 +1 @@`f\n`F0a0+back\\\\slash`f\n"

  /// What the reference wrote that diff as, read as a commit message.
  private static let formattedCommit =
    "diff --git a/a.txt b/a.txt\nindex 1111111..2222222 100644\n\\--- a/a.txt\n+++ b/a.txt\n@@ -1,3 +1,4 @@\n alpha\n\\-beta\n+BETA\n gamma\n+delta\ndiff --git a/b.txt b/b.txt\ndeleted file mode 100644\nindex 1111111..2222222\n\\--- a/b.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n\\-x \\`tick\\`\ndiff --git a/c.txt b/c.txt\nnew file mode 100644\nindex 1111111..2222222\n\\--- /dev/null\n+++ b/c.txt\n@@ -0,0 +1 @@\n+back\\\\slash\n"
}
