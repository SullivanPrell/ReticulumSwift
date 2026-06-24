import Foundation

/// Disk-based announce packet cache for path table persistence across restarts.
///
/// Mirrors Python's `Transport.cache(packet, force_cache=True, packet_type="announce")`,
/// `Transport.get_cached_packet(hash, packet_type="announce")`, and
/// `Transport.clean_announce_cache()`.
///
/// Storage layout (under `Transport.cacheDirectory`):
///   announces/<32-byte-hash-hex>   — JSON {"rawHex": "...", "interfaceName": "..." | null}
///
/// The announce packet is stored with its raw bytes and the receiving interface name so
/// that it can be reconstructed with the interface reference on restore.
extension Transport {

    // MARK: - Announces subdirectory

    private var announcesDirectory: URL? {
        guard let base = cacheDirectory else { return nil }
        return base.appendingPathComponent("announces")
    }

    // MARK: - Write

    /// Write `packet` to the announce cache keyed by its full SHA-256 packet hash.
    /// Creates the `announces/` subdirectory if needed.
    /// Mirrors Python's `Transport.cache(packet, force_cache=True, packet_type="announce")`.
    public func cacheAnnounce(_ packet: Packet, receivingInterfaceName: String? = nil) throws {
        guard let dir = announcesDirectory else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let hashable = try? packet.hashablePart() else { return }
        let hash = Hashes.fullHash(hashable)
        let hexName = hash.hexString
        let raw = try packet.pack()

        let entry = CachedAnnounceEntry(rawHex: raw.hexString, interfaceName: receivingInterfaceName)
        let data = try JSONEncoder().encode(entry)
        try data.write(to: dir.appendingPathComponent(hexName), options: .atomic)
    }

    // MARK: - Read

    /// Load a cached announce packet by its full packet hash.
    /// Returns nil if not found or if the file is corrupt.
    /// Mirrors Python's `Transport.get_cached_packet(hash, packet_type="announce")`.
    public func getCachedAnnounce(hash: Data) throws -> Packet? {
        guard let dir = announcesDirectory else { return nil }
        let file = dir.appendingPathComponent(hash.hexString)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }

        let data = try Data(contentsOf: file)
        let entry = try JSONDecoder().decode(CachedAnnounceEntry.self, from: data)
        guard let raw = Data(hex: entry.rawHex) else { return nil }
        return try Packet.unpack(raw)
    }

    // MARK: - Clean

    /// Remove cached announces that are no longer referenced by any active path or tunnel.
    /// Mirrors Python's `Transport.clean_announce_cache()`.
    public func cleanAnnounceCache() throws {
        guard let dir = announcesDirectory else { return }
        guard FileManager.default.fileExists(atPath: dir.path) else { return }

        // Collect all hashes referenced by active paths and tunnels.
        let activeHashes = Set(paths.values.compactMap { $0.cachedAnnounceHash?.hexString })
        let tunnelHashes = Set(tunnels.values.flatMap { $0.paths.values }
            .compactMap { $0.cachedAnnounceHash?.hexString })
        let referenced = activeHashes.union(tunnelHashes)

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        for name in files {
            if !referenced.contains(name) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    // MARK: - cache_request_packet (mirrors Python Transport.cache_request_packet)

    /// Handle an inbound CACHE_REQUEST packet.
    ///
    /// If `packet.data` is exactly `Constants.fullHashLength` (32) bytes,
    /// treat it as a full packet hash, look up the announce cache, and
    /// replay the cached announce into the inbound pipeline.
    ///
    /// Returns `true` if the request was served from cache, `false` otherwise.
    /// Mirrors Python's `Transport.cache_request_packet(packet)`.
    @discardableResult
    public func cacheRequestPacket(_ packet: Packet) -> Bool {
        guard packet.data.count == Constants.fullHashLength else { return false }
        guard let cached = try? getCachedAnnounce(hash: packet.data),
              let iface = interfaces.first else { return false }
        handleIncoming(packet: cached, from: iface)
        return true
    }

    // MARK: - cache_request (mirrors Python Transport.cache_request)

    /// Satisfy a cache request for `packetHash` against `destination`.
    ///
    /// If the packet is found in the local announce cache it is replayed directly
    /// into the inbound pipeline (no network hop needed). Otherwise a CACHE_REQUEST
    /// DATA packet is sent to `destination` asking the peer to replay the packet.
    ///
    /// Mirrors Python's `Transport.cache_request(packet_hash, destination)`.
    public func cacheRequest(packetHash: Data, destination: Destination) {
        if let cached = try? getCachedAnnounce(hash: packetHash),
           let iface = interfaces.first {
            handleIncoming(packet: cached, from: iface)
        } else {
            let pkt = Packet(
                destinationType: .single,
                packetType: .data,
                destinationHash: destination.hash,
                context: .cacheRequest,
                data: packetHash
            )
            try? send(pkt, generateReceipt: false)
        }
    }

    // MARK: - Codable helper

    private struct CachedAnnounceEntry: Codable {
        let rawHex: String
        let interfaceName: String?
    }
}

