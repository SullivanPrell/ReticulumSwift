import XCTest
@testable import ReticulumSwift

/// The path table must be the file the reference writes, in name *and* shape.
///
/// `bugs/029` — the port writes `storage/paths.json`, a JSON document whose entries inline the
/// destination's public key and ratchet. The reference writes `storage/destination_table`,
/// msgpack, whose entries are an 8-element list carrying a *reference* to a cached announce and
/// nothing else about the identity: the public key comes back through `known_destinations` and the
/// ratchet through `storage/ratchets/`. Re-encoding the port's shape as msgpack under the
/// reference's name would produce a file Python still cannot read, which is why the shape changes
/// too (design D2).
///
/// The announce reference is what makes this a *gated* change rather than a sibling of the
/// announce-cache fix: the reference discards any entry whose announce cannot be loaded
/// (`Transport.py:334-345`), so field 7 has to name a file that actually parses.
final class PathTableParityTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-pathtable-parity-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Fixture

    /// A transport holding one learned path, with the announce that established it in the cache —
    /// the state the reference persists and restores from.
    private struct Fixture {
        let transport: Transport
        let interface: LoopbackInterface
        let identity: Identity
        let destinationHash: Data
        let announce: Packet
        let announceHash: Data
        let entry: Transport.PathEntry
    }

    private func makeFixture(hops: UInt8 = 3,
                             nextHopTransportID: Data? = nil,
                             randomBlobs: [Data] = [],
                             cacheAnnounce: Bool = true) throws -> Fixture {
        let transport = Transport()
        transport.cacheDirectory = tmpDir.appendingPathComponent("cache")
        let iface = LoopbackInterface(name: "eth0")
        transport.register(interface: iface)

        let identity = Identity()
        let destination = try Destination(identity: identity, direction: .in, kind: .single,
                                          appName: "pathparity", aspects: ["table"])
        let announce = try Announce.make(for: destination)
        let announceHash = Hashes.fullHash(try announce.hashablePart())

        let entry = Transport.PathEntry(
            destinationHash: destination.hash,
            nextHopInterface: iface,
            hops: hops,
            lastHeard: Date(),
            identityHash: identity.hash,
            nextHopTransportID: nextHopTransportID,
            cachedAnnounceHash: announceHash,
            randomBlobs: randomBlobs
        )
        transport.restore(path: entry, forDestination: destination.hash)
        transport.restore(identity: identity, forDestination: destination.hash)
        if cacheAnnounce {
            try transport.cacheAnnounce(announce, receivingInterfaceName: iface.name)
        }

        return Fixture(transport: transport, interface: iface, identity: identity,
                       destinationHash: destination.hash, announce: announce,
                       announceHash: announceHash, entry: entry)
    }

    /// A second transport with the same interface registered under the same name, so
    /// `Interface.hash` matches across the restart the way a real interface rebuilt from the same
    /// config does. Shares the fixture's cache directory: the announce cache is on disk.
    private func makeReceiver() -> (Transport, LoopbackInterface) {
        let transport = Transport()
        transport.cacheDirectory = tmpDir.appendingPathComponent("cache")
        let iface = LoopbackInterface(name: "eth0")
        transport.register(interface: iface)
        return (transport, iface)
    }

    private var tableURL: URL {
        StorageInventory.url(.destinationTable, storage: tmpDir)
    }

    // MARK: - The shape

    /// `Transport.save_path_table`: `umsgpack.packb(serialised_destinations)` written to
    /// `storagepath+"/destination_table"`, each entry the 8-element list at
    /// `Transport.py:3390-3397`.
    func testDestinationTableIsReferenceShape() throws {
        let fixture = try makeFixture(hops: 3,
                                      nextHopTransportID: Data(repeating: 0xAB, count: 16),
                                      randomBlobs: [Data(repeating: 0x11, count: 10)])

        try PathStore.snapshot(of: fixture.transport).write(to: tableURL)

        // Deliberately no `fileExists(atPath: tableURL.path)` assertion here. `write(to:)` writes
        // wherever it is pointed, so such a check would pass for any filename this test chose and
        // observe nothing — the name is decided by the *call sites*. The name is guarded where it
        // is actually decided: `StorageInventoryTests` (no call site composes its own literal) and
        // task 2.9 (the created file set matches the reference's).
        let decoded = try MsgPack.decode(Data(contentsOf: tableURL))
        guard case .array(let entries) = decoded else {
            return XCTFail("""
                the file is `umsgpack.packb(serialised_destinations)` — a msgpack array of \
                entries (Transport.py:3407), read back with `umsgpack.unpackb` (:313). \
                Got: \(decoded)
                """)
        }
        XCTAssertEqual(entries.count, 1, "one learned path, one serialised entry")

        guard case .array(let fields) = entries[0] else {
            return XCTFail("each entry is a msgpack list, not \(entries[0])")
        }
        XCTAssertEqual(fields.count, 8,
                       """
                       an entry is the 8-element list at Transport.py:3390-3397: \
                       destination_hash, timestamp, received_from, hops, expires, random_blobs, \
                       interface_hash, packet_hash. Python indexes these positionally \
                       (:317-327), so a differing arity is a differing file.
                       """)
        guard fields.count == 8 else { return }

        XCTAssertEqual(fields[0], .bytes(fixture.destinationHash),
                       "field 0 is the raw 16-byte destination hash; Python gates on "
                       + "`len(destination_hash) == TRUNCATED_HASHLENGTH//8` (:319)")

        guard case .double(let timestamp) = fields[1] else {
            return XCTFail("field 1 is `de[IDX_PT_TIMESTAMP]`, a unix timestamp as written by "
                           + "`time.time()` (Transport.py:2051). Got: \(fields[1])")
        }
        XCTAssertEqual(timestamp, fixture.entry.lastHeard.timeIntervalSince1970, accuracy: 0.001)

        XCTAssertEqual(fields[2], .bytes(Data(repeating: 0xAB, count: 16)),
                       """
                       field 2 is `received_from` — the next hop's transport ID, which Python \
                       inserts verbatim as the HEADER_2 transport field when forwarding \
                       (Transport.py:1158). It is not the interface and not the destination.
                       """)

        XCTAssertEqual(fields[3], .uint(3), "field 3 is the hop count (Transport.py:3392)")

        guard case .double(let expires) = fields[4] else {
            return XCTFail("field 4 is `expires`, a unix timestamp. Got: \(fields[4])")
        }
        XCTAssertEqual(expires, fixture.entry.expires.timeIntervalSince1970, accuracy: 0.001)

        XCTAssertEqual(fields[5], .array([.bytes(Data(repeating: 0x11, count: 10))]),
                       "field 5 is the random-blob list, raw bytes per blob (Transport.py:3394)")

        XCTAssertEqual(fields[6], .bytes(fixture.interface.hash),
                       """
                       field 6 is `interface.get_hash()` (Transport.py:3388), resolved back with \
                       `find_interface_from_hash` on load (:326). Names are deliberately not \
                       unique — every connection accepted by one listener is "Client on <name>" \
                       — which is `bugs/027`.
                       """)

        XCTAssertEqual(fields[7], .bytes(fixture.announceHash),
                       """
                       field 7 is the announce packet's full hash (Transport.py:3396), the key \
                       under which `storage/cache/announces/` holds it.
                       """)
    }

    /// Field 7 is not merely present: the reference resolves it through `get_cached_packet` and
    /// discards the entry when that returns None (`Transport.py:334-345`). A hash naming nothing
    /// is a hash that restores nothing.
    func testAnnounceHashResolvesInTheCache() throws {
        let fixture = try makeFixture()
        try PathStore.snapshot(of: fixture.transport).write(to: tableURL)

        let decoded = try MsgPack.decode(Data(contentsOf: tableURL))
        guard case .array(let entries) = decoded, case .array(let fields) = entries.first,
              fields.count == 8, case .bytes(let announceHash) = fields[7] else {
            return XCTFail("entry does not carry an announce hash at field 7")
        }

        let (receiver, _) = makeReceiver()
        let cached = try receiver.getCachedAnnounce(hash: announceHash)
        XCTAssertNotNil(cached,
                        """
                        the hash at field 7 must name a file in `storage/cache/announces/` that \
                        parses. Python restores the path only when `get_cached_packet` returns a \
                        packet, and logs "The announce packet could not be loaded from cache" \
                        otherwise (Transport.py:334,347).
                        """)
        XCTAssertEqual(try cached?.pack(), try fixture.announce.pack(),
                       "and it must be the announce that established this path")
    }

    // MARK: - Restore

    /// The reference rebuilds the entry from the cached announce and the resolved interface, and
    /// increments the restored packet's hop count because reading from cache is equivalent to
    /// receiving the packet again (`Transport.py:336-343`).
    func testRestoreRebuildsThePathFromTheCachedAnnounce() throws {
        let fixture = try makeFixture(hops: 4,
                                      nextHopTransportID: Data(repeating: 0xCD, count: 16),
                                      randomBlobs: [Data(repeating: 0x22, count: 10)])
        try PathStore.snapshot(of: fixture.transport).write(to: tableURL)

        let (receiver, iface) = makeReceiver()
        try PathStore.read(from: tableURL).apply(to: receiver)

        let restored = try XCTUnwrap(receiver.paths[fixture.destinationHash],
                                     "the entry must come back")
        XCTAssertEqual(restored.hops, 4)
        XCTAssertEqual(restored.nextHopInterface?.hash, iface.hash,
                       "the interface is resolved from its hash (Transport.py:326)")
        XCTAssertEqual(restored.nextHopTransportID, Data(repeating: 0xCD, count: 16))
        XCTAssertEqual(restored.randomBlobs, [Data(repeating: 0x22, count: 10)],
                       "replay protection survives the restart")
        XCTAssertEqual(restored.cachedAnnounceHash, fixture.announceHash,
                       "the restored path names the same announce it held before the stop")
    }

    /// `announce_packet.hops += 1` (`Transport.py:337-339`), asserted at the step that produces
    /// the packet — the gate `apply` gets its go/no-go from — because that is the only place the
    /// value exists. The hop count is not part of a packet's hashable part, so the increment
    /// leaves the announce hash alone and the restored path still names the same cache entry.
    func testRestoredAnnounceHopCountIsIncremented() throws {
        let fixture = try makeFixture()
        let cachedHops = fixture.announce.hops
        try PathStore.snapshot(of: fixture.transport).write(to: tableURL)

        let (receiver, _) = makeReceiver()
        let stored = try PathStore.read(from: tableURL)
        let entry = try XCTUnwrap(stored.entries.first)

        let restored = try XCTUnwrap(PathStore.restoredAnnounce(for: entry, from: receiver),
                                     """
                                     the restore step must produce the announce packet, not just \
                                     confirm its hash: Python unpacks it and increments its hops \
                                     before installing the entry (Transport.py:336-343).
                                     """)
        XCTAssertEqual(restored.hops, cachedHops + 1,
                       """
                       reading a packet from cache is equivalent to receiving it again over an \
                       interface, and it is cached with its non-increased hop count \
                       (Transport.py:337-339, and the comment at :2640-2644).
                       """)
        XCTAssertEqual(Hashes.fullHash(try restored.hashablePart()), fixture.announceHash,
                       "the increment must not move the announce hash — hops is not hashable")
    }

    /// `if announce_packet != None and receiving_interface != None` — an entry failing either
    /// gate is dropped whole, not installed with a placeholder (`Transport.py:334-345`).
    func testEntryWithNoCachedAnnounceIsDropped() throws {
        let fixture = try makeFixture(cacheAnnounce: false)
        try PathStore.snapshot(of: fixture.transport).write(to: tableURL)

        let (receiver, _) = makeReceiver()
        try PathStore.read(from: tableURL).apply(to: receiver)

        XCTAssertNil(receiver.paths[fixture.destinationHash],
                     """
                     with no file in `storage/cache/announces/` for field 7, the reference logs \
                     "The announce packet could not be loaded from cache" and installs nothing \
                     (Transport.py:334,347). A path with a synthesised announce is a route \
                     nobody can prove.
                     """)
    }

    /// The identity comes back through `known_destinations`, not through the path entry —
    /// `Identity.recall(destination_hash)`, loaded at `Reticulum.py:344` *before* the path table
    /// is read at `:346`. The entry carries no public key of its own.
    func testEntryCarriesNoIdentityMaterial() throws {
        let fixture = try makeFixture()
        try PathStore.snapshot(of: fixture.transport).write(to: tableURL)

        let raw = try Data(contentsOf: tableURL)
        let explanation = """
            the reference's entry holds no identity material: the public key is resolved through \
            `known_destinations` (Identity.py:220) and the ratchet through `storage/ratchets/`. \
            Inlining them makes the file the port's shape under the reference's name.
            """
        // Both encodings, because the defect stores it hex-encoded. Checking only for the raw
        // 64 bytes passes against `paths.json` — they genuinely are not in that file, they are
        // 128 ASCII characters — so that assertion alone reports "no identity material" about the
        // very file that inlines it. Observed: it passed before the fix.
        XCTAssertNil(raw.range(of: fixture.identity.publicKeyBytes), explanation)
        XCTAssertNil(raw.range(of: Data(fixture.identity.publicKeyBytes.hexString.utf8)),
                     explanation)
    }
}
