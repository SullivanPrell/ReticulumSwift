import XCTest
@testable import ReticulumSwift

/// Tests for the four text encodings `rnid` accepts and emits.
///
/// Python reference: RNS/Utilities/rnid.py — `create_rsg` (:508-514), `get_rsg_data`
/// (:397-411), the `-m`/`-M` import ladder (:282-358).
final class RNIDEncodingTests: XCTestCase {

    // MARK: - Base32 (RFC 4648)

    /// The RFC 4648 §10 test vectors, which are exactly what `base64.b32encode` produces.
    func testBase32RFC4648Vectors() {
        let vectors: [(String, String)] = [
            ("", ""),
            ("f", "MY======"),
            ("fo", "MZXQ===="),
            ("foo", "MZXW6==="),
            ("foob", "MZXW6YQ="),
            ("fooba", "MZXW6YTB"),
            ("foobar", "MZXW6YTBOI======")
        ]
        for (plain, encoded) in vectors {
            // Python: base64.b32encode(plain.encode()).decode()
            XCTAssertEqual(Base32.encode(Data(plain.utf8)), encoded, "encoding \"\(plain)\"")
            XCTAssertEqual(Base32.decode(encoded), Data(plain.utf8), "decoding \"\(encoded)\"")
        }
    }

    func testBase32RejectsLowercase() {
        // Python: base64.b32decode defaults to casefold=False, so lowercase is an error.
        XCTAssertNil(Base32.decode("mzxw6ytb"))
    }

    func testBase32RejectsCharactersOutsideTheAlphabet() {
        XCTAssertNil(Base32.decode("MZXW6YT1"))   // '1' is not in A-Z2-7
        XCTAssertNil(Base32.decode("MZ=XW6YT"))   // padding in the middle
    }

    func testBase32RoundTripsAllByteValues() {
        let data = Data((0...255).map { UInt8($0) })
        XCTAssertEqual(Base32.decode(Base32.encode(data)), data)
    }

    func testBase32OfA64ByteBlobIs104Characters() {
        // The import ladder relies on hex(64)=128, base32(64)=104 and base64(64)=88 not
        // colliding.
        XCTAssertEqual(Base32.encode(Data(repeating: 0x41, count: 64)).count, 104)
    }

    // MARK: - Base64 (URL-safe)

    func testBase64URLUsesTheURLSafeAlphabet() {
        // Verified against Python: base64.urlsafe_b64encode(bytes([251,255,190])) == b"-_--"
        XCTAssertEqual(RNIDEncoding.base64URLEncode(Data([251, 255, 190])), "-_--")
    }

    func testBase64URLRetainsPadding() {
        // Python: base64.urlsafe_b64encode(b"f") == b"Zg=="
        XCTAssertEqual(RNIDEncoding.base64URLEncode(Data("f".utf8)), "Zg==")
    }

    func testBase64URLRoundTrips() {
        let data = Data((0...255).map { UInt8($0) })
        XCTAssertEqual(RNIDEncoding.base64URLDecode(RNIDEncoding.base64URLEncode(data)), data)
    }

    func testBase64URLIsStricterThanPython() {
        // Python's urlsafe_b64decode("!!!!") returns b"" without raising; that leniency is
        // exactly what breaks Python's own get_rsg_data ladder, so this decoder returns nil.
        XCTAssertNil(RNIDEncoding.base64URLDecode("!!!!"))
    }

    func testBase64OfA64ByteBlobIs88Characters() {
        XCTAssertEqual(RNIDEncoding.base64URLEncode(Data(repeating: 0x41, count: 64)).count, 88)
    }

    // MARK: - Hex

    func testHexEncodeIsUndelimitedLowercase() {
        // Python: RNS.hexrep(data, delimit=False)
        XCTAssertEqual(RNIDEncoding.hexEncode(Data([0xDE, 0xAD, 0xBE, 0xEF])), "deadbeef")
    }

