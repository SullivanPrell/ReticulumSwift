import Foundation

/// HDLC byte-stuffing for byte-oriented serial / TCP interfaces. Frames are
/// delimited by `FLAG`. `ESC` and `FLAG` bytes inside a frame are stuffed by
/// emitting `ESC` followed by `byte ^ ESC_MASK`.
public enum HDLC {
    public static let flag: UInt8 = 0x7E
    public static let esc: UInt8 = 0x7D
    public static let escMask: UInt8 = 0x20

    public static func escape(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        for byte in data {
            if byte == esc {
                out.append(esc); out.append(esc ^ escMask)
            } else if byte == flag {
                out.append(esc); out.append(flag ^ escMask)
            } else {
                out.append(byte)
            }
        }
        return out
    }

    public static func unescape(_ data: Data) -> Data {
        var out = Data()
        out.reserveCapacity(data.count)
        var pendingEscape = false
        for byte in data {
            if pendingEscape {
                out.append(byte ^ escMask)
                pendingEscape = false
            } else if byte == esc {
                pendingEscape = true
            } else {
                out.append(byte)
            }
        }
        return out
    }

    /// Wrap a packet body in HDLC delimiters: `FLAG ... FLAG`.
    public static func frame(_ data: Data) -> Data {
        var out = Data()
        out.append(flag)
        out.append(escape(data))
        out.append(flag)
        return out
    }

    /// Stateful frame extractor. Feed bytes as they arrive; receive complete
    /// frames as they're delimited. Tolerates back-to-back FLAGs (treated as
    /// frame boundaries with zero-byte content, which are silently dropped).
    public final class FrameDecoder {
        private var buffer = Data()
        private var inFrame = false

        public init() {}

        /// Feed received bytes and return any complete frames.
        ///
        /// When `hwMtu` is supplied, two received-side safeguards from Python's
        /// `TCPInterface.check_frame_len` / read-loop (RNS 1.3.9, commit a5ed0a43)
        /// are applied:
        ///  - a completed frame longer than `hwMtu + ifacSize` is dropped
        ///    (oversized frames that the interface cannot legitimately carry);
        ///  - an in-frame buffer that grows past `2 * hwMtu` without a closing
        ///    FLAG is discarded, bounding memory against an unterminated/garbage
        ///    partial frame.
        ///
        /// Passing `hwMtu == nil` (the default) preserves the original unbounded
        /// behavior. These bounds never affect the bytes sent on the wire; a
        /// compliant peer never emits a frame that violates them.
        public func feed(_ bytes: Data, hwMtu: Int? = nil, ifacSize: Int = 0) -> [Data] {
            var frames: [Data] = []
            for byte in bytes {
                if byte == HDLC.flag {
                    if inFrame {
                        if !buffer.isEmpty {
                            let frame = HDLC.unescape(buffer)
                            if let hwMtu, frame.count > hwMtu + ifacSize {
                                // Oversized frame — drop it (Python check_frame_len
                                // upper bound). Small frames are still emitted and
                                // rejected downstream by Packet.unpack.
                            } else {
                                frames.append(frame)
                            }
                        }
                        buffer.removeAll(keepingCapacity: true)
                        inFrame = false
                    } else {
                        inFrame = true
                    }
                } else if inFrame {
                    buffer.append(byte)
                    // Bound a runaway/unterminated partial frame.
                    if let hwMtu, buffer.count > hwMtu * 2 {
                        buffer.removeAll(keepingCapacity: true)
                        inFrame = false
                    }
                }
            }
            return frames
        }
    }
}
