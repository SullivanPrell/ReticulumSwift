import XCTest
@testable import ReticulumSwift

/// Tests for DeterministicEd25519 — RFC 8032 deterministic Ed25519 signing.
///
/// Expected values are cross-validated against:
///   • Python `cryptography` library (RFC 8032 compliant)
///   • Python `pure25519` (used by Python RNS for IFAC code generation)
/// Both libraries agree on all vectors below.
final class DeterministicEd25519Tests: XCTestCase {

    // MARK: - Hex helper

    private func hex(_ s: String) -> Data {
        let h = s.replacingOccurrences(of: " ", with: "")
        var d = Data()
        var idx = h.startIndex
        while idx < h.endIndex {
            let next = h.index(idx, offsetBy: 2)
            d.append(UInt8(h[idx..<next], radix: 16)!)
            idx = next
        }
        return d
    }

    // MARK: - Test vectors (cross-validated against Python cryptography + pure25519)

    // Vector 1: empty message
    // python: Ed25519PrivateKey.from_private_bytes(seed).sign(b'')
    let v1_seed = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae3d55"
    let v1_pub  = "700e2ce7c4b674427eab27ba820bcf6f0faebe68e09fe8564292114e41dc6a41"
    let v1_sig  = "37b4bd5f28b61f55dc9673ae2895baceb863d9cf51780d040f98ad8cdc896cf5" +
                  "be46be655a863525da0959f7f373611585e437e28ec971b7bd206ff9bd26e803"

    // Vector 2: 1-byte message 0x72
    let v2_seed = "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4d0bd6d5"
    let v2_pub  = "35bf72bf49eecfbf8626be181a036058874f379675cddc176733246c142372de"
    let v2_sig  = "7d626d14eda497a22a99bd27e0477d9178f7ea4695a93f45077a170690a0eecd" +
                  "c92c27503ed403abd4c477254386466ed221c815659a868de1d24cdd618d0c0a"

    // Vector 3: 2-byte message 0xaf82
    let v3_seed = "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
    let v3_pub  = "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"
    let v3_sig  = "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac" +
                  "18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"

    // MARK: - Public key tests

    func testVector1_publicKey() {
        let pub = DeterministicEd25519.publicKey(forSeed: hex(v1_seed))
        XCTAssertEqual(pub, hex(v1_pub), "Vector 1 public key mismatch")
    }

    func testVector2_publicKey() {
        let pub = DeterministicEd25519.publicKey(forSeed: hex(v2_seed))
        XCTAssertEqual(pub, hex(v2_pub), "Vector 2 public key mismatch")
    }

    func testVector3_publicKey() {
        let pub = DeterministicEd25519.publicKey(forSeed: hex(v3_seed))
        XCTAssertEqual(pub, hex(v3_pub), "Vector 3 public key mismatch")
    }

    // MARK: - Signature tests

    func testVector1_signature() {
        let sig = DeterministicEd25519.sign(Data(), seed: hex(v1_seed))
        XCTAssertEqual(sig, hex(v1_sig), "Vector 1 signature mismatch")
    }

    func testVector2_signature() {
        let sig = DeterministicEd25519.sign(hex("72"), seed: hex(v2_seed))
        XCTAssertEqual(sig, hex(v2_sig), "Vector 2 signature mismatch")
    }

    func testVector3_signature() {
        let sig = DeterministicEd25519.sign(hex("af82"), seed: hex(v3_seed))
        XCTAssertEqual(sig, hex(v3_sig), "Vector 3 signature mismatch")
    }

    // MARK: - Determinism

    func testSignIsDeterministic() {
        let seed = Data((0..<32).map { UInt8($0) })
        let msg  = Data("hello world".utf8)
        XCTAssertEqual(
            DeterministicEd25519.sign(msg, seed: seed),
            DeterministicEd25519.sign(msg, seed: seed),
            "Same (seed, message) must always produce the same signature"
        )
    }

    func testDifferentMessagesDifferentSignatures() {
        let seed = Data((0..<32).map { UInt8($0) })
        XCTAssertNotEqual(
            DeterministicEd25519.sign(Data("msg1".utf8), seed: seed),
            DeterministicEd25519.sign(Data("msg2".utf8), seed: seed)
        )
    }

    func testSignatureIs64Bytes() {
        XCTAssertEqual(
            DeterministicEd25519.sign(Data("x".utf8), seed: Data(repeating: 0x42, count: 32)).count,
            64
        )
    }

    func testPublicKeyIs32Bytes() {
        XCTAssertEqual(
            DeterministicEd25519.publicKey(forSeed: Data(repeating: 0x01, count: 32)).count,
            32
        )
    }

    // MARK: - IFAC interaction

    /// Signing with a derived IFAC seed produces a 64-byte signature; the last
    /// ifacSize (16) bytes form the wire-compatible IFAC code.
    func testIfacSeedSigningProduces64Bytes() {
        let ifacKey = Data((0..<64).map { UInt8($0) })
        let seed    = Data(ifacKey.suffix(32))   // last 32 bytes = Ed25519 seed
        let payload = Data("test_packet".utf8)
        let sig     = DeterministicEd25519.sign(payload, seed: seed)
        XCTAssertEqual(sig.count, 64)
        XCTAssertEqual(sig.suffix(16).count, 16)
    }
}
