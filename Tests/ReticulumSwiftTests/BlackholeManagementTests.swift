import XCTest
@testable import ReticulumSwift

/// Tests for Transport blackhole identity management.
///
/// Mirrors Python's `Transport.blackhole_identity()`, `Transport.unblackhole_identity()`,
/// and `Transport.remove_blackholed_paths()`.
///
/// Blackholed identities have their path table entries removed and announces dropped.
final class BlackholeManagementTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-bh-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - blackholeIdentity

    func testBlackholeIdentityAddsToTable() {
        let t = Transport()
        let identity = Identity()

        let result = t.blackholeIdentity(identity.hash)
        XCTAssertTrue(result == true, "blackholeIdentity must return true on first blackhole")
        XCTAssertTrue(t.isBlackholed(identity.hash), "identity must be in blackhole table after blackholing")
    }

    func testBlackholeIdentityReturnsFalseIfAlreadyBlackholed() {
        let t = Transport()
        let identity = Identity()

        _ = t.blackholeIdentity(identity.hash)
        let second = t.blackholeIdentity(identity.hash)
        XCTAssertNil(second, "blackholeIdentity must return nil when identity already blackholed")
    }

    // MARK: - unblackholeIdentity

    func testUnblackholeIdentityRemovesFromTable() {
        let t = Transport()
        let identity = Identity()

        _ = t.blackholeIdentity(identity.hash)
        XCTAssertTrue(t.isBlackholed(identity.hash))

        let result = t.unblackholeIdentity(identity.hash)
        XCTAssertTrue(result == true, "unblackholeIdentity must return true when entry existed")
        XCTAssertFalse(t.isBlackholed(identity.hash), "identity must not be blackholed after lifting")
    }

    func testUnblackholeIdentityReturnsNilForUnknown() {
        let t = Transport()
        let identity = Identity()

        let result = t.unblackholeIdentity(identity.hash)
        XCTAssertNil(result, "unblackholeIdentity must return nil when identity not blackholed")
    }

    // MARK: - removeBlackholedPaths

    func testRemoveBlackholedPathsDropsAffectedPaths() throws {
        let t = Transport()
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "bh", aspects: ["test"])

        // Register a path for this destination.
        let path = Transport.PathEntry(
            destinationHash: dest.hash,
            nextHopInterfaceName: "eth0",
            hops: 2,
            lastHeard: Date(),
            identityHash: identity.hash
        )
        t.restore(path: path, forDestination: dest.hash)
        t.restore(identity: identity, forDestination: dest.hash)
        XCTAssertNotNil(t.paths[dest.hash], "path must exist before blackholing")

        _ = t.blackholeIdentity(identity.hash)
        t.removeBlackholedPaths()

        XCTAssertNil(t.paths[dest.hash],
            "path for blackholed identity must be removed by removeBlackholedPaths()")
    }

    func testRemoveBlackholedPathsKeepsUnaffectedPaths() throws {
        let t = Transport()
        let good = Identity()
        let bad = Identity()
        let destGood = try Destination(identity: good, direction: .in, kind: .single,
                                       appName: "bh", aspects: ["good"])
        let destBad = try Destination(identity: bad, direction: .in, kind: .single,
                                      appName: "bh", aspects: ["bad"])

        t.restore(path: Transport.PathEntry(destinationHash: destGood.hash,
            nextHopInterfaceName: "eth0", hops: 1, lastHeard: Date(), identityHash: good.hash),
            forDestination: destGood.hash)
        t.restore(identity: good, forDestination: destGood.hash)

        t.restore(path: Transport.PathEntry(destinationHash: destBad.hash,
            nextHopInterfaceName: "eth0", hops: 1, lastHeard: Date(), identityHash: bad.hash),
            forDestination: destBad.hash)
        t.restore(identity: bad, forDestination: destBad.hash)

        _ = t.blackholeIdentity(bad.hash)
        t.removeBlackholedPaths()

        XCTAssertNotNil(t.paths[destGood.hash], "non-blackholed path must be retained")
        XCTAssertNil(t.paths[destBad.hash], "blackholed path must be removed")
    }

    // MARK: - Timed blackhole expiry

    func testBlackholeWithUntilExpiresInSweep() {
        let t = Transport()
        let identity = Identity()

        // Blackhole with an expiry in the past.
        let expiredUntil = Date().timeIntervalSince1970 - 1
        _ = t.blackholeIdentity(identity.hash, until: expiredUntil)
        XCTAssertTrue(t.isBlackholed(identity.hash))

        // Sweep should remove expired entries.
        t.sweepExpiredBlackholes(now: Date().timeIntervalSince1970)
        XCTAssertFalse(t.isBlackholed(identity.hash),
            "blackhole with expired 'until' must be removed by sweep")
    }

    func testBlackholeWithFutureUntilNotExpiredYet() {
        let t = Transport()
        let identity = Identity()

        let futureUntil = Date().timeIntervalSince1970 + 3600
        _ = t.blackholeIdentity(identity.hash, until: futureUntil)

        t.sweepExpiredBlackholes(now: Date().timeIntervalSince1970)
        XCTAssertTrue(t.isBlackholed(identity.hash),
            "blackhole with future 'until' must not be removed by sweep")
    }

    // MARK: - Persistence

    func testBlackholePersistAndLoad() throws {
        let t = Transport()
        let id1 = Identity(); let id2 = Identity()
        _ = t.blackholeIdentity(id1.hash)
        _ = t.blackholeIdentity(id2.hash, until: Date().timeIntervalSince1970 + 3600, reason: "spam")

        let url = tmpDir.appendingPathComponent("blackhole.json")
        try t.saveBlacklist(to: url)

        let t2 = Transport()
        try t2.loadBlacklist(from: url)

        XCTAssertTrue(t2.isBlackholed(id1.hash), "id1 must be blackholed after load")
        XCTAssertTrue(t2.isBlackholed(id2.hash), "id2 must be blackholed after load")
    }

    func testLoadBlacklistFromMissingFileIsNoop() throws {
        let t = Transport()
        let url = tmpDir.appendingPathComponent("nonexistent.json")
        XCTAssertNoThrow(try t.loadBlacklist(from: url))
    }

    // MARK: - Announce filter

    func testBlackholedAnnounceIsDropped() throws {
        let t = Transport()
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "bh", aspects: ["filter"])

        final class TestIface: Interface {
            var name = "bh-iface"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestIface()
        t.register(interface: iface)

        // Blackhole the identity BEFORE the announce arrives.
        _ = t.blackholeIdentity(identity.hash)

        // Deliver the announce.
        let ann = try Announce.make(for: dest)
        iface.inboundHandler?(try Packet.unpack(ann.pack()), iface)

        // The path must NOT be added.
        XCTAssertNil(t.paths[dest.hash],
            "announce from blackholed identity must not create a path table entry")
    }
}
