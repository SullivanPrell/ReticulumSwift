import Foundation

/// On-disk snapshot of Transport's path table — `storage/destination_table`.
///
/// The format is the reference's, byte for byte: `umsgpack.packb` of a list of 8-element entries
/// (`Transport.py:3390-3407` writing, `:307-360` reading). A config directory is a shared surface
/// the moment `rnsd` can be either implementation, so this file has to be one either can read.
///
/// **The shape is the reference's too, not just the encoding** (`bugs/029`, design D2). The port
/// used to inline the destination's public key and ratchet into each entry; the reference stores
/// neither, and instead carries a *reference* to an announce packet held in
/// `storage/cache/announces/`, resolving the identity through `known_destinations`
/// (`Identity.py:220`) and the ratchet through `storage/ratchets/`. Re-encoding the old shape as
/// msgpack under the reference's name would have produced a file with the right name that Python
/// still cannot read — the worst of the available outcomes, because it reads as correct in a
/// directory listing.
///
/// That announce reference is also why the announce cache had to be brought to parity *first*: an
/// entry whose announce cannot be loaded is discarded whole (`Transport.py:334-345`), so a correct
/// `destination_table` beside a JSON announce cache restores nothing at all.
public struct PathStore {

    /// One serialised path — the reference's 8-element entry, in its order.
    ///
    /// Field order is load-bearing: Python indexes positionally (`Transport.py:317-327`), so a
    /// field in the wrong slot is a silently wrong path rather than a parse failure.
    public struct Entry {
        /// 0 — the 16-byte destination hash. Python drops any entry of a different length
        /// (`Transport.py:319`).
        public var destinationHash: Data
        /// 1 — `IDX_PT_TIMESTAMP`, when the path was last heard, as unix seconds.
        public var timestamp: TimeInterval
        /// 2 — `received_from`: the next hop's transport ID, inserted verbatim as the HEADER_2
        /// transport field when forwarding (`Transport.py:1158`). The reference falls back to the
        /// destination hash for an announce that arrived without one (`:1798`), and this mirrors
        /// that, so `nil` in memory and the fallback on disk stay the same value.
        public var receivedFrom: Data
        /// 3 — hop count.
        public var hops: UInt8
        /// 4 — wall-clock expiry, unix seconds.
        public var expires: TimeInterval
        /// 5 — recently-heard announce random blobs, newest last. Replay protection and the
        /// path-freshness timebase both come from these, so they have to survive a restart.
        public var randomBlobs: [Data]
        /// 6 — `interface.get_hash()` (`Transport.py:3388`), resolved back through
        /// ``Transport/findInterface(fromHash:)`` on load (`:326`).
        ///
        /// The hash rather than the name, because names are deliberately not unique: every
        /// connection accepted by one listening interface is `"Client on <server name>"`
        /// (`TCPInterface.py:590`), so resolving a route by name sends traffic to whichever peer
        /// registered first, whatever the announce said (`bugs/027`).
        public var interfaceHash: Data
        /// 7 — the full hash of the announce packet that established this path, under which
        /// `storage/cache/announces/` holds it.
        public var announceHash: Data

        public init(destinationHash: Data,
                    timestamp: TimeInterval,
                    receivedFrom: Data,
                    hops: UInt8,
                    expires: TimeInterval,
                    randomBlobs: [Data],
                    interfaceHash: Data,
                    announceHash: Data) {
            self.destinationHash = destinationHash
            self.timestamp = timestamp
            self.receivedFrom = receivedFrom
            self.hops = hops
            self.expires = expires
            self.randomBlobs = randomBlobs
            self.interfaceHash = interfaceHash
            self.announceHash = announceHash
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) { self.entries = entries }

    // MARK: - Snapshot

    public static func snapshot(of transport: Transport) -> PathStore {
        // Copy the routing table under Transport's lock, then build entries from the local
        // snapshot (the table is mutated on inbound/jobs threads).
        transport.lock.lock()
        let paths = transport.paths
        transport.lock.unlock()
        let liveInterfaceHashes = transport.interfaceHashes()

        var entries: [Entry] = []
        for (destHash, path) in paths {
            // Only persist an entry whose interface is still active, matching
            // `Transport.py:3374`. A path whose interface is gone cannot be resolved back on
            // load, and writing it down would leave a route pointing at nothing.
            guard let interface = path.nextHopInterface,
                  liveInterfaceHashes.contains(interface.hash) else {
                Reticulum.log("Skipping persist for path table entry "
                              + "\(destHash.hexString), interface "
                              + "\(path.nextHopInterfaceName) no longer active", level: .debug)
                continue
            }
            // An entry with no announce reference is unrestorable by definition — the reference
            // discards exactly this case on load (`Transport.py:334`) — so it is not written.
            guard let announceHash = path.cachedAnnounceHash else {
                Reticulum.log("Skipping persist for path table entry "
                              + "\(destHash.hexString), no cached announce", level: .debug)
                continue
            }
            entries.append(Entry(
                destinationHash: destHash,
                timestamp: path.lastHeard.timeIntervalSince1970,
                receivedFrom: path.nextHopTransportID ?? destHash,
                hops: path.hops,
                expires: path.expires.timeIntervalSince1970,
                randomBlobs: Array(path.randomBlobs.suffix(Transport.persistRandomBlobs)),
                interfaceHash: interface.hash,
                announceHash: announceHash
            ))
        }
        return PathStore(entries: entries)
    }

    // MARK: - Restore

