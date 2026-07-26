import XCTest
@testable import ReticulumSwift

/// Tests for the RSG container — the byte format `rnid -s` / `-S` produce and `-V` consumes.
///
/// Python reference: RNS/Utilities/rnid.py — `create_rsg` (:488-516), `validate_rsg`
/// (:436-486), `rsg_is_legacy_format` (:431-434), `extract_signed_rsg_data` (:413-419),
/// `get_rsg_hash` (:421-429), `wrap_rsg`/`unwrap_rsg` (:518-564).
final class RSGTests: XCTestCase {

    // MARK: - Golden envelope bytes

    /// The minimal envelope is exactly 160 bytes, generated live from RNS's vendored
    /// umsgpack during the porting audit.
    func testMinimalEnvelopeGoldenBytes() {
        let signedData = RSG.SignedData(
            hashType: "sha256",
            hash: Data(repeating: 0x01, count: 32),
            meta: [("signer", .bytes(Data(repeating: 0x02, count: 16))),
                   ("pubkey", .bytes(Data(repeating: 0x03, count: 64)))],
            message: nil)

        let expected = "83a86861736874797065a6736861323536a468617368c420"
            + String(repeating: "01", count: 32)
            + "a46d65746182a67369676e6572c410"
            + String(repeating: "02", count: 16)
            + "a67075626b6579c440"
            + String(repeating: "03", count: 64)

        let envelope = signedData.envelope()
        XCTAssertEqual(envelope.count, 160)
        XCTAssertEqual(RNIDEncoding.hexEncode(envelope), expected)
        // The first 20 bytes are the fixed prefix every modern RSG shares.
        XCTAssertEqual(RNIDEncoding.hexEncode(envelope.prefix(20)),
                       "83a86861736874797065a6736861323536a46861")
    }

    /// Python: `signed_data["message"] = message` is assigned after "meta" already exists, so
    /// it always lands LAST at top level and the fixmap header becomes 0x84.
    func testEmbeddedMessageIsLastAndBumpsTheMapHeader() {
        let signedData = RSG.SignedData(
            hashType: "sha256",
            hash: Data(repeating: 0x01, count: 32),
            meta: [("signer", .bytes(Data(repeating: 0x02, count: 16))),
                   ("pubkey", .bytes(Data(repeating: 0x03, count: 64)))],
            message: Data("hello".utf8))

        let envelope = signedData.envelope()
        XCTAssertEqual(envelope.count, 175)
        XCTAssertEqual(envelope[envelope.startIndex], 0x84)
        XCTAssertTrue(RNIDEncoding.hexEncode(envelope).hasSuffix("616765c40568656c6c6f"))
        XCTAssertEqual(signedData.entries.last?.0, "message")
    }

    func testInnerMetaHeaderIsFixmap2WithNoExtras() {
        let signedData = RSG.SignedData(
            hashType: "sha256", hash: Data(repeating: 0x01, count: 32),
            meta: [("signer", .bytes(Data(count: 16))), ("pubkey", .bytes(Data(count: 64)))],
            message: nil)
        // "a46d657461" is the "meta" key; the next byte is the inner map header.
        let hex = RNIDEncoding.hexEncode(signedData.envelope())
        guard let range = hex.range(of: "a46d657461") else { return XCTFail("no meta key") }
        XCTAssertEqual(String(hex[range.upperBound...].prefix(2)), "82")
    }

    // MARK: - MsgPack boundary parity

