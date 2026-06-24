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

        public func feed(_ bytes: Data) -> [Data] {
            var frames: [Data] = []
            for byte in bytes {
                if byte == HDLC.flag {
                    if inFrame {
                        if !buffer.isEmpty {
                            frames.append(HDLC.unescape(buffer))
                        }
                        buffer.removeAll(keepingCapacity: true)
                        inFrame = false
                    } else {
                        inFrame = true
                    }
                } else if inFrame {
                    buffer.append(byte)
                }
            }
            return frames
        }
    }
}
