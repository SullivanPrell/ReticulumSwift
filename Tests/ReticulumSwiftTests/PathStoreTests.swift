import XCTest
@testable import ReticulumSwift

/// Round-trip behaviour of `storage/destination_table`.
///
/// A path entry is persisted as its interface's `Interface.hash` and resolved back through
/// `Transport.findInterface(fromHash:)` on load (`bugs/027`, D6), mirroring the reference
/// (`Transport.py:3388`, `:326`). So each round trip here registers the same interface on both
/// transports — a store written by a node and read by one that no longer has that interface
/// legitimately drops the path, which `PathStoreInterfaceIdentityTests` covers.
///
/// Each round trip also installs a *real* destination with its announce in the cache. The
/// reference's entry references an announce and discards any entry whose announce cannot be
/// loaded (`Transport.py:334-345`), so a synthetic destination hash is not a persistable path —
/// see `PersistablePathFixture.swift` for why every test here used to use one.
final class PathStoreTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-pathstore-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    /// Same type and same name on both sides, so `Interface.hash` — `fullHash(displayName)` —
    /// matches across the round trip, exactly as it does for a real interface rebuilt from the
    /// same config. The cache directory is shared for the same reason: the announce cache is on
    /// disk and outlives the process.
    private func makeTransport() -> (Transport, LoopbackInterface) {
        let transport = Transport()
        transport.cacheDirectory = tmpDir.appendingPathComponent("cache")
        let iface = LoopbackInterface(name: "eth0")
        transport.register(interface: iface)
        return (transport, iface)
    }

    private var tableURL: URL {
        tmpDir.appendingPathComponent(StorageInventory.Entry.destinationTable.components.last!)
    }

    func testRoundTripThroughFile() throws {
        let (live, eth0) = makeTransport()
        let installed = try installPersistablePath(on: live, through: eth0, hops: 3,
                                                   aspect: "roundtrip")

        try PathStore.snapshot(of: live).write(to: tableURL)

        let (revived, _) = makeTransport()
        try PathStore.read(from: tableURL).apply(to: revived)

        let entry = try XCTUnwrap(revived.paths[installed.destinationHash])
        XCTAssertEqual(entry.nextHopInterfaceName, "eth0")
        XCTAssertEqual(entry.hops, 3)
        XCTAssertFalse(entry.isExpired)
        XCTAssertEqual(entry.cachedAnnounceHash, installed.announceHash)
    }

    /// The identity comes back through `known_destinations`, not through the path entry — so a
    /// transport that has loaded it resolves the entry's identity hash, and one that has not
    /// still routes. Mirrors `Identity.recall` at `Transport.py:331` and the load order at
    /// `Reticulum.py:344-346`.
    func testIdentityIsResolvedFromKnownDestinationsNotTheEntry() throws {
        let (live, eth0) = makeTransport()
        let installed = try installPersistablePath(on: live, through: eth0, aspect: "identity")
        try PathStore.snapshot(of: live).write(to: tableURL)

        let (withoutIdentity, _) = makeTransport()
        try PathStore.read(from: tableURL).apply(to: withoutIdentity)
        XCTAssertNotNil(withoutIdentity.paths[installed.destinationHash],
                        "an unknown identity does not stop the path restoring — the reference "
                        + "gates only on the announce and the interface (Transport.py:334)")
        XCTAssertEqual(withoutIdentity.paths[installed.destinationHash]?.identityHash, Data())

        let (withIdentity, _) = makeTransport()
        withIdentity.restore(identity: installed.identity,
                             forDestination: installed.destinationHash)
        try PathStore.read(from: tableURL).apply(to: withIdentity)
        XCTAssertEqual(withIdentity.paths[installed.destinationHash]?.identityHash,
                       installed.identity.hash)
    }

    /// Per-path announce random blobs must survive a round trip, so announce-replay protection
    /// and the path-freshness timebase both persist across restarts.
    func testRandomBlobsSurviveRoundTrip() throws {
        let blobs = [Data(repeating: 0x01, count: 10), Data(repeating: 0x02, count: 10)]
        let (live, eth0) = makeTransport()
        let installed = try installPersistablePath(on: live, through: eth0, aspect: "blobs")
        live.paths[installed.destinationHash]?.randomBlobs = blobs

        try PathStore.snapshot(of: live).write(to: tableURL)

        let (revived, _) = makeTransport()
        try PathStore.read(from: tableURL).apply(to: revived)

        XCTAssertEqual(revived.paths[installed.destinationHash]?.randomBlobs, blobs,
            "random blobs must round-trip so replay protection survives a restart")
    }

    /// Only the most recent `PERSIST_RANDOM_BLOBS` blobs are persisted, newest preserved.
    ///
    /// The reference truncates to this bound when persisting its tunnel paths
    /// (`Transport.py:3468`) and — inconsistently — does not when persisting the destination
    /// table, where the in-memory `MAX_RANDOM_BLOBS` cap of 64 is what reaches disk. Either is
    /// readable by either implementation, since the reader takes the list as it finds it; the
    /// documented bound is kept.
    func testRandomBlobsCappedAtPersistLimit() throws {
        var blobs: [Data] = []
        for i in 0 ..< (Transport.persistRandomBlobs + 10) {
            blobs.append(Data(repeating: UInt8(i & 0xFF), count: 10))
        }
        let (live, eth0) = makeTransport()
        let installed = try installPersistablePath(on: live, through: eth0, aspect: "blobcap")
        live.paths[installed.destinationHash]?.randomBlobs = blobs

        try PathStore.snapshot(of: live).write(to: tableURL)

        let (revived, _) = makeTransport()
        try PathStore.read(from: tableURL).apply(to: revived)

        XCTAssertEqual(revived.paths[installed.destinationHash]?.randomBlobs,
                       Array(blobs.suffix(Transport.persistRandomBlobs)),
                       "only the newest PERSIST_RANDOM_BLOBS blobs are kept on disk")
    }

    func testHexRoundTrip() {
        let bytes = Data([0x00, 0xFF, 0x10, 0xAB])
        XCTAssertEqual(bytes.hexString, "00ff10ab")
        XCTAssertEqual(Data(hex: "00ff10ab"), bytes)
        XCTAssertNil(Data(hex: "0z"))
        XCTAssertNil(Data(hex: "abc"))
    }
}
