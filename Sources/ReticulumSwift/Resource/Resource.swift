import Foundation

/// Reliable, segmented bulk transfer over a Link. Splits a payload into
/// MDU-sized segments, hashes each, and tracks segment-level retries.
///
/// Wire-compatible with Python `RNS.Resource`:
/// - 4-byte random hash prefix prepended to encrypted data stream
/// - map_hash = sha256(encryptedSegment + randomHash)[:4]
/// - resource_hash = sha256(plaintext + randomHash) — full 32 bytes
/// - Resource handles its own encryption (link layer does NOT re-encrypt parts)
public enum ResourceError: Error {
    case metadataTooLarge
}

public final class Resource {
    public enum Status: Sendable { case queued, transferring, complete, failed, rejected, corrupt }

    /// Size of the random hash prepended to wire data (matches Python RANDOM_HASH_SIZE = 4).
    public static let randomHashSize: Int = 4

    /// Size of each map hash entry in bytes (matches Python MAPHASH_LEN = 4).
    public static let mapHashLength: Int = 4

    /// Maximum size to auto-compress (matches Python AUTO_COMPRESS_MAX_SIZE = 64 MB).
    public static let autoCompressMaxSize: Int = 64 * 1024 * 1024

    /// Maximum metadata size in bytes (matches Python METADATA_MAX_SIZE = 16777215).
    public static let metadataMaxSize: Int = 16_777_215

    public let link: Link
    /// Uncompressed original payload (without metadata prefix).
    public let uncompressedData: Data
    /// Pre-packed metadata bytes (without the 3-byte size prefix), or nil.
    public let metadata: Data?
    /// True if the payload was compressed before encryption.
    public private(set) var isCompressed: Bool
    /// 4-byte random hash used in map hash computation.
    public let randomHash: Data
    /// Full 32-byte SHA256 resource hash: sha256(plaintext + randomHash).
    public let resourceHash: Data
    /// Full 32-byte SHA256 expected proof: sha256(plaintext + resourceHash).
    public let expectedProof: Data

    /// Pre-encrypted wire data (randomHash prefix + compressed/plain data, encrypted).
    public let encryptedStream: Data
    /// Pre-encrypted, SDU-sized segments of encryptedStream.
    public let encryptedSegments: [Data]
    /// 4-byte map hash per encrypted segment.
    public let mapHashes: [Data]

    public private(set) var status: Status = .queued

