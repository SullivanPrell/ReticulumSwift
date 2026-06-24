import XCTest
@testable import ReticulumSwift

/// Tests for destination_data / identity_data RPC handlers and the
/// associated Transport methods — covering Phase 30 parity with RNS 1.3.4.
///
/// These mirror Python's:
///   • `Identity._used_destination_data(destination_hash)`
///   • `Identity._retain_destination_data(destination_hash)`
///   • `Identity._unretain_destination_data(destination_hash)`
///   • `Identity._retain_identity(identity_hash)`
///   • `Identity.clean_known_destinations()` → ratchet file cleanup (1.3.4)
final class DestinationDataRPCTests: XCTestCase {

    // MARK: - markDestinationUsed

    func testMarkDestinationUsed_unknownDestination_returnsFalse() {
        let t = Transport()
        XCTAssertFalse(t.markDestinationUsed(randomHash()))
    }

    func testMarkDestinationUsed_knownDestination_returnsTrue() {
        let t = Transport()
        let id = Identity()
        let hash = randomHash()
        t.restore(identity: id, forDestination: hash)
        XCTAssertTrue(t.markDestinationUsed(hash))
    }

    func testMarkDestinationUsed_knownDestination_setsLastUsed() {
        let t = Transport()
        let id = Identity()
        let hash = randomHash()
        t.restore(identity: id, forDestination: hash)
        let before = Date()
        t.markDestinationUsed(hash)
        t.lock.lock()
        let used = t.knownDestinationLastUsed[hash]
        t.lock.unlock()
        XCTAssertNotNil(used)
        XCTAssertGreaterThanOrEqual(used!.timeIntervalSince1970, before.timeIntervalSince1970 - 1)
    }

    func testMarkDestinationUsed_retainedDestination_returnsFalse() {
        // Python: if slot[4] < 0 (retained), don't update and return False
        let t = Transport()
        let id = Identity()
        let hash = randomHash()
        t.restore(identity: id, forDestination: hash)
        t.retainDestinationData(hash)
        XCTAssertFalse(t.markDestinationUsed(hash))
    }

    func testMarkDestinationUsed_retainedDestination_doesNotSetLastUsed() {
        let t = Transport()
        let id = Identity()
        let hash = randomHash()
        t.restore(identity: id, forDestination: hash)
        t.retainDestinationData(hash)
        t.markDestinationUsed(hash)
        t.lock.lock()
        let used = t.knownDestinationLastUsed[hash]
        t.lock.unlock()
        XCTAssertNil(used)
    }

    // MARK: - retainDestinationData

    func testRetainDestinationData_unknownDestination_returnsFalse() {
        let t = Transport()
        XCTAssertFalse(t.retainDestinationData(randomHash()))
    }

    func testRetainDestinationData_knownDestination_returnsTrue() {
        let t = Transport()
        let hash = randomHash()
        t.restore(identity: Identity(), forDestination: hash)
        XCTAssertTrue(t.retainDestinationData(hash))
    }

    func testRetainDestinationData_preventsCleanup() {
        let t = Transport()
        let hash = randomHash()
        // Very old announcement — would normally be stale
        t.restore(identity: Identity(), forDestination: hash,
                  announcedAt: Date().addingTimeInterval(-1_000_000))
        t.retainDestinationData(hash)
        t.cleanKnownDestinations(now: Date().addingTimeInterval(1_000_000))
        XCTAssertNotNil(t.recall(identity: hash))
    }

    // MARK: - unretainDestinationData

    func testUnretainDestinationData_unknownDestination_returnsFalse() {
        let t = Transport()
        XCTAssertFalse(t.unretainDestinationData(randomHash()))
    }

    func testUnretainDestinationData_knownRetained_returnsTrue() {
        let t = Transport()
        let hash = randomHash()
        t.restore(identity: Identity(), forDestination: hash)
        t.retainDestinationData(hash)
        XCTAssertTrue(t.unretainDestinationData(hash))
    }

    func testUnretainDestinationData_allowsCleanup() {
        let t = Transport()
        let hash = randomHash()
        t.restore(identity: Identity(), forDestination: hash,
                  announcedAt: Date().addingTimeInterval(-1_000_000))
        t.retainDestinationData(hash)
        t.unretainDestinationData(hash)
        // Now the destination can be cleaned
        t.cleanKnownDestinations(now: Date().addingTimeInterval(1_000_000))
        XCTAssertNil(t.recall(identity: hash))
    }

    // MARK: - retainIdentity

    func testRetainIdentity_noMatchingDestinations_returnsFalse() {
        let t = Transport()
        let targetId = Identity()
        // Add a destination for a DIFFERENT identity — no match
        t.restore(identity: Identity(), forDestination: randomHash())
        XCTAssertFalse(t.retainIdentity(targetId.hash))
    }

    func testRetainIdentity_matchingDestination_returnsTrue() {
        let t = Transport()
        let id = Identity()
        let hash = randomHash()
        t.restore(identity: id, forDestination: hash)
        XCTAssertTrue(t.retainIdentity(id.hash))
    }

