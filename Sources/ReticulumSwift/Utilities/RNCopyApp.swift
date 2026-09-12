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

/// Constants mirroring `RNS/Utilities/rncp.py` (Reticulum Copy Utility).
///
/// `rncp.py` implements authenticated file transfer over RNS using the Resource API.
/// These named constants are exposed for use by Swift applications that implement
/// compatible file-transfer endpoints.
public enum RNCopyApp {

    /// Application name used for RNS destinations.
    ///
    /// Python: `APP_NAME = "rncp"`.
    public static let appName: String = "rncp"

    /// Response code returned when a fetch request isn't authorised.
    ///
    /// Python: `REQ_FETCH_NOT_ALLOWED = 0xF0`.
    public static let reqFetchNotAllowed: UInt8 = 0xF0
}
