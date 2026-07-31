import XCTest
@testable import ReticulumSwift

/// `storage/known_destinations` must be the file the reference writes.
///
/// `bugs/029` — the port writes `storage/known_destinations.json`, a JSON object of hex strings.
/// The reference writes `umsgpack.dump(Identity.known_destinations)` (`Identity.py:198`): a map
/// keyed by the raw 16-byte destination hash, whose values are the 5-element list
/// `[last_announce, packet_hash, public_key, app_data, last_use]` read back positionally at
/// `:220-231`.
///
/// This is the store the path table resolves identities through — the reference's
/// `destination_table` entry carries no public key of its own — so a Python daemon that cannot
/// read this file cannot name the identity behind any path it restores.
final class KnownDestinationsParityTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-knowndest-parity-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private var fileURL: URL {
        tmpDir.appendingPathComponent(StorageInventory.Entry.knownDestinations.components.last!)
    }

    private func makeIdentity(appData: Data?) -> (Identity, Data) {
        let identity = Identity()
        identity.appData = appData
        let destHash = Hashes.truncatedHash(Data("known-\(UUID().uuidString)".utf8))
        return (identity, destHash)
    }

    /// Decode the file into the reference's own view of it: hash → 5-element list.
    private func decodedEntries() throws -> [Data: [MsgPack.Value]] {
        guard case .map(let pairs) = try MsgPack.decode(Data(contentsOf: fileURL)) else {
            XCTFail("""
                the file is `umsgpack.dump(Identity.known_destinations)` — a msgpack map \
                (Identity.py:198), loaded with `umsgpack.load` and indexed by destination hash \
                (:220-224).
                """)
            return [:]
        }
        var result: [Data: [MsgPack.Value]] = [:]
        for (key, value) in pairs {
            guard case .bytes(let hash) = key else {
                XCTFail("""
                    keys are the raw 16-byte destination hashes Python uses as dict keys, not \
                    hex strings — `len(known_destination) == TRUNCATED_HASHLENGTH//8` is the gate \
                    at Identity.py:225, and a hex string is 32 characters, so every entry would \
                    be silently dropped. Got: \(key)
                    """)
                continue
            }
            guard case .array(let fields) = value else {
                XCTFail("each value is the list at Identity.py:107, not \(value)")
                continue
            }
            result[hash] = fields
        }
        return result
    }

    // MARK: - The shape

    func testFileIsMsgpackDictOfFiveElementLists() throws {
        let transport = Transport()
        let (identity, destHash) = makeIdentity(appData: Data("app".utf8))
        let announcedAt = Date(timeIntervalSince1970: 1_700_000_000)
        transport.restore(identity: identity, forDestination: destHash, announcedAt: announcedAt)

        try transport.saveKnownDestinations(to: fileURL)

        let entries = try decodedEntries()
        XCTAssertEqual(entries.count, 1)
        let fields = try XCTUnwrap(entries[destHash],
                                   "the entry must be keyed by the raw destination hash")

        XCTAssertEqual(fields.count, 5,
                       """
                       `[time.time(), packet_hash, public_key, app_data, last_use]` \
                       (Identity.py:107). Python indexes these positionally — `[2]` for the key, \
                       `[3]` for app data, `[4]` for last use — so a differing arity is a \
                       differing file, and a shorter one is backfilled at :226-229.
                       """)
        guard fields.count == 5 else { return }

        guard case .double(let lastAnnounce) = fields[0] else {
            return XCTFail("field 0 is the last-announce timestamp. Got: \(fields[0])")
        }
        XCTAssertEqual(lastAnnounce, announcedAt.timeIntervalSince1970, accuracy: 0.001)

        XCTAssertEqual(fields[2], .bytes(identity.publicKeyBytes),
                       """
                       field 2 is the raw 64-byte public key, loaded with \
                       `identity.load_public_key(identity_data[2])` (Identity.py:148). Hex here \
                       is 128 bytes of ASCII and fails that load.
                       """)

        XCTAssertEqual(fields[3], .bytes(Data("app".utf8)),
                       "field 3 is the raw app data (Identity.py:149)")

        XCTAssertEqual(fields[4], .uint(0),
                       """
                       field 4 is `last_use`: 0 for never used, a timestamp once used, -1 when \
                       retained (Identity.py:107,245-255,314-324). The reference seeds it with \
                       the *integer* 0 — `remember` at :107 — so msgpack holds a fixint, not a \
                       float64.
                       """)
    }

    /// `app_data = None` is a legitimate value the reference writes (`Identity.py:107` with
    /// `remember`'s default), and `identity.app_data = identity_data[3]` assigns it back.
    func testAbsentAppDataIsStoredAsNil() throws {
        let transport = Transport()
        let (identity, destHash) = makeIdentity(appData: nil)
        transport.restore(identity: identity, forDestination: destHash)

        try transport.saveKnownDestinations(to: fileURL)

        let fields = try XCTUnwrap(try decodedEntries()[destHash])
        guard fields.count == 5 else { return XCTFail("entry is not the 5-element list") }
        XCTAssertEqual(fields[3], .nil, "no app data is None, not empty bytes")
    }

    /// The `last_use` sentinels, which drive `clean_known_destinations`
    /// (`Identity.py:314-324`): a used destination carries its timestamp, a retained one carries
    /// -1 and is never swept.
    func testLastUseSentinelsAreWritten() throws {
        let transport = Transport()
        let (usedIdentity, usedHash) = makeIdentity(appData: nil)
        let (retainedIdentity, retainedHash) = makeIdentity(appData: nil)
        transport.restore(identity: usedIdentity, forDestination: usedHash)
        transport.restore(identity: retainedIdentity, forDestination: retainedHash)

        let usedAt = Date(timeIntervalSince1970: 1_700_000_500)
        transport.markDestinationUsed(usedHash, at: usedAt)
        transport.retainDestinationData(retainedHash)

        try transport.saveKnownDestinations(to: fileURL)
        let entries = try decodedEntries()

        guard let used = entries[usedHash], used.count == 5,
              let retained = entries[retainedHash], retained.count == 5 else {
            return XCTFail("entries are not the 5-element list")
        }
        guard case .double(let lastUse) = used[4] else {
            return XCTFail("a used destination carries its timestamp. Got: \(used[4])")
        }
        XCTAssertEqual(lastUse, usedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(retained[4], .int(-1),
                       "a retained destination carries the -1 sentinel (Identity.py:255)")
    }

    // MARK: - Reading

    /// `if len(loaded_known_destinations[known_destination]) < 5: … [e[0], e[1], e[2], e[3], 0]`
    /// (`Identity.py:226-229`) — a file written by an older reference has 4-element entries and
    /// is backfilled with a zero `last_use`, not discarded.
    func testFourElementEntryIsBackfilled() throws {
        let identity = Identity()
        let destHash = Hashes.truncatedHash(Data("backfill".utf8))
        let legacy = MsgPack.Value.map([(
            .bytes(destHash),
            .array([.double(1_700_000_000), .bytes(Data(repeating: 0x01, count: 32)),
                    .bytes(identity.publicKeyBytes), .nil])
        )])
        try MsgPack.encode(legacy).write(to: fileURL)

        let transport = Transport()
        try transport.loadKnownDestinations(from: fileURL)

        XCTAssertEqual(transport.recall(identity: destHash)?.publicKeyBytes,
                       identity.publicKeyBytes,
                       "a 4-element entry is backfilled, not dropped (Identity.py:226-229)")
    }

    /// `if len(known_destination) == RNS.Reticulum.TRUNCATED_HASHLENGTH//8` (`Identity.py:225`) —
    /// an entry whose key is not a destination hash is skipped, and does not abort the load.
    func testEntryWithWrongKeyLengthIsSkipped() throws {
        let identity = Identity()
        let goodHash = Hashes.truncatedHash(Data("good".utf8))
        let file = MsgPack.Value.map([
            (.bytes(Data(repeating: 0xFF, count: 8)),
             .array([.double(1), .bytes(Data()), .bytes(identity.publicKeyBytes), .nil, .double(0)])),
            (.bytes(goodHash),
             .array([.double(1), .bytes(Data()), .bytes(identity.publicKeyBytes), .nil, .double(0)])),
        ])
        try MsgPack.encode(file).write(to: fileURL)

        let transport = Transport()
        try transport.loadKnownDestinations(from: fileURL)

        XCTAssertNil(transport.recall(identity: Data(repeating: 0xFF, count: 8)))
        XCTAssertNotNil(transport.recall(identity: goodHash),
                        "a bad key must not stop the rest of the file loading")
    }

    /// Everything the reference reads back — key, app data and both `last_use` sentinels —
    /// survives a write/read cycle through the port.
    func testRoundTrip() throws {
        let transport = Transport()
        let (used, usedHash) = makeIdentity(appData: Data("hello".utf8))
        let (retained, retainedHash) = makeIdentity(appData: nil)
        let announcedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let usedAt = Date(timeIntervalSince1970: 1_700_000_500)
        transport.restore(identity: used, forDestination: usedHash, announcedAt: announcedAt)
        transport.restore(identity: retained, forDestination: retainedHash, announcedAt: announcedAt)
        transport.markDestinationUsed(usedHash, at: usedAt)
        transport.retainDestinationData(retainedHash)

        try transport.saveKnownDestinations(to: fileURL)

        let revived = Transport()
        try revived.loadKnownDestinations(from: fileURL)

        XCTAssertEqual(revived.recall(identity: usedHash)?.publicKeyBytes, used.publicKeyBytes)
        XCTAssertEqual(revived.recallAppData(forDestination: usedHash), Data("hello".utf8))
        XCTAssertNil(revived.recallAppData(forDestination: retainedHash))
        XCTAssertEqual(revived.knownDestinationAnnouncedAt[usedHash]?.timeIntervalSince1970 ?? 0,
                       announcedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(revived.knownDestinationLastUsed[usedHash]?.timeIntervalSince1970 ?? 0,
                       usedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(revived.knownDestinationLastUsed[retainedHash],
                     "the -1 sentinel is retention, not a use time")
        XCTAssertTrue(revived.retainedDestinations.contains(retainedHash),
                      "retention survives the restart — otherwise a pinned destination is swept "
                      + "on the next clean (Identity.py:322-324)")
    }
}
