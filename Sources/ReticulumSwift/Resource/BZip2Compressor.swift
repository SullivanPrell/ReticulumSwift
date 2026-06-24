import Foundation
import CBZip2

/// Wire-compatible bz2 compressor using Apple's system `libbz2`.
///
/// Set `Resource.compressor = BZip2Compressor()` once at startup to enable
/// bz2 compression for both sending and receiving `Resource` transfers,
/// matching Python's `bz2.compress` / `bz2.decompress`.
///
/// Usage:
/// ```swift
/// // In your app startup (once):
/// Resource.compressor = BZip2Compressor()
/// ```
///
/// Wire format: identical to Python's `bz2.compress(data, compresslevel=9)`.
public struct BZip2Compressor: DataCompressor {
    /// bz2 block size (1–9). 9 matches Python's `bz2.compress` default.
    public let blockSize: Int32
    /// verbosity passed to BZ2_bzBuffToBuffCompress (0 = silent).
    public let verbosity: Int32
    /// workFactor for compression (0 = default = 30).
    public let workFactor: Int32

    public init(blockSize: Int32 = 9, verbosity: Int32 = 0, workFactor: Int32 = 0) {
        self.blockSize  = blockSize
        self.verbosity  = verbosity
        self.workFactor = workFactor
    }

    // MARK: - DataCompressor

    public func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }

        // Upper bound from bz2 docs: destLen >= (sourceLen * 1.01) + 600 bytes.
        var destLen = UInt32(Double(data.count) * 1.02) + 1024

        return data.withUnsafeBytes { src in
            guard let srcPtr = src.bindMemory(to: Int8.self).baseAddress else { return nil }
            var out = Data(count: Int(destLen))
            let status = out.withUnsafeMutableBytes { dst -> Int32 in
                guard let dstPtr = dst.bindMemory(to: Int8.self).baseAddress else { return BZ_MEM_ERROR }
                return BZ2_bzBuffToBuffCompress(
                    dstPtr,
                    &destLen,
                    UnsafeMutablePointer(mutating: srcPtr),
                    UInt32(data.count),
                    blockSize,
                    verbosity,
                    workFactor
                )
            }
            guard status == BZ_OK else { return nil }
            out.count = Int(destLen)
            return out
        }
    }

    public func decompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }

        // Try expanding buffer geometrically until it fits.
        var destLen = UInt32(max(data.count * 4, 1024))
        let maxLen  = UInt32(256 * 1024 * 1024)   // 256 MB safety cap

        return data.withUnsafeBytes { src in
            guard let srcPtr = src.bindMemory(to: Int8.self).baseAddress else { return nil }
            while destLen <= maxLen {
                var out = Data(count: Int(destLen))
                var currentLen = destLen
                let status = out.withUnsafeMutableBytes { dst -> Int32 in
                    guard let dstPtr = dst.bindMemory(to: Int8.self).baseAddress else { return BZ_MEM_ERROR }
                    return BZ2_bzBuffToBuffDecompress(
                        dstPtr,
                        &currentLen,
                        UnsafeMutablePointer(mutating: srcPtr),
                        UInt32(data.count),
                        0,   // small (0 = use more memory but faster)
                        verbosity
                    )
                }
                if status == BZ_OK {
                    out.count = Int(currentLen)
                    return out
                }
                if status == BZ_OUTBUFF_FULL {
                    destLen = min(destLen * 2, maxLen + 1)
                    continue
                }
                return nil  // real error (bad data, etc.)
            }
            return nil  // exceeded max output size
        }
    }

    /// Decompress `data` with a hard cap on the output size. If the
    /// decompressed stream would exceed `maxLength` bytes, returns
    /// `.exceededMaxLength` without allocating the bomb output.
    /// Mirrors Python's `BZ2Decompressor.decompress(data, max_length=…)` +
    /// `decompressor.eof` overflow check (RNS commit 09b0469f).
    public func decompress(_ data: Data, maxLength: Int) -> DecompressionResult {
        guard !data.isEmpty else { return .success(Data()) }
        guard maxLength >= 0 else { return .error }

        // Allocate a single buffer at exactly maxLength + 1. If the bz2
        // stream decodes to <= maxLength bytes, BZ_OK; if it would exceed,
        // BZ_OUTBUFF_FULL → reject as bomb. This avoids the geometric retry
        // loop bringing us above the cap.
        let bufCap = UInt32(maxLength) &+ 1
        var destLen = bufCap

        return data.withUnsafeBytes { src -> DecompressionResult in
            guard let srcPtr = src.bindMemory(to: Int8.self).baseAddress else { return .error }
            var out = Data(count: Int(destLen))
            let status = out.withUnsafeMutableBytes { dst -> Int32 in
                guard let dstPtr = dst.bindMemory(to: Int8.self).baseAddress else { return BZ_MEM_ERROR }
                return BZ2_bzBuffToBuffDecompress(
                    dstPtr,
                    &destLen,
                    UnsafeMutablePointer(mutating: srcPtr),
                    UInt32(data.count),
                    0,
                    verbosity
                )
            }
            if status == BZ_OK {
                if Int(destLen) > maxLength { return .exceededMaxLength }
                out.count = Int(destLen)
                return .success(out)
            }
            if status == BZ_OUTBUFF_FULL { return .exceededMaxLength }
            return .error
        }
    }
}
