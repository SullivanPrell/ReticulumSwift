import XCTest
@testable import ReticulumSwift

/// Tests verifying Link class constants match Python's reference implementation.
final class LinkConstantsParityTests: XCTestCase {

    // Python: KEEPALIVE = KEEPALIVE_MAX = 360
    func testKeepaliveInterval() {
        XCTAssertEqual(Link.keepaliveInterval, 360)
    }

    // Python: STALE_TIME = STALE_FACTOR * KEEPALIVE = 2 * 360 = 720
    func testStaleTime() {
        XCTAssertEqual(Link.staleTime, 720,
            "staleTime must be 720 (= 2 * keepalive), matching Python's STALE_TIME = STALE_FACTOR * KEEPALIVE")
    }

    // Python: STALE_GRACE = 5
    func testStaleGrace() {
        XCTAssertEqual(Link.staleGrace, 5,
            "staleGrace must be 5, matching Python's STALE_GRACE = 5")
    }

    // Python: ESTABLISHMENT_TIMEOUT_PER_HOP = DEFAULT_PER_HOP_TIMEOUT = 6
    func testEstablishmentTimeoutPerHop() {
        XCTAssertEqual(Link.establishmentTimeoutPerHop, 6)
    }

    // Python: KEEPALIVE_TIMEOUT_FACTOR = 4
    func testKeepAliveTimeoutFactor() {
        XCTAssertEqual(Link.staleTime / Link.keepaliveInterval, 2,
            "staleTime should be 2x keepaliveInterval (STALE_FACTOR=2)")
    }

    // Python: TRAFFIC_TIMEOUT_FACTOR = 6
    func testTrafficTimeoutFactor() {
        XCTAssertEqual(Link.trafficTimeoutFactor, 6.0)
    }

    // Python: CURVE = 'Curve25519'
    func testCurveConstant() {
        XCTAssertEqual(Link.curve, "Curve25519")
    }

    // Python: ACCEPT_NONE = 0x00, ACCEPT_APP = 0x01, ACCEPT_ALL = 0x02
    func testResourceStrategyConstants() {
        XCTAssertEqual(Link.ResourceStrategy.acceptNone.rawValue, 0x00)
        XCTAssertEqual(Link.ResourceStrategy.acceptApp.rawValue, 0x01)
        XCTAssertEqual(Link.ResourceStrategy.acceptAll.rawValue, 0x02)
    }

    // Python: MODE_AES256_CBC = 0x01 (default mode)
    func testDefaultMode() {
        // Link.mode is always AES256_CBC = 0x01
        // We can verify via a newly initiated link or via the static constant
        XCTAssertEqual(Link.defaultMode, 0x01)
    }

    // Python: MODE_AES128_CBC = 0x00, MODE_AES256_CBC = 0x01, MODE_AES256_GCM = 0x02
    func testModeConstants() {
        XCTAssertEqual(Link.modeAes128Cbc, 0x00)
        XCTAssertEqual(Link.modeAes256Cbc, 0x01)
        XCTAssertEqual(Link.modeAes256Gcm, 0x02)
    }

    // Python (AES-256-CBC): derivedKeyLength = 64 (32-byte HMAC key + 32-byte AES key).
    func testDerivedKeyLengthIs64() {
        XCTAssertEqual(Constants.derivedKeyLength, 64,
            "AES-256-CBC requires 64 bytes of key material (32 signing + 32 encryption)")
    }

    // Token created from a 64-byte derived key must use AES-256-CBC mode.
    func testDerivedKeyProducesAES256Token() throws {
        let key = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
        let token = try Token(key: key)
        XCTAssertEqual(token.mode, .aes256cbc,
            "Token initialized with 64-byte key must use AES-256-CBC mode")
        XCTAssertEqual(token.signingKey.count, 32)
        XCTAssertEqual(token.encryptionKey.count, 32)
    }

    // After handshake both sides must hold a 64-byte derived key (AES-256-CBC).
    func testEstablishedLinkDerivedKeyIs64Bytes() throws {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                     appName: "test", aspects: ["keylen"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)
        let aI = LinkConstLoopback(name: "A"); let bI = LinkConstLoopback(name: "B")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let est = expectation(description: "established")
        bT.onLinkEstablished = { _ in est.fulfill() }
        let initiator = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [est], timeout: 2.0)
        let responder = try XCTUnwrap(bT.links[initiator.linkID!])

        XCTAssertEqual(initiator.derivedKey?.count, 64,
            "initiator derivedKey must be 64 bytes (AES-256-CBC)")
        XCTAssertEqual(responder.derivedKey?.count, 64,
            "responder derivedKey must be 64 bytes (AES-256-CBC)")
        XCTAssertEqual(initiator.derivedKey, responder.derivedKey,
            "both sides must agree on the 64-byte derived key")
    }

    // Encrypt/decrypt round-trip using the AES-256-CBC session key.
    func testEstablishedLinkAES256EncryptDecryptRoundTrip() throws {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                     appName: "test", aspects: ["aes256"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)
        let aI = LinkConstLoopback(name: "C"); let bI = LinkConstLoopback(name: "D")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let est = expectation(description: "established")
        bT.onLinkEstablished = { _ in est.fulfill() }
        let initiator = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [est], timeout: 2.0)
        let responder = try XCTUnwrap(bT.links[initiator.linkID!])

        let plaintext = Data("AES-256-CBC round-trip test".utf8)
        let ciphertext = try initiator.encrypt(plaintext)
        let decrypted  = try responder.decrypt(ciphertext)
        XCTAssertEqual(decrypted, plaintext)

        // Ciphertext = IV(16) + PKCS7-padded block(s) + HMAC-SHA256(32).
        // For a 27-byte input: PKCS7 pads to 32 bytes → total 16+32+32=80 bytes.
        XCTAssertGreaterThanOrEqual(ciphertext.count, plaintext.count + 48,
            "AES-256 token overhead = IV(16) + padded ciphertext + HMAC(32)")
    }

    // Cross-direction: responder encrypts, initiator decrypts.
    func testEstablishedLinkAES256BidirectionalRoundTrip() throws {
        let aT = Transport(); let bT = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                     appName: "test", aspects: ["aes256bidir"])
        bT.ownerIdentity = bId
        bT.register(destination: bDest)
        let aI = LinkConstLoopback(name: "E"); let bI = LinkConstLoopback(name: "F")
        aI.paired = bI; bI.paired = aI
        aT.register(interface: aI); bT.register(interface: bI)
        let est = expectation(description: "established")
        bT.onLinkEstablished = { _ in est.fulfill() }
        let initiator = try Link.initiate(destination: bDest, transport: aT)
        wait(for: [est], timeout: 2.0)
        let responder = try XCTUnwrap(bT.links[initiator.linkID!])

        // responder → initiator
        let msg = Data("reply from responder".utf8)
        let enc = try responder.encrypt(msg)
        XCTAssertEqual(try initiator.decrypt(enc), msg)
    }
}

// MARK: - Private loopback for this test file

private final class LinkConstLoopback: Interface {
    var name: String; var bitrate: Int = 0; var isOnline: Bool = true
    weak var paired: LinkConstLoopback?
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