    /// - Parameters:
    ///   - metadata: Pre-packed (e.g. msgpack) metadata bytes to prepend. The receiver will
    ///               receive both the metadata and the payload via ``ResourceTransfer``.
    ///               Mirrors Python `Resource(data, link, metadata=...)`.
    public init(link: Link, payload: Data, metadata: Data? = nil,
                segmentSize: Int = Constants.mdu, autoCompress: Bool = true) throws {
        self.link = link
        self.uncompressedData = payload
        self.metadata = metadata

        if let m = metadata, m.count > Resource.metadataMaxSize {
            throw ResourceError.metadataTooLarge
        }

        // Generate 4-byte random hash prefix.
        var rh = Data(count: Resource.randomHashSize)
        _ = rh.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, Resource.randomHashSize, $0.baseAddress!)
        }
        self.randomHash = rh

        // Build the plaintext: optional [3-byte size][metadata] + payload.
        var plaintext = Data()
        if let m = metadata {
            let sz = m.count
            plaintext.append(UInt8((sz >> 16) & 0xFF))
            plaintext.append(UInt8((sz >>  8) & 0xFF))
            plaintext.append(UInt8( sz        & 0xFF))
            plaintext.append(contentsOf: m)
        }
        plaintext.append(contentsOf: payload)

        // Attempt compression.
        var compressed = false
        var transferData = plaintext
        if autoCompress, plaintext.count <= Resource.autoCompressMaxSize {
            if let cdata = Resource.compressor.compress(plaintext), cdata.count < plaintext.count {
                transferData = cdata
                compressed = true
            }
        }
        self.isCompressed = compressed

        // Resource hash = sha256(plaintext + randomHash).
        //
        // Python computes the hash over the ORIGINAL (pre-compression) plaintext, not
        // the compressed transferData. Swift must do the same so that:
        //   • Python can verify a Swift-sent resource (it decompresses and checks)
        //   • Swift can verify a Python-sent resource (it decompresses and checks)
        //
        // When compressed == false, transferData == plaintext, so this is a no-op.
        let resourceHash = Hashes.fullHash(plaintext + rh)
        self.resourceHash = resourceHash

        // Expected proof = sha256(plaintext + resourceHash).
        // Python: proof = sha256(original_data + resource_hash).
        self.expectedProof = Hashes.fullHash(plaintext + resourceHash)

        // Build wire data: randomHash prefix + transferData, then encrypt.
        let wireData = rh + transferData
        let encrypted = try link.encrypt(wireData)
        self.encryptedStream = encrypted

        // Segment the encrypted stream.
        var segments: [Data] = []
        var offset = 0
        while offset < encrypted.count {
            let end = min(offset + segmentSize, encrypted.count)
            segments.append(encrypted[offset ..< end])
            offset = end
        }
        self.encryptedSegments = segments

        // Compute 4-byte map hash for each segment: sha256(segment + randomHash)[:4].
        self.mapHashes = segments.map { seg in
            Hashes.fullHash(seg + rh).prefix(Resource.mapHashLength)
        }.map { Data($0) }
    }

    public var transferSize: Int { encryptedStream.count }
    public var dataSize: Int { uncompressedData.count }
    public var partCount: Int { encryptedSegments.count }
    public var hasMetadata: Bool { metadata != nil }

    // MARK: - Receiving

    /// Assembled result from a received resource.
    public struct AssemblyResult {
        /// The actual payload bytes (metadata prefix already stripped).
        public let payload: Data
        /// Pre-packed metadata bytes (without the 3-byte size prefix), or nil if none.
        public let metadata: Data?
    }

    /// Reconstruct a resource from the encrypted stream and advertisement fields.
    /// Decrypts, strips random hash, decompresses if needed, verifies hash,
    /// and separates metadata from payload when `hasMetadata` is true.
    ///
    /// Mirrors Python `Resource.__assemble` + the metadata extraction path.
    public static func assemble(
        encryptedParts: [Data],
        randomHash: Data,
        resourceHash: Data,
        compressed: Bool,
        hasMetadata: Bool = false,
        maxDecompressedSize: Int = Resource.autoCompressMaxSize,
        link: Link
    ) -> AssemblyResult? {
        let encryptedStream = encryptedParts.reduce(Data(), +)
        guard let decrypted = try? link.decrypt(encryptedStream) else { return nil }
        guard decrypted.count > randomHashSize else { return nil }
        let body = decrypted.dropFirst(randomHashSize)
        let plaintext: Data
        if compressed {
            // Bounded decompression. Rejects decompression bombs that would
            // produce more than `maxDecompressedSize` bytes. Mirrors Python
            // commit 09b0469f's `BZ2Decompressor(max_length=...)` guard.
            switch Resource.compressor.decompress(Data(body), maxLength: maxDecompressedSize) {
            case .success(let d):       plaintext = d
            case .exceededMaxLength:    return nil
            case .error:                return nil
            }
        } else {
            plaintext = Data(body)
        }
        // Verify: sha256(plaintext + randomHash) == resourceHash
        let computed = Hashes.fullHash(plaintext + randomHash)
        guard computed == resourceHash else { return nil }

        if hasMetadata && plaintext.count >= 3 {
            let sz = Int(plaintext[0]) << 16 | Int(plaintext[1]) << 8 | Int(plaintext[2])
            guard plaintext.count >= 3 + sz else { return nil }
            let meta = Data(plaintext[3 ..< 3 + sz])
            let payload = Data(plaintext[(3 + sz)...])
            return AssemblyResult(payload: payload, metadata: meta)
        }
        return AssemblyResult(payload: plaintext, metadata: nil)
    }

    // MARK: - Advertisement inspection helpers (mirrors Python ResourceAdvertisement statics)

    /// Decode the advertisement in `packet.data` and return it, or nil on failure.
    private static func decodeAd(_ packet: Packet) -> ResourceAdvertisement? {
        try? ResourceAdvertisement.unpack(packet.data)
    }

    /// Returns `true` if the advertisement packet carries the request flag.
    /// Mirrors Python `Resource.is_request(advertisement_packet)`.
    public static func isRequest(advertisementPacket packet: Packet) -> Bool {
        decodeAd(packet)?.isRequest ?? false
    }

    /// Returns `true` if the advertisement packet carries the response flag.
    /// Mirrors Python `Resource.is_response(advertisement_packet)`.
    public static func isResponse(advertisementPacket packet: Packet) -> Bool {
        decodeAd(packet)?.isResponse ?? false
    }

    /// Returns the request ID embedded in the advertisement, or `nil`.
    /// Mirrors Python `Resource.read_request_id(advertisement_packet)`.
    public static func readRequestID(advertisementPacket packet: Packet) -> Data? {
        guard let ad = decodeAd(packet) else { return nil }
        return ad.requestID
    }

    /// Returns the encoded (wire) transfer size in bytes.
    /// Mirrors Python `Resource.read_transfer_size(advertisement_packet)`.
    public static func readTransferSize(advertisementPacket packet: Packet) -> Int {
        Int(decodeAd(packet)?.transferSize ?? 0)
    }

    /// Returns the original (plaintext) data size in bytes.
    /// Mirrors Python `Resource.read_size(advertisement_packet)`.
    public static func readSize(advertisementPacket packet: Packet) -> Int {
        Int(decodeAd(packet)?.dataSize ?? 0)
    }
}

