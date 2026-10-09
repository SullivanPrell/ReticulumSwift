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

/// The shared-instance port is free again when `PosixTCPServer.stop()` returns.
///
/// Python's `LocalServerInterface` leaves the release to process exit, so this is a Swift-only
/// concern: a shared instance stopped and attached again in one process binds the port a
/// second time (`InstanceConnection.attach`) and attaches as a client of its own old socket if
/// the first descriptor is still open.
final class PosixTCPServerStopTests: XCTestCase {

  /// The accept source's cancel handler closes the descriptor on the source's queue, after
  /// `cancel()` has returned. On an idle machine the handler usually wins, so the rounds run
  /// beside busy threads that delay it.
  func testStopClosesTheSocketBeforeItReturns() throws {
    let port = try freeLoopbackPort()
    let finished = LockedFlag(false)
    defer { finished.value = true }
    for _ in 0..<(ProcessInfo.processInfo.activeProcessorCount * 2) {
      Thread.detachNewThread { while !finished.value {} }
    }

    for round in 1...2_000 {
      let server = PosixTCPServer(name: "Shared Instance", port: port)
      do {
        try server.start()
      } catch {
        return XCTFail("round \(round): the previous server's socket was still open: \(error)")
      }
      server.stop()
      guard loopbackPortState(port) == .refused else {
        return XCTFail("round \(round): a connect after stop() was not refused")
      }
    }
  }
}
