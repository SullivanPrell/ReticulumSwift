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

/// The stamping switches and costs Python keeps as `Transport` class attributes
/// (`Transport.py:191-206`), set from the `[stamps]` config section.
///
/// Every value defaults to RNS 1.6.0's.
public struct StampSettings: Equatable {
  /// Python: `STAMPS_ENABLED`, whether announces and path requests are checked for stamps.
  public var enabled = true
  /// Python: `STAMPS_ENFORCED`, whether an announce or path request without a sufficient stamp
  /// is dropped.
  public var enforced = false
  /// Python: `LR_STAMPS_ENFORCED`, whether a link request without a sufficient stamp is refused.
  public var lrEnforced = false
  /// Python: `STAMP_DESTINATIONS`, whether this node stamps its own announces.
  public var stampDestinations = false
  /// Python: `STAMP_PRS`, whether this node stamps its own path requests.
  public var stampPRs = false
  /// Python: `STAMP_LRS`, whether this node stamps link requests to destinations that
  /// announced a cost.
  public var stampLRs = true
  /// Python: `ALWAYS_STAMP_LRS`, whether link requests are stamped even without an announced
  /// cost.
  public var alwaysStampLRs = false
  /// Python: `DESTINATION_COST`, the value an announce stamp needs unless the receiving
  /// interface sets its own.
  public var destinationCost = 23.5
  /// Python: `DESTINATION_VALUE`, the value this node stamps its announces to.
  public var destinationValue = 25.0
  /// Python: `PR_COST`, the value a path-request stamp needs unless the interface sets its own.
  public var prCost = 15.8
  /// Python: `PR_VALUE`, the value this node stamps its path requests to.
  public var prValue = 15.8
  /// Python: `LR_COST`, the link-request cost announced when a destination sets none.
  public var lrCost = 12.5
  /// Python: `LINK_STAMP_TIMEOUT`.
  public var linkStampTimeout: TimeInterval = 15
  /// Python: `PR_STAMP_TIMEOUT`.
  public var prStampTimeout: TimeInterval = 15