    func testRetainIdentity_retainsAllMatchingDestinations() {
        let t = Transport()
        let id = Identity()
        let hash1 = randomHash()
        let hash2 = randomHash()
        t.restore(identity: id, forDestination: hash1)
        t.restore(identity: id, forDestination: hash2)
        t.retainIdentity(id.hash)
        t.lock.lock()
        let retained1 = t.retainedDestinations.contains(hash1)
        let retained2 = t.retainedDestinations.contains(hash2)
        t.lock.unlock()
        XCTAssertTrue(retained1)
        XCTAssertTrue(retained2)
    }

    func testRetainIdentity_doesNotRetainOtherDestinations() {
        let t = Transport()
        let id = Identity()
        let otherId = Identity()
        let idHash  = randomHash()
        let otherHash = randomHash()
        t.restore(identity: id, forDestination: idHash)
        t.restore(identity: otherId, forDestination: otherHash)
        t.retainIdentity(id.hash)
        t.lock.lock()
        let retainedOther = t.retainedDestinations.contains(otherHash)
        t.lock.unlock()
        XCTAssertFalse(retainedOther)
    }

    // MARK: - cleanKnownDestinations — ratchet file cleanup (1.3.4)

    func testCleanKnownDestinations_deletesRatchetFileForStaleDest() throws {
        let t = Transport()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ratchets-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        t.ratchetsDirectory = tmpDir

        let hash = randomHash()
        // Very old announcement = stale
        t.restore(identity: Identity(), forDestination: hash,
                  announcedAt: Date().addingTimeInterval(-1_000_000))

        // Write a ratchet file for this destination
        let ratchetFile = tmpDir.appendingPathComponent(hash.hexString)
        try Data("fake ratchet".utf8).write(to: ratchetFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ratchetFile.path))

        // Clean with far-future time — destination becomes stale
        t.cleanKnownDestinations(now: Date().addingTimeInterval(1_000_000))

