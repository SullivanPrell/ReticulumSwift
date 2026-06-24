import XCTest
@testable import ReticulumSwift

// MARK: - Mock IFAC-capable interface

private final class IFACInterface: Interface {
    let name: String
    var bitrate: Int = 1_000_000
    var isOnline: Bool = true

    var inboundHandler: ((Packet, any Interface) -> Void)?
    var rawInboundHandler: ((Data, any Interface) -> Void)?
    var ifacIdentity: Identity?
    var ifacKey: Data?
    var ifacSize: Int = Constants.defaultIfacSize

    weak var paired: IFACInterface?
    var sentRaw: [Data] = []

    init(_ name: String) { self.name = name }

    func send(_ packet: Packet) throws {
        let raw = try packet.pack()
        let wrapped = wrapIfac(raw)
        sentRaw.append(wrapped)
        // Deliver to paired interface's rawInboundHandler (or inboundHandler)
        if let h = paired?.rawInboundHandler {
            h(wrapped, paired!)
        } else if let verified = paired?.unwrapIfac(wrapped),
                  let pkt = try? Packet.unpack(verified) {
            paired?.inboundHandler?(pkt, paired!)
        }
    }

    func start() throws {}
    func stop() {}
}

// MARK: - IFACTests

final class IFACTests: XCTestCase {

    // MARK: - Constants

    func testIfacSaltHex() {
        let expected = Data([
            0xad,0xf5,0x4d,0x88,0x2c,0x9a,0x9b,0x80,
            0x77,0x1e,0xb4,0x99,0x5d,0x70,0x2d,0x4a,
            0x3e,0x73,0x33,0x91,0xb2,0xa0,0xf5,0x3f,
            0x41,0x6d,0x9f,0x90,0x7e,0x55,0xcf,0xf8
        ])
        XCTAssertEqual(Constants.ifacSalt, expected)
    }

    // MARK: - wrap / unwrap round-trip

