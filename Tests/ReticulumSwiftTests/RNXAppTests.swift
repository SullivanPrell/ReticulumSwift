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

/// Tests for RNXApp constants.
/// Python reference: RNS/Utilities/rnx.py

final class RNXAppTests: XCTestCase {

  func testAppName() {
    // Python: APP_NAME = "rnx"
    XCTAssertEqual(RNXApp.appName, "rnx")
  }
}
