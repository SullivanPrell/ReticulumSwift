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

/// HDLC byte-stuffing for byte-oriented serial / TCP interfaces.
///
/// Frames are
/// delimited by `FLAG`. `ESC` and `FLAG` bytes inside a frame are stuffed by
/// emitting `ESC` followed by `byte ^ ESC_MASK`.
public enum HDLC {
  /// The byte that delimits a frame.
  public static let flag: UInt8 = 0x7E
  /// The byte that escapes the one following it.
  public static let esc: UInt8 = 0x7D
  /// The mask an escaped byte is XORed with.
  public static let escMask: UInt8 = 0x20

  /// Returns `data` with its flag and escape bytes stuffed.
  public static func escape(_ data: Data) -> Data {
    // Per-element `Data` iteration and appends cost Foundation overhead on every byte;
    // scan and build through raw buffers instead (Python uses C `bytes.replace`).
    data.withUnsafeBytes { src in
      guard src.contains(where: { $0 == esc || $0 == flag }) else { return Data(src) }
      var out = [UInt8]()
      out.reserveCapacity(src.count + src.count / 8)
      for byte in src {
        if byte == esc || byte == flag {
          out.append(esc)
          out.append(byte ^ escMask)
        } else {
          out.append(byte)
        }
      }
      return Data(out)
    }
  }

  /// Returns `data` with its byte stuffing removed.
  public static func unescape(_ data: Data) -> Data {
    data.withUnsafeBytes { src in
      guard src.contains(esc) else { return Data(src) }
      var out = [UInt8]()
      out.reserveCapacity(src.count)
      var pendingEscape = false
      for byte in src {
        if pendingEscape {
          out.append(byte ^ escMask)
          pendingEscape = false
        } else if byte == esc {
          pendingEscape = true
        } else {
          out.append(byte)
        }
      }
      return Data(out)
    }
  }

  /// Wrap a packet body in HDLC delimiters: `FLAG ... FLAG`.
  public static func frame(_ data: Data) -> Data {
    var out = Data()
    out.append(flag)
    out.append(escape(data))
    out.append(flag)
    return out
  }

  /// Stateful frame extractor.
  ///
  /// Feed bytes as they arrive; receive complete
  /// frames as they're delimited. Tolerates back-to-back FLAGs (treated as
  /// frame boundaries with zero-byte content, which are silently dropped).
  public final class FrameDecoder {
    private var buffer = Data()
    private var inFrame = false

    /// Creates a decoder holding no partial frame.
    public init() {}

    /// Discard any partially received frame.
    ///
    /// Called when the underlying connection is replaced: Python allocates a fresh
    /// read buffer per socket, so a half-decoded frame from the previous session must
    /// not be prepended to the first bytes of the new one.
    public func reset() {
      buffer.removeAll(keepingCapacity: false)
      inFrame = false
    }

    /// Feed received bytes and return any complete frames.
    ///
    /// When `hwMtu` is supplied, two received-side safeguards from Python's
    /// `TCPInterface.check_frame_len` / read-loop (RNS 1.3.9, commit a5ed0a43)
    /// are applied:
    ///  - a completed frame longer than `hwMtu + ifacSize` is dropped
    ///    (oversized frames that the interface can't legitimately carry);
    ///  - an in-frame buffer that grows past `2 * hwMtu` without a closing
    ///    FLAG is discarded, bounding memory against an unterminated/garbage
    ///    partial frame.
    ///
    /// Passing `hwMtu == nil` (the default) preserves the original unbounded
    /// behavior. These bounds never affect the bytes sent on the wire; a
    /// compliant peer never emits a frame that violates them.
    public func feed(_ bytes: Data, hwMtu: Int? = nil, ifacSize: Int = 0) -> [Data] {
      var frames: [Data] = []
      bytes.withUnsafeBytes { src in
        var start = 0
        while start <= src.count {
          // Everything up to the next FLAG (or the end of this chunk) is one run of body bytes.
          let end = src[start...].firstIndex(of: HDLC.flag) ?? src.count
          if inFrame, end > start {
            // Bound a runaway/unterminated partial frame. Once past the bound the rest of
            // the run is outside any frame, exactly as the per-byte check left it.
            if let hwMtu, buffer.count + (end - start) > hwMtu * 2 {
              buffer.removeAll(keepingCapacity: true)
              inFrame = false
            } else {
              buffer.append(contentsOf: UnsafeRawBufferPointer(rebasing: src[start..<end]))
            }
          }
          guard end < src.count else { break }
          // A closing FLAG also opens the next frame: Python keeps it in the buffer
          // (`frame_buffer = frame_buffer[frame_end:]`, `TCPInterface.py:406`).
          if inFrame, !buffer.isEmpty {
            let frame = HDLC.unescape(buffer)
            if let hwMtu, frame.count > hwMtu + ifacSize {
              // Oversized frame—drop it (Python check_frame_len
              // upper bound). Small frames are still emitted and
              // rejected downstream by Packet.unpack.
            } else {
              frames.append(frame)
            }
          }
          buffer.removeAll(keepingCapacity: true)
          inFrame = true
          start = end + 1
        }
      }
      return frames
    }
  }
}
