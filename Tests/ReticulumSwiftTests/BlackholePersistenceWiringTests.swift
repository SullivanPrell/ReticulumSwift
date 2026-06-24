import XCTest
@testable import ReticulumSwift

/// Tests for blackhole directory-based persistence and Reticulum wiring.
///
/// Mirrors Python's `Transport.persist_blackhole()` / `Transport.reload_blackhole()`:
/// - `persist_blackhole()` saves only own-sourced entries to `<blackholepath>/local`.
/// - `reload_blackhole()` loads from `<blackholepath>/local` + external source files
///   (only those listed in `Reticulum.blackhole_sources()`).
final class BlackholePersistenceWiringTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-bh-wire-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - persistBlacklist: only saves own entries

    func testPersistBlacklistSavesOwnEntriesToLocalFile() throws {
        let ownIdentity = Identity()
        let t = Transport()
        t.ownerIdentity = ownIdentity

        let id1 = Identity(); let id2 = Identity()
        // Add own-sourced entries (source == ownerIdentity.hash).
        t.blackholedIdentities[id1.hash] = Transport.BlackholeEntry(
            source: ownIdentity.hash, until: nil, reason: nil)
        t.blackholedIdentities[id2.hash] = Transport.BlackholeEntry(
            source: ownIdentity.hash, until: nil, reason: "spam")

        try t.persistBlacklist(toDirectory: tmpDir)

        let localFile = tmpDir.appendingPathComponent("local")
        XCTAssertTrue(FileManager.default.fileExists(atPath: localFile.path),
            "persistBlacklist must create 'local' file in the directory")

        // Reload into a fresh transport and verify entries are present.
        let t2 = Transport()
        t2.ownerIdentity = ownIdentity
        try t2.reloadBlacklist(fromDirectory: tmpDir, allowedSources: [])

        XCTAssertTrue(t2.isBlackholed(id1.hash), "id1 must be present after reload")
        XCTAssertTrue(t2.isBlackholed(id2.hash), "id2 must be present after reload")
    }

    // MARK: - persistBlacklist: does NOT save external entries

    func testPersistBlacklistSkipsExternalSourceEntries() throws {
        let ownIdentity = Identity()
        let externalSource = Identity()
        let t = Transport()
        t.ownerIdentity = ownIdentity

        let ownId = Identity()
        let extId = Identity()

        // Own entry.
        t.blackholedIdentities[ownId.hash] = Transport.BlackholeEntry(
            source: ownIdentity.hash, until: nil, reason: nil)
        // External entry (source is a different identity).
        t.blackholedIdentities[extId.hash] = Transport.BlackholeEntry(
            source: externalSource.hash, until: nil, reason: nil)

        try t.persistBlacklist(toDirectory: tmpDir)

        // Reload — only own entries should come back from "local".
        let t2 = Transport()
        t2.ownerIdentity = ownIdentity
        try t2.reloadBlacklist(fromDirectory: tmpDir, allowedSources: [])

        XCTAssertTrue(t2.isBlackholed(ownId.hash),
            "own entry must be loaded from 'local' file")
        XCTAssertFalse(t2.isBlackholed(extId.hash),
            "external entry must NOT be loaded from 'local' file")
    }

    // MARK: - reloadBlacklist: loads external source when in allowedSources

    func testReloadBlacklistLoadsAllowedExternalSource() throws {
        let ownIdentity = Identity()
        let externalSource = Identity()

        // Write an external source file with two entries.
        let extId1 = Identity(); let extId2 = Identity()
        let extEntries: [String: Transport.BlackholeEntry] = [
            extId1.hash.hexString: .init(source: externalSource.hash, until: nil, reason: nil),
            extId2.hash.hexString: .init(source: externalSource.hash, until: nil, reason: "test"),
        ]
        let extData = try JSONEncoder().encode(extEntries)
        let extFile = tmpDir.appendingPathComponent(externalSource.hash.hexString)
        try extData.write(to: extFile)

        let t = Transport()
        t.ownerIdentity = ownIdentity
        // allowedSources includes the external source hash.
        try t.reloadBlacklist(fromDirectory: tmpDir, allowedSources: [externalSource.hash])

        XCTAssertTrue(t.isBlackholed(extId1.hash),
            "extId1 must be loaded when external source is allowed")
        XCTAssertTrue(t.isBlackholed(extId2.hash),
            "extId2 must be loaded when external source is allowed")
    }

    // MARK: - reloadBlacklist: skips external source when NOT in allowedSources

    func testReloadBlacklistSkipsDisallowedExternalSource() throws {
        let ownIdentity = Identity()
        let externalSource = Identity()

        let extId = Identity()
        let extEntries: [String: Transport.BlackholeEntry] = [
            extId.hash.hexString: .init(source: externalSource.hash, until: nil, reason: nil),
        ]
        let extData = try JSONEncoder().encode(extEntries)
        let extFile = tmpDir.appendingPathComponent(externalSource.hash.hexString)
        try extData.write(to: extFile)

        let t = Transport()
        t.ownerIdentity = ownIdentity
        // allowedSources is empty — external source is not allowed.
        try t.reloadBlacklist(fromDirectory: tmpDir, allowedSources: [])

        XCTAssertFalse(t.isBlackholed(extId.hash),
            "external entries must not be loaded when source is not in allowedSources")
    }

    // MARK: - reloadBlacklist: skips expired entries

    func testReloadBlacklistSkipsExpiredEntries() throws {
        let ownIdentity = Identity()
        let t = Transport()
        t.ownerIdentity = ownIdentity

        let expiredId = Identity(); let validId = Identity()

        let past = Date().timeIntervalSince1970 - 10
        let future = Date().timeIntervalSince1970 + 3600

        t.blackholedIdentities[expiredId.hash] = Transport.BlackholeEntry(
            source: ownIdentity.hash, until: past, reason: nil)
        t.blackholedIdentities[validId.hash] = Transport.BlackholeEntry(
            source: ownIdentity.hash, until: future, reason: nil)

        try t.persistBlacklist(toDirectory: tmpDir)

        let t2 = Transport()
        t2.ownerIdentity = ownIdentity
        try t2.reloadBlacklist(fromDirectory: tmpDir, allowedSources: [])

        XCTAssertFalse(t2.isBlackholed(expiredId.hash),
            "expired entry (until in past) must not be loaded")
        XCTAssertTrue(t2.isBlackholed(validId.hash),
            "valid entry (until in future) must be loaded")
    }

    // MARK: - reloadBlacklist: permanent entries (until == nil) always load

    func testReloadBlacklistLoadsPermanentEntries() throws {
        let ownIdentity = Identity()
        let t = Transport()
        t.ownerIdentity = ownIdentity

        let permanentId = Identity()
        t.blackholedIdentities[permanentId.hash] = Transport.BlackholeEntry(
            source: ownIdentity.hash, until: nil, reason: nil)

        try t.persistBlacklist(toDirectory: tmpDir)

        let t2 = Transport()
        t2.ownerIdentity = ownIdentity
        try t2.reloadBlacklist(fromDirectory: tmpDir, allowedSources: [])

        XCTAssertTrue(t2.isBlackholed(permanentId.hash),
            "permanent entry (until == nil) must always be loaded")
    }

    // MARK: - reloadBlacklist: local entries don't overwrite existing own-source entry

    func testReloadBlacklistLocalEntryNotOverwrittenByExternal() throws {
        let ownIdentity = Identity()
        let externalSource = Identity()
        let sharedId = Identity()

        // External source file contains sharedId.
        let extEntries: [String: Transport.BlackholeEntry] = [
            sharedId.hash.hexString: .init(source: externalSource.hash, until: nil, reason: "external"),
        ]
        let extData = try JSONEncoder().encode(extEntries)
        let extFile = tmpDir.appendingPathComponent(externalSource.hash.hexString)
        try extData.write(to: extFile)

        // Local file also contains sharedId (own entry takes priority).
        let localEntries: [String: Transport.BlackholeEntry] = [
            sharedId.hash.hexString: .init(source: ownIdentity.hash, until: nil, reason: "local"),
        ]
        let localData = try JSONEncoder().encode(localEntries)
        let localFile = tmpDir.appendingPathComponent("local")
        try localData.write(to: localFile)

        let t = Transport()
        t.ownerIdentity = ownIdentity
        try t.reloadBlacklist(fromDirectory: tmpDir, allowedSources: [externalSource.hash])

        // Own entry must be kept (not overwritten by external).
        let entry = t.blackholedIdentities[sharedId.hash]
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.reason, "local",
            "own entry must not be overwritten by external source for the same identity hash")
    }

    // MARK: - Reticulum wiring: start loads, stop saves

    func testReticulumStartLoadsAndStopSavesBlacklist() throws {
        let storagePath = tmpDir.appendingPathComponent("storage")
        let config = Reticulum.Configuration(storagePath: storagePath, shareInstance: false)
        let r = Reticulum(configuration: config)

        // Prime the blackhole directory before start.
        let blackholePath = storagePath.appendingPathComponent("blackhole")
        try FileManager.default.createDirectory(at: blackholePath, withIntermediateDirectories: true)

        let ownIdentity = Identity()
        r.transport.ownerIdentity = ownIdentity

        let id1 = Identity()
        r.transport.blackholedIdentities[id1.hash] = Transport.BlackholeEntry(
            source: ownIdentity.hash, until: nil, reason: nil)

        // stop() should persist to <storagePath>/blackhole/local.
        try r.start()
        r.stop()

        let localFile = blackholePath.appendingPathComponent("local")
        XCTAssertTrue(FileManager.default.fileExists(atPath: localFile.path),
            "Reticulum.stop() must save blackhole list to <storagePath>/blackhole/local")

        // A fresh Reticulum.start() should reload the saved list.
        let r2 = Reticulum(configuration: Reticulum.Configuration(storagePath: storagePath, shareInstance: false))
        r2.transport.ownerIdentity = ownIdentity
        try r2.start()
        defer { r2.stop() }

        XCTAssertTrue(r2.transport.isBlackholed(id1.hash),
            "Reticulum.start() must reload blackhole list persisted by previous stop()")
    }
}
