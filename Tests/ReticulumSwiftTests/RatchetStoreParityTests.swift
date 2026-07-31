import XCTest
@testable import ReticulumSwift

/// `storage/ratchets/<desthash>` must be the file the reference writes.
///
/// The fifth `bugs/029` divergence, and the one the design warned about by name: ratchets carry a
/// matching *directory* and matching *filenames* on both sides, which is exactly the "looks right
/// in a directory listing" condition that hid the other four. The contents do not match. The
/// reference writes `umsgpack.packb({"ratchet": <32 raw bytes>, "received": <float>})`
/// (`Identity.py:426-436`, read at `:487-497`); the port wrote JSON with a hex-encoded key and an
/// ISO-8601 date.
///
/// It is worse than an unreadable file, because both implementations *delete* what they cannot
/// parse at this path — the reference in `_clean_ratchets` ("Corrupted ratchet data … removing
/// file", `:452-482`), the port in its own loader. So each side silently destroys the other's
/// forward-secrecy state on the first start after a switch.
final class RatchetStoreParityTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-ratchetstore-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    /// Drive the live learning path — an inbound announce carrying a ratchet — because that is
    /// the only thing that writes this file.
    private func learnRatchet(on transport: Transport, aspect: String) throws -> (Data, Data) {
        let iface = LoopbackInterface(name: "ratchet-\(aspect)")
        transport.register(interface: iface)
        let identity = Identity()
        let ratchet = identity.rotateRatchet()
        let destination = try Destination(identity: identity, direction: .in, kind: .single,
                                          appName: "ratchetparity", aspects: [aspect])
        let announce = try Announce.make(for: destination, ratchet: ratchet)
        transport.handleIncoming(packet: announce, from: iface)
        return (destination.hash, ratchet)
    }

    func testFileIsMsgpackRatchetAndReceived() throws {
        let transport = Transport()
        transport.ratchetsDirectory = dir
        let (destHash, ratchet) = try learnRatchet(on: transport, aspect: "shape")

        let file = dir.appendingPathComponent(destHash.hexString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "the reference keys the file by `hexrep(destination_hash, delimit=False)` "
                      + "(Identity.py:423,428)")

        let decoded = try MsgPack.decode(Data(contentsOf: file))
        guard case .map(let pairs) = decoded else {
            return XCTFail("""
                the file is `umsgpack.packb({"ratchet": …, "received": …})` (Identity.py:424,434) \
                and is read straight back with `umsgpack.unpackb` (:493). Got: \(decoded)
                """)
        }
        var fields: [String: MsgPack.Value] = [:]
        for (key, value) in pairs {
            if case .string(let name) = key { fields[name] = value }
        }

        XCTAssertEqual(fields["ratchet"], .bytes(ratchet),
                       """
                       `ratchet` is the raw 32-byte key: the reference gates on \
                       `len(ratchet_data["ratchet"]) == RATCHETSIZE//8` (Identity.py:494), which \
                       a 64-character hex string fails.
                       """)

        guard case .double(let received)? = fields["received"] else {
            return XCTFail("""
                `received` is `time.time()`, a float the reference does arithmetic on — \
                `now > ratchet_data["received"]+RATCHET_EXPIRY` (Identity.py:463). An ISO-8601 \
                string raises there. Got: \(String(describing: fields["received"]))
                """)
        }
        XCTAssertEqual(received, Date().timeIntervalSince1970, accuracy: 5)
    }

    /// And it round-trips: a fresh transport pointed at the directory rehydrates.
    ///
    /// On its own this proves nothing about parity — the port round-tripped its own JSON just as
    /// happily, and this assertion passed before the fix. It is the regression half of a pair
    /// whose parity half is `testReferenceWrittenFileIsRead`, and is meaningless without it.
    func testRoundTrip() throws {
        let transport = Transport()
        transport.ratchetsDirectory = dir
        let (destHash, ratchet) = try learnRatchet(on: transport, aspect: "roundtrip")

        let revived = Transport()
        revived.ratchetsDirectory = dir
        revived.loadKnownRatchets()

        XCTAssertEqual(revived.knownRatchets[destHash], ratchet)
        XCTAssertNotNil(revived.knownRatchetTimes[destHash])
    }

    /// A file the reference wrote is read by this implementation — the direction the port could
    /// never do, since it decoded this path as JSON.
    func testReferenceWrittenFileIsRead() throws {
        let destHash = Hashes.truncatedHash(Data("py-written".utf8))
        let ratchet = Data(repeating: 0x7C, count: 32)
        let entry = MsgPack.Value.map([
            (.string("ratchet"), .bytes(ratchet)),
            (.string("received"), .double(Date().timeIntervalSince1970)),
        ])
        try MsgPack.encode(entry).write(to: dir.appendingPathComponent(destHash.hexString))

        let transport = Transport()
        transport.ratchetsDirectory = dir
        transport.loadKnownRatchets()

        XCTAssertEqual(transport.knownRatchets[destHash], ratchet,
                       "a ratchet written by a Python daemon must load here")
    }

    /// `if time.time() < ratchet_data["received"]+Identity.RATCHET_EXPIRY` (`Identity.py:494`) —
    /// an expired ratchet is not loaded, and `_clean_ratchets` removes the file (`:463,476`).
    ///
    /// A fresh reference-written ratchet is planted alongside and asserted present. Without that
    /// control the test passes against the *unfixed* build, where nothing loads at all: "the
    /// expired one is absent" is satisfied by "everything is absent". Verified — it did.
    func testExpiredRatchetIsNotLoaded() throws {
        func plant(_ label: String, receivedAgo: TimeInterval) throws -> Data {
            let destHash = Hashes.truncatedHash(Data(label.utf8))
            let entry = MsgPack.Value.map([
                (.string("ratchet"), .bytes(Data(repeating: 0x01, count: 32))),
                (.string("received"), .double(Date().timeIntervalSince1970 - receivedAgo)),
            ])
            try MsgPack.encode(entry).write(to: dir.appendingPathComponent(destHash.hexString))
            return destHash
        }
        let expired = try plant("expired", receivedAgo: Transport().ratchetExpiry + 60)
        let fresh = try plant("fresh", receivedAgo: 60)

        let transport = Transport()
        transport.ratchetsDirectory = dir
        transport.loadKnownRatchets()

        XCTAssertNil(transport.knownRatchets[expired], "the expired ratchet is not loaded")
        XCTAssertNotNil(transport.knownRatchets[fresh],
                        "and a fresh one beside it is — otherwise the assertion above proves "
                        + "only that nothing was loaded at all")
    }

    /// A file this implementation cannot parse is removed, which is what the reference does with
    /// one it cannot parse at this path (`Identity.py:459-462,476`). That is also what retires
    /// the port's own JSON ratchets on the first start after this change: unlike
    /// `known_destinations.json` and its siblings, these sit at a name the reference *does* use,
    /// so leaving them would mean leaving a file a Python daemon will delete anyway.
    func testUnparseableFileIsRemoved() throws {
        let file = dir.appendingPathComponent(Hashes.truncatedHash(Data("junk".utf8)).hexString)
        try Data(#"{"ratchet":"aabb","received":"2026-07-01T00:00:00Z"}"#.utf8).write(to: file)

        let transport = Transport()
        transport.ratchetsDirectory = dir
        transport.loadKnownRatchets()

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "corrupted ratchet data is removed (Identity.py:459-462,476)")
    }
}
