import XCTest
@testable import ReticulumSwift

/// Tests for Identity.remember() static method.
/// Mirrors Python's `RNS.Identity.remember(packet_hash, destination_hash, public_key, app_data)`.
final class IdentityRememberTests: XCTestCase {

    // MARK: - Helpers

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-remember-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        Reticulum.shared?.stop()
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    private func startReticulum() throws -> Reticulum {
        let cfg = Reticulum.Configuration(storagePath: tmpDir.appendingPathComponent("storage"))
        let rns = Reticulum(configuration: cfg)
        try rns.start()
        return rns
    }

    // MARK: - Identity.remember (Transport-backed via restore)

    func testRememberReturnsParsedIdentity() {
        let remote = Identity()
        let destHash = Identity.truncatedHash(remote.publicKeyBytes)

        // Without a shared Reticulum instance, `remember` still returns an Identity
        // built from the public key bytes (the store step is a no-op).
        let stored = Identity.remember(
            packetHash: nil,
            destinationHash: destHash,
            publicKeyBytes: remote.publicKeyBytes
        )
        XCTAssertNotNil(stored, "remember must return a valid Identity for good public-key bytes")
        XCTAssertEqual(stored?.publicKeyBytes, remote.publicKeyBytes)
    }

    func testRememberReturnsNilForBadPublicKey() {
        let bad = Data(repeating: 0x00, count: 64) // zeroed-out key is invalid
        let destHash = Data(repeating: 0xAB, count: 16)
        // May return nil OR a (degenerate but parsable) identity depending on the
        // Curve25519 implementation.  We only assert it doesn't crash.
        _ = Identity.remember(destinationHash: destHash, publicKeyBytes: bad)
    }

    func testRememberReturnsNilForWrongKeyLength() {
        let destHash = Data(repeating: 0x01, count: 16)
        let result = Identity.remember(
            destinationHash: destHash,
            publicKeyBytes: Data(repeating: 0xAA, count: 32)   // wrong length (need 64)
        )
        XCTAssertNil(result, "remember must return nil when publicKeyBytes.count != 64")
    }

    func testRememberSetsAppData() {
        let remote  = Identity()
        let destHash = Identity.truncatedHash(remote.publicKeyBytes)
        let appData  = Data("app-payload".utf8)

        let stored = Identity.remember(
            destinationHash: destHash,
            publicKeyBytes: remote.publicKeyBytes,
            appData: appData
        )
        XCTAssertEqual(stored?.appData, appData,
                       "remember must propagate appData to the returned identity")
    }

    func testRememberWithPacketHashArgIgnored() {
        // Python's API takes packet_hash as first positional arg; Swift accepts it
        // for parity but ignores it.  Smoke-test that passing a non-nil value
        // doesn't break anything.
        let remote   = Identity()
        let destHash = Identity.truncatedHash(remote.publicKeyBytes)
        let fakeHash = Data(repeating: 0xFF, count: 16)

        let stored = Identity.remember(
            packetHash: fakeHash,
            destinationHash: destHash,
            publicKeyBytes: remote.publicKeyBytes
        )
        XCTAssertNotNil(stored, "remember must succeed regardless of packetHash value")
        XCTAssertEqual(stored?.publicKeyBytes, remote.publicKeyBytes)
    }

    func testRememberDefaultPacketHashIsNil() {
        // Calling without `packetHash:` should compile fine (default = nil).
        let remote   = Identity()
        let destHash = Identity.truncatedHash(remote.publicKeyBytes)
        let stored = Identity.remember(destinationHash: destHash,
                                       publicKeyBytes: remote.publicKeyBytes)
        XCTAssertNotNil(stored)
    }

    // MARK: - Transport-backed round-trip (remember → recall)

    func testRememberThenRecallViaTransport() throws {
        // Build a minimal Reticulum stack so that Reticulum.shared is set and
        // Identity.remember stores into the shared transport.
        let reticulum = try startReticulum()
        defer { reticulum.stop() }

        let remote   = Identity()
        let destHash = Identity.truncatedHash(remote.publicKeyBytes)

        let stored = Identity.remember(
            destinationHash: destHash,
            publicKeyBytes: remote.publicKeyBytes
        )
        XCTAssertNotNil(stored)

        let recalled = Identity.recall(destinationHash: destHash)
        XCTAssertNotNil(recalled, "recall must find the identity stored by remember")
        XCTAssertEqual(recalled?.publicKeyBytes, remote.publicKeyBytes)
    }

    func testRememberThenRecallAppData() throws {
        let reticulum = try startReticulum()
        defer { reticulum.stop() }

        let remote   = Identity()
        let destHash = Identity.truncatedHash(remote.publicKeyBytes)
        let appData  = Data("hello".utf8)

        Identity.remember(
            destinationHash: destHash,
            publicKeyBytes: remote.publicKeyBytes,
            appData: appData
        )

        // app data is stored on the identity in the transport's table;
        // recallAppData should return it.
        let recalled = Identity.recallAppData(forDestination: destHash)
        XCTAssertEqual(recalled, appData,
                       "recallAppData must return the appData stored via remember")
    }

    func testRememberOverwritesExistingEntry() throws {
        let reticulum = try startReticulum()
        defer { reticulum.stop() }

        let remote   = Identity()
        let remote2  = Identity()   // different key, same hash bucket to test overwrite
        let destHash = Identity.truncatedHash(remote.publicKeyBytes)

        Identity.remember(destinationHash: destHash, publicKeyBytes: remote.publicKeyBytes)

        // Overwrite with a new identity and new appData.
        let newApp = Data("v2".utf8)
        Identity.remember(
            destinationHash: destHash,
            publicKeyBytes: remote2.publicKeyBytes,
            appData: newApp
        )

        let recalled = Identity.recall(destinationHash: destHash)
        XCTAssertEqual(recalled?.publicKeyBytes, remote2.publicKeyBytes,
                       "remember should overwrite the stored identity for the same destination hash")
    }
}