    func testHexDecodeAcceptsEitherCaseAndRejectsGarbage() {
        // Python: bytes.fromhex accepts "DEADBEEF" as well as "deadbeef".
        XCTAssertEqual(RNIDEncoding.hexDecode("DEADBEEF"), Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertNil(RNIDEncoding.hexDecode("deadbee"))    // odd length
        XCTAssertNil(RNIDEncoding.hexDecode("zzzz"))
    }

    // MARK: - Base256

    func testBase256RoundTripsAllByteValues() {
        let data = Data((0...255).map { UInt8($0) })
        XCTAssertEqual(RNIDEncoding.base256Decode(RNIDEncoding.base256Encode(data)), data)
    }

    func testBase256AlphabetHasItsDeliberateGaps() {
        // The alphabet is byte-identical to RNS/__init__.py:515-521, including the absent
        // "V" and "w". A hand-typed table would silently break wire compatibility.
        XCTAssertEqual(RNSUtilities.b256Alphabet.count, 256)
        XCTAssertEqual(RNSUtilities.b256Alphabet[0x15], "v")
        XCTAssertFalse(RNSUtilities.b256Alphabet.contains("V"))
        XCTAssertFalse(RNSUtilities.b256Alphabet.contains("w"))
    }

    // MARK: - The decode ladder

    /// Pins the CORRECTED first-plausible-success ordering.
    ///
    /// Python's `get_rsg_data` is broken twice over: `str.strip(b"=")` raises `TypeError`
    /// (so base32 and hex can never succeed for str input), and the four attempts are
    /// last-success-wins with `urlsafe_b64decode` never raising — so base256, whose alphabet
    /// contains every hex character, would win for hex input and decode it to garbage.
    func testDecodeLadderPrefersHexOverBase256ForAHexArmouredRSG() throws {
        let identity = Identity()
        guard case .binary(let raw) = try RSG.create(signer: identity, message: .bytes(Data("hello".utf8))) else {
            return XCTFail("expected binary output")
        }
        let hexArmoured = RNIDEncoding.hexEncode(raw)
        XCTAssertEqual(RSG.data(fromText: hexArmoured), raw)
    }

    func testDecodeLadderHandlesEveryEncodedFormat() throws {
        let identity = Identity()
        guard case .binary(let raw) = try RSG.create(signer: identity, message: .bytes(Data("hello".utf8))) else {
            return XCTFail("expected binary output")
        }
        // Encode the SAME bytes four ways: Ed25519 signing in CryptoKit is randomised, so
        // re-signing per format would produce four different blobs.
        let encodings: [(String, String)] = [
            ("hex", RNIDEncoding.hexEncode(raw)),
            ("base32", RNIDEncoding.base32Encode(raw)),
            ("base64", RNIDEncoding.base64URLEncode(raw)),
            ("base256", RNIDEncoding.base256Encode(raw))
        ]
        for (name, text) in encodings {
            XCTAssertEqual(RSG.data(fromText: text), raw, "round trip through \(name)")
        }
    }

    func testDecodeLadderRejectsGarbage() {
        // Python would hand back the empty bytes urlsafe_b64decode produces; we return nil.
        XCTAssertNil(RSG.data(fromText: "!!!!"))
        XCTAssertNil(RSG.data(fromText: ""))
    }

    func testDecodeLadderAcceptsALegacy64ByteSignature() {
        // Python's two consumable shapes are len == 64 and len >= 65.
        let signature = Data((0..<64).map { UInt8($0) })
        XCTAssertEqual(RSG.data(fromText: RNIDEncoding.hexEncode(signature)), signature)
    }

    func testDecodeLadderRejectsShortCandidates() {
        // 63 bytes is neither the legacy length nor long enough for a signature + envelope.
        XCTAssertNil(RSG.data(fromText: RNIDEncoding.hexEncode(Data(count: 63))))
    }

    /// Length alone is not a strong enough gate: a hex string is also a valid base64 string,
    /// so an earlier codec in the ladder can otherwise claim a blob belonging to a later one.
    func testDecodeLadderRequiresADecodableEnvelope() {
        let notAnRSG = Data(repeating: 0x7B, count: 200)
        XCTAssertNil(RSG.data(fromText: RNIDEncoding.base64URLEncode(notAnRSG)))
    }
}
