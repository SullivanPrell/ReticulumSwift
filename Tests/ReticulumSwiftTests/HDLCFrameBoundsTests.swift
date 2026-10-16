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

/// Parity tests for RNS 1.3.9 HDLC received-frame length bounds
/// (Python TCPInterface.check_frame_len / read-loop, commit a5ed0a43).
final class HDLCFrameBoundsTests: XCTestCase {

  private let hwMtu = 64
  private let ifacSize = 4

  /// A frame within bounds is delivered unchanged.
  func testInBoundsFrameIsDelivered() {
    let decoder = HDLC.FrameDecoder()
    let payload = Data(repeating: 0x11, count: 40)
    let frames = decoder.feed(HDLC.frame(payload), hwMtu: hwMtu, ifacSize: ifacSize)
    XCTAssertEqual(frames, [payload])
  }

  /// A frame at exactly hwMtu + ifacSize is still delivered (upper bound is inclusive).
  func testFrameAtUpperBoundIsDelivered() {
    let decoder = HDLC.FrameDecoder()
    let payload = Data(repeating: 0x22, count: hwMtu + ifacSize)
    let frames = decoder.feed(HDLC.frame(payload), hwMtu: hwMtu, ifacSize: ifacSize)
    XCTAssertEqual(frames, [payload])
  }

  /// A frame larger than hwMtu + ifacSize is dropped.
  func testOversizedFrameIsDropped() {
    let decoder = HDLC.FrameDecoder()
    let payload = Data(repeating: 0x33, count: hwMtu + ifacSize + 1)
    let frames = decoder.feed(HDLC.frame(payload), hwMtu: hwMtu, ifacSize: ifacSize)
    XCTAssertTrue(frames.isEmpty, "oversized frame must be dropped")
  }

  /// With no bounds supplied (default), oversized frames are still delivered—preserving
  /// the original unbounded behavior for callers that don't opt in.
  func testUnboundedDecoderStillDeliversLargeFrame() {
    let decoder = HDLC.FrameDecoder()
    let payload = Data(repeating: 0x44, count: hwMtu * 10)
    let frames = decoder.feed(HDLC.frame(payload))
    XCTAssertEqual(frames, [payload])
  }

  /// An unterminated partial frame that grows past 2×hwMtu is discarded, and the
  /// decoder resynchronizes on the next FLAG-delimited frame.
  func testRunawayPartialFrameIsDiscardedThenResyncs() {
    let decoder = HDLC.FrameDecoder()

    // Open a frame (FLAG) then feed a runaway body with no closing FLAG.
    var runaway = Data([HDLC.flag])
    runaway.append(Data(repeating: 0x55, count: hwMtu * 2 + 10))
    let none = decoder.feed(runaway, hwMtu: hwMtu, ifacSize: ifacSize)
    XCTAssertTrue(none.isEmpty, "runaway partial frame must not emit anything")

    // A subsequent, well-formed frame must still decode (decoder resynced).
    let payload = Data(repeating: 0x66, count: 20)
    let frames = decoder.feed(HDLC.frame(payload), hwMtu: hwMtu, ifacSize: ifacSize)
    XCTAssertEqual(frames, [payload], "decoder must resync after discarding a runaway frame")
  }

  // MARK: - Every FLAG opens a frame (`TCPInterface.py:394-412`)

  private let a = Data(repeating: 0x0A, count: 20)
  private let b = Data(repeating: 0x0B, count: 20)
  private let c = Data(repeating: 0x0C, count: 20)

  /// Python keeps the closing FLAG as the next frame's opening one (`frame_buffer[frame_end:]`).
  func testAClosingFlagAlsoOpensTheNextFrame() {
    let decoder = HDLC.FrameDecoder()
    let stream = Data([HDLC.flag]) + a + Data([HDLC.flag]) + b + Data([HDLC.flag])
    XCTAssertEqual(decoder.feed(stream, hwMtu: hwMtu, ifacSize: ifacSize), [a, b])
  }

  /// A runaway body closed by a FLAG leaves the frames after it decodable.
  func testFramesAfterAClosedRunawayBodyDecode() {
    let decoder = HDLC.FrameDecoder()
    let runaway =
      Data([HDLC.flag]) + Data(repeating: 0x55, count: hwMtu * 2 + 10) + Data([HDLC.flag])
    let stream = runaway + HDLC.frame(a) + HDLC.frame(b) + HDLC.frame(c)
    XCTAssertEqual(decoder.feed(stream, hwMtu: hwMtu, ifacSize: ifacSize), [a, b, c])
  }

  /// A frame that lost its closing FLAG leaves the frames after it decodable.
  func testFramesAfterALostFlagDecode() {
    let decoder = HDLC.FrameDecoder()
    let stream = Data([HDLC.flag]) + a + HDLC.frame(b) + HDLC.frame(c)
    XCTAssertEqual(decoder.feed(stream, hwMtu: hwMtu, ifacSize: ifacSize), [a, b, c])
  }
}
