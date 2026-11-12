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

/// Proof-of-work stamps with fixed-point costs, from `RNS/Stamps.py` (RNS 1.6.0).
///
/// A cost is held as a fixed-point integer with eight fractional bits, so `12.5` is `3200`. A
/// stamp is valid at a cost when `SHA-256(workblock + stamp)` is at or below the target that
/// cost maps to, and its value is how far below the target it lands, floored to the 1/256 grid.
///
/// Generation runs on one core, as Python's does on Darwin (`Stamps.py:269-270`).
public enum Stamps {

  /// Python: `WORKBLOCK_EXPAND_CHUNK`.
  public static let workblockExpandChunk = 256
  /// Python: `WORKBLOCK_EXPAND_ROUNDS`.
  public static let workblockExpandRounds = 3000
  /// Python: `STAMP_SIZE`, the default for detached stamps. Announce and path-request stamps
  /// are `Identity.stampLength` bytes.
  public static let stampSize = 32
  /// Python: `MANTISSA_BITS`.
  public static let mantissaBits = 33
  /// Python: `COST_FP_BITS`.
  public static let costFPBits = 8
  /// Python: `COST_FP`, the fixed-point representation of a cost of 1.
  public static let costFP = 1 << costFPBits
  /// Python: `DESTINATION_STAMP_EXTENSION`.
  public static let destinationStampExtension = ".dstamp"
  /// Python: `STAMP_FILE_VERSION`.
  public static let stampFileVersion = 1

