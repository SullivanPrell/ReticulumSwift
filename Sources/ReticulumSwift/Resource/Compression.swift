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

/// No-op compressor. When installed as `Resource.compressor`, resources are
/// sent uncompressed (the `compressed` flag in the advertisement is `false`),
/// which is compatible with all RNS implementations. Received compressed data
/// cannot be decompressed while this is installed. Note this is no longer the
/// default — `Resource.compressor` defaults to `BZip2Compressor` so compressed
/// resources from Python peers can be received. Install this only to opt out.
public struct NoCompressor: DataCompressor {
    public init() {}
    public func compress(_ data: Data) -> Data? { nil }
    public func decompress(_ data: Data) -> Data? { nil }
}

extension Resource {
    /// The active compressor used for all new Resource transfers.
    ///
    /// Defaults to `BZip2Compressor` — matching the Python reference, which
    /// always bz2-compresses resource-sized payloads. This is required to
    /// *receive* compressed resources from Python peers: the `compressed` flag
    /// is carried per-resource in the advertisement, and a peer that compresses
    /// (any Python node) sends `compressed = true`, so a receiver whose
    /// compressor cannot decode bz2 fails to assemble the resource and tears the
    /// link down. On send, a resource is compressed only when bz2 actually
    /// shrinks it (and the `compressed` flag records that), so the wire format
    /// is unchanged and remains compatible with every RNS implementation.
    ///
    /// Set to `NoCompressor()` to opt out (resources always sent uncompressed;
    /// compressed resources from peers cannot be received).
    public static var compressor: any DataCompressor = BZip2Compressor()
}
