import XCTest
@testable import ReticulumSwift

/// Pins the on-disk format of the blackhole source files.
///
/// Python reference: `RNS/Transport.py` — `persist_blackhole()` (writes
/// `umsgpack.packb({identity_hash: entry})`) and `reload_blackhole()` (reads it back
/// with `umsgpack.unpackb`, iterating raw 16-byte keys).
///
/// These files are a *shared* format, not private state: an instance publishes its
/// `local` list and other instances consume it as a blackhole source
/// (`blackhole_sources` in the config). The port previously wrote JSON keyed by hex
/// strings, which meant:
///
/// - a Python instance reading a Swift-written file raised
///   `TypeError: 'int' object is not iterable`, because `{` decodes as the msgpack
///   positive fixint 123 and `for identity_hash in 123` then fails; and
/// - a Swift instance reading a Python-written file silently loaded nothing, so every
///   published blackhole list was ignored.
///
/// The golden bytes below came from running `umsgpack.packb` in the reference
/// implementation's own vendored copy.
final class BlackholePersistenceFormatTests: XCTestCase {

    private var directory: URL!

    private let identityHash = Data((0..<16).map { UInt8($0) })
    private let sourceHash   = Data((0x10..<0x20).map { UInt8($0) })

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blackhole-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        super.tearDown()
    }

    private var localFile: URL { directory.appendingPathComponent("local") }

    private func makeTransport(owner: Identity) -> Transport {
        let transport = Transport()
        transport.ownerIdentity = owner
        return transport
    }

    // MARK: - Written format

    func testEmptyTableWritesMsgpackEmptyMap() throws {
        // Python: umsgpack.packb({}) == b"\x80". The JSON encoder produced b"{}",
        // which Python then choked on.
        let transport = Transport()
        try transport.persistBlacklist(toDirectory: directory)
        let written = try Data(contentsOf: localFile)
        XCTAssertEqual(written.hexString, "80")
    }

    func testEntryWithNilFieldsMatchesPythonBytes() throws {
        // umsgpack.packb({ident: {"source": src, "until": None, "reason": None}})
        let owner = Identity()
        let transport = makeTransport(owner: owner)
        transport.blackholeLock.lock()
        transport.blackholedIdentities[identityHash] =
            Transport.BlackholeEntry(source: owner.hash, until: nil, reason: nil)
        transport.blackholeLock.unlock()

        try transport.persistBlacklist(toDirectory: directory)
        let written = try Data(contentsOf: localFile)

        // The source hash is the owner's, so compare structurally rather than to a
        // fixed blob; the key encoding and the field names are what matter.
        guard case .map(let pairs) = try MsgPack.decode(written), pairs.count == 1 else {
            return XCTFail("expected a single-entry msgpack map")
        }
        XCTAssertEqual(pairs[0].0, .bytes(identityHash), "key must be the raw 16-byte hash")
        let fields = try XCTUnwrap(pairs[0].1.asDictionary)
        XCTAssertEqual(fields["source"], .bytes(owner.hash))
        XCTAssertEqual(fields["until"], .nil)
        XCTAssertEqual(fields["reason"], .nil)
    }

    func testWrittenFileIsNotJSON() {
        // The regression guard: a JSON first byte is what broke Python.
        let transport = Transport()
        XCTAssertNoThrow(try transport.persistBlacklist(toDirectory: directory))
        let written = try? Data(contentsOf: localFile)
        XCTAssertNotEqual(written?.first, UInt8(ascii: "{"))
    }

    // MARK: - Reading Python's bytes

    func testReadsPythonWrittenEntry() throws {
        // Golden bytes from umsgpack.packb({ident: {"source": src,
        //                                           "until": 1800000000.5,
        //                                           "reason": "spam"}})
        let golden = Data(hex: "81c410000102030405060708090a0b0c0d0e0f83a6736f75726365c410"
                             + "101112131415161718191a1b1c1d1e1fa5756e74696ccb41dad274802"
                             + "00000a6726561736f6ea47370616d")!
        try golden.write(to: directory.appendingPathComponent(sourceHash.hexString))

        let transport = Transport()
        try transport.reloadBlacklist(fromDirectory: directory, allowedSources: [sourceHash])

        transport.blackholeLock.lock()
        let entry = transport.blackholedIdentities[identityHash]
        transport.blackholeLock.unlock()

        let loaded = try XCTUnwrap(entry, "a Python-written blackhole file must be readable")
        XCTAssertEqual(loaded.reason, "spam")
        XCTAssertEqual(try XCTUnwrap(loaded.until), 1_800_000_000.5, accuracy: 0.001)
        // Python overrides the file's own "source" with the identity the file came from.
        XCTAssertEqual(loaded.source, sourceHash)
    }

    func testReadsPythonEmptyMap() throws {
        try Data(hex: "80")!.write(to: localFile)
        let transport = Transport()
        XCTAssertNoThrow(try transport.reloadBlacklist(fromDirectory: directory, allowedSources: []))
    }

    func testIgnoresLegacyJSONFileInsteadOfCrashing() throws {
        // Files written by an older Swift build are simply skipped.
        try Data("{}".utf8).write(to: localFile)
        let transport = Transport()
        XCTAssertNoThrow(try transport.reloadBlacklist(fromDirectory: directory, allowedSources: []))
    }

    // MARK: - Round trip

    func testSwiftRoundTrip() throws {
        let owner = Identity()
        let transport = makeTransport(owner: owner)
        let until = Date().timeIntervalSince1970 + 3600
        transport.blackholeLock.lock()
        transport.blackholedIdentities[identityHash] =
            Transport.BlackholeEntry(source: owner.hash, until: until, reason: "announce flood")
        transport.blackholeLock.unlock()
        try transport.persistBlacklist(toDirectory: directory)

        // Reload into a fresh transport, treating the writer as an allowed source.
        let reader = Transport()
        try FileManager.default.moveItem(at: localFile,
                                         to: directory.appendingPathComponent(owner.hash.hexString))
        try reader.reloadBlacklist(fromDirectory: directory, allowedSources: [owner.hash])

        reader.blackholeLock.lock()
        let entry = reader.blackholedIdentities[identityHash]
        reader.blackholeLock.unlock()

        let loaded = try XCTUnwrap(entry)
        XCTAssertEqual(loaded.reason, "announce flood")
        XCTAssertEqual(try XCTUnwrap(loaded.until), until, accuracy: 0.001)
    }

    func testExpiredEntriesAreSkippedOnLoad() throws {
        let owner = Identity()
        let transport = makeTransport(owner: owner)
        transport.blackholeLock.lock()
        transport.blackholedIdentities[identityHash] = Transport.BlackholeEntry(
            source: owner.hash, until: Date().timeIntervalSince1970 - 60, reason: "stale")
        transport.blackholeLock.unlock()
        try transport.persistBlacklist(toDirectory: directory)
        try FileManager.default.moveItem(at: localFile,
                                         to: directory.appendingPathComponent(owner.hash.hexString))

        let reader = Transport()
        try reader.reloadBlacklist(fromDirectory: directory, allowedSources: [owner.hash])
        reader.blackholeLock.lock()
        let entry = reader.blackholedIdentities[identityHash]
        reader.blackholeLock.unlock()
        XCTAssertNil(entry, "Python: `if until == None or now < until` — expired entries drop")
    }

    func testFileBytesAreDeterministic() throws {
        // Two runs over the same table must produce identical bytes, so that a published
        // list does not appear to change when it has not.
        let owner = Identity()
        let transport = makeTransport(owner: owner)
        transport.blackholeLock.lock()
        for byte in UInt8(1)...UInt8(5) {
            transport.blackholedIdentities[Data(repeating: byte, count: 16)] =
                Transport.BlackholeEntry(source: owner.hash, until: nil, reason: "r\(byte)")
        }
        transport.blackholeLock.unlock()

        try transport.persistBlacklist(toDirectory: directory)
        let first = try Data(contentsOf: localFile)
        try transport.persistBlacklist(toDirectory: directory)
        let second = try Data(contentsOf: localFile)
        XCTAssertEqual(first, second)
    }
}