    /// Load the announce an entry names, as `Transport.py:334-343` does.
    ///
    /// Returns `nil` when the cache holds no packet for that hash or it will not unpack; the
    /// caller then drops the entry whole rather than installing a path with a synthesised
    /// announce. The returned packet has its hop count **incremented by one**, because reading a
    /// packet from cache is equivalent to receiving it again over an interface and it is cached
    /// with its non-increased hop count (`Transport.py:337-339`, and the comment at `:2640-2644`).
    /// The hop count is not part of a packet's hashable part, so the increment does not move the
    /// announce hash.
    public static func restoredAnnounce(for entry: Entry, from transport: Transport) -> Packet? {
        guard var announce = (try? transport.getCachedAnnounce(hash: entry.announceHash))
            ?? nil else { return nil }
        announce.hops &+= 1
        return announce
    }

    public func apply(to transport: Transport) {
        for entry in entries {
            // `len(destination_hash) == RNS.Reticulum.TRUNCATED_HASHLENGTH//8` (Transport.py:319).
            guard entry.destinationHash.count == Constants.truncatedHashLength else { continue }

            // Resolve the stored interface hash back to a live interface, and drop the entry if
            // nothing answers — the reference gates the restore on `receiving_interface != None`
            // (`Transport.py:326,334`). A route that cannot name the interface it goes through is
            // not a route; falling back to a name is `bugs/027`. Interface identity is derived
            // from `displayName`, so a daemon upgrading across a release that changes any display
            // name drops those paths and relearns them from announces.
            guard let interface = transport.findInterface(fromHash: entry.interfaceHash) else {
                Reticulum.log("Could not reconstruct path table entry from storage for "
                              + "\(entry.destinationHash.hexString): the interface is no longer "
                              + "available", level: .debug)
                continue
            }
            // `announce_packet != None` (`Transport.py:334`). An entry whose announce is missing
            // is dropped, not half-restored.
            //
            // The packet itself is the gate and nothing more, which is also true of the
            // reference: it unpacks the announce, increments its hops, stores only
            // `announce_packet.packet_hash` — a value the increment cannot change, since hops is
            // excluded from a packet's hashable part (`Packet.py:348-353`) — and drops the
            // object. So the increment at `Transport.py:337-339` has no consumer *there* either.
            // Ported anyway, because a restored announce that under-reports its hops would be
            // wrong the moment anything does read it, and asserted at this seam rather than
            // through a path entry that cannot show it.
            guard PathStore.restoredAnnounce(for: entry, from: transport) != nil else {
                Reticulum.log("Could not reconstruct path table entry from storage for "
                              + "\(entry.destinationHash.hexString): the announce packet could "
                              + "not be loaded from cache", level: .debug)
                continue
            }

            // The identity comes from `known_destinations`, exactly as `Identity.recall` does
            // there — which is why `Reticulum.start` loads that file before this one, mirroring
            // `Reticulum.py:344` preceding `:346`. An entry for a destination we have no key for
            // still routes; it just cannot be displayed with an identity hash, same as Python.
            let identityHash = transport.recall(identity: entry.destinationHash)?.hash ?? Data()

            var path = Transport.PathEntry(
                destinationHash: entry.destinationHash,
                nextHopInterface: interface,
                hops: entry.hops,
                lastHeard: Date(timeIntervalSince1970: entry.timestamp),
                identityHash: identityHash,
                expires: Date(timeIntervalSince1970: entry.expires),
                nextHopTransportID: entry.receivedFrom == entry.destinationHash
                    ? nil : entry.receivedFrom,
                cachedAnnounceHash: entry.announceHash,
                randomBlobs: entry.randomBlobs
            )
            path.announceEmittedAt = Transport.timebaseFromRandomBlobs(entry.randomBlobs)

            // Skip entries that are already expired.
            guard !path.isExpired else { continue }
            transport.restore(path: path, forDestination: entry.destinationHash)
        }
    }

    // MARK: - Codec

    /// `umsgpack.packb(serialised_destinations)` — `Transport.py:3407`.
    public func encoded() -> Data {
        MsgPack.encode(.array(entries.map { entry in
            .array([
                .bytes(entry.destinationHash),
                .double(entry.timestamp),
                .bytes(entry.receivedFrom),
                .uint(UInt64(entry.hops)),
                .double(entry.expires),
                .array(entry.randomBlobs.map { .bytes($0) }),
                .bytes(entry.interfaceHash),
                .bytes(entry.announceHash),
            ])
        }))
    }

    /// `umsgpack.unpackb(file.read())` — `Transport.py:313`.
    ///
    /// A file that does not decode throws, so the caller starts with an empty table and logs it,
    /// as the reference does at `:357-359`. Individual entries that do not have the reference's
    /// arity are skipped rather than aborting the load.
    public static func decode(_ data: Data) throws -> PathStore {
        guard case .array(let serialised) = try MsgPack.decode(data) else {
            throw MsgPack.Error.typeMismatch
        }
        var entries: [Entry] = []
        for element in serialised {
            guard case .array(let f) = element, f.count == 8,
                  case .bytes(let destinationHash) = f[0],
                  let timestamp = f[1].asDouble,
                  case .bytes(let receivedFrom) = f[2],
                  let hops = f[3].asDouble,
                  let expires = f[4].asDouble,
                  case .array(let blobs) = f[5],
                  case .bytes(let interfaceHash) = f[6],
                  case .bytes(let announceHash) = f[7] else { continue }
            entries.append(Entry(
                destinationHash: destinationHash,
                timestamp: timestamp,
                receivedFrom: receivedFrom,
                hops: UInt8(clamping: Int(hops)),
                expires: expires,
                randomBlobs: blobs.compactMap(\.asData),
                interfaceHash: interfaceHash,
                announceHash: announceHash
            ))
        }
        return PathStore(entries: entries)
    }

    // MARK: - File I/O

    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> PathStore {
        try decode(Data(contentsOf: url))
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