/// Wire-compatible Resource advertisement matching Python's
/// `RNS.Resource.ResourceAdvertisement`. Encoded as a msgpack map with
/// keys `t, d, n, h, r, o, i, l, q, f, m` in that insertion order.
public struct ResourceAdvertisement: Equatable {
    /// Bytes per map hash entry (matches Python MAPHASH_LEN = 4).
    public static let mapHashLength = 4

    /// Fixed advertisement overhead in bytes (msgpack envelope plus all fixed-size
    /// fields, excluding the variable-length hashmap). Mirrors Python
    /// `ResourceAdvertisement.OVERHEAD = 134`.
    public static let overhead = 134

    /// Maximum number of part-hashes carried in a single advertisement or
    /// hashmap-update (HMU) segment. Mirrors Python
    /// `HASHMAP_MAX_LEN = floor((Link.MDU - OVERHEAD) / MAPHASH_LEN)` — which is 74 at
    /// the default MTU (Link.MDU = 431). Resources with more parts than this are
    /// advertised one segment at a time; the receiver pulls later segments via HMU
    /// packets indexed by `partIndex / HASHMAP_MAX_LEN`.
    public static let hashmapMaxLength = (Constants.linkMdu - overhead) / mapHashLength

    /// Sender-side search window (in parts) used both for matching requested
    /// part-hashes and for locating the HMU pivot, sized to tolerate 4-byte map-hash
    /// collisions. Mirrors Python
    /// `COLLISION_GUARD_SIZE = 2*WINDOW_MAX + HASHMAP_MAX_LEN` (= 224), where
    /// `WINDOW_MAX` is the fast-window cap (75).
    public static let collisionGuardSize = 2 * ResourceTransfer.windowMaxFast + hashmapMaxLength

    public var transferSize: UInt64        // t
    public var dataSize: UInt64            // d
    public var partCount: UInt64           // n
    public var resourceHash: Data          // h — full 32-byte SHA256
    public var randomHash: Data            // r — 4 bytes
    public var originalHash: Data          // o
    public var segmentIndex: UInt64        // i
    public var totalSegments: UInt64       // l
    public var requestID: Data?            // q (nil when not a request/response)
    public var hashmap: Data               // m — MAPHASH_LEN bytes per part

    // Flag bits packed into `f`:
    //   bit 0 (0x01) e – encrypted
    //   bit 1 (0x02) c – compressed
    //   bit 2 (0x04) s – split
    //   bit 3 (0x08) u – is request
    //   bit 4 (0x10) p – is response
    //   bit 5 (0x20) x – has metadata
    public var encrypted: Bool
    public var compressed: Bool
    public var split: Bool
    public var isRequest: Bool
    public var isResponse: Bool
    public var hasMetadata: Bool

