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

/// PKCS#7 padding for AES-CBC.
///
/// Block size is 16 bytes; pad value equals the
/// number of pad bytes appended.
public enum PKCS7 {
  /// The cipher block size padding is measured against.
  public static let blockSize: Int = 16

  /// Returns `data` padded up to a whole number of blocks.
  public static func pad(_ data: Data, blockSize: Int = blockSize) -> Data {
    let padLength = blockSize - (data.count % blockSize)
    return data + Data(repeating: UInt8(padLength), count: padLength)
  }

  /// A failure raised when padding is malformed.
  public enum UnpadError: Error { case invalidPadding }

  /// Returns `data` with its padding removed.
  ///
  /// Mirrors Python's `PKCS7.unpad`: only the last byte is read, as the pad
  /// length `n`, and `n` bytes are dropped from the end. The other pad bytes
  /// and the block alignment go unchecked, so ANSI X.923 padding (zeros, then
  /// the length byte), which microReticulum sends, unpads like PKCS#7, and an
  /// `n` of 0 returns `data` unchanged. Callers must authenticate `data` first:
  /// `Token.decrypt` verifies the HMAC before it unpads.
  ///
  /// - Throws: `UnpadError.invalidPadding` when `n` exceeds `blockSize`, which
  ///   is Python's only check, or when `data` is empty or shorter than `n`,
  ///   where Python raises `IndexError` or slices from the end instead.
  public static func unpad(_ data: Data, blockSize: Int = blockSize) throws -> Data {
    guard let last = data.last else { throw UnpadError.invalidPadding }
    let padLength = Int(last)
    guard padLength <= blockSize, padLength <= data.count else {
      throw UnpadError.invalidPadding
    }
    return data.prefix(data.count - padLength)
  }
}
