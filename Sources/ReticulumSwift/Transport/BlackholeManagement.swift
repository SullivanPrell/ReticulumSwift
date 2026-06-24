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
        guard !blackholedIdentities.keys.contains(identityHash) else { return nil }
        let entry = BlackholeEntry(
            source: ownerIdentity?.hash,
            until: until,
            reason: reason
        )
        blackholedIdentities[identityHash] = entry
        removeBlackholedPaths()
        return true
    }

    /// Remove `identityHash` from the blackhole table.
    /// Returns `true` on success, `nil` if not blackholed.
    /// Mirrors Python's `Transport.unblackhole_identity(identity_hash)`.
    @discardableResult
    public func unblackholeIdentity(_ identityHash: Data) -> Bool? {
        guard blackholedIdentities[identityHash] != nil else { return nil }
        blackholedIdentities.removeValue(forKey: identityHash)
        return true
    }

    /// Returns true if `identityHash` is currently blackholed.
    public func isBlackholed(_ identityHash: Data) -> Bool {
        blackholedIdentities[identityHash] != nil
    }

    /// Remove path table entries whose associated identity is blackholed.
    /// Mirrors Python's `Transport.remove_blackholed_paths()`.
    public func removeBlackholedPaths() {
        let toRemove = paths.keys.filter { destHash in
            guard let identity = knownIdentities[destHash] else { return false }
            return isBlackholed(identity.hash)
        }
        lock.lock()
        for h in toRemove { paths.removeValue(forKey: h) }
        lock.unlock()
    }


    /// Remove expired blackhole entries (where `until` has passed).
    /// Called from the jobs loop. Mirrors Python's expiry sweep in the scheduler.
    public func sweepExpiredBlackholes(now: TimeInterval = Date().timeIntervalSince1970) {
        let expired = blackholedIdentities.keys.filter { hash in
            if let until = blackholedIdentities[hash]?.until { return now > until }
            return false
        }
        for h in expired { blackholedIdentities.removeValue(forKey: h) }
    }

    // MARK: - Persistence (simple file API, used by tests)

    /// Persist the blackhole table to a JSON file.
    public func saveBlacklist(to url: URL) throws {
        let map = Dictionary(uniqueKeysWithValues:
            blackholedIdentities.map { (k, v) in (k.hexString, v) }
        )
        let data = try JSONEncoder().encode(map)
        try data.write(to: url, options: .atomic)
    }

    /// Load the blackhole table from a JSON file.
    public func loadBlacklist(from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url)
        let map = try JSONDecoder().decode([String: BlackholeEntry].self, from: data)
        for (hexHash, entry) in map {
            if let hash = Data(hex: hexHash) {
                blackholedIdentities[hash] = entry
            }
        }
    }

    // MARK: - Directory-based persistence (mirrors Python persist_blackhole / reload_blackhole)

    /// Save only own-sourced entries to `<directory>/local`.
    ///
    /// Mirrors Python's `Transport.persist_blackhole()` which writes
    /// `{identity_hash: entry}` for entries whose source is the local transport identity.
    public func persistBlacklist(toDirectory directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ownHash = ownerIdentity?.hash
        let local = blackholedIdentities.filter { $0.value.source == ownHash }
        let map = Dictionary(uniqueKeysWithValues: local.map { ($0.key.hexString, $0.value) })
        let data = try JSONEncoder().encode(map)
        let localFile = directory.appendingPathComponent("local")
        let tmpFile = directory.appendingPathComponent("local.tmp")
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
            guard let data = try? Data(contentsOf: fileURL),
                  let map = try? JSONDecoder().decode([String: BlackholeEntry].self, from: data)
            else { continue }
            for (hexHash, entry) in map {
                guard let hash = Data(hex: hexHash),
                      hash.count == Constants.truncatedHashLength else { continue }
                // Skip expired entries.
                if let until = entry.until, now >= until { continue }
                // Don't overwrite an existing own-source entry with an external one.
                if let existing = blackholedIdentities[hash],
                   existing.source == ownHash, src != ownHash { continue }
                let loaded = BlackholeEntry(source: src, until: entry.until, reason: entry.reason)
                blackholedIdentities[hash] = loaded
            }
        }
    }
}
