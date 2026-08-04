import Foundation

/// The single declaration of every path this implementation reads or writes inside a Reticulum
/// configuration directory.
///
/// Persisted state is an interop surface. A configuration directory becomes shared the moment
/// `rnsd` can be either implementation — which is what the RetiOS macOS daemon probe and the
/// interop suite already assume — so a file whose name or encoding differs from the reference's is
/// a compatibility defect, not a local detail.
///
/// This type exists because `bugs/029` could not have been found any other way. Four files
/// diverged from the reference in both name and encoding for the whole life of the port, under a
/// full unit suite and a green three-implementation interop suite, because each name was a string
/// literal at its own call site and nothing held the claim "this is the set of files we persist."
/// `StorageInventoryTests` compares this declaration against the sources, and the round-trip cells
/// in `tri-test` compare it against what a live Python daemon writes.
public enum StorageInventory {

    /// Whether the entry names a file or a directory. Both matter: the reference creates
    /// `storage/blackhole` with `os.makedirs` (`Reticulum.py:324`), so getting the kind wrong is
    /// as incompatible as getting the name wrong.
    public enum Kind {
        case file
        case directory
    }

    /// Why a name is correct.
    ///
    /// Typed rather than a free-text note, so a test can ask which entries the reference backs
    /// and which are ours. `bugs/029`'s conclusion is that the one indefensible position is a
    /// divergence nobody wrote down — and a divergence recorded in prose nothing can read is
    /// barely better.
    public enum Authority {
        /// The Python `file:line` this name and encoding mirror.
        case reference(String)
        /// A path the reference has no counterpart for, and why it exists anyway.
        case portOnly(reason: String)

        public var citation: String {
            switch self {
            case .reference(let cite): return cite
            case .portOnly(let reason): return "port-only: \(reason)"
            }
        }

        public var isPortOnly: Bool {
            if case .portOnly = self { return true }
            return false
        }
    }

    public struct Entry {
        /// Path components relative to the configuration directory.
        public let components: [String]
        public let kind: Kind
        /// Why this name is correct: the Python `file:line` it mirrors, or an explicit statement
        /// that it is port-only and the reason.
        public let authority: Authority

        public var relativePath: String { components.joined(separator: "/") }

        public init(_ components: [String], _ kind: Kind, authority: Authority) {
            self.components = components
            self.kind = kind
            self.authority = authority
        }
    }

    /// Names the port used before `bugs/029` brought these files to the reference's.
    ///
    /// They are orphans: not read, not written, not deleted. A daemon upgrading past `029` leaves
    /// them on disk and starts these three structures empty, which is exactly what the reference
    /// does when it does not find its own files (`Identity.py:238-240`, `Transport.py:243`). They
    /// are listed here so the guard can assert they are never created again, and so the CHANGELOG
    /// and the operator have one place naming what is safe to delete.
    public static let preParityOrphans = [
        "paths.json",
        "known_destinations.json",
        "packet_hashlist",
    ]

    /// Resolve an entry against a configuration directory.
    public static func url(_ entry: Entry, in configDirectory: URL) -> URL {
        entry.components.reduce(configDirectory) { $0.appendingPathComponent($1) }
    }

    /// Resolve an entry against a storage directory.
    ///
    /// ``Reticulum/Configuration/storagePath`` is settable independently of the configuration
    /// directory — tests point it at a temporary directory, and platforms where two instances
    /// cannot share a config directory rely on it — so a caller holding only the storage path
    /// cannot re-derive the configuration directory from it. Traps for an entry that does not
    /// live under `storage/`: that is a programming error at the call site, not a runtime
    /// condition.
    public static func url(_ entry: Entry, storage storagePath: URL) -> URL {
        precondition(entry.components.first == Entry.storage.relativePath,
                     "\(entry.relativePath) does not live under storage/; "
                     + "resolve it with url(_:in:) against the config directory")
        return entry.components.dropFirst().reduce(storagePath) { $0.appendingPathComponent($1) }
    }

    /// Every distinct path component named by the inventory, for the source guard.
    public static var declaredComponents: Set<String> {
        Set(Entry.all.flatMap(\.components))
    }

}

// MARK: - The inventory

public extension StorageInventory.Entry {

    // The configuration directory itself.