  /// Settings with Python's defaults.
  public init() {}
}

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
  /// Python: `STAMP_SIZE`, the default for detached stamps.
  ///
  /// Announce and path-request stamps are `Identity.stampLength` bytes.
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

  /// Python: `TAB`, `floor(2^33 * 2^(f/256))` for `f` in `0..<256`.
  ///
  /// Copied, never computed: `Stamps.py:769-771` makes the table authoritative and pins it by
  /// digest.
  static let tab: [UInt64] = [
    0x2_0000_0000, 0x2_0163_5f4b, 0x2_02c7_b53f, 0x2_042d_0287, 0x2_0593_47ce, 0x2_06fa_85c2,
    0x2_0862_bd0d, 0x2_09cb_ee5e, 0x2_0b36_1a62, 0x2_0ca1_41c7, 0x2_0e0d_653b, 0x2_0f7a_856e,
    0x2_10e8_a30e, 0x2_1257_becc, 0x2_13c7_d958, 0x2_1538_f363, 0x2_16ab_0d9f, 0x2_181e_28bc,
    0x2_1992_456e, 0x2_1b07_6467, 0x2_1c7d_865a, 0x2_1df4_abfb, 0x2_1f6c_d5ff, 0x2_20e6_051a,
    0x2_2260_3a02, 0x2_23db_756b, 0x2_2557_b80d, 0x2_26d5_029e, 0x2_2853_55d5, 0x2_29d2_b269,
    0x2_2b53_1914, 0x2_2cd4_8a8e, 0x2_2e57_078f, 0x2_2fda_90d2, 0x2_315f_2711, 0x2_32e4_cb06,
    0x2_346b_7d6d, 0x2_35f3_3f02, 0x2_377c_1080, 0x2_3905_f2a5, 0x2_3a90_e62d, 0x2_3c1c_ebd6,
    0x2_3daa_045f, 0x2_3f38_3087, 0x2_40c7_710c, 0x2_4257_c6af, 0x2_43e9_322f, 0x2_457b_b44f,
    0x2_470f_4dce, 0x2_48a3_ff70, 0x2_4a39_c9f6, 0x2_4bd0_ae23, 0x2_4d68_acbc, 0x2_4f01_c683,
    0x2_509b_fc3e, 0x2_5237_4eb2, 0x2_53d3_bea3, 0x2_5571_4cda, 0x2_570f_fa1b, 0x2_58af_c72e,
    0x2_5a50_b4dc, 0x2_5bf2_c3ec, 0x2_5d95_f527, 0x2_5f3a_4957, 0x2_60df_c146, 0x2_6286_5dbd,
    0x2_642e_1f89, 0x2_65d7_0775, 0x2_6781_164c, 0x2_692c_4cdc, 0x2_6ad8_abf2, 0x2_6c86_345b,
    0x2_6e34_e6e7, 0x2_6fe4_c463, 0x2_7195_cda0, 0x2_7348_036e, 0x2_74fb_669c, 0x2_76af_f7fd,
    0x2_7865_b862, 0x2_7a1c_a89d, 0x2_7bd4_c982, 0x2_7d8e_1be3, 0x2_7f48_a095, 0x2_8104_586c,
    0x2_82c1_443e, 0x2_847f_64e1, 0x2_863e_bb2a, 0x2_87ff_47f0, 0x2_89c1_0c0c, 0x2_8b84_0854,
    0x2_8d48_3da3, 0x2_8f0d_acd1, 0x2_90d4_56b8, 0x2_929c_3c32, 0x2_9465_5e1a, 0x2_962f_bd4d,
    0x2_97fb_5aa6, 0x2_99c8_3702, 0x2_9b96_533f, 0x2_9d65_b03b, 0x2_9f36_4ed3, 0x2_a108_2fe8,
    0x2_a2db_5459, 0x2_a4af_bd07, 0x2_a685_6ad3, 0x2_a85c_5e9e, 0x2_aa34_994b, 0x2_ac0e_1bbd,
    0x2_ade8_e6d6, 0x2_afc4_fb7c, 0x2_b1a2_5a92, 0x2_b381_04ff, 0x2_b560_fba9, 0x2_b742_3f75,
    0x2_b924_d14b, 0x2_bb08_b213, 0x2_bced_e2b5, 0x2_bed4_641b, 0x2_c0bc_372e, 0x2_c2a5_5cd9,
    0x2_c48f_d607, 0x2_c67b_a3a3, 0x2_c868_c699, 0x2_ca57_3fd7, 0x2_cc47_104a, 0x2_ce38_38e1,
    0x2_d02a_ba89, 0x2_d21e_9633, 0x2_d413_cccf, 0x2_d60a_5f4e, 0x2_d802_4ea1, 0x2_d9fb_9bba,
    0x2_dbf6_478c, 0x2_ddf2_530b, 0x2_dfef_bf2a, 0x2_e1ee_8cde, 0x2_e3ee_bd1d, 0x2_e5f0_50dd,
    0x2_e7f3_4914, 0x2_e9f7_a6ba, 0x2_ebfd_6ac8, 0x2_ee04_9635, 0x2_f00d_29fb, 0x2_f217_2715,
    0x2_f422_8e7d, 0x2_f62f_612e, 0x2_f83d_a026, 0x2_fa4d_4c5f, 0x2_fc5e_66d9, 0x2_fe70_f092,
    0x3_0084_ea87, 0x3_029a_55ba, 0x3_04b1_3329, 0x3_06c9_83d7, 0x3_08e3_48c4, 0x3_0afe_82f3,
    0x3_0d1b_3368, 0x3_0f39_5b26, 0x3_1158_fb31, 0x3_137a_148f, 0x3_159c_a845, 0x3_17c0_b75a,
    0x3_19e6_42d6, 0x3_1c0d_4bc1, 0x3_1e35_d322, 0x3_205f_da05, 0x3_228b_6172, 0x3_24b8_6a75,
    0x3_26e6_f619, 0x3_2917_056b, 0x3_2b48_9979, 0x3_2d7b_b34e, 0x3_2fb0_53fb, 0x3_31e6_7c8f,
    0x3_341e_2e19, 0x3_3657_69aa, 0x3_3892_3054, 0x3_3ace_8329, 0x3_3d0c_633c, 0x3_3f4b_d1a0,
    0x3_418c_cf6b, 0x3_43cf_5db1, 0x3_4613_7d89, 0x3_4859_3008, 0x3_4aa0_7647, 0x3_4ce9_515e,
    0x3_4f33_c266, 0x3_517f_ca78, 0x3_53cd_6aaf, 0x3_561c_a426, 0x3_586d_77fa, 0x3_5abf_e747,
    0x3_5d13_f32b, 0x3_5f69_9cc4, 0x3_61c0_e531, 0x3_6419_cd93, 0x3_6674_5709, 0x3_68d0_82b6,
    0x3_6b2e_51bc, 0x3_6d8d_c53e, 0x3_6fee_de5f, 0x3_7251_9e44, 0x3_74b6_0614, 0x3_771c_16f3,
    0x3_7983_d209, 0x3_7bed_387e, 0x3_7e58_4b7a, 0x3_80c5_0c28, 0x3_8333_7bb0, 0x3_85a3_9b3f,
    0x3_8815_6bff, 0x3_8a88_ef1f, 0x3_8cfe_25ca, 0x3_8f75_1131, 0x3_91ed_b280, 0x3_9468_0aea,
    0x3_96e4_1b9d, 0x3_9961_e5cd, 0x3_9be1_6aab, 0x3_9e62_ab6b, 0x3_a0e5_a940, 0x3_a36a_6561,
    0x3_a5f0_e101, 0x3_a879_1d59, 0x3_ab03_1b9f, 0x3_ad8e_dd0c, 0x3_b01c_62d9, 0x3_b2ab_ae3f,
    0x3_b53c_c07b, 0x3_b7cf_9ac7, 0x3_ba64_3e60, 0x3_bcfa_ac83, 0x3_bf92_e66f, 0x3_c22c_ed63,
    0x3_c4c8_c29e, 0x3_c766_6762, 0x3_ca05_dcf1, 0x3_cca7_248c, 0x3_cf4a_3f78, 0x3_d1ef_2ef9,
    0x3_d495_f454, 0x3_d73e_90cf, 0x3_d9e9_05b1, 0x3_dc95_5443, 0x3_df43_7dcc, 0x3_e1f3_8396,
    0x3_e4a5_66ed, 0x3_e759_291b, 0x3_ea0e_cb6d, 0x3_ecc6_4f31, 0x3_ef7f_b5b3, 0x3_f23b_0044,
    0x3_f4f8_3033, 0x3_f7b7_46d2, 0x3_fa78_4571, 0x3_fd3b_2d65,

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

  /// Python: `generate_stamp`.
  ///
  /// Searches random `size`-byte stamps until one meets `stampCost`.
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

  /// Python: `generate_stamped_key`.
  ///
  /// Generates X25519 keys until the public key is a stamp meeting `stampCost` over `material`.
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
      Reticulum.log(
        "An error occurred while persisting destination stamp: \(error)", level: .warning)
      return false
    }
  }

  /// Python: `load_destination_stamp`.
  ///
  /// A stored stamp no longer meeting `requiredValue` over `material` loads as `nil`, so the caller
  /// generates a new one.
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