  /// Python: `TAB`, `floor(2^33 * 2^(f/256))` for `f` in `0..<256`. Copied, never computed:
  /// `Stamps.py:769-771` makes the table authoritative and pins it by digest.
  static let tab: [UInt64] = [
    0x200000000, 0x201635f4b, 0x202c7b53f, 0x2042d0287, 0x2059347ce, 0x206fa85c2,
    0x20862bd0d, 0x209cbee5e, 0x20b361a62, 0x20ca141c7, 0x20e0d653b, 0x20f7a856e,
    0x210e8a30e, 0x21257becc, 0x213c7d958, 0x21538f363, 0x216ab0d9f, 0x2181e28bc,
    0x21992456e, 0x21b076467, 0x21c7d865a, 0x21df4abfb, 0x21f6cd5ff, 0x220e6051a,
    0x222603a02, 0x223db756b, 0x22557b80d, 0x226d5029e, 0x2285355d5, 0x229d2b269,
    0x22b531914, 0x22cd48a8e, 0x22e57078f, 0x22fda90d2, 0x2315f2711, 0x232e4cb06,
    0x2346b7d6d, 0x235f33f02, 0x2377c1080, 0x23905f2a5, 0x23a90e62d, 0x23c1cebd6,
    0x23daa045f, 0x23f383087, 0x240c7710c, 0x24257c6af, 0x243e9322f, 0x2457bb44f,
    0x2470f4dce, 0x248a3ff70, 0x24a39c9f6, 0x24bd0ae23, 0x24d68acbc, 0x24f01c683,
    0x2509bfc3e, 0x252374eb2, 0x253d3bea3, 0x255714cda, 0x2570ffa1b, 0x258afc72e,
    0x25a50b4dc, 0x25bf2c3ec, 0x25d95f527, 0x25f3a4957, 0x260dfc146, 0x262865dbd,
    0x2642e1f89, 0x265d70775, 0x26781164c, 0x2692c4cdc, 0x26ad8abf2, 0x26c86345b,
    0x26e34e6e7, 0x26fe4c463, 0x27195cda0, 0x27348036e, 0x274fb669c, 0x276aff7fd,
    0x27865b862, 0x27a1ca89d, 0x27bd4c982, 0x27d8e1be3, 0x27f48a095, 0x28104586c,
    0x282c1443e, 0x2847f64e1, 0x2863ebb2a, 0x287ff47f0, 0x289c10c0c, 0x28b840854,
    0x28d483da3, 0x28f0dacd1, 0x290d456b8, 0x2929c3c32, 0x294655e1a, 0x2962fbd4d,
    0x297fb5aa6, 0x299c83702, 0x29b96533f, 0x29d65b03b, 0x29f364ed3, 0x2a1082fe8,
    0x2a2db5459, 0x2a4afbd07, 0x2a6856ad3, 0x2a85c5e9e, 0x2aa34994b, 0x2ac0e1bbd,
    0x2ade8e6d6, 0x2afc4fb7c, 0x2b1a25a92, 0x2b38104ff, 0x2b560fba9, 0x2b7423f75,
    0x2b924d14b, 0x2bb08b213, 0x2bcede2b5, 0x2bed4641b, 0x2c0bc372e, 0x2c2a55cd9,
    0x2c48fd607, 0x2c67ba3a3, 0x2c868c699, 0x2ca573fd7, 0x2cc47104a, 0x2ce3838e1,
    0x2d02aba89, 0x2d21e9633, 0x2d413cccf, 0x2d60a5f4e, 0x2d8024ea1, 0x2d9fb9bba,
    0x2dbf6478c, 0x2ddf2530b, 0x2dfefbf2a, 0x2e1ee8cde, 0x2e3eebd1d, 0x2e5f050dd,
    0x2e7f34914, 0x2e9f7a6ba, 0x2ebfd6ac8, 0x2ee049635, 0x2f00d29fb, 0x2f2172715,
    0x2f4228e7d, 0x2f62f612e, 0x2f83da026, 0x2fa4d4c5f, 0x2fc5e66d9, 0x2fe70f092,
    0x30084ea87, 0x3029a55ba, 0x304b13329, 0x306c983d7, 0x308e348c4, 0x30afe82f3,
    0x30d1b3368, 0x30f395b26, 0x31158fb31, 0x3137a148f, 0x3159ca845, 0x317c0b75a,
    0x319e642d6, 0x31c0d4bc1, 0x31e35d322, 0x3205fda05, 0x3228b6172, 0x324b86a75,
    0x326e6f619, 0x32917056b, 0x32b489979, 0x32d7bb34e, 0x32fb053fb, 0x331e67c8f,
    0x3341e2e19, 0x3365769aa, 0x338923054, 0x33ace8329, 0x33d0c633c, 0x33f4bd1a0,
    0x3418ccf6b, 0x343cf5db1, 0x346137d89, 0x348593008, 0x34aa07647, 0x34ce9515e,
    0x34f33c266, 0x3517fca78, 0x353cd6aaf, 0x3561ca426, 0x3586d77fa, 0x35abfe747,
    0x35d13f32b, 0x35f699cc4, 0x361c0e531, 0x36419cd93, 0x366745709, 0x368d082b6,
    0x36b2e51bc, 0x36d8dc53e, 0x36feede5f, 0x372519e44, 0x374b60614, 0x3771c16f3,
    0x37983d209, 0x37bed387e, 0x37e584b7a, 0x380c50c28, 0x383337bb0, 0x385a39b3f,
    0x388156bff, 0x38a88ef1f, 0x38cfe25ca, 0x38f751131, 0x391edb280, 0x394680aea,
    0x396e41b9d, 0x39961e5cd, 0x39be16aab, 0x39e62ab6b, 0x3a0e5a940, 0x3a36a6561,
    0x3a5f0e101, 0x3a8791d59, 0x3ab031b9f, 0x3ad8edd0c, 0x3b01c62d9, 0x3b2abae3f,
    0x3b53cc07b, 0x3b7cf9ac7, 0x3ba643e60, 0x3bcfaac83, 0x3bf92e66f, 0x3c22ced63,
    0x3c4c8c29e, 0x3c7666762, 0x3ca05dcf1, 0x3cca7248c, 0x3cf4a3f78, 0x3d1ef2ef9,
    0x3d495f454, 0x3d73e90cf, 0x3d9e905b1, 0x3dc955443, 0x3df437dcc, 0x3e1f38396,
    0x3e4a566ed, 0x3e759291b, 0x3ea0ecb6d, 0x3ecc64f31, 0x3ef7fb5b3, 0x3f23b0044,
    0x3f4f83033, 0x3f7b746d2, 0x3fa784571, 0x3fd3b2d65

  ]

  // MARK: - Fixed point

