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

/// RNS 1.6.1's `storage/announce_rate_table` file (`Storage.py:167-345`).
///
/// A 16-byte header (`RNSART`, version 1, flags 0, ring size, key length, two reserved bytes,
/// a little-endian `uint32` entry count), then columns: the keys, `last` and `blocked` as
/// doubles, `rate_violations` as `int32`, `ts_len` and `ts_head` as bytes, and a ring of
/// `max_ts` doubles per entry, all little-endian.
extension Transport {

  static let announceRateTableMagic = Data("RNSART".utf8)

  /// `save_announce_rate_table` (`Transport.py:4701-4706`): only a transport node that isn't
  /// attached to a shared instance writes the file.
  public func saveAnnounceRateTable(to url: URL) throws {
    guard transportEnabled, !isConnectedToSharedInstance else { return }
    metricsLock.lock()
    let entries = Array(announceRateTable)
    metricsLock.unlock()
    let maxTS = Transport.maxRateTimestamps
    let keyLength = entries.first?.key.count ?? Constants.truncatedHashLength
    guard entries.allSatisfy({ $0.key.count == keyLength }) else {
      Reticulum.log(
        "Could not persist announce rate table to \(url.path): Inconsistent destination hash "
          + "lengths in table", level: .error)
      return
    }
    var blob = Self.announceRateTableMagic
    blob += [0x01, 0x00, UInt8(maxTS & 0xFF), UInt8(keyLength & 0xFF), 0x00, 0x00]
    blob += littleEndian(UInt32(entries.count))
    for entry in entries { blob += entry.key }
    for entry in entries { blob += littleEndian(entry.value.last.bitPattern) }
    for entry in entries { blob += littleEndian(entry.value.blockedUntil.bitPattern) }
    for entry in entries { blob += littleEndian(UInt32(bitPattern: Int32(entry.value.violations))) }
    // This port keeps the timestamps oldest first, so the ring's write cursor sits after the
    // newest one: `len % max_ts`.
    for entry in entries { blob.append(UInt8(entry.value.timestamps.count)) }
    for entry in entries { blob.append(UInt8(entry.value.timestamps.count % maxTS)) }
    for entry in entries {
      let ring =
        entry.value.timestamps + Array(repeating: 0, count: maxTS - entry.value.timestamps.count)
      for timestamp in ring { blob += littleEndian(timestamp.bitPattern) }
    }
    try blob.write(to: url, options: .atomic)
  }

  /// `AnnounceRateTable.load` (`Storage.py:250-327`), replacing the table. Returns `false`, and
  /// leaves the table alone, for a missing or malformed file.
  @discardableResult
  public func loadAnnounceRateTable(from url: URL) -> Bool {
    guard let blob = try? Data(contentsOf: url), blob.count >= 16 else { return false }
    let bytes = [UInt8](blob)
    guard Data(bytes[0..<6]) == Self.announceRateTableMagic, bytes[6] == 0x01, bytes[7] == 0x00
    else { return false }
    let fileMaxTS = Int(bytes[8])
    let keyLength = Int(bytes[9])
    let count = Int(readLE(bytes, at: 12, width: 4))
    guard fileMaxTS >= 1, keyLength >= 1,
      bytes.count == 16 + count * (keyLength + 22 + fileMaxTS * 8)
    else { return false }

    var offset = 16
    var keys: [Data] = []
    for _ in 0..<count {
      keys.append(Data(bytes[offset..<offset + keyLength]))
      offset += keyLength
    }
    guard Set(keys).count == count else { return false }
    func column(_ width: Int) -> [UInt64] {
      defer { offset += count * width }
      return (0..<count).map { readLE(bytes, at: offset + $0 * width, width: width) }
    }
    let last = column(8)
    let blocked = column(8)
    let violations = column(4)
    let lengths = column(1)
    let heads = column(1)
    var table: [Data: AnnounceRateEntry] = [:]
    for slot in 0..<count {
      let length = Int(lengths[slot])
      let head = Int(heads[slot])
      guard length <= fileMaxTS, head < fileMaxTS else { return false }
      let base = offset + slot * fileMaxTS * 8
      let ring = (0..<fileMaxTS).map {
        Double(bitPattern: readLE(bytes, at: base + $0 * 8, width: 8))
      }
      // Oldest first, keeping the newest `max_ts` (`Storage.py:293-300`).
      let chronological =
        length < fileMaxTS ? Array(ring[0..<length]) : Array(ring[head...] + ring[..<head])
      table[keys[slot]] = AnnounceRateEntry(
        last: Double(bitPattern: last[slot]),
        violations: Int(Int32(bitPattern: UInt32(violations[slot]))),
        blockedUntil: Double(bitPattern: blocked[slot]),
        timestamps: Array(chronological.suffix(Transport.maxRateTimestamps)))
    }
    metricsLock.lock()
    announceRateTable = table
    metricsLock.unlock()
    return true
  }

  private func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
    withUnsafeBytes(of: value.littleEndian) { Data($0) }
  }

  private func readLE(_ bytes: [UInt8], at offset: Int, width: Int) -> UInt64 {
    (0..<width).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * $1) }
  }
}
