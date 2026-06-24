import Foundation

/// Protocol for pluggable data compression. Inject a concrete implementation
/// to enable compressed Resource and Buffer transfers compatible with the
/// Python reference (which uses `bz2`).
///
/// Enable bz2 for both Resources and Buffer streams at startup:
/// ```swift
/// let bz2 = BZip2Compressor()
/// Resource.compressor = bz2
/// StreamDataMessage.compressor = bz2
/// ```
/// Outcome of a bounded decompression. Distinguishes a real decode error from
/// a decompression bomb (output exceeded the caller-supplied cap).
public enum DecompressionResult: Equatable {
    case success(Data)
    case error
    /// The decompressed stream exceeded `maxLength` bytes. Used by callers to
    /// reject decompression bomb attacks (mirrors Python's `BZ2Decompressor`
    /// `max_length` overflow check added in RNS commit 09b0469f).
    case exceededMaxLength
}

public protocol DataCompressor {
    /// Compress `data`. Returns nil if compression fails or would expand the data.
    func compress(_ data: Data) -> Data?
    /// Decompress `data`. Returns nil on failure.
    func decompress(_ data: Data) -> Data?
    /// Decompress `data` with a hard upper bound on the output size. Returns
    /// `.exceededMaxLength` if the stream would produce more than `maxLength`
    /// bytes (decompression bomb guard). Default implementation wraps
    /// `decompress(_:)` and checks the result length afterwards — concrete
    /// implementations should override with a streaming check that aborts
    /// before allocating the bomb output.
    func decompress(_ data: Data, maxLength: Int) -> DecompressionResult
}

public extension DataCompressor {
    func decompress(_ data: Data, maxLength: Int) -> DecompressionResult {
        guard let out = decompress(data) else { return .error }
        if out.count > maxLength { return .exceededMaxLength }
        return .success(out)
    }
}

/// No-op compressor. With this default, resources are sent uncompressed
/// (the `compressed` flag in the advertisement is `false`), which is
/// compatible with all RNS implementations. Received compressed data
/// cannot be decompressed until a real compressor is injected.
public struct NoCompressor: DataCompressor {
    public init() {}
    public func compress(_ data: Data) -> Data? { nil }
    public func decompress(_ data: Data) -> Data? { nil }
}

extension Resource {
    /// The active compressor used for all new Resource transfers.
    /// Replace with `BZip2Compressor()` to enable wire-compatible
    /// bz2 compression matching the Python reference. Default: `NoCompressor`.
    public static var compressor: any DataCompressor = NoCompressor()
}