    /// `<configdir>/config` — the INI configuration file. Python: `Reticulum.py:245`.
    static let config = StorageInventory.Entry(
        ["config"], .file,
        authority: .reference("Reticulum.py:245")
    )

    /// `<configdir>/storage`. Python: `Reticulum.py:246`.
    static let storage = StorageInventory.Entry(
        ["storage"], .directory,
        authority: .reference("Reticulum.py:246")
    )

    /// `<configdir>/interfaces` — external interface modules. Python: `Reticulum.py:252`.
    static let interfaceModules = StorageInventory.Entry(
        ["interfaces"], .directory,
        authority: .reference("Reticulum.py:252")
    )

    // Identity material.

    /// `storage/identity` — this node's primary identity. Python: `Identity.to_file` /
    /// `Reticulum.py` identity handling.
    static let identity = StorageInventory.Entry(
        ["storage", "identity"], .file,
        authority: .reference("Identity.py:to_file / from_file")
    )

    /// `storage/transport_identity` — the transport identity, loaded at `Transport.start` and
    /// created if absent. Python: `Transport.py:223-231`.
    static let transportIdentity = StorageInventory.Entry(
        ["storage", "transport_identity"], .file,
        authority: .reference("Transport.py:223-231")
    )

    /// `storage/ratchets` — per-destination ratchet files. Python: `Identity.py:293,426,453,487`.
    static let ratchets = StorageInventory.Entry(
        ["storage", "ratchets"], .directory,
        authority: .reference("Identity.py:293,426,453,487")
    )

    /// `storage/identity.ratchets` — this node's *own* ratchet privates.
    ///
    /// Port-only, and the audit (task 3.1) confirmed it is a divergence RNS cannot have: the
    /// reference has no location for this at all. `storage/ratchets/` holds ratchets *learned
    /// from peers*, keyed by their destination hash; a destination's own ratchets are written
    /// wherever the application says, through `Destination.enable_ratchets(path)`
    /// (`Destination.py:207-221,477`) — LXMF, for instance, puts them at
    /// `<lxmf-storage>/ratchets/<desthash>.ratchets`. ReticulumSwift keeps the stack usable
    /// without an application choosing a path, so it picks one.
    ///
    /// Harmless for interop in both directions: no Python code reads this name, so a Python
    /// daemon on the same directory ignores it rather than mis-parsing or deleting it. The cost
    /// of a switch is that the node's own ratchet history does not carry over, and peers relearn
    /// the current one from the next announce.
    ///
    /// The *format* also differs from the reference's own-ratchet format
    /// (`umsgpack.packb(self.ratchets)`, a list of raw privates newest-first) — but since the
    /// path is ours alone, nothing on the other side ever reads it.
    static let identityRatchets = StorageInventory.Entry(
        ["storage", "identity.ratchets"], .file,
        authority: .portOnly(reason: "the local identity's own ratchets; the reference has no "
                             + "config-directory location for these — see Destination.enable_ratchets")
    )

    // Routing state. These four are `bugs/029`: the reference's names and encodings.

    /// `storage/known_destinations` — umsgpack dict, hash → 5-element list.
    /// Python: `Identity.py:198` (write), `:220` (read).
    static let knownDestinations = StorageInventory.Entry(
        ["storage", "known_destinations"], .file,
        authority: .reference("Identity.py:198,220")
    )

    /// `storage/destination_table` — umsgpack list of 8-element entries.
    /// Python: `Transport.py:3405-3408` (write), `:307-360` (read).
    static let destinationTable = StorageInventory.Entry(
        ["storage", "destination_table"], .file,
        authority: .reference("Transport.py:3405-3408,307-360")
    )

    /// `storage/tunnels` — umsgpack list of 4-element entries.
    /// Python: `Transport.py:3490-3493` (write), `:368-405` (read).
    static let tunnels = StorageInventory.Entry(
        ["storage", "tunnels"], .file,
        authority: .reference("Transport.py:3490-3493,368-405")
    )

    /// `storage/packet_hashlist.raw` — raw concatenated 32-byte hashes.
    /// Python: `Transport.py:3314-3316` (write), `:242-251` (read).
    static let packetHashlist = StorageInventory.Entry(
        ["storage", "packet_hashlist.raw"], .file,
        authority: .reference("Transport.py:3314-3316,242-251")
    )

