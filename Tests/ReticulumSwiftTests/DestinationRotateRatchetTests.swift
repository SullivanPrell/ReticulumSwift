import XCTest
@testable import ReticulumSwift

/// Tests for Destination.rotateRatchets() — mirrors Python's Destination.rotate_ratchets().
final class DestinationRotateRatchetTests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-rot-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - rotate without ratchets enabled → throws

    func testRotateRatchetsThrowsIfRatchetsNotEnabled() throws {
        let identity = Identity()
        let dest = try Destination(
            identity: identity, direction: .out, kind: .single,
            appName: "test", aspects: ["rotate"]
        )
        XCTAssertThrowsError(try dest.rotateRatchets()) { error in
            guard case Destination.DestinationError.ratchetsNotEnabled = error else {
                XCTFail("Expected ratchetsNotEnabled, got \(error)")
                return
            }
        }
    }

    // MARK: - rotate with ratchets enabled and interval elapsed → rotates

    func testRotateRatchetsRotatesWhenIntervalElapsed() throws {
        let identity = Identity()
        let dest = try Destination(
            identity: identity, direction: .out, kind: .single,
            appName: "test", aspects: ["rotate"]
        )
        let sidecar = tempDir().appendingPathComponent("d.ratchets")
        try dest.enableRatchets(path: sidecar)

        // Set a very short interval so any elapsed time triggers rotation.
        dest.setRatchetInterval(0)

        let rotated = try dest.rotateRatchets()
        XCTAssertTrue(rotated, "rotateRatchets must return true when a new ratchet is generated")
        XCTAssertNotNil(identity.activeRatchetPublicKey,
            "Identity must have an active ratchet after rotation")
    }

    // MARK: - rotate within interval → returns true (interval not elapsed, no rotation)

    func testRotateRatchetsReturnsTrueWithinInterval() throws {
        let identity = Identity()
        let dest = try Destination(
            identity: identity, direction: .out, kind: .single,
            appName: "test", aspects: ["rotate"]
        )
        let sidecar = tempDir().appendingPathComponent("d2.ratchets")
        try dest.enableRatchets(path: sidecar)

        // Long interval so no rotation is needed yet.
        dest.setRatchetInterval(3600)
        // Force a first rotation to set the last rotation time.
        _ = identity.rotateRatchet()

        let result = try dest.rotateRatchets()
        XCTAssertTrue(result, "rotateRatchets must return true even when interval has not elapsed")
    }

    // MARK: - rotate persists ratchet file

    func testRotateRatchetsPersistsSidecarFile() throws {
        let identity = Identity()
        let dest = try Destination(
            identity: identity, direction: .out, kind: .single,
            appName: "test", aspects: ["rotate"]
        )
        let sidecar = tempDir().appendingPathComponent("d3.ratchets")
        try dest.enableRatchets(path: sidecar)
        dest.setRatchetInterval(0)

        _ = try dest.rotateRatchets()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path),
            "rotateRatchets must persist ratchet privates to the sidecar path")
    }
}
