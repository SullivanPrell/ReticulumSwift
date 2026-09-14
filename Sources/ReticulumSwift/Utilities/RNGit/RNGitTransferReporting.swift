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

/// How a client says what a transfer still arriving has done so far.
///
/// The first report starts the clock rather than going out itself, and a report goes out no more
/// often than once every `interval` after that, so a transfer over inside one says nothing. Speed
/// is what arrived since the last report, over the time it took.
struct RNGitTransferReporting {

  /// What the client calls the transfer.
  let label: String

  /// What every report is written behind.
  let indent: String

  /// How long the client waits between reports.
  let interval: TimeInterval

  /// How far along the last report was.
  private var previous: Double = 0

  /// When the last report went out.
  private var updated: TimeInterval?

  /// Creates a reporting of a transfer the client calls `label`, written behind `indent`.
  ///
  /// A transfer the client calls nothing is written with no name at all.
  init(label: String, indent: String, interval: TimeInterval = 0.5) {
    self.label = label
    self.indent = indent
    self.interval = interval
  }

  /// Writes what `progress` says to `output`, where a report is due at `instant`.
  mutating func report(
    _ progress: RNGitTransferProgress, at instant: TimeInterval, to output: RNGitClientOutput
  ) {
    guard let last = updated else {
      updated = instant
      return
    }
    guard instant > last + interval else { return }

    let elapsed = instant - last
    let size = progress.size ?? 0
    let carried = size == 0 ? 0 : (progress.fraction - previous) * Double(size)
    let speed = elapsed > 0 ? (carried / elapsed) * 8 : 0
    previous = progress.fraction
    updated = instant

    guard size != 0 else { return }
    let percent = NetworkProbe.pythonFloatString(
      NetworkProbe.pythonRound(progress.fraction * 100, 1))
    output.write(
      indent + "Transferring" + (label.isEmpty ? "" : " " + label) + ": \(percent)% ("
        + RNSUtilities.prettysize(Double(size) * progress.fraction) + "/"
        + RNSUtilities.prettysize(size) + ") " + RNSUtilities.prettyspeed(speed)
        + String(repeating: " ", count: 10) + "\r")
  }
}
