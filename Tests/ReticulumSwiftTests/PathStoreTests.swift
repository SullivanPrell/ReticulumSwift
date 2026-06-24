import XCTest
@testable import ReticulumSwift

final class PathStoreTests: XCTestCase {

    func testRoundTripThroughFile() throws {
        let identity = Identity()
        let destinationHash = Hashes.truncatedHash(Data("dest".utf8))
        // Use a lastHeard of "now" so the default 7-day expiry is in the future.
        let entry = Transport.PathEntry(
            destinationHash: destinationHash,
            nextHopInterfaceName: "eth0",
            hops: 3,
            lastHeard: Date(),
            identityHash: identity.hash
        )

        let live = Transport()
        live.restore(path: entry, forDestination: destinationHash)
        live.restore(identity: identity, forDestination: destinationHash)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paths-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try PathStore.snapshot(of: live).write(to: url)

        let revived = Transport()
        try PathStore.read(from: url).apply(to: revived)

        // Compare fields individually — Date equality has sub-millisecond rounding.
        let revived_entry = revived.paths[destinationHash]
        XCTAssertNotNil(revived_entry)
        XCTAssertEqual(revived_entry?.nextHopInterfaceName, entry.nextHopInterfaceName)
        XCTAssertEqual(revived_entry?.hops, entry.hops)
        XCTAssertFalse(revived_entry?.isExpired ?? true)
        XCTAssertEqual(
            revived.knownIdentities[destinationHash]?.publicKeyBytes,
            identity.publicKeyBytes
        )
    }

    /// Per-path announce random blobs must survive a path-store round trip, so
    /// announce-replay protection persists across restarts (Python persists
    /// `PERSIST_RANDOM_BLOBS = 32` blobs per path entry).
    func testRandomBlobsSurviveRoundTrip() throws {
        let identity = Identity()
        let destinationHash = Hashes.truncatedHash(Data("blobdest".utf8))
        let blobs = [Data(repeating: 0x01, count: 10), Data(repeating: 0x02, count: 10)]
        let entry = Transport.PathEntry(
            destinationHash: destinationHash,
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: Date(),
            identityHash: identity.hash,
            randomBlobs: blobs
        )

        let live = Transport()
        live.restore(path: entry, forDestination: destinationHash)
        live.restore(identity: identity, forDestination: destinationHash)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paths-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try PathStore.snapshot(of: live).write(to: url)

        let revived = Transport()
        try PathStore.read(from: url).apply(to: revived)

        XCTAssertEqual(revived.paths[destinationHash]?.randomBlobs, blobs,
            "random blobs must round-trip so replay protection survives a restart")
    }

    /// Only the most recent `PERSIST_RANDOM_BLOBS` blobs are persisted (matching
    /// Python's on-disk cap), newest preserved.
    func testRandomBlobsCappedAtPersistLimit() throws {
        let identity = Identity()
        let destinationHash = Hashes.truncatedHash(Data("blobcap".utf8))
        var blobs: [Data] = []
        for i in 0 ..< (Transport.persistRandomBlobs + 10) {
            blobs.append(Data(repeating: UInt8(i & 0xFF), count: 10))
        }
        let entry = Transport.PathEntry(
            destinationHash: destinationHash,
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: Date(),
            identityHash: identity.hash,
            randomBlobs: blobs
        )

        let live = Transport()
        live.restore(path: entry, forDestination: destinationHash)
        live.restore(identity: identity, forDestination: destinationHash)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paths-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try PathStore.snapshot(of: live).write(to: url)

        let revived = Transport()
        try PathStore.read(from: url).apply(to: revived)

        XCTAssertEqual(revived.paths[destinationHash]?.randomBlobs,
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