  /// Python: `cost_to_fp`, rounded to the nearest grid step and clamped to `0...stampCostCap`.
  public static func costToFP(_ cost: Double) -> Int {
    let fp = (cost * Double(costFP) + 0.5).rounded(.down)
    return fp.isNaN ? 0 : Int(min(max(fp, 0), Double(Transport.stampCostCap * costFP)))
  }

  /// Python: `fp_to_bytes`.
  public static func fpToBytes(_ fp: Int) -> Data {
    Data([UInt8((fp >> costFPBits) & 0xFF), UInt8(fp & 0xFF)])
  }

  /// Python: `cost_to_bytes`.
  public static func costToBytes(_ cost: Double) -> Data { fpToBytes(costToFP(cost)) }

  /// Python: `fp_from_bytes`, over the first two bytes of `bytes`.
  public static func fpFromBytes(_ bytes: Data) -> Int {
    Int(bytes[bytes.startIndex]) << costFPBits | Int(bytes[bytes.startIndex + 1])
  }

  /// Python: `cost_from_fp`.
  public static func costFromFP(_ fp: Int) -> Double { Double(fp) / Double(costFP) }

  /// Python: `cost_from_bytes`.
  public static func costFromBytes(_ bytes: Data) -> Double { costFromFP(fpFromBytes(bytes)) }

  /// Python: `quantize_cost`.
  public static func quantizeCost(_ cost: Double) -> Double { costFromFP(costToFP(cost)) }

  /// Python: `target_from_fp`, as 33 big-endian bytes since a cost of 0 maps to `2^256`.
  static func targetFromFP(_ fp: Int) -> [UInt8] {
    precondition((0...Transport.stampCostCap * costFP).contains(fp))
    let (i, f) = (256 * costFP - fp).quotientAndRemainder(dividingBy: costFP)
    // (TAB[f] << i) >> 33 with i >= 156, so a left shift of a 34-bit mantissa.
    let shift = i - mantissaBits
    let mantissa = tab[f] << (shift % 8)
    var target = [UInt8](repeating: 0, count: 33)
    for k in 0..<6 where 32 - shift / 8 - k >= 0 {
      target[32 - shift / 8 - k] = UInt8(truncatingIfNeeded: mantissa >> (8 * k))
    }
    return target
  }

  /// Whether a 32-byte hash is at or below a 33-byte target.
  private static func meets<Hash: Sequence>(_ hash: Hash, _ target: [UInt8]) -> Bool
  where Hash.Element == UInt8 {
    if target[0] != 0 { return true }
    for (h, t) in zip(hash, target.dropFirst()) where h != t { return h < t }
    return true
  }

  // MARK: - Validation

  /// Python: `stamp_workblock`. `expandRounds` of 0 returns `material` unexpanded.
  public static func stampWorkblock(_ material: Data, expandRounds: Int = workblockExpandRounds)
    -> Data
  {
    guard expandRounds > 0 else { return material }
    var workblock = Data()
    for n in 0..<expandRounds {
      workblock += HKDF.derive(
        length: workblockExpandChunk, derivedFrom: material,
        salt: Hashes.fullHash(material + MsgPack.encode(.int(Int64(n)))))
    }
    return workblock
  }

  /// Python: `stamp_value`, the stamp's value floored to the 1/256 grid.
  public static func stampValue(workblock: Data, stamp: Data) -> Double {
    let product = [UInt8](Hashes.fullHash(workblock + stamp))
    guard let first = product.firstIndex(where: { $0 != 0 }) else { return 256 }
    let leadingZeros = first * 8 + product[first].leadingZeroBitCount
    // The 34 bits from the leading one, zero-padded past the end (`Stamps.py:148-150`).
    var mantissa: UInt64 = 0
    for bit in leadingZeros..<(leadingZeros + mantissaBits + 1) {
      mantissa = mantissa << 1 | (bit < 256 ? UInt64(product[bit / 8] >> (7 - bit % 8) & 1) : 0)
    }
    let climb = tab.prefix(while: { $0 <= mantissa }).count  // bisect_right
    return costFromFP(((leadingZeros + 1) << costFPBits) - climb)
  }

