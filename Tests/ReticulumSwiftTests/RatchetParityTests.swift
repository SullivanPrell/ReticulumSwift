import XCTest
@testable import ReticulumSwift

final class RatchetParityTests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rs-parity-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
        return url
    }

    // MARK: - Identity

    func testRatchetIDIsTenBytesAndDeterministic() {
        let pub = Data(repeating: 0xAB, count: 32)
        let id = Identity.ratchetID(forPublicKey: pub)
        XCTAssertEqual(id.count, Constants.nameHashLength)
        XCTAssertEqual(id, Hashes.fullHash(pub).prefix(Constants.nameHashLength))
    }

    func testDecryptResultPopulatesRatchetIDOnRatchetMatch() throws {
        let recipient = Identity()
        let pub = recipient.rotateRatchet()
        let pubOnly = try Identity(publicKeyBytes: recipient.publicKeyBytes)
        let token = try pubOnly.encrypt(Data("hi".utf8), ratchetPublicKey: pub)

        let result = try recipient.decrypt(
            token,
            ratchetPrivateKeys: recipient.ratchetPrivateKeyPool,
            enforceRatchets: false
        )
        XCTAssertEqual(result.plaintext, Data("hi".utf8))
        XCTAssertEqual(result.ratchetID, Identity.ratchetID(forPublicKey: pub))
    }

    func testDecryptResultRatchetIDNilForStaticKeyDecrypt() throws {
        let recipient = Identity()
        let pubOnly = try Identity(publicKeyBytes: recipient.publicKeyBytes)
        let token = try pubOnly.encrypt(Data("static".utf8))
        let result = try recipient.decrypt(
            token, ratchetPrivateKeys: [], enforceRatchets: false
        )
        XCTAssertNil(result.ratchetID)
    }

    func testEnforceRatchetsRejectsStaticKey() throws {
        let recipient = Identity()
        recipient.rotateRatchet()
        let pubOnly = try Identity(publicKeyBytes: recipient.publicKeyBytes)
        // Encrypt to the static key — no ratchet pub passed.
        let token = try pubOnly.encrypt(Data("nope".utf8))

        XCTAssertThrowsError(try recipient.decrypt(
            token,
            ratchetPrivateKeys: recipient.ratchetPrivateKeyPool,
            enforceRatchets: true
        ))
    }

    // MARK: - Destination

    func testEnableRatchetsLoadsExistingSidecar() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sidecar = dir.appendingPathComponent("dest.ratchets")

        let identity = Identity()
        let pub = identity.rotateRatchet()
        try identity.writeRatchets(toFile: sidecar)

        let restored = Identity()  // fresh, no ratchets
        let dest = try Destination(
            identity: restored, direction: .in, kind: .single, appName: "x"
        )
        try dest.enableRatchets(path: sidecar)

        XCTAssertTrue(dest.ratchetsEnabled)
        XCTAssertEqual(restored.activeRatchetPublicKey, pub)
    }

    func testAnnounceAutoRotatesAndPersistsWhenRatchetsEnabled() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sidecar = dir.appendingPathComponent("dest.ratchets")

        let identity = Identity()
        let dest = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        try dest.enableRatchets(path: sidecar)

        XCTAssertNil(identity.activeRatchetPrivateKey)
        let announce = try Announce.make(for: dest)
        let decoded = try Announce.validate(announce)
        XCTAssertNotNil(decoded.ratchet)
        XCTAssertEqual(decoded.ratchet, identity.activeRatchetPublicKey)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
    }

    func testEnforceRatchetsOnDestinationRefusesStaticDecrypt() throws {
        let identity = Identity()
        identity.rotateRatchet()
        let dest = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try dest.enableRatchets(path: dir.appendingPathComponent("d.ratchets"))
        XCTAssertTrue(dest.enforceRatchets())

        let pubOnly = try Identity(publicKeyBytes: identity.publicKeyBytes)
        let token = try pubOnly.encrypt(Data("nope".utf8))  // static-key
        XCTAssertThrowsError(try dest.decrypt(token))
    }

    func testDestinationLatestRatchetIDPopulatedOnRatchetDecrypt() throws {
        let identity = Identity()
        let pub = identity.rotateRatchet()
        let dest = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try dest.enableRatchets(path: dir.appendingPathComponent("d.ratchets"))

        let pubOnly = try Identity(publicKeyBytes: identity.publicKeyBytes)
        let token = try pubOnly.encrypt(Data("yo".utf8), ratchetPublicKey: pub)
        let plaintext = try dest.decrypt(token)
        XCTAssertEqual(plaintext, Data("yo".utf8))
        XCTAssertEqual(dest.latestRatchetID, Identity.ratchetID(forPublicKey: pub))
    }

    // MARK: - Transport

    final class RecordingInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        weak var paired: RecordingInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    func testTransportPersistsLearnedRatchetToDirectory() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let transport = Transport()
        transport.ratchetsDirectory = dir
        let iface = RecordingInterface(name: "in")
        let pair = RecordingInterface(name: "pair")
        iface.paired = pair; pair.paired = iface
        transport.register(interface: iface)

        let originIdentity = Identity()
        let ratchet = originIdentity.rotateRatchet()
        let destination = try Destination(
            identity: originIdentity, direction: .in, kind: .single, appName: "x"
        )
        let announce = try Announce.make(for: destination, ratchet: ratchet)
        try pair.send(announce)

        let url = dir.appendingPathComponent(destination.hash.hexString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // A fresh Transport pointed at the same directory must rehydrate.
        let restored = Transport()
        restored.ratchetsDirectory = dir
        restored.loadKnownRatchets()
        XCTAssertEqual(restored.knownRatchets[destination.hash], ratchet)
        XCTAssertNotNil(restored.knownRatchetTimes[destination.hash])
    }

    func testSweepKnownRatchetsDropsExpired() throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let transport = Transport()
        transport.ratchetsDirectory = dir
        transport.ratchetExpiry = 60

        let destHash = Data(repeating: 0x42, count: Constants.truncatedHashLength)
        let stale = Date().addingTimeInterval(-3600)
        transport.restore(ratchet: Data(repeating: 0x11, count: 32),
                          forDestination: destHash,
                          receivedAt: stale)
        XCTAssertNotNil(transport.knownRatchets[destHash])
        transport.sweepKnownRatchets()
        XCTAssertNil(transport.knownRatchets[destHash])
        XCTAssertNil(transport.knownRatchetTimes[destHash])
    }
}
