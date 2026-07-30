import Foundation

/// On-disk snapshot of Transport's path table and known-identity table.
///
/// The format is intentionally simple JSON keyed by hex-encoded destination
/// hash, so it stays inspectable and forward-compatible with renames.
/// `Reticulum.start` loads the snapshot if present; `Reticulum.stop` (or
/// any caller that wants to checkpoint) writes it.
public struct PathStore: Codable {
    public struct Entry: Codable {
        public var destinationHashHex: String
        /// `Interface.hash` of the interface this route leads through.
        ///
        /// The routed value is the interface *object*, which cannot be written down, so
        /// persistence stores its hash and resolves it back through
        /// `Transport.findInterface(fromHash:)` on load — exactly what the reference does
        /// (`Transport.py:3387-3395` writing `interface.get_hash()`, `:326` restoring with
        /// `find_interface_from_hash`). An entry whose hash resolves to nothing is dropped, as
        /// it is there.
        ///
        /// Optional only so a path store written before `bugs/027` still decodes; such an entry
        /// has no resolvable identity and is dropped on load.
        public var nextHopInterfaceHashHex: String?
        /// Display name, for a path listing (`Reticulum.py:1532`). Never used to resolve a route.
        public var nextHopInterfaceName: String
        public var hops: UInt8
        public var lastHeard: Date
        /// Wall-clock expiry, persisted so paths survive restarts with their
        /// original remaining lifetime. Absent entries default to 7 days from
        /// `lastHeard` on load (matching `Transport.pathExpiry`).
        public var expires: Date?
        public var identityHashHex: String
        public var identityPublicKeyHex: String
        public var nextHopTransportIDHex: String?
        public var ratchetPublicKeyHex: String?
        /// Recently-heard announce random blobs (hex, newest last), capped at
        /// `Transport.persistRandomBlobs`. Optional for backward compatibility
        /// with path stores written before replay-protection persistence.
        public var randomBlobsHex: [String]?
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) { self.entries = entries }

    // MARK: - Snapshot

    public static func snapshot(of transport: Transport) -> PathStore {
        // Copy the routing tables under Transport's lock, then build entries from
        // the local snapshots (the tables are mutated on inbound/jobs threads).
        transport.lock.lock()
        let paths = transport.paths
        let knownIdentities = transport.knownIdentities
        let knownRatchets = transport.knownRatchets
        transport.lock.unlock()
        let liveInterfaceHashes = transport.interfaceHashes()
        var entries: [Entry] = []
        for (destHash, path) in paths {
            // Only persist an entry whose interface is still active, matching
            // `Transport.py:3374`. A path whose interface is gone cannot be resolved back on
            // load, and writing it down would leave a route pointing at nothing (R2).
            guard let interface = path.nextHopInterface,
                  liveInterfaceHashes.contains(interface.hash) else {
                Reticulum.log("Skipping persist for path table entry "
                              + "\(destHash.hexString), interface "
                              + "\(path.nextHopInterfaceName) no longer active", level: .debug)
                continue
            }
            let identityHex = knownIdentities[destHash]?
                .publicKeyBytes.hexString ?? ""
            entries.append(Entry(
                destinationHashHex: destHash.hexString,
                nextHopInterfaceHashHex: interface.hash.hexString,
                nextHopInterfaceName: path.nextHopInterfaceName,
                hops: path.hops,
                lastHeard: path.lastHeard,
                expires: path.expires,
                identityHashHex: path.identityHash.hexString,
                identityPublicKeyHex: identityHex,
                nextHopTransportIDHex: path.nextHopTransportID?.hexString,
                ratchetPublicKeyHex: knownRatchets[destHash]?.hexString,
                randomBlobsHex: path.randomBlobs.isEmpty ? nil
                    : path.randomBlobs.suffix(Transport.persistRandomBlobs).map { $0.hexString }
            ))
        }
        return PathStore(entries: entries)
    }

    public func apply(to transport: Transport) {
        for entry in entries {
            guard let destHash = Data(hex: entry.destinationHashHex) else { continue }
            // Resolve the stored interface hash back to a live interface, and drop the entry if
            // nothing answers — the reference does the same (`Transport.py:326`,
            // `receiving_interface != None` gating the restore). A route that cannot name the
            // interface it goes through is not a route; keeping it would mean falling back to a
            // name, which is `bugs/027`. Interface identity is derived from `displayName`, so a
            // daemon upgrading across a release that changes any display name drops those paths
            // and relearns them from announces (R2).
            guard let hashHex = entry.nextHopInterfaceHashHex,
                  let interfaceHash = Data(hex: hashHex),
                  let interface = transport.findInterface(fromHash: interfaceHash) else {
                Reticulum.log("Dropping restored path for \(entry.destinationHashHex): "
                              + "interface \(entry.nextHopInterfaceName) is not registered",
                              level: .debug)
                continue
            }
            let path = Transport.PathEntry(
                destinationHash: destHash,
                nextHopInterface: interface,
                hops: entry.hops,
                lastHeard: entry.lastHeard,
                identityHash: Data(hex: entry.identityHashHex) ?? Data(),
                expires: entry.expires,
                nextHopTransportID: entry.nextHopTransportIDHex.flatMap(Data.init(hex:)),
                randomBlobs: (entry.randomBlobsHex ?? []).compactMap(Data.init(hex:))
            )
            // Skip entries that are already expired.
            guard !path.isExpired else { continue }
            transport.restore(path: path, forDestination: destHash)
            if let pubBytes = Data(hex: entry.identityPublicKeyHex),
               let identity = try? Identity(publicKeyBytes: pubBytes) {
                transport.restore(identity: identity, forDestination: destHash)
            }
            if let ratchetHex = entry.ratchetPublicKeyHex,
               let ratchet = Data(hex: ratchetHex) {
                transport.restore(ratchet: ratchet, forDestination: destHash)
            }
        }
    }

    // MARK: - File I/O

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> PathStore {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PathStore.self, from: Data(contentsOf: url))
    }
}

// MARK: - Hex helpers

public extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(); data.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