  /// Python: `stamp_valid`.
  public static func stampValid(stamp: Data, targetCost: Double, workblock: Data) -> Bool {
    meets(Hashes.fullHash(workblock + stamp), targetFromFP(costToFP(targetCost)))
  }

  // MARK: - Generation

  /// Python: `generate_stamp`. Searches random `size`-byte stamps until one meets `stampCost`.
  ///
  /// - Returns: `nil` for a cost outside `0...stampCostCap`, or when `isCancelled` turns true.
  public static func generateStamp(
    _ messageID: Data, stampCost: Double, expandRounds: Int = workblockExpandRounds,
    size: Int = stampSize, isCancelled: () -> Bool = { false }
  ) -> (stamp: Data, value: Double)? {
    guard stampCost >= 0, stampCost <= Double(Transport.stampCostCap) else { return nil }
    let workblock = stampWorkblock(messageID, expandRounds: expandRounds)
    let target = targetFromFP(costToFP(stampCost))
    var base = SHA256()
    base.update(data: workblock)
    var rounds = 0
    while true {
      let stamp = SecureRandom.bytes(size)
      var hasher = base
      hasher.update(data: stamp)
      if meets(hasher.finalize(), target) {
        return (stamp, stampValue(workblock: workblock, stamp: stamp))
      }
      rounds += 1
      if rounds % 64 == 0, isCancelled() { return nil }  // Python: STOP_CHECK_INTERVAL
    }
  }

  /// Python: `generate_stamped_key`. Generates X25519 keys until the public key is a stamp
  /// meeting `stampCost` over `material`.
  ///
  /// - Returns: `nil` for a cost outside `0...stampCostCap`, or when `isCancelled` turns true.
  public static func generateStampedKey(
    material: Data, stampCost: Double, isCancelled: () -> Bool = { false }
  ) -> (privateKey: Data, publicKey: Data, value: Double)? {
    guard stampCost >= 0, stampCost <= Double(Transport.stampCostCap) else { return nil }
    let target = targetFromFP(costToFP(stampCost))
    var base = SHA256()
    base.update(data: material)
    while !isCancelled() {
      let key = Curve25519.KeyAgreement.PrivateKey()
      let publicKey = key.publicKey.rawRepresentation
      var hasher = base
      hasher.update(data: publicKey)
      if meets(hasher.finalize(), target) {
        return (key.rawRepresentation, publicKey, stampValue(workblock: material, stamp: publicKey))
      }
    }
    return nil
  }

  // MARK: - Persistence

  /// Python: `store_destination_stamp`, into `directory` (Python's `<storagepath>/stamps`).
  @discardableResult
  public static func storeDestinationStamp(
    _ destinationHash: Data, stamp: Data, value: Double, in directory: URL
  ) -> Bool {
    let entry = MsgPack.encode(
      .map([
        (.string("v"), .int(Int64(stampFileVersion))), (.string("stamp"), .bytes(stamp)),
        (.string("value"), .double(value)),
        (.string("generated"), .double(Date().timeIntervalSince1970)),
      ]))
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try entry.write(to: stampFile(destinationHash, in: directory), options: .atomic)
      return true
    } catch {
      Reticulum.log("An error occurred while persisting destination stamp: \(error)", level: .warning)
      return false
    }
  }

  /// Python: `load_destination_stamp`. A stored stamp no longer meeting `requiredValue` over
  /// `material` loads as `nil`, so the caller generates a new one.
  public static func loadDestinationStamp(
    _ destinationHash: Data, material: Data, requiredValue: Double, in directory: URL
  ) -> (stamp: Data, value: Double)? {
    guard let bytes = try? Data(contentsOf: stampFile(destinationHash, in: directory)),
      let entry = (try? MsgPack.decode(bytes))?.asDictionary,
      entry["v"]?.asInt == stampFileVersion,
      let stamp = entry["stamp"]?.asData, stamp.count == Identity.stampLength,
      stampValid(stamp: stamp, targetCost: requiredValue, workblock: material)
    else { return nil }
    return (stamp, stampValue(workblock: material, stamp: stamp))
  }

  private static func stampFile(_ destinationHash: Data, in directory: URL) -> URL {
    directory.appendingPathComponent(destinationHash.hexString + destinationStampExtension)
  }
}
