import Foundation

/// Blackhole identity management for Transport.
///
/// Mirrors Python's `Transport.blackhole_identity()`, `unblackhole_identity()`,
/// `remove_blackholed_paths()`, and the jobs-loop expiry sweep.
extension Transport {

    // MARK: - Stored state (backed by Transport properties added below)

    /// Per-identity blackhole entry.
    public struct BlackholeEntry: Codable {
        public var source: Data?           // identity hash of who issued the blackhole
        public var until: TimeInterval?    // expiry timestamp (nil = permanent)
        public var reason: String?
    }

    // MARK: - Public API (mirrors Python Transport.blackhole_identity / unblackhole_identity)

    /// Add `identityHash` to the blackhole table.
    /// Returns `true` on success, `nil` if already blackholed, `false` on error.
    /// Mirrors Python's `Transport.blackhole_identity(identity_hash, until, reason)`.
    @discardableResult
    public func blackholeIdentity(_ identityHash: Data,
                                  until: TimeInterval? = nil,
                                  reason: String? = nil) -> Bool? {
        // Insert under blackholeLock, RELEASE it, then removeBlackholedPaths()
        // (which re-acquires blackholeLock via its own check) — the leaf lock is
        // non-recursive, so it must not be held across that call.
        blackholeLock.lock()
        guard !blackholedIdentities.keys.contains(identityHash) else {
            blackholeLock.unlock(); return nil
        }
        blackholedIdentities[identityHash] = BlackholeEntry(
            source: ownerIdentity?.hash,
            until: until,
            reason: reason
        )
        blackholeLock.unlock()
        removeBlackholedPaths()
        return true
    }

    /// Remove `identityHash` from the blackhole table.
    /// Returns `true` on success, `nil` if not blackholed.
    /// Mirrors Python's `Transport.unblackhole_identity(identity_hash)`.
    @discardableResult
    public func unblackholeIdentity(_ identityHash: Data) -> Bool? {
        blackholeLock.lock(); defer { blackholeLock.unlock() }
        guard blackholedIdentities[identityHash] != nil else { return nil }
        blackholedIdentities.removeValue(forKey: identityHash)
        return true
    }

    /// Returns true if `identityHash` is currently blackholed.
    public func isBlackholed(_ identityHash: Data) -> Bool {
        blackholeLock.lock(); defer { blackholeLock.unlock() }
        return blackholedIdentities[identityHash] != nil
    }

    /// Remove path table entries whose associated identity is blackholed.
    /// Mirrors Python's `Transport.remove_blackholed_paths()`.
    public func removeBlackholedPaths() {
        // Snapshot (destHash → identityHash) under `lock`, decide which are
        // blackholed under blackholeLock, then remove under `lock` — the two
        // locks are never held simultaneously.
        lock.lock()
        let candidates: [(dest: Data, identity: Data)] = paths.keys.compactMap { destHash in
            guard let identity = knownIdentities[destHash] else { return nil }
            return (destHash, identity.hash)
        }
        lock.unlock()
        blackholeLock.lock()
        let toRemove = candidates.filter { blackholedIdentities[$0.identity] != nil }.map { $0.dest }
        blackholeLock.unlock()
        guard !toRemove.isEmpty else { return }
        lock.lock()
        for h in toRemove { paths.removeValue(forKey: h) }
        lock.unlock()
    }


    /// Remove expired blackhole entries (where `until` has passed).
    /// Called from the jobs loop. Mirrors Python's expiry sweep in the scheduler.
    public func sweepExpiredBlackholes(now: TimeInterval = Date().timeIntervalSince1970) {
        blackholeLock.lock(); defer { blackholeLock.unlock() }
        let expired = blackholedIdentities.keys.filter { hash in
            if let until = blackholedIdentities[hash]?.until { return now > until }
            return false
        }
        for h in expired { blackholedIdentities.removeValue(forKey: h) }
    }

    // MARK: - Persistence (simple file API, used by tests)

    /// Persist the blackhole table to a JSON file.
    public func saveBlacklist(to url: URL) throws {
        blackholeLock.lock()
        let snapshot = blackholedIdentities
        blackholeLock.unlock()
        let map = Dictionary(uniqueKeysWithValues:
            snapshot.map { (k, v) in (k.hexString, v) }
        )
        let data = try JSONEncoder().encode(map)
        try data.write(to: url, options: .atomic)
    }

    /// Load the blackhole table from a JSON file.
    public func loadBlacklist(from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        let map = try JSONDecoder().decode([String: BlackholeEntry].self, from: data)
        blackholeLock.lock(); defer { blackholeLock.unlock() }
        for (hexHash, entry) in map {
            if let hash = Data(hex: hexHash) {
                blackholedIdentities[hash] = entry
            }
        }
    }