    private func makePacket(destinationHash: Data = Data(repeating: 0xAB, count: Constants.truncatedHashLength)) -> Packet {
        Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: destinationHash,
            data: Data("hello IFAC".utf8)
        )
    }

    func testWrapUnwrapRoundTrip() throws {
        let iface = IFACInterface("a")
        Transport.configureIfac(on: iface, netname: "testnet")

        let pkt = makePacket()
        let raw = try pkt.pack()

        let wrapped = iface.wrapIfac(raw)
        XCTAssertNotEqual(wrapped, raw, "wrapped must differ from original")
        XCTAssertEqual(wrapped.count, raw.count + iface.ifacSize, "IFAC bytes inserted")
        XCTAssertEqual(wrapped[0] & 0x80, 0x80, "IFAC flag must be set")

        let verified = iface.unwrapIfac(wrapped)
        XCTAssertNotNil(verified, "unwrap must succeed")
        XCTAssertEqual(verified!, raw, "round-tripped bytes must equal original")
    }

    func testUnwrapFailsOnTamperedIfac() throws {
        let iface = IFACInterface("a")
        Transport.configureIfac(on: iface, netname: "testnet")

        let raw = try makePacket().pack()
        var wrapped = iface.wrapIfac(raw)
        // Flip a bit inside the IFAC code (bytes 2..ifacSize+1)
        wrapped[2] ^= 0xFF
        XCTAssertNil(iface.unwrapIfac(wrapped), "tampered IFAC must be rejected")
    }

    func testUnwrapDropsPacketMissingIfacFlag() throws {
        let iface = IFACInterface("a")
        Transport.configureIfac(on: iface, netname: "testnet")

        let raw = try makePacket().pack()
        // IFAC flag not set — must be dropped when interface has IFAC enabled
        XCTAssertNil(iface.unwrapIfac(raw))
    }

    func testUnwrapDropsIfacFlagOnNonIfacInterface() throws {
        let iface = IFACInterface("a")  // no IFAC configured

        var raw = try makePacket().pack()
        // Manually set IFAC flag without actually embedding a code
        raw[0] |= 0x80
        XCTAssertNil(iface.unwrapIfac(raw), "spurious IFAC flag must be dropped")
    }

    func testNoIfacInterfacePassesThrough() throws {
        let iface = IFACInterface("a")  // no IFAC

        let raw = try makePacket().pack()
        XCTAssertEqual(iface.wrapIfac(raw), raw, "no IFAC: wrap is identity")
        XCTAssertEqual(iface.unwrapIfac(raw), raw, "no IFAC: unwrap is identity")
    }

    // MARK: - Different netnames produce different IFACs

    func testDifferentNetnamesDifferentWrap() throws {
        let a = IFACInterface("a")
        let b = IFACInterface("b")
        Transport.configureIfac(on: a, netname: "netA")
        Transport.configureIfac(on: b, netname: "netB")

        let raw = try makePacket().pack()
        let wrappedA = a.wrapIfac(raw)
        let wrappedB = b.wrapIfac(raw)
        XCTAssertNotEqual(wrappedA, wrappedB)

        // Cross-verification must fail
        XCTAssertNil(a.unwrapIfac(wrappedB))
        XCTAssertNil(b.unwrapIfac(wrappedA))
    }

    // MARK: - Transport integration

    func testTransportIfacEndToEnd() throws {
        let t1 = Transport()
        let t2 = Transport()

        let a = IFACInterface("a")
        let b = IFACInterface("b")
        a.paired = b
        b.paired = a
        Transport.configureIfac(on: a, netname: "shared")
        Transport.configureIfac(on: b, netname: "shared")

        t1.register(interface: a)
        t2.register(interface: b)

        let dest = try Destination(identity: nil, direction: .in, kind: .plain,
                                   appName: "app", aspects: ["svc"])
        t2.register(destination: dest)

        var received: Data?
        dest.onPacketReceived = { data, _ in received = data }

        let pkt = Packet(
            destinationType: .plain,
            packetType: .data,
            destinationHash: dest.hash,
            data: Data("ifac-e2e".utf8)
        )
        try t1.send(pkt)

        let deadline = Date().addingTimeInterval(0.5)
        while received == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(received, "packet must arrive through IFAC-protected link")
    }

    // MARK: - Size variants

    func testSmallIfacSize() throws {
        let iface = IFACInterface("a")
        Transport.configureIfac(on: iface, netname: "net", size: 4)
        XCTAssertEqual(iface.ifacSize, 4)

        let raw = try makePacket().pack()
        let wrapped = iface.wrapIfac(raw)
        XCTAssertEqual(wrapped.count, raw.count + 4)
        XCTAssertEqual(iface.unwrapIfac(wrapped), raw)
    }

    // MARK: - Network key

    func testNetnameAndNetkeyBothUsed() throws {
        let a = IFACInterface("a")
        let b = IFACInterface("b")
        Transport.configureIfac(on: a, netname: "net", netkey: "key")
        Transport.configureIfac(on: b, netname: "net", netkey: "key")

        let raw = try makePacket().pack()
        let wrapped = a.wrapIfac(raw)
        XCTAssertNotNil(b.unwrapIfac(wrapped), "same netname+netkey must interoperate")

        let c = IFACInterface("c")
        Transport.configureIfac(on: c, netname: "net", netkey: "wrongkey")
        XCTAssertNil(c.unwrapIfac(wrapped), "wrong netkey must be rejected")
    }

    // MARK: - Python cross-compatibility

    /// Verify that Swift's IFAC code matches Python's for a known passphrase.
    ///
    /// Python reference (using passphrase "test_ifac_shared_secret", ifac_size=8):
    ///   ifac_origin = SHA-256("test_ifac_shared_secret")
    ///   ifac_origin_hash = SHA-256(ifac_origin)
    ///   ifac_key = HKDF-SHA256(64, ifac_origin_hash, IFAC_SALT)
    ///   seed = ifac_key[32:]  =  "1708d94bd0eeaf7c57cb9b8562a6f1d9b016a431f3923c137b57260cc8fcbec7"
    ///   sig = DeterministicEd25519.sign(raw, seed)
    ///   ifac_code = sig[-8:]
    ///
    /// Verified against Python cryptography + pure25519 libraries.
    func testIfacCodeMatchesPython() throws {
        let passphrase = "test_ifac_shared_secret"

        let iface = IFACInterface("a")
        Transport.configureIfac(on: iface, netkey: passphrase, size: 8)

        // Use the same test payload as the Python cross-check script
        let testRaw = Data((0..<32).map { UInt8($0) })

        // Expected: Python computed IFAC code for this (seed, payload) pair.
        // seed = "1708d94bd0eeaf7c57cb9b8562a6f1d9b016a431f3923c137b57260cc8fcbec7"
        // sig  = "78d9edc25bb4fdfd...54caff05a3063c0b"
        // ifac (last 8 bytes) = "54caff05a3063c0b"
        let expectedSeed = Data(bytes: [
            0x17,0x08,0xd9,0x4b,0xd0,0xee,0xaf,0x7c,0x57,0xcb,0x9b,0x85,0x62,0xa6,0xf1,0xd9,
            0xb0,0x16,0xa4,0x31,0xf3,0x92,0x3c,0x13,0x7b,0x57,0x26,0x0c,0xc8,0xfc,0xbe,0xc7
        ])
        let expectedIfacCode = Data(bytes: [0x54,0xca,0xff,0x05,0xa3,0x06,0x3c,0x0b])

        // Verify the IFAC key's last 32 bytes match the expected seed
        guard let ifacKey = iface.ifacKey else {
            return XCTFail("IFAC key not set")
        }
        XCTAssertEqual(Data(ifacKey.suffix(32)), expectedSeed,
                       "IFAC key derivation mismatch — signing will be incompatible with Python")

        // Verify the IFAC code matches Python
        let sig = DeterministicEd25519.sign(testRaw, seed: Data(ifacKey.suffix(32)))
        let swiftIfacCode = Data(sig.suffix(8))
        XCTAssertEqual(swiftIfacCode, expectedIfacCode,
                       "IFAC code mismatch — Swift and Python produce different IFAC codes")
    }

    // MARK: - Determinism (same inputs → same IFAC key)

    func testSameNetnameProducesSameIfacKey() throws {
        let a = IFACInterface("a")
        let b = IFACInterface("b")
        Transport.configureIfac(on: a, netname: "deterministic")
        Transport.configureIfac(on: b, netname: "deterministic")

        let raw = try makePacket().pack()
        let wrapped = a.wrapIfac(raw)
        XCTAssertNotNil(b.unwrapIfac(wrapped),
                        "same netname must produce the same IFAC key (deterministic derivation)")
    }
}
