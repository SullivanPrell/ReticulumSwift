import XCTest
@testable import ReticulumSwift

final class RatchetTests: XCTestCase {

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

    func testRotateRatchetGeneratesFreshKeyAndRetainsHistory() {
        let identity = Identity()
        XCTAssertNil(identity.activeRatchetPublicKey)

        let pub1 = identity.rotateRatchet()
        XCTAssertEqual(pub1.count, Constants.ratchetSize)
        XCTAssertEqual(identity.activeRatchetPublicKey, pub1)
        XCTAssertEqual(identity.previousRatchetPrivateKeys.count, 0)

        let pub2 = identity.rotateRatchet()
        XCTAssertNotEqual(pub1, pub2)
        XCTAssertEqual(identity.activeRatchetPublicKey, pub2)
        XCTAssertEqual(identity.previousRatchetPrivateKeys.count, 1)
    }

    func testEncryptToRatchetDecryptsViaHistory() throws {
        let recipient = Identity()
        recipient.rotateRatchet()
        let oldPub = try XCTUnwrap(recipient.activeRatchetPublicKey)

        // Sender encrypts to the *current* ratchet.
        let plaintext = Data("forward secret".utf8)
        let pubOnly = try Identity(publicKeyBytes: recipient.publicKeyBytes)
        let token = try pubOnly.encrypt(plaintext, ratchetPublicKey: oldPub)

        // Recipient rotates *after* the message was sent — old priv now
        // sits in history. Decrypt should still succeed via history.
        recipient.rotateRatchet()

        let recovered = try recipient.decrypt(
            token,
            ratchetPrivateKeys: recipient.ratchetPrivateKeyPool
        )
        XCTAssertEqual(recovered, plaintext)
    }

    func testTransportLearnsRatchetFromAnnounce() throws {
        let transport = Transport()
        let iface = RecordingInterface(name: "in")
        let pair = RecordingInterface(name: "pair")
        iface.paired = pair; pair.paired = iface
        transport.register(interface: iface)

        let originIdentity = Identity()
        let ratchetPub = originIdentity.rotateRatchet()
        let destination = try Destination(
            identity: originIdentity, direction: .in, kind: .single,
            appName: "lxmf"
        )
        let announce = try Announce.make(for: destination, ratchet: ratchetPub)
        try pair.send(announce)

        XCTAssertEqual(transport.knownRatchets[destination.hash], ratchetPub)
    }

    func testTransportEncryptUsesLearnedRatchet() throws {
        let transport = Transport()
        let iface = RecordingInterface(name: "x")
        let pair = RecordingInterface(name: "p")
        iface.paired = pair; pair.paired = iface
        transport.register(interface: iface)

        let recipientIdentity = Identity()
        let ratchetPub = recipientIdentity.rotateRatchet()
        let destination = try Destination(
            identity: recipientIdentity, direction: .in, kind: .single, appName: "x"
        )
        let announce = try Announce.make(for: destination, ratchet: ratchetPub)
        try pair.send(announce)

        let plaintext = Data("hello via ratchet".utf8)
        let token = try transport.encrypt(plaintext, forDestination: destination.hash)

        // Recipient must decrypt using the matching ratchet priv.
        let recovered = try recipientIdentity.decrypt(
            token,
            ratchetPrivateKeys: recipientIdentity.ratchetPrivateKeyPool
        )
        XCTAssertEqual(recovered, plaintext)
    }

    func testRotateRatchetIfNeededRespectsInterval() {
        let identity = Identity()
        identity.ratchetInterval = 60
        identity.rotateRatchet()
        let pub1 = identity.activeRatchetPublicKey

        // Within the interval — must not rotate.
        let pub2 = identity.rotateRatchetIfNeeded()
        XCTAssertEqual(pub1, pub2)
        XCTAssertEqual(identity.previousRatchetPrivateKeys.count, 0)

        // Past the interval — rotates.
        let pub3 = identity.rotateRatchetIfNeeded(
            now: Date().addingTimeInterval(120)
        )
        XCTAssertNotEqual(pub1, pub3)
        XCTAssertEqual(identity.previousRatchetPrivateKeys.count, 1)
    }

    func testRotateRatchetIfNeededOnUninitializedReturnsNil() {
        let identity = Identity()
        XCTAssertNil(identity.rotateRatchetIfNeeded())
    }

    func testSweepExpiredRatchetsViaSidecarReload() throws {
        let identity = Identity()
        identity.rotateRatchet()
        identity.rotateRatchet()
        XCTAssertEqual(identity.previousRatchets.count, 1)

        // Round-trip through the sidecar with a hand-edited stale
        // retiredAt to verify expiry sweeps it out on load.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ratchets-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try identity.writeRatchets(toFile: url)

        var json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as! [String: Any]
        var history = json["history"] as! [[String: Any]]
        let staleDate = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-60 * 60 * 24 * 60)  // 60 days ago
        )
        history[0]["retiredAt"] = staleDate
        json["history"] = history
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let reloaded = Identity()
        try reloaded.loadRatchets(fromFile: url)
        XCTAssertEqual(reloaded.previousRatchets.count, 0)
    }

    func testPathStoreRoundTripsRatchet() throws {
        let t1 = Transport()
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let ratchet = identity.rotateRatchet()
        t1.restore(
            path: Transport.PathEntry(
                destinationHash: destination.hash,
                nextHopInterfaceName: "iface",
                hops: 1,
                lastHeard: Date(),
                identityHash: identity.hash
            ),
            forDestination: destination.hash
        )
        t1.restore(identity: identity, forDestination: destination.hash)
        t1.restore(ratchet: ratchet, forDestination: destination.hash)

        let snapshot = PathStore.snapshot(of: t1)
        let t2 = Transport()
        snapshot.apply(to: t2)

        XCTAssertEqual(t2.knownRatchets[destination.hash], ratchet)
    }
}
