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

/// Tests for Destination class-level ratchet constants.
/// Python: Destination.RATCHET_COUNT = 512, Destination.RATCHET_INTERVAL = 30*60
final class DestinationRatchetConstantsTests: XCTestCase {

    func testRatchetCountConstant() {
        // Python: Destination.RATCHET_COUNT = 512
        XCTAssertEqual(Destination.ratchetCount, 512)
    }

    func testRatchetIntervalConstant() {
        // Python: Destination.RATCHET_INTERVAL = 30*60 = 1800
        XCTAssertEqual(Destination.ratchetInterval, 1800)
    }

    /// The constant is only worth anything if a destination actually retains that many.
    ///
    /// This assertion used to re-check `Destination.ratchetCount == 512`—the same check
    /// as the preceding `testRatchetCountConstant`—under a name that implied it covered the
    /// runtime default, while the default was 8 and nothing tested it.
    func testDefaultRetainedRatchetsIsTheConstantAndNotJustDeclaredAsIt() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "test", aspects: ["ratchets"]
        )
        XCTAssertNotNil(destination.identity)
        for _ in 0..<(Destination.ratchetCount + 10) { identity.rotateRatchet() }
        // Python: `self.ratchets[:512]`, active ratchet included at index 0.
        XCTAssertEqual(identity.ratchetPrivateKeyPool.count, Destination.ratchetCount)
    }

    func testDefaultRatchetIntervalConstantValue() throws {
        // Python: Destination.RATCHET_INTERVAL = 1800 (30 minutes)
        XCTAssertEqual(Destination.ratchetInterval, 1800)
    }
}