    // Caches.

    /// `storage/cache`. Python: `Reticulum.py:247`.
    static let cache = StorageInventory.Entry(
        ["storage", "cache"], .directory,
        authority: .reference("Reticulum.py:247")
    )

    /// `storage/cache/announces` — one file per cached announce, keyed by full packet hash in
    /// lowercase hex, holding umsgpack `[raw, interface_name]`.
    /// Python: `Transport.py:2646-2657` (write), `:2663-2690` (read).
    ///
    /// Path-table restore depends on this: the reference discards any `destination_table` entry
    /// whose announce cannot be loaded (`Transport.py:334-345`).
    static let announceCache = StorageInventory.Entry(
        ["storage", "cache", "announces"], .directory,
        authority: .reference("Transport.py:2646-2657,2663-2690")
    )

    /// `storage/resources` — in-progress resource transfers. Python: `Reticulum.py:248`.
    static let resources = StorageInventory.Entry(
        ["storage", "resources"], .directory,
        authority: .reference("Reticulum.py:248")
    )

    /// `storage/identities` — `Reticulum.identitypath`, the identity store the utilities
    /// (`rncp`, `rnx`) keep their keys in.
    static let identities = StorageInventory.Entry(
        ["storage", "identities"], .directory,
        authority: .reference("Reticulum.py:249,320")
    )

    /// `storage/blackhole` — a *directory* in the reference, created with `os.makedirs`.
    /// Python: `Reticulum.py:250,324`.
    static let blackhole = StorageInventory.Entry(
        ["storage", "blackhole"], .directory,
        authority: .reference("Reticulum.py:250,324")
    )

    /// `storage/blackhole/local` — this node's own blackhole entries, umsgpack. The rest of the
    /// directory is one file per remote source, named by its identity hash (`Discovery.py:794`,
    /// read at `Transport.py:3579-3589`).
    static let blackholeLocal = StorageInventory.Entry(
        ["storage", "blackhole", "local"], .file,
        authority: .reference("Transport.py:3652-3657")
    )

    /// `storage/blackhole/local.tmp` — the write-then-rename temporary for the above. The
    /// reference's own name: `tmppath = f"{localpath}.tmp"`.
    static let blackholeLocalTemp = StorageInventory.Entry(
        ["storage", "blackhole", "local.tmp"], .file,
        authority: .reference("Transport.py:3654-3657")
    )

    // Interface discovery.

    /// `storage/discovery` — the parent of the discovered-interface store below.
    ///
    /// Declared port-only pending audit while §1 was in flight; the audit (task 3.4) settled it
    /// the other way. `InterfaceDiscovery.__init__` composes
    /// `os.path.join(storagepath, "discovery", "interfaces")` and `makedirs` it, so the reference
    /// creates both levels.
    static let discovery = StorageInventory.Entry(
        ["storage", "discovery"], .directory,
        authority: .reference("Discovery.py:451-452")
    )

    /// `storage/discovery/interfaces` — one msgpack record per discovered interface, named by
    /// `hexrep(discovery_hash, delimit=False)`, holding the announce's `info` dict plus
    /// `discovered`, `last_heard` and `heard_count`.
    /// Python: `Discovery.py:451-452` (path), `:510-560` (write), `:463-467` (read).
    static let discoveredInterfaces = StorageInventory.Entry(
        ["storage", "discovery", "interfaces"], .directory,
        authority: .reference("Discovery.py:451-452,510-560")
    )

    /// `storage/i2p` — the I2P interface's own state. The reference composes
    /// `rns_storagepath + "/i2p"` and creates it on interface construction
    /// (`I2PInterface.py:90-91`); the port hands it to the embedded i2pd daemon as its data
    /// directory when a config block constructs the interface (`bugs/031`).
    static let i2p = StorageInventory.Entry(
        ["storage", "i2p"], .directory,
        authority: .reference("I2PInterface.py:90-91")
    )

    static let all: [StorageInventory.Entry] = [
        config, storage, interfaceModules,
        identity, transportIdentity, ratchets, identityRatchets,
        knownDestinations, destinationTable, tunnels, packetHashlist,
        cache, announceCache, resources, identities,
        blackhole, blackholeLocal, blackholeLocalTemp, i2p,
        discovery, discoveredInterfaces,
    ]
}