    /// Guards the golden-byte tests: they are only meaningful while ReticulumSwift's encoder
    /// stays byte-identical to RNS's vendored umsgpack at every boundary an envelope can hit.
    func testMsgPackMatchesUmsgpackAtEveryEnvelopeBoundary() {
        func hex(_ value: MsgPack.Value) -> String { RNIDEncoding.hexEncode(MsgPack.encode(value)) }

        XCTAssertEqual(hex(.string("")), "a0")
        XCTAssertEqual(hex(.string(String(repeating: "a", count: 31))).prefix(2), "bf")
        XCTAssertEqual(hex(.string(String(repeating: "a", count: 32))).prefix(4), "d920")
        XCTAssertEqual(hex(.string(String(repeating: "a", count: 255))).prefix(4), "d9ff")
        XCTAssertEqual(hex(.string(String(repeating: "a", count: 256))).prefix(6), "da0100")

        XCTAssertEqual(hex(.bytes(Data())), "c400")
        XCTAssertEqual(hex(.bytes(Data(count: 255))).prefix(4), "c4ff")
        XCTAssertEqual(hex(.bytes(Data(count: 256))).prefix(6), "c50100")
        XCTAssertEqual(hex(.bytes(Data(count: 65535))).prefix(6), "c5ffff")
        XCTAssertEqual(hex(.bytes(Data(count: 65536))).prefix(10), "c600010000")

        let sixteenPairs = (0..<16).map { (MsgPack.Value.uint(UInt64($0)), MsgPack.Value.nil) }
        XCTAssertEqual(hex(.map(sixteenPairs)).prefix(6), "de0010")
        XCTAssertEqual(hex(.array((0..<16).map { MsgPack.Value.uint(UInt64($0)) })).prefix(6), "dc0010")

        XCTAssertEqual(hex(.int(-32)), "e0")
        XCTAssertEqual(hex(.int(-33)), "d0df")
        XCTAssertEqual(hex(.double(1.5)), "cb3ff8000000000000")
        XCTAssertEqual(hex(.bool(true)), "c3")
        XCTAssertEqual(hex(.nil), "c0")
        XCTAssertEqual(hex(.uint(255)), "ccff")
        XCTAssertEqual(hex(.uint(4242)), "cd1092")
    }

    // MARK: - create_rsg

    func testCreateProducesA224ByteMinimalRSG() throws {
        let identity = Identity()
        guard case .binary(let rsg) = try RSG.create(signer: identity, message: .bytes(Data("hello".utf8)))
        else { return XCTFail("expected binary output") }

        // Python: 64-byte signature + 160-byte minimal envelope.
        XCTAssertEqual(rsg.count, 224)
        let signature = rsg.prefix(RSG.signatureLength)
        let envelope = rsg.subdata(in: RSG.signatureLength..<rsg.count)
        XCTAssertEqual(envelope.count, 160)
        // Python: `signature = signer_identity.sign(envelope)`.
        XCTAssertTrue(identity.validate(signature: Data(signature), for: envelope))
    }

    func testCreateThrowsForAPublicOnlyIdentity() throws {
        let publicOnly = try Identity(publicKeyBytes: Identity().getPublicKey())
        XCTAssertThrowsError(try RSG.create(signer: publicOnly, message: .bytes(Data("x".utf8)))) { error in
            // Python: ValueError(f"{signer_identity} does not hold a private key")
            XCTAssertEqual(error as? RSG.RSGError, .missingPrivateKey)
        }
    }

    func testCreateRejectsAnUnknownOutputFormatName() {
        let identity = Identity()
        // Python: TypeError("Invalid output format for rsg creation")
        XCTAssertThrowsError(try RSG.create(signer: identity, message: .bytes(Data("x".utf8)),
                                            outputName: "rot13")) { error in
            XCTAssertEqual(error as? RSG.RSGError, .invalidOutputFormat)
        }
    }

    func testCreateSilentlyIgnoresEmptyMeta() throws {
        let identity = Identity()
        // Python: `if meta and type(meta) == dict:` — an empty mapping never merges.
        guard case .binary(let rsg) = try RSG.create(signer: identity, message: .bytes(Data("x".utf8)),
                                                     embed: false, meta: [], output: .bin)
        else { return XCTFail("expected binary output") }
        XCTAssertEqual(rsg.count, 224)
    }

