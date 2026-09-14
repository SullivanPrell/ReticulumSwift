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

/// How a page writes sizes, times, tabs and diffs.
public enum RNGitPageFormatting {

  /// A size the way the rest of the stack writes one.
  public static func size(_ bytes: Int) -> String { RNSUtilities.prettysize(bytes) }

  /// `timestamp` as a date and a time of day, in `timeZone`.
  public static func absoluteTime(_ timestamp: TimeInterval, in timeZone: TimeZone = .current)
    -> String
  {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: Date(timeIntervalSince1970: timestamp))
    return String(
      format: "%04d-%02d-%02d %02d:%02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
      parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
  }

  /// How long ago `timestamp` was, counted in whichever unit it last fits whole.
  ///
  /// A month is thirty days and a year is 365, so the units are how long ago something was rather
  /// than which calendar month or year it fell in.
  public static func relativeTime(
    _ timestamp: TimeInterval,
    now: TimeInterval = Date()
      .timeIntervalSince1970
  ) -> String {
    let elapsed = now - timestamp
    let units: [(within: TimeInterval, each: TimeInterval, name: String)] = [
      (3600, 60, "minute"), (86_400, 3600, "hour"), (604_800, 86_400, "day"),
      (2_592_000, 604_800, "week"), (31_536_000, 2_592_000, "month"),
    ]

    if elapsed < 60 { return "just now" }
    for unit in units where elapsed < unit.within {
      return counted(Int(elapsed / unit.each), unit.name)
    }
    return counted(Int(elapsed / 31_536_000), "year")
  }

  /// Every tab in `text` written as the spaces a tab is drawn with.
  public static func tabs(_ text: String?) -> String? {
    text?.replacingOccurrences(of: "\t", with: RNGitPage.tabWidth)
  }

  /// `diff` with each line coloured by what it does to the file.
  ///
  /// The blank line before each file's header is what separates one file from the last.
  public static func diff(_ diff: String) -> String {
    lines(of: diff).map { line -> String in
      if line.hasPrefix("+") {
        return line.hasPrefix("+++")
          ? RNGitPageMicron.escape(line)
          : RNGitPage.Colour.diffAdded + RNGitPageMicron.escape(line) + "`f"
      }
      if line.hasPrefix("-") {
        return line.hasPrefix("---")
          ? RNGitPageMicron.escape("\\" + line)
          : RNGitPage.Colour.diffRemoved + RNGitPageMicron.escape(line) + "`f"
      }
      if line.hasPrefix("@@") {
        return RNGitPage.Colour.diffPosition + RNGitPageMicron.escape(line) + "`f"
      }
      if line.hasPrefix("diff ") || line.hasPrefix("index ") || line.hasPrefix("new file")
        || line.hasPrefix("deleted file")
      {
        let separated = line.hasPrefix("diff --git a") ? "\n" : ""
        return separated + RNGitPage.Colour.dim + RNGitPageMicron.escape(line) + "`f"
      }
      return RNGitPageMicron.escape(line)
    }.joined(separator: "\n")
  }

  /// `text` with nothing coloured, which is how a commit message is written out.
  public static func commit(_ text: String) -> String {
    lines(of: text).map { line in
      RNGitPageMicron.escape(line.hasPrefix("-") ? "\\" + line : line)
    }.joined(separator: "\n")
  }

  /// The lines of `text`, each backslash in it already doubled so micron leaves it alone.
  private static func lines(of text: String) -> [String] {
    text.replacingOccurrences(of: "\\", with: "\\\\").components(separatedBy: "\n")
  }

  /// `count` of `unit`, in the plural unless there is one.
  private static func counted(_ count: Int, _ unit: String) -> String {
    "\(count) " + unit + (count == 1 ? "" : "s") + " ago"
  }
}
