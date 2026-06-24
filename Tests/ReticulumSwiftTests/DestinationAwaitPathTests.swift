import XCTest
@testable import ReticulumSwift

/// Tests for `Destination.awaitPath()`.
/// Mirrors Python's convenience wrapper that requests a path and blocks.
final class DestinationAwaitPathTests: XCTestCase {

    // MARK: - Path already known

    func testAwaitPathReturnsTrueWhenPathAlreadyKnown() throws {
        let transport = Transport()
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "await", aspects: ["test"])

        // Seed the path table directly.
        let path = Transport.PathEntry(
            destinationHash: dest.hash,
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: Date(),
            identityHash: identity.hash
        )
        transport.restore(path: path, forDestination: dest.hash)

        let result = dest.awaitPath(using: transport, timeout: 0.1)
        XCTAssertTrue(result, "awaitPath must return true immediately when path already known")
    }

    // MARK: - Path not found within timeout

    func testAwaitPathReturnsFalseOnTimeout() throws {
        let transport = Transport()
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "await", aspects: ["timeout"])

        let start = Date()
        let result = dest.awaitPath(using: transport, timeout: 0.15)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(result, "awaitPath must return false when path not found within timeout")
        XCTAssertGreaterThanOrEqual(elapsed, 0.1, "must wait at least timeout seconds before returning")
    }

    // MARK: - Uses destination hash

    func testAwaitPathUsesDestinationHash() throws {
        let transport = Transport()
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "await", aspects: ["hash"])

        // Seed a path for a different destination — awaitPath must use dest.hash specifically.
        let other = Hashes.truncatedHash(Data("other".utf8))
        let path = Transport.PathEntry(
            destinationHash: other,
            nextHopInterfaceName: "eth0",
            hops: 1,
            lastHeard: Date(),
            identityHash: identity.hash
        )
        transport.restore(path: path, forDestination: other)

        let result = dest.awaitPath(using: transport, timeout: 0.1)
        XCTAssertFalse(result, "awaitPath must use the destination's own hash, not another")
    }
}
