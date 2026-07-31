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

    public struct Entry {
        /// Path components relative to the configuration directory.
        public let components: [String]
        public let kind: Kind
        /// Why this name is correct: the Python `file:line` it mirrors, or an explicit statement
        /// that it is port-only and the reason. `bugs/029`'s conclusion is that the one
        /// indefensible position is a divergence nobody wrote down.
        public let authority: String

        public var relativePath: String { components.joined(separator: "/") }

        public init(_ components: [String], _ kind: Kind, authority: String) {
            self.components = components
            self.kind = kind
            self.authority = authority
        }
    }

    /// Resolve an entry against a configuration directory.
    public static func url(_ entry: Entry, in configDirectory: URL) -> URL {
        entry.components.reduce(configDirectory) { $0.appendingPathComponent($1) }
    }

    /// Every distinct path component named by the inventory, for the source guard.
    public static var declaredComponents: Set<String> {
        Set(entries.flatMap(\.components))
    }

    // MARK: - The inventory

    // The configuration directory itself.

    /// `<configdir>/config` — the INI configuration file. Python: `Reticulum.py:245`.
    public static let config = Entry(["config"], .file, authority: "Reticulum.py:245")

    /// `<configdir>/storage`. Python: `Reticulum.py:246`.
    public static let storage = Entry(["storage"], .directory, authority: "Reticulum.py:246")

    /// `<configdir>/interfaces` — external interface modules. Python: `Reticulum.py:252`.
    public static let interfaceModules = Entry(["interfaces"], .directory,
                                               authority: "Reticulum.py:252")

    // Identity material.

    /// `storage/identity` — this node's primary identity. Python: `Identity.to_file` /
    /// `Reticulum.py` identity handling.
    public static let identity = Entry(["storage", "identity"], .file,
                                       authority: "Identity.py:to_file / from_file")

    /// `storage/transport_identity` — the transport identity, loaded at `Transport.start` and
    /// created if absent. Python: `Transport.py:223-231`.
    public static let transportIdentity = Entry(["storage", "transport_identity"], .file,
                                                authority: "Transport.py:223-231")

    /// `storage/ratchets` — per-destination ratchet files. Python: `Identity.py:293,426,453,487`.
    public static let ratchets = Entry(["storage", "ratchets"], .directory,
                                       authority: "Identity.py:293,426,453,487")

    /// `storage/identity.ratchets` — this node's own ratchet set.
    ///
    /// Port-only *name*: the reference keeps every ratchet under `storage/ratchets/` keyed by
    /// destination hash, and has no separate file for the local identity's. Declared as a
    /// divergence pending the comparison in task 3.1 rather than left implicit — an undocumented
    /// divergence is the one outcome `bugs/029` rules out.
    public static let identityRatchets = Entry(["storage", "identity.ratchets"], .file,
                                               authority: "port-only, pending audit — see bugs/029 §3.1")

    // Routing state. These four are `bugs/029`: the reference's names and encodings.

    /// `storage/known_destinations` — umsgpack dict, hash → 5-element list.
    /// Python: `Identity.py:198` (write), `:220` (read).
    public static let knownDestinations = Entry(["storage", "known_destinations"], .file,
                                                authority: "Identity.py:198,220")

    /// `storage/destination_table` — umsgpack list of 8-element entries.
    /// Python: `Transport.py:3405-3408` (write), `:307-360` (read).
    public static let destinationTable = Entry(["storage", "destination_table"], .file,
                                               authority: "Transport.py:3405-3408,307-360")

    /// `storage/tunnels` — umsgpack list of 4-element entries.
    /// Python: `Transport.py:3490-3493` (write), `:368-405` (read).
    public static let tunnels = Entry(["storage", "tunnels"], .file,
                                      authority: "Transport.py:3490-3493,368-405")

    /// `storage/packet_hashlist.raw` — raw concatenated 32-byte hashes.
    /// Python: `Transport.py:3314-3316` (write), `:242-251` (read).
    public static let packetHashlist = Entry(["storage", "packet_hashlist.raw"], .file,
                                             authority: "Transport.py:3314-3316,242-251")

    // Caches.

    /// `storage/cache`. Python: `Reticulum.py:247`.
    public static let cache = Entry(["storage", "cache"], .directory,
                                    authority: "Reticulum.py:247")

    /// `storage/cache/announces` — one file per cached announce, keyed by full packet hash in
    /// lowercase hex, holding umsgpack `[raw, interface_name]`.
    /// Python: `Transport.py:2646-2657` (write), `:2663-2690` (read).
    ///
    /// Path-table restore depends on this: the reference discards any `destination_table` entry
    /// whose announce cannot be loaded (`Transport.py:334-345`).
    public static let announceCache = Entry(["storage", "cache", "announces"], .directory,
                                            authority: "Transport.py:2646-2657,2663-2690")

    /// `storage/resources` — in-progress resource transfers. Python: `Reticulum.py:248`.
    public static let resources = Entry(["storage", "resources"], .directory,
                                        authority: "Reticulum.py:248")

    /// `storage/identities` — identities held by the utilities (`rncp`, `rnx`).
    public static let identities = Entry(["storage", "identities"], .directory,
                                         authority: "rncp/rnx identity store, RNS utilities")

    /// `storage/blackhole` — a *directory* in the reference, created with `os.makedirs`.
    /// Python: `Reticulum.py:250,324`.
    public static let blackhole = Entry(["storage", "blackhole"], .directory,
                                        authority: "Reticulum.py:250,324")

    /// `storage/blackhole/local` — the locally-maintained blackhole list.
    public static let blackholeLocal = Entry(["storage", "blackhole", "local"], .file,
                                             authority: "Reticulum.py:250,324 (contents of the directory)")

    /// `storage/blackhole/local.tmp` — the atomic-replace temporary for the above.
    public static let blackholeLocalTemp = Entry(["storage", "blackhole", "local.tmp"], .file,
                                                 authority: "port-only: atomic write temporary for blackholeLocal")

    // Interface discovery.

    /// `storage/discovery`.
    ///
    /// Port-only: RNS 1.4.x interface discovery keeps discovered peers in the config file, not in
    /// a separate store. Declared pending the comparison in task 3.4.
    public static let discovery = Entry(["storage", "discovery"], .directory,
                                        authority: "port-only, pending audit — see bugs/029 §3.4")

    /// `storage/discovery/interfaces` — discovered interface records.
    public static let discoveredInterfaces = Entry(["storage", "discovery", "interfaces"], .directory,
                                                   authority: "port-only, pending audit — see bugs/029 §3.4")

    public static let entries: [Entry] = [
        config, storage, interfaceModules,
        identity, transportIdentity, ratchets, identityRatchets,
        knownDestinations, destinationTable, tunnels, packetHashlist,
        cache, announceCache, resources, identities,
        blackhole, blackholeLocal, blackholeLocalTemp,
        discovery, discoveredInterfaces,
    ]
}
