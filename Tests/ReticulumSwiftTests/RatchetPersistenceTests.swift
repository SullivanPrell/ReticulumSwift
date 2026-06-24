import XCTest
@testable import ReticulumSwift

final class RatchetPersistenceTests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rs-ratchet-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }

    func testRatchetSidecarRoundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let identityURL = dir.appendingPathComponent("identity")
        let ratchetsURL = dir.appendingPathComponent("identity.ratchets")

        let identity = Identity()
        identity.rotateRatchet()
        let oldPub = try XCTUnwrap(identity.activeRatchetPublicKey)
        identity.rotateRatchet()  // pushes oldPub's priv into history
        let newPub = try XCTUnwrap(identity.activeRatchetPublicKey)

        try identity.write(toFile: identityURL)
        try identity.writeRatchets(toFile: ratchetsURL)

        let restored = try Identity.read(fromFile: identityURL)
        try restored.loadRatchets(fromFile: ratchetsURL)

        XCTAssertEqual(restored.activeRatchetPublicKey, newPub)
        XCTAssertEqual(restored.previousRatchetPrivateKeys.count, 1)

        // A token addressed to the historical ratchet must still decrypt
        // after reload.
        let pubOnly = try Identity(publicKeyBytes: identity.publicKeyBytes)
        let token = try pubOnly.encrypt(Data("post-restart".utf8), ratchetPublicKey: oldPub)
        let recovered = try restored.decrypt(token, ratchetPrivateKeys: restored.ratchetPrivateKeyPool)
        XCTAssertEqual(recovered, Data("post-restart".utf8))
    }

    func testReticulumLoadOrCreateIdentityPersistsRatchets() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let stack1 = Reticulum(configuration: .init(storagePath: dir))
        try stack1.start()
        let identity1 = try stack1.loadOrCreateIdentity()
        let pub = identity1.rotateRatchet()
        try stack1.checkpoint()
        stack1.stop()

        let stack2 = Reticulum(configuration: .init(storagePath: dir))
        try stack2.start()
        let identity2 = try stack2.loadOrCreateIdentity()
        XCTAssertEqual(identity2.publicKeyBytes, identity1.publicKeyBytes)
        XCTAssertEqual(identity2.activeRatchetPublicKey, pub)
        stack2.stop()
    }
}
