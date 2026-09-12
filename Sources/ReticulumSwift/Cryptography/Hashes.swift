//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import CryptoKit
import Foundation

/// The hash functions the Reticulum wire format uses.
public enum Hashes {
  /// Returns the full 32-byte SHA-256 of `data`.
  public static func fullHash(_ data: Data) -> Data {
    Data(SHA256.hash(data: data))
  }

  /// Returns the leading 16 bytes of the SHA-256 of `data`.
  public static func truncatedHash(_ data: Data) -> Data {
    Data(SHA256.hash(data: data).prefix(Constants.truncatedHashLength))
  }

  /// Returns the 64-byte SHA-512 of `data`.
  public static func sha512(_ data: Data) -> Data {
    Data(SHA512.hash(data: data))
  }

  /// Returns a truncated hash over fresh random bytes.
  public static func randomHash() -> Data {
    let bytes = SecureRandom.bytes(Constants.truncatedHashLength)
    return Data(SHA256.hash(data: bytes).prefix(Constants.truncatedHashLength))
  }
}
