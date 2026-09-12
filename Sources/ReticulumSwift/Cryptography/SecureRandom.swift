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

/// Cryptographically secure random bytes.
///
/// Every caller in the port needs the same thing — `n` unpredictable bytes — and each one
/// used to reach for `SecRandomCopyBytes` through an unsafe mutable buffer, force-unwrapping
/// `baseAddress` and discarding the `OSStatus`. That shape had two defects beyond the banned
/// `!`: a failure filled the buffer with zeroes and reported nothing, and the check would
/// have had to be repeated correctly at eleven call sites. Binding the pointer and checking
/// the status once, here, removes both.
public enum SecureRandom {

  /// Returns `count` cryptographically secure random bytes.
  ///
  /// A `count` of zero or less yields empty data without consulting the generator. If
  /// `SecRandomCopyBytes` reports a failure the bytes are drawn from
  /// `SystemRandomNumberGenerator` instead, which is also seeded from the system entropy
  /// pool, so the result is never a partially filled buffer.
  ///
  /// - Parameter count: The number of bytes to produce.
  /// - Returns: Exactly `count` random bytes.
  public static func bytes(_ count: Int) -> Data {
    guard count > 0 else { return Data() }
    var bytes = Data(count: count)
    let status = bytes.withUnsafeMutableBytes { buffer -> Int32 in
      guard let base = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, count, base)
    }
    guard status == errSecSuccess else { return fallbackBytes(count) }
    return bytes
  }

  /// Draws `count` bytes from `SystemRandomNumberGenerator`.
  ///
  /// Reached only when `SecRandomCopyBytes` fails, which it does not do in normal operation.
  private static func fallbackBytes(_ count: Int) -> Data {
    var generator = SystemRandomNumberGenerator()
    var bytes = Data(capacity: count)
    for _ in 0..<count {
      bytes.append(UInt8.random(in: UInt8.min...UInt8.max, using: &generator))
    }
    return bytes
  }
}