    // MARK: - Directory-based persistence (mirrors Python persist_blackhole / reload_blackhole)

    /// Save only own-sourced entries to `<directory>/local`.
    ///
    /// Mirrors Python's `Transport.persist_blackhole()` (`RNS/Transport.py:3550`), which
    /// writes `umsgpack.packb({identity_hash: entry})` for entries whose source is the
    /// local transport identity.
    ///
    /// The encoding is **msgpack, keyed by the raw 16-byte identity hash** — not JSON and
    /// not hex strings. These files are a shared, cross-implementation format: an instance
    /// publishes its `local` list for others to consume as a blackhole source, and
    /// `reload_blackhole` on the other side feeds whatever it finds straight into
    /// `umsgpack.unpackb`. A JSON file written here makes a Python instance raise
    /// `TypeError: 'int' object is not iterable` on startup, because `{` decodes as the
    /// msgpack positive fixint 123.
    public func persistBlacklist(toDirectory directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ownHash = ownerIdentity?.hash
        blackholeLock.lock()
        let local = blackholedIdentities.filter { $0.value.source == ownHash }
        blackholeLock.unlock()
        let pairs: [(MsgPack.Value, MsgPack.Value)] = local
            .sorted { $0.key.hexString < $1.key.hexString }   // deterministic file bytes
            .map { hash, entry in
                (.bytes(hash), .map([
                    (.string("source"), entry.source.map { .bytes($0) } ?? .nil),
                    (.string("until"),  entry.until.map  { .double($0) } ?? .nil),
                    (.string("reason"), entry.reason.map { .string($0) } ?? .nil),
                ]))
            }
        let data = MsgPack.encode(.map(pairs))
        let localFile = directory.appendingPathComponent(
            StorageInventory.Entry.blackholeLocal.components.last!)
        let tmpFile = directory.appendingPathComponent(
            StorageInventory.Entry.blackholeLocalTemp.components.last!)
        try data.write(to: tmpFile, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(localFile, withItemAt: tmpFile)
        // Fallback: rename if replaceItemAt fails (e.g. localFile didn't exist).
        if FileManager.default.fileExists(atPath: tmpFile.path) {
            try? FileManager.default.moveItem(at: tmpFile, to: localFile)
        }
    }

    /// Load blackhole entries from a directory, matching Python's multi-source logic.
    ///
    /// - `<directory>/local` — own entries (source = ownerIdentity.hash)
    /// - `<directory>/<identity-hash-hex>` — external source files;
    ///   only loaded when the source identity hash is in `allowedSources`.
    ///
    /// Entries whose `until` timestamp is in the past are skipped.
    /// Existing own-sourced entries are not overwritten by external sources.
    ///
    /// Mirrors Python's `Transport.reload_blackhole()`.
    public func reloadBlacklist(fromDirectory directory: URL, allowedSources: [Data]) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let now = Date().timeIntervalSince1970
        let ownHash = ownerIdentity?.hash
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        for filename in files {
            let fileURL = directory.appendingPathComponent(filename)
            let sourceHash: Data?
            if filename == "local" {
                sourceHash = ownHash
            } else {
                guard let decoded = Data(hex: filename),
                      decoded.count == Constants.truncatedHashLength else { continue }
                guard allowedSources.contains(decoded) else { continue }
                sourceHash = decoded
            }
            guard let src = sourceHash else { continue }
            // Python: `source_list = umsgpack.unpackb(packed)`, a map keyed by the raw
            // 16-byte identity hash. Decoding these as JSON silently yields nothing, so a
            // Swift instance would ignore every blackhole list published by a Python one.
            guard let data = try? Data(contentsOf: fileURL),
                  case .map(let entries)? = try? MsgPack.decode(data)
            else { continue }
            // File I/O is done; guard only the in-memory merge under blackholeLock.
            blackholeLock.lock()
            for (key, value) in entries {
                guard case .bytes(let hash) = key,
                      hash.count == Constants.truncatedHashLength else { continue }
                let fields = value.asDictionary ?? [:]
                let until = fields["until"]?.asDouble
                let reason = fields["reason"]?.asString
                // Skip expired entries.
                if let until, now >= until { continue }
                // Don't overwrite an existing own-source entry with an external one.
                if let existing = blackholedIdentities[hash],
                   existing.source == ownHash, src != ownHash { continue }
                // Python overrides the file's own "source" with the identity the file
                // came from, so a source cannot attribute a blackhole to somebody else.
                blackholedIdentities[hash] = BlackholeEntry(source: src, until: until, reason: reason)
            }
            blackholeLock.unlock()
        }
    }
}