    /// Extras can never override the two canonical meta keys, and land after them in order.
    func testMetaMergeKeepsSignerAndPubkeyAndAppendsExtras() throws {
        let identity = Identity()
        let meta: [(String, MsgPack.Value)] = [
            ("signer", .bytes(Data(repeating: 0xFF, count: 16))),
            ("pubkey", .bytes(Data(repeating: 0xFF, count: 64))),
            ("custom", .string("value"))
        ]
        guard case .binary(let rsg) = try RSG.create(signer: identity, message: .bytes(Data("x".utf8)),
                                                     embed: true, meta: meta, output: .bin)
        else { return XCTFail("expected binary output") }

        let envelope = rsg.subdata(in: RSG.signatureLength..<rsg.count)
        let decoded = try RSG.SignedData.decode(envelope: envelope)
        // Assert on order, not on a dictionary, so ordering is actually pinned.
        XCTAssertEqual(decoded.meta.map { $0.0 }, ["signer", "pubkey", "custom"])
        XCTAssertEqual(decoded.signer, identity.hash)
        XCTAssertEqual(decoded.pubkey, identity.getPublicKey())
    }

    // MARK: - Legacy detection

    func testIsLegacyFormatOnlyForExactly64Bytes() {
        XCTAssertTrue(RSG.isLegacyFormat(Data(count: 64)))
        XCTAssertFalse(RSG.isLegacyFormat(Data(count: 63)))
        XCTAssertFalse(RSG.isLegacyFormat(Data(count: 65)))
        XCTAssertFalse(RSG.isLegacyFormat(Data(count: 224)))
        // Python: `if not rsg_data: return False`
        XCTAssertFalse(RSG.isLegacyFormat(Data()))
    }

    func testValidateThrowsLegacyFormatForA64ByteInput() {
        XCTAssertThrowsError(try RSG.validate(rsgData: Data(count: 64),
                                              message: .bytes(Data("x".utf8)),
                                              requiredSigner: .none)) { error in
            // Python: ValueError("Cannot validate legacy rsg format")
            XCTAssertEqual(error as? RSG.RSGError, .legacyFormat)
        }
    }

    func testValidateLegacySignature() throws {
        let identity = Identity()
        let payload = Data("the quick brown fox".utf8)
        let signature = try identity.sign(payload)
        XCTAssertTrue(RSG.validateLegacy(signature: signature, fileData: payload, identity: identity))

        var tampered = signature
        tampered[tampered.startIndex] ^= 0x01
        XCTAssertFalse(RSG.validateLegacy(signature: tampered, fileData: payload, identity: identity))
    }

    // MARK: - validate_rsg gate matrix

    /// Builds an RSG whose envelope is whatever `mutate` produces, signed correctly.
    private func makeRSG(signer: Identity,
                         message: Data,
                         mutate: (inout [(String, MsgPack.Value)]) -> Void = { _ in }) throws -> Data {
        var entries: [(String, MsgPack.Value)] = [
            ("hashtype", .string("sha256")),
            ("hash", .bytes(Hashes.fullHash(message))),
            ("meta", .map([(.string("signer"), .bytes(signer.hash)),
                           (.string("pubkey"), .bytes(signer.getPublicKey()))]))
        ]
        mutate(&entries)
        let envelope = RSG.SignedData(entries: entries).envelope()
        return try signer.sign(envelope) + envelope
    }

    func testValidateAcceptsAWellFormedRSG() throws {
        let identity = Identity()
        let message = Data("payload".utf8)
        let rsg = try makeRSG(signer: identity, message: message)
        let result = try RSG.validate(rsgData: rsg, message: .bytes(message), requiredSigner: .none)
        XCTAssertTrue(result.isValid)
        XCTAssertNotNil(result.signedData)
        XCTAssertEqual(result.signingIdentity?.hash, identity.hash)
    }