    public init(
        transferSize: UInt64, dataSize: UInt64, partCount: UInt64,
        resourceHash: Data, randomHash: Data, originalHash: Data,
        segmentIndex: UInt64, totalSegments: UInt64,
        requestID: Data? = nil, hashmap: Data = Data(),
        encrypted: Bool = false, compressed: Bool = false, split: Bool = false,
        isRequest: Bool = false, isResponse: Bool = false, hasMetadata: Bool = false
    ) {
        self.transferSize = transferSize
        self.dataSize = dataSize
        self.partCount = partCount
        self.resourceHash = resourceHash
        self.randomHash = randomHash
        self.originalHash = originalHash
        self.segmentIndex = segmentIndex
        self.totalSegments = totalSegments
        self.requestID = requestID
        self.hashmap = hashmap
        self.encrypted = encrypted
        self.compressed = compressed
        self.split = split
        self.isRequest = isRequest
        self.isResponse = isResponse
        self.hasMetadata = hasMetadata
    }

    public var flags: UInt8 {
        var f: UInt8 = 0
        if encrypted   { f |= 0x01 }
        if compressed  { f |= 0x02 }
        if split       { f |= 0x04 }
        if isRequest   { f |= 0x08 }
        if isResponse  { f |= 0x10 }
        if hasMetadata { f |= 0x20 }
        return f
    }

    /// Pack the advertisement, carrying only the `segment`-th window of part-hashes in
    /// the `m` field. Later segments are delivered to the receiver via HMU packets.
    /// Mirrors Python `ResourceAdvertisement.pack(segment=0)`: a full hashmap may be
    /// held in `self.hashmap`, but the wire form never carries more than
    /// `HASHMAP_MAX_LEN` (74) hashes — otherwise large resources would produce an
    /// advertisement exceeding the link MDU and the segment offsets would not line up
    /// with the receiver's HMU indexing.
    public func pack(segment: Int = 0) -> Data {
        let hml = ResourceAdvertisement.hashmapMaxLength
        let mhl = ResourceAdvertisement.mapHashLength
        let hm = Data(hashmap)  // 0-based copy for safe slicing
        let endByte = min(min((segment + 1) * hml, Int(partCount)) * mhl, hm.count)
        let startByte = min(segment * hml * mhl, endByte)
        let segmentHashmap = hm.subdata(in: startByte ..< endByte)

        let q: MsgPack.Value = requestID.map { .bytes($0) } ?? .nil
        let map: MsgPack.Value = .map([
            (.string("t"), .uint(transferSize)),
            (.string("d"), .uint(dataSize)),
            (.string("n"), .uint(partCount)),
            (.string("h"), .bytes(resourceHash)),
            (.string("r"), .bytes(randomHash)),
            (.string("o"), .bytes(originalHash)),
            (.string("i"), .uint(segmentIndex)),
            (.string("l"), .uint(totalSegments)),
            (.string("q"), q),
            (.string("f"), .uint(UInt64(flags))),
            (.string("m"), .bytes(segmentHashmap)),
        ])
        return MsgPack.encode(map)
    }

    public static func unpack(_ data: Data) throws -> ResourceAdvertisement {
        guard case .map(let pairs) = try MsgPack.decode(data) else {
            throw MsgPack.Error.typeMismatch
        }
        var dict: [String: MsgPack.Value] = [:]
        for (k, v) in pairs {
            if case .string(let s) = k { dict[s] = v }
        }

        func uint(_ key: String) throws -> UInt64 {
            switch dict[key] {
            case .uint(let n)?: return n
            case .int(let n)? where n >= 0: return UInt64(n)
            default: throw MsgPack.Error.typeMismatch
            }
        }
        func bytes(_ key: String) throws -> Data {
            switch dict[key] {
            case .bytes(let b)?: return b
            case .string(let s)?: return Data(s.utf8)
            default: throw MsgPack.Error.typeMismatch
            }
        }

        let f = UInt8(try uint("f") & 0xFF)
        let adv = ResourceAdvertisement(
            transferSize: try uint("t"),
            dataSize: try uint("d"),
            partCount: try uint("n"),
            resourceHash: try bytes("h"),
            randomHash: try bytes("r"),
            originalHash: try bytes("o"),
            segmentIndex: try uint("i"),
            totalSegments: try uint("l"),
            requestID: {
                switch dict["q"] {
                case .bytes(let b)?: return b
                case .nil?, nil: return nil
                default: return nil
                }
            }(),
            hashmap: try bytes("m"),
            encrypted:   (f & 0x01) != 0,
            compressed:  (f & 0x02) != 0,
            split:       (f & 0x04) != 0,
            isRequest:   (f & 0x08) != 0,
            isResponse:  (f & 0x10) != 0,
            hasMetadata: (f & 0x20) != 0
        )
        return adv
    }
}
