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

/// Constants mirroring `RNS/Utilities/rnx.py` (Reticulum Remote Execute Utility).
///
/// `rnx.py` allows running commands on a remote host over authenticated RNS links.
/// These named constants expose the application-name used for RNS destinations, enabling
/// Swift applications to interoperate with `rnx` listen endpoints.
public enum RNXApp {

  /// Application name used for RNS destinations.
  ///
  /// Python: `APP_NAME = "rnx"`.
  public static let appName: String = "rnx"

  /// Response code returned when a fetch request isn't allowed.
  ///
  /// Python: `REQ_FETCH_NOT_ALLOWED = 0xF0` in **rncp.py:70**—despite living here,
  /// this constant belongs to `rncp`, not `rnx`; `rnx.py` declares no `0xF0`. Kept
  /// because `RNXProtocolTests.testReqFetchNotAllowed` asserts it, but the rnx port
  /// doesn't reference it anywhere.
  public static let reqFetchNotAllowed: UInt8 = 0xF0
}
