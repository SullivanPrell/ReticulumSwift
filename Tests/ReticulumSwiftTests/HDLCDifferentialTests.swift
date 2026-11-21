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

/// Checks the bulk-copy HDLC codec against the byte-at-a-time algorithm it replaced.
///
/// The decoder scans for FLAG and copies whole runs, so its edge cases sit at chunk
/// boundaries: an ESC ending one `feed` call, a runaway bound crossed by a later chunk,
/// and a slice with a nonzero `startIndex`. Random streams over a FLAG/ESC-heavy alphabet,
/// cut at random points, compare every frame against the oracle below.
final class HDLCDifferentialTests: XCTestCase {

  /// The per-byte decoder `HDLC.FrameDecoder` used through ReticulumSwift 1.29.0.
  private final class OracleDecoder {
    private var buffer: [UInt8] = []
    private var inFrame = false

    func feed(_ bytes: Data, hwMtu: Int?, ifacSize: Int) -> [Data] {
      var frames: [Data] = []
      for byte in bytes {
        if byte == HDLC.flag {
          if inFrame, !buffer.isEmpty {
            let frame = OracleDecoder.unescape(buffer)
            if let hwMtu, frame.count > hwMtu + ifacSize {
            } else {
              frames.append(frame)
            }
          }
          buffer.removeAll()
          inFrame = true
        } else if inFrame {
          buffer.append(byte)
          if let hwMtu, buffer.count > hwMtu * 2 {
            buffer.removeAll()
            inFrame = false
          }
        }
      }
      return frames
    }

    static func unescape(_ bytes: [UInt8]) -> Data {
      var out = Data()
      var pendingEscape = false
      for byte in bytes {
        if pendingEscape {
          out.append(byte ^ HDLC.escMask)
          pendingEscape = false
        } else if byte == HDLC.esc {
          pendingEscape = true
        } else {
          out.append(byte)
        }
      }
      return out
    }
  }

  private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  /// Mostly FLAG, ESC and ESC-able values, so stuffing and boundaries are dense.
  private func randomStream(_ rng: inout SplitMix64, count: Int) -> Data {
    let alphabet: [UInt8] = [
      HDLC.flag, HDLC.esc, HDLC.flag ^ HDLC.escMask, HDLC.esc ^ HDLC.escMask, 0x00, 0x41,
    ]
    var out = Data(capacity: count)
    for _ in 0..<count {
      out.append(
        Bool.random(using: &rng)
          ? alphabet.randomElement(using: &rng)! : UInt8.random(in: 0...255, using: &rng))
    }
    return out
  }

  func testDecoderMatchesPerByteOracleAcrossRandomChunking() {
    var rng = SplitMix64(state: 0x5EED)
    for round in 0..<400 {
      let stream = randomStream(&rng, count: Int.random(in: 0...600, using: &rng))
      let hwMtu: Int? = round % 3 == 0 ? nil : Int.random(in: 4...64, using: &rng)
      let ifacSize = Int.random(in: 0...8, using: &rng)
      let decoder = HDLC.FrameDecoder()
      let oracle = OracleDecoder()
      var got: [Data] = []
      var want: [Data] = []
      var i = 0
      while i < stream.count {
        let n = min(stream.count - i, Int.random(in: 1...80, using: &rng))
        // A slice keeps the parent's indices, so the decoder sees a nonzero startIndex.
        let chunk = stream[(stream.startIndex + i)..<(stream.startIndex + i + n)]
        got += decoder.feed(chunk, hwMtu: hwMtu, ifacSize: ifacSize)
        want += oracle.feed(chunk, hwMtu: hwMtu, ifacSize: ifacSize)
        i += n
      }
      XCTAssertEqual(
        got, want, "round \(round), hwMtu \(String(describing: hwMtu)), ifacSize \(ifacSize)")
      if got != want { return }
    }
  }

  func testEscapeUnescapeMatchOracleOnRandomData() {
    var rng = SplitMix64(state: 0xE5C)
    for _ in 0..<400 {
      let raw = randomStream(&rng, count: Int.random(in: 0...300, using: &rng))
      let escaped = HDLC.escape(raw)
      XCTAssertFalse(escaped.contains(HDLC.flag), "an escaped body never carries FLAG")
      XCTAssertEqual(HDLC.unescape(escaped), raw)
      XCTAssertEqual(HDLC.unescape(raw), OracleDecoder.unescape(Array(raw)))
    }
  }

  /// An ESC ending one chunk escapes the first byte of the next.
  func testEscapeSplitAcrossFeedCalls() {
    let decoder = HDLC.FrameDecoder()
    XCTAssertTrue(decoder.feed(Data([HDLC.flag, 0x01, HDLC.esc])).isEmpty)
    XCTAssertEqual(
      decoder.feed(Data([HDLC.flag ^ HDLC.escMask, 0x02, HDLC.flag])),
      [Data([0x01, HDLC.flag, 0x02])])
  }
}
