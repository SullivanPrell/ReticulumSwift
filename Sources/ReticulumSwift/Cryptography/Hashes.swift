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
import CryptoKit

public enum Hashes {
    public static func fullHash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    public static func truncatedHash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data).prefix(Constants.truncatedHashLength))
    }

    public static func sha512(_ data: Data) -> Data {
        Data(SHA512.hash(data: data))
    }

    public static func randomHash() -> Data {
        let bytes = SecureRandom.bytes(Constants.truncatedHashLength)
        return Data(SHA256.hash(data: bytes).prefix(Constants.truncatedHashLength))
    }
}
