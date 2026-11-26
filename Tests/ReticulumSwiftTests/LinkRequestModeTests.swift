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

/// A link request whose mode bits name a mode outside `ENABLED_MODES` is refused.
///
/// Python reads the mode from the request (`Link.py:173-177`, `:207`). `prove` then packs it with
/// `mode_byte`, which raises for a mode outside `ENABLED_MODES` (`:168-170`, `:453`), so
/// `validate_request` returns None and registers nothing (`:232-234`).
final class LinkRequestModeTests: XCTestCase {

  private func answer(mode: UInt8) throws -> Link {
    let identity = try Identity(privateKeyBytes: Data(0..<64))
    let destination = try Destination(
      identity: identity, direction: .in, kind: .single, appName: "linkmode", aspects: ["test"])
    let request = Packet(
      destinationType: .single, packetType: .linkRequest, destinationHash: destination.hash,
      data: LinkStampTests.pub + LinkStampTests.sig
        + LinkMTUSignallingTests.signallingBytes(mode: mode))
    return try Link.answer(
      request: request, destination: destination, owner: identity, transport: Transport())
  }

  func testTheEnabledModeIsAnswered() throws {
    XCTAssertNoThrow(try answer(mode: Link.modeAes256Cbc))
  }

  func testAModeOutsideTheEnabledModesIsRefused() {
    for mode in [Link.modeAes128Cbc, Link.modeAes256Gcm, Link.modePqReserved4] {
      XCTAssertThrowsError(try answer(mode: mode), "mode \(mode)") {
        XCTAssertEqual($0 as? Link.LinkError, .malformedRequest)
      }
    }
  }
}