        // Ratchet file must be gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: ratchetFile.path))
    }

    func testCleanKnownDestinations_keepsRatchetFileForActiveDest() throws {
        let t = Transport()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ratchets-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        t.ratchetsDirectory = tmpDir

        let hash = randomHash()
        let now = Date()
        t.restore(identity: Identity(), forDestination: hash, announcedAt: now)
        // Active path keeps it from being cleaned
        t.restore(path: Transport.PathEntry(
            destinationHash: hash,
            nextHopInterfaceName: "test",
            hops: 1,
            lastHeard: now,
            identityHash: randomHash(),
            expires: now.addingTimeInterval(3600)
        ), forDestination: hash)

        let ratchetFile = tmpDir.appendingPathComponent(hash.hexString)
        try Data("keep this".utf8).write(to: ratchetFile)

        t.cleanKnownDestinations(now: now.addingTimeInterval(10))

        // File should still be there — destination has active path
        XCTAssertTrue(FileManager.default.fileExists(atPath: ratchetFile.path))
    }

    // MARK: - RPCServer MsgPack dispatch

    func testRPCServer_destinationData_used_returnsTrue() throws {
        let (server, t) = makeServerWithTransport()
        let id = Identity()
        let hash = randomHash()
        t.restore(identity: id, forDestination: hash)

        let call = MsgPack.encode(.map([
            (.string("destination_data"), .string("used")),
            (.string("destination_hash"), .bytes(hash)),
        ]))
        let response = try MsgPack.decode(server.respond(to: call))
        XCTAssertEqual(response, .bool(true))
    }

    func testRPCServer_destinationData_used_unknownDest_returnsFalse() throws {
        let (server, _) = makeServerWithTransport()
        let call = MsgPack.encode(.map([
            (.string("destination_data"), .string("used")),
            (.string("destination_hash"), .bytes(randomHash())),
        ]))
        let response = try MsgPack.decode(server.respond(to: call))
        XCTAssertEqual(response, .bool(false))
    }

    func testRPCServer_destinationData_retain_returnsTrue() throws {
        let (server, t) = makeServerWithTransport()
        let hash = randomHash()
        t.restore(identity: Identity(), forDestination: hash)

        let call = MsgPack.encode(.map([
            (.string("destination_data"), .string("retain")),
            (.string("destination_hash"), .bytes(hash)),
        ]))
        let response = try MsgPack.decode(server.respond(to: call))
        XCTAssertEqual(response, .bool(true))
    }

    func testRPCServer_destinationData_retain_unknownDest_returnsFalse() throws {
        let (server, _) = makeServerWithTransport()
        let call = MsgPack.encode(.map([
            (.string("destination_data"), .string("retain")),
            (.string("destination_hash"), .bytes(randomHash())),
        ]))
        let response = try MsgPack.decode(server.respond(to: call))
        XCTAssertEqual(response, .bool(false))
    }

    func testRPCServer_destinationData_unretain_returnsTrue() throws {
        let (server, t) = makeServerWithTransport()
        let hash = randomHash()
        t.restore(identity: Identity(), forDestination: hash)
        t.retainDestinationData(hash)

        let call = MsgPack.encode(.map([
            (.string("destination_data"), .string("unretain")),
            (.string("destination_hash"), .bytes(hash)),
        ]))
        let response = try MsgPack.decode(server.respond(to: call))
        XCTAssertEqual(response, .bool(true))
    }

    func testRPCServer_identityData_retain_returnsTrue() throws {
        let (server, t) = makeServerWithTransport()
        let id = Identity()
        let hash = randomHash()
        t.restore(identity: id, forDestination: hash)

        let call = MsgPack.encode(.map([
            (.string("identity_data"), .string("retain")),
            (.string("identity_hash"), .bytes(id.hash)),
        ]))
        let response = try MsgPack.decode(server.respond(to: call))
        XCTAssertEqual(response, .bool(true))
    }

    func testRPCServer_identityData_retain_noMatch_returnsFalse() throws {
        let (server, _) = makeServerWithTransport()
        let id = Identity()
        let call = MsgPack.encode(.map([
            (.string("identity_data"), .string("retain")),
            (.string("identity_hash"), .bytes(id.hash)),
        ]))
        let response = try MsgPack.decode(server.respond(to: call))
        XCTAssertEqual(response, .bool(false))
    }

    func testRPCServer_destinationData_retainedDest_usedReturnsFalse() throws {
        // A retained destination's timestamp should NOT be updated by "used"
        let (server, t) = makeServerWithTransport()
        let id = Identity()
        let hash = randomHash()
        t.restore(identity: id, forDestination: hash)
        t.retainDestinationData(hash)

        let call = MsgPack.encode(.map([
            (.string("destination_data"), .string("used")),
            (.string("destination_hash"), .bytes(hash)),
        ]))
        let response = try MsgPack.decode(server.respond(to: call))
        XCTAssertEqual(response, .bool(false))
    }

    // MARK: - blackhole_identity / unblackhole_identity key fix

    func testRPCServer_blackholeIdentity_hashIsValueOfKey() throws {
        // Python sends {"blackhole_identity": <hash bytes>, "until": None, "reason": None}
        // The hash is the VALUE of "blackhole_identity", NOT a separate "identity_hash" key.
        let (server, t) = makeServerWithTransport()
        let id = Identity()
        let idHash = id.hash

        let call = MsgPack.encode(.map([
            (.string("blackhole_identity"), .bytes(idHash)),
            (.string("until"),  .nil),
            (.string("reason"), .nil),
        ]))
        _ = server.respond(to: call)

        // Verify the identity is now blackholed in transport
        t.lock.lock()
        let isBlackholed = t.blackholedIdentities[idHash] != nil
        t.lock.unlock()
        XCTAssertTrue(isBlackholed, "blackhole_identity: hash must be read from the key's VALUE")
    }

    func testRPCServer_unblackholeIdentity_hashIsValueOfKey() throws {
        // Python sends {"unblackhole_identity": <hash bytes>}
        let (server, t) = makeServerWithTransport()
        let id = Identity()
        let idHash = id.hash

        // First blackhole it
        t.blackholeIdentity(idHash)

        let call = MsgPack.encode(.map([
            (.string("unblackhole_identity"), .bytes(idHash)),
        ]))
        _ = server.respond(to: call)

        t.lock.lock()
        let stillBlackholed = t.blackholedIdentities[idHash] != nil
        t.lock.unlock()
        XCTAssertFalse(stillBlackholed, "unblackhole_identity: hash must be read from the key's VALUE")
    }

    func testRPCServer_blackholeIdentity_withUntil() throws {
        // Python can send a non-nil `until` timestamp
        let (server, t) = makeServerWithTransport()
        let id = Identity()
        let idHash = id.hash
        let until = Date().addingTimeInterval(3600).timeIntervalSince1970

        let call = MsgPack.encode(.map([
            (.string("blackhole_identity"), .bytes(idHash)),
            (.string("until"),  .double(until)),
            (.string("reason"), .string("test")),
        ]))
        _ = server.respond(to: call)

        t.lock.lock()
        let entry = t.blackholedIdentities[idHash]
        t.lock.unlock()
        XCTAssertNotNil(entry)
        if let actualUntil = entry?.until {
            XCTAssertEqual(actualUntil, until, accuracy: 0.001)
        } else {
            XCTFail("Expected entry.until to be set")
        }
    }

    // MARK: - Helpers

    private func makeServerWithTransport() -> (RPCServer, Transport) {
        let t = Transport()
        let server = RPCServer(port: 37429, authkey: Data(repeating: 0, count: 32))
        server.transport = t
        return (server, t)
    }

    private func randomHash() -> Data {
        Data((0..<16).map { _ in UInt8.random(in: 0...255) })
    }
}