    func testValidateRejectsAnUndecodableEnvelope() throws {
        let identity = Identity()
        let rsg = try identity.sign(Data("x".utf8)) + Data([0xC1, 0xC1, 0xC1])
        let result = try RSG.validate(rsgData: rsg, message: .bytes(Data("x".utf8)), requiredSigner: .none)
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.signedData)
        XCTAssertNil(result.signingIdentity)
    }

    func testValidateGateMatrix() throws {
        let identity = Identity()
        let message = Data("payload".utf8)

        // Each mutation trips exactly one of validate_rsg's early returns.
        let mutations: [(String, (inout [(String, MsgPack.Value)]) -> Void)] = [
            ("missing hashtype", { $0.removeAll { $0.0 == "hashtype" } }),
            ("missing hash", { $0.removeAll { $0.0 == "hash" } }),
            ("wrong hashtype", { entries in
                entries = entries.map { $0.0 == "hashtype" ? ($0.0, .string("sha512")) : $0 } }),
            ("missing meta", { $0.removeAll { $0.0 == "meta" } }),
            ("meta missing signer", { entries in
                entries = entries.map { entry in
                    guard entry.0 == "meta", case .map(let pairs) = entry.1 else { return entry }
                    return (entry.0, .map(pairs.filter { $0.0 != .string("signer") }))
                } }),
            ("meta missing pubkey", { entries in
                entries = entries.map { entry in
                    guard entry.0 == "meta", case .map(let pairs) = entry.1 else { return entry }
                    return (entry.0, .map(pairs.filter { $0.0 != .string("pubkey") }))
                } }),
            ("wrong-length pubkey", { entries in
                entries = entries.map { entry in
                    guard entry.0 == "meta", case .map(let pairs) = entry.1 else { return entry }
                    return (entry.0, .map(pairs.map { pair in
                        pair.0 == .string("pubkey") ? (pair.0, .bytes(Data(count: 8))) : pair
                    }))
                } })
        ]

        for (label, mutate) in mutations {
            let rsg = try makeRSG(signer: identity, message: message, mutate: mutate)
            let result = try RSG.validate(rsgData: rsg, message: .bytes(message), requiredSigner: .none)
            XCTAssertFalse(result.isValid, label)
            XCTAssertNil(result.signedData, label)
            XCTAssertNil(result.signingIdentity, label)
        }
    }

    /// A signer-hash mismatch returns `signedData == nil` but a NON-nil signing identity.
    func testValidateSignerMismatchReturnsSigningIdentityButNoSignedData() throws {
        let identity = Identity()
        let other = Identity()
        let message = Data("payload".utf8)
        let rsg = try makeRSG(signer: identity, message: message)

        let result = try RSG.validate(rsgData: rsg, message: .bytes(message),
                                      requiredSigner: .hash(other.hash))
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.signedData)
        XCTAssertEqual(result.signingIdentity?.hash, identity.hash)
    }

    /// A hash mismatch behaves the same way.
    func testValidateHashMismatchReturnsSigningIdentityButNoSignedData() throws {
        let identity = Identity()
        let message = Data("payload".utf8)
        let rsg = try makeRSG(signer: identity, message: message)

        let result = try RSG.validate(rsgData: rsg, message: .bytes(Data("different".utf8)),
                                      requiredSigner: .none)
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.signedData)
        XCTAssertEqual(result.signingIdentity?.hash, identity.hash)
    }

    /// A tampered signature is the one failure that still returns signedData.
    func testValidateTamperedSignatureStillReturnsSignedData() throws {
        let identity = Identity()
        let message = Data("payload".utf8)
        var rsg = try makeRSG(signer: identity, message: message)
        rsg[rsg.startIndex] ^= 0x01

        let result = try RSG.validate(rsgData: rsg, message: .bytes(message), requiredSigner: .none)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.signedData)
        XCTAssertNotNil(result.signingIdentity)
    }

    func testValidateThrowsForAnEmptyMessage() throws {
        let identity = Identity()
        let rsg = try makeRSG(signer: identity, message: Data())
        // Python: `if not message: raise ValueError("No message specified for rsg validation")`.
        // The operation layer maps this to R_UNKNOWN_ERROR (254), not R_INVALID_SIGNATURE.
        XCTAssertThrowsError(try RSG.validate(rsgData: rsg, message: .bytes(Data()),
                                              requiredSigner: .none)) { error in
            XCTAssertEqual(error as? RSG.RSGError, .noMessage)
        }
    }

    func testValidateRejectsA63ByteInput() throws {
        let result = try RSG.validate(rsgData: Data(count: 63), message: .bytes(Data("x".utf8)),
                                      requiredSigner: .none)
        XCTAssertFalse(result.isValid)
        XCTAssertNil(result.signedData)
    }

    /// With an explicit Identity the embedded pubkey is ignored entirely.
    func testRequiredSignerIdentityIgnoresTheEmbeddedPubkey() throws {
        let signer = Identity()
        let decoy = Identity()
        let message = Data("payload".utf8)

        let rsg = try makeRSG(signer: signer, message: message) { entries in
            entries = entries.map { entry in
                guard entry.0 == "meta", case .map(let pairs) = entry.1 else { return entry }
                return (entry.0, .map(pairs.map { pair in
                    pair.0 == .string("pubkey") ? (pair.0, .bytes(decoy.getPublicKey())) : pair
                }))
            }
        }

        // Explicit Identity → passes, because the decoy pubkey is never consulted.
        let withSigner = try RSG.validate(rsgData: rsg, message: .bytes(message),
                                          requiredSigner: .identity(signer))
        XCTAssertTrue(withSigner.isValid)

        // No required signer → the decoy pubkey is loaded and the signature fails.
        let withoutSigner = try RSG.validate(rsgData: rsg, message: .bytes(message),
                                             requiredSigner: .none)
        XCTAssertFalse(withoutSigner.isValid)
    }

    // MARK: - extract_signed_rsg_data

    func testExtractSignedDataReadsTheEmbeddedMessage() throws {
        let identity = Identity()
        guard case .binary(let rsg) = try RSG.create(signer: identity,
                                                     message: .text("hi"), embed: true,
                                                     meta: nil, output: .bin)
        else { return XCTFail("expected binary output") }
        let extracted = try RSG.extractSignedData(rsg)
        XCTAssertEqual(extracted?.message, Data("hi".utf8))
    }

    func testExtractSignedDataThrowsForNilInput() {
        // Python: `rsg_data[siglen:]` sits OUTSIDE the try, so None propagates a TypeError.
        XCTAssertThrowsError(try RSG.extractSignedData(nil)) { error in
            XCTAssertEqual(error as? RSG.RSGError, .undecodableInput)
        }
    }

    func testExtractSignedDataReturnsNilForATruncatedInput() throws {
        // Python: a <64-byte rsg yields an EMPTY envelope, and mp.unpackb(b"") raises → None.
        XCTAssertNil(try RSG.extractSignedData(Data(count: 10)))
    }

    // MARK: - get_rsg_hash

    func testMessageHashMatchesForEveryInputShape() throws {
        let payload = Data("the quick brown fox".utf8)
        XCTAssertEqual(try RSG.hash(of: .bytes(payload)), Hashes.fullHash(payload))
        XCTAssertEqual(try RSG.hash(of: .text("the quick brown fox")), Hashes.fullHash(payload))
    }

    /// Proves the chunked hasher matches Python's `hashlib.file_digest` for a large payload
    /// delivered in odd-sized chunks.
    func testStreamingHashMatchesOneShotForALargePayload() throws {
        var payload = Data(capacity: 3 * 1024 * 1024)
        for index in 0..<(3 * 1024 * 1024) { payload.append(UInt8(index % 251)) }

        final class OddChunkReader: RNIDByteReader {
            private let data: Data
            private var offset = 0
            init(_ data: Data) { self.data = data }
            func read(upTo count: Int) throws -> Data {
                guard offset < data.count else { return Data() }
                // Deliberately short reads, in a pattern that never divides the payload evenly.
                let take = min(min(count, 7919), data.count - offset)
                defer { offset += take }
                return data.subdata(in: offset..<(offset + take))
            }
        }

        XCTAssertEqual(try RSG.hash(of: .file(OddChunkReader(payload))), Hashes.fullHash(payload))
    }

    // MARK: - Armour

    func testArmourHeaderAndFooterAreExactly64Characters() {
        XCTAssertEqual(RSGArmour.header,
                       "#### Start of rsg data #########################################")
        XCTAssertEqual(RSGArmour.footer,
                       "########################################### End of rsg data ####")
        XCTAssertEqual(RSGArmour.header.count, 64)
        XCTAssertEqual(RSGArmour.footer.count, 64)
        XCTAssertEqual(String(RSGArmour.header.suffix(41)), String(repeating: "#", count: 41))
        XCTAssertEqual(String(RSGArmour.footer.prefix(43)), String(repeating: "#", count: 43))
    }

    func testArmourPadsTheFinalShortRow() {
        let payload = String(repeating: "a", count: 100)
        let lines = RSGArmour.wrap(payload).split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(String(lines[0]), RSGArmour.header)
        XCTAssertEqual(lines[1].count, 64)
        XCTAssertEqual(String(lines[2]), String(repeating: "a", count: 36) + String(repeating: "=", count: 28))
        XCTAssertEqual(String(lines[3]), RSGArmour.footer)
        // Python appends the footer with no trailing newline.
        XCTAssertFalse(RSGArmour.wrap(payload).hasSuffix("\n"))
    }

    func testArmourOfAnEmptyPayloadIsHeaderAndFooterOnly() {
        // Python: the `while len(rsg)` loop never runs.
        XCTAssertEqual(RSGArmour.wrap(""), RSGArmour.header + "\n" + RSGArmour.footer)
    }

    func testUnwrapRoundTripsWrap() {
        for length in [1, 63, 64, 65, 128] {
            let payload = String(repeating: "x", count: length)
            let unwrapped = RSGArmour.unwrap(RSGArmour.wrap(payload))
            // Padding is deliberately left for get_rsg_data to strip.
            XCTAssertEqual(unwrapped?.replacingOccurrences(of: "=", with: ""), payload,
                           "length \(length)")
        }
    }

    // MARK: - check_release_rsm_structure

    func testCheckReleaseRSMStructure() {
        func check(_ meta: [(String, MsgPack.Value)]) -> String? {
            RSG.checkReleaseRSMStructure(
                RSG.SignedData(hashType: "sha256", hash: Data(count: 32), meta: meta, message: nil))
        }

        let empty: [(String, MsgPack.Value)] = []
        XCTAssertEqual(check(empty), "No release metadata in manifest")

        let nameOnly: [(String, MsgPack.Value)] = [("name", .string("pkg"))]
        XCTAssertEqual(check(nameOnly), "Incomplete package data in manifest")

        let noOrigin: [(String, MsgPack.Value)] = [("name", .string("pkg")),
                                                   ("version", .string("1.0"))]
        XCTAssertEqual(check(noOrigin), "Incomplete release origin data in manifest")

        let slashInName: [(String, MsgPack.Value)] = [("name", .string("p/kg")),
                                                      ("version", .string("1.0")),
                                                      ("origin", .bytes(Data(count: 16))),
                                                      ("path", .string("/x"))]
        XCTAssertEqual(check(slashInName), "Invalid data in release manifest")

        let shortOrigin: [(String, MsgPack.Value)] = [("name", .string("pkg")),
                                                      ("version", .string("1.0")),
                                                      ("origin", .bytes(Data(count: 8))),
                                                      ("path", .string("/x"))]
        XCTAssertEqual(check(shortOrigin), "Invalid origin hash length in manifest")

        // Python checks LENGTH before TYPE, so a 16-character str origin reaches the type gate.
        let stringOrigin: [(String, MsgPack.Value)] = [("name", .string("pkg")),
                                                       ("version", .string("1.0")),
                                                       ("origin", .string(String(repeating: "a", count: 16))),
                                                       ("path", .string("/x"))]
        XCTAssertEqual(check(stringOrigin), "Invalid origin hash in manifest")

        let valid: [(String, MsgPack.Value)] = [("name", .string("pkg")),
                                                ("version", .string("1.0")),
                                                ("origin", .bytes(Data(count: 16))),
                                                ("path", .string("/x"))]
        XCTAssertNil(check(valid))
    }
}
