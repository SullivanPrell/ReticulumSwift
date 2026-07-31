import Foundation

/// On-disk snapshot of Transport's tunnel table — `storage/tunnels`.
///
/// `bugs/029`'s one *absence* rather than divergence: the reference writes this file on the same
/// clock as the path table (`Transport.persist_data`, `Transport.py:3510-3512`) and restores it at
/// start (`:368-405`); the port wrote no counterpart at all. A node with an established tunnel
/// therefore lost every tunnel path across a restart, and could not serve them again until the
/// peer re-announced — which for a tunnel endpoint that is itself waiting is not guaranteed.
///
/// `umsgpack.packb` of a list of `[tunnel_id, interface_hash, paths, expires]` (`:3487`), where
/// each path is the same 8-element list a `destination_table` entry uses. That shared shape is
/// shared here too: both go through ``PathStore/Entry``'s codec, so the two files cannot drift
/// into disagreeing about what a field means.
public struct TunnelStore {

    public struct Entry {
        /// 0 — `IDX_TT_TUNNEL_ID`.
        public var tunnelID: Data
        /// 1 — `IDX_TT_IF`, the tunnel's `interface.get_hash()`, or `nil` when the interface has
        /// gone (`Transport.py:3456-3457`).
        ///
        /// The reference reads this field on restore and then does not use it: it rebuilds each
        /// path's interface from that path's own field 6 and sets the tunnel's own to `None`
        /// (`:374`, `:403`). Written because the entry is positional.
        public var interfaceHash: Data?
        /// 2 — `IDX_TT_PATHS`.
        public var paths: [PathStore.Entry]
        /// 3 — `IDX_TT_EXPIRES`, unix seconds.
        public var expires: TimeInterval

        public init(tunnelID: Data,
                    interfaceHash: Data?,
                    paths: [PathStore.Entry],
                    expires: TimeInterval) {
            self.tunnelID = tunnelID
            self.interfaceHash = interfaceHash
            self.paths = paths
            self.expires = expires
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) { self.entries = entries }

    // MARK: - Snapshot

    public static func snapshot(of transport: Transport) -> TunnelStore {
        transport.lock.lock()
        let tunnels = transport.tunnels
        transport.lock.unlock()

        var entries: [Entry] = []
        for (tunnelID, tunnel) in tunnels {
            // A tunnel whose interface has gone is still written, with a null interface hash —
            // `Transport.py:3456-3457`. Unlike the path table, which skips such entries, a tunnel
            // exists to be re-attached when its endpoint reappears.
            let interfaceHash = tunnel.iface?.hash
            let paths = tunnel.paths.compactMap { destHash, path -> PathStore.Entry? in
                guard let announceHash = path.cachedAnnounceHash else { return nil }
                // Field 6 is the *tunnel's* interface hash, not the path's — `Transport.py:3476`
                // reuses the one computed for the tunnel above.
                return PathStore.Entry(path,
                                       destinationHash: destHash,
                                       interfaceHash: interfaceHash,
                                       announceHash: announceHash)
            }
            entries.append(Entry(tunnelID: tunnelID,
                                 interfaceHash: interfaceHash,
                                 paths: paths,
                                 expires: tunnel.expires.timeIntervalSince1970))
        }
        return TunnelStore(entries: entries)
    }

    // MARK: - Restore

    public func apply(to transport: Transport) {
        for entry in entries {
            var paths: [Data: Transport.PathEntry] = [:]
            for path in entry.paths {
                // Only the announce gates a tunnel path — `if announce_packet != None`
                // (`Transport.py:398`). Deliberately weaker than the destination table's gate,
                // which also requires a live interface (`:334`): a tunnel path with no interface
                // is exactly what a restored tunnel holds until its endpoint reappears and
                // `handle_tunnel` re-attaches one.
                guard PathStore.restoredAnnounce(for: path, from: transport) != nil else {
                    Reticulum.log("Dropping tunnel path for \(path.destinationHash.hexString): "
                                  + "the announce packet could not be loaded from cache",
                                  level: .debug)
                    continue
                }
                let interface = path.interfaceHash
                    .flatMap { transport.findInterface(fromHash: $0) }
                let identityHash = transport.recall(identity: path.destinationHash)?.hash ?? Data()
                paths[path.destinationHash] = path.pathEntry(interface: interface,
                                                             identityHash: identityHash)
            }
            // `if len(tunnel_paths) > 0` (`Transport.py:402`) — a tunnel none of whose paths came
            // back is not installed. An empty tunnel can route nothing.
            guard !paths.isEmpty else { continue }
            // `tunnel = [tunnel_id, None, tunnel_paths, expires]` (`:403`) — the interface is
            // null until the endpoint reappears; the restore does not re-attach one.
            transport.restore(tunnel: Transport.TunnelEntry(
                tunnelID: entry.tunnelID,
                iface: nil,
                paths: paths,
                expires: Date(timeIntervalSince1970: entry.expires)
            ))
        }
    }

    // MARK: - Codec

    /// `umsgpack.packb(serialised_tunnels)` — `Transport.py:3491`.
    public func encoded() -> Data {
        MsgPack.encode(.array(entries.map { entry in
            .array([
                .bytes(entry.tunnelID),
                entry.interfaceHash.map(MsgPack.Value.bytes) ?? .nil,
                .array(entry.paths.map(\.msgpackValue)),
                .double(entry.expires),
            ])
        }))
    }

    /// `umsgpack.unpackb(file.read())` — `Transport.py:371`.
    public static func decode(_ data: Data) throws -> TunnelStore {
        guard case .array(let serialised) = try MsgPack.decode(data) else {
            throw MsgPack.Error.typeMismatch
        }
        var entries: [Entry] = []
        for element in serialised {
            guard case .array(let f) = element, f.count == 4,
                  case .bytes(let tunnelID) = f[0],
                  case .array(let paths) = f[2],
                  let expires = f[3].asDouble else { continue }
            var interfaceHash: Data?
            if case .bytes(let hash) = f[1] { interfaceHash = hash }
            entries.append(Entry(tunnelID: tunnelID,
                                 interfaceHash: interfaceHash,
                                 paths: paths.compactMap(PathStore.Entry.decode),
                                 expires: expires))
        }
        return TunnelStore(entries: entries)
    }

    // MARK: - File I/O

    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> TunnelStore {
        try decode(Data(contentsOf: url))
    }
}
