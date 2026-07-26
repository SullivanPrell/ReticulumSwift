import XCTest
@testable import ReticulumSwift

/// Tests for `get_operating_identity` — the `-g` / `-i` / `-m` / `-M` ladder.
///
/// Python reference: RNS/Utilities/rnid.py:202-370.
final class RNIDIdentityResolverTests: XCTestCase {

    /// Returns false immediately, so no test ever sleeps or reaches `Transport.awaitPath`.
    private final class InstantWaiter: RNIDPathWaiter {
        private(set) var messages: [String] = []
        func wait(until condition: () -> Bool, message: String, timeout: TimeInterval) -> Bool {
            messages.append(message)
            return condition()
        }
    }

    private func makeResolver(files: [String: Data] = [:],
                              transport: Transport? = nil,
                              waiter: RNIDPathWaiter? = nil)
    -> (RNIDIdentityResolver, RNIDCapturingOutput, RNIDMemoryFileSystem) {
        let output = RNIDCapturingOutput()
        let fileSystem = RNIDMemoryFileSystem(files: files)
        let resolver = RNIDIdentityResolver(transport: transport, reticulum: nil,
                                            output: output, fileSystem: fileSystem,
                                            pathWaiter: waiter)
        return (resolver, output, fileSystem)
    }

    // MARK: - -g / --generate

    /// `-g` is the one input path Python never runs through `os.path.expanduser`
    /// (rnid.py:208, :213), so `-g ~/x.rid` creates a literal `~/x.rid`.
    func testGenerateDoesNotExpandTilde() {
        let (resolver, output, fileSystem) = makeResolver()
        let result = resolver.resolve(source: .generate(path: "~/x.rid", force: false))

        guard case .success(let identity?) = result else { return XCTFail("expected an identity") }
        XCTAssertNotNil(fileSystem.files["~/x.rid"])
        XCTAssertNil(fileSystem.files["/home/test/x.rid"])
        XCTAssertEqual(fileSystem.files["~/x.rid"]?.count, 64)
        XCTAssertEqual(output.lines,
                       ["New identity \(RNSUtilities.prettyhexrep(identity.hash)) written to ~/x.rid"])
    }

    func testGenerateRefusesToOverwriteWithoutForce() {
        let (resolver, output, _) = makeResolver(files: ["x.rid": Data(count: 64)])
        let result = resolver.resolve(source: .generate(path: "x.rid", force: false))

        guard case .failure(let code) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(code, .fileExists)
        XCTAssertEqual(output.lines, ["Identity file x.rid already exists. Not overwriting."])
    }

    func testGenerateOverwritesWithForce() {
        let (resolver, _, fileSystem) = makeResolver(files: ["x.rid": Data(count: 64)])
        let result = resolver.resolve(source: .generate(path: "x.rid", force: true))

        guard case .success(let identity?) = result else { return XCTFail("expected an identity") }
        XCTAssertEqual(fileSystem.files["x.rid"], identity.privateKeyBytes)
    }

    // MARK: - -i as a file path

    func testIdentityFileLoads() throws {
        let source = Identity()
        let blob = try XCTUnwrap(source.privateKeyBytes)
        let (resolver, output, _) = makeResolver(files: ["/home/test/id.rid": blob])

        let result = resolver.resolve(source: .identityArgument("~/id.rid"))
        guard case .success(let identity?) = result else { return XCTFail("expected an identity") }
        XCTAssertEqual(identity.hash, source.hash)
        // Python prints the EXPANDED path.
        XCTAssertEqual(output.lines,
                       ["Loaded Identity \(RNSUtilities.prettyhexrep(source.hash)) from /home/test/id.rid"])
    }

    func testIdentityFileOfTheWrongLengthFails() {
        let (resolver, output, _) = makeResolver(files: ["id.rid": Data(count: 63)])
        let result = resolver.resolve(source: .identityArgument("id.rid"))

        guard case .failure(let code) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(code, .invalidIdentity)
        XCTAssertTrue(output.lines.first?.hasPrefix("Could not load Identity from specified file: ") ?? false)
    }

    /// A shared Python/Swift quirk: `from_file` → `load_private_key` accepts ANY 64 bytes, so
    /// pointing `-i` at a 64-byte `.pub` file silently yields a WRONG identity. Do not "fix"
    /// this, or `-i` behaviour diverges from Python.
    func testIdentityFilePointedAtAPublicBlobSilentlyLoadsAWrongIdentity() {
        let source = Identity()
        let (resolver, _, _) = makeResolver(files: ["id.pub": source.getPublicKey()])
        let result = resolver.resolve(source: .identityArgument("id.pub"))

        guard case .success(let identity?) = result else { return XCTFail("expected an identity") }
        XCTAssertNotEqual(identity.hash, source.hash)
        XCTAssertTrue(identity.hasPrivateKey)
    }

    // MARK: - -N / --no-cache

    func testNoCacheShortCircuitsBeforeAnyRecall() {
        let (resolver, output, _) = makeResolver()
        let hex = String(repeating: "a", count: 32)

        let allowed = resolver.resolve(source: .identityArgument(hex), allowNone: true, noCache: true)
        guard case .success(let none) = allowed else { return XCTFail("expected success") }
        XCTAssertNil(none)
        XCTAssertTrue(output.lines.isEmpty)

        let required = resolver.resolve(source: .identityArgument(hex), allowNone: false, noCache: true)
        guard case .failure(let code) = required else { return XCTFail("expected a failure") }
        XCTAssertEqual(code, .noIdentity)
        XCTAssertEqual(output.lines, ["Could not resolve identity"])
    }

    // MARK: - -i as a hex hash

    func testRecallByDestinationHash() throws {
        let transport = Transport()
        let source = Identity()
        let destinationHash = Data(repeating: 0xAB, count: 16)
        transport.restore(identity: source, forDestination: destinationHash)

        let (resolver, output, _) = makeResolver(transport: transport)
        let result = resolver.resolve(source: .identityArgument(RNIDEncoding.hexEncode(destinationHash)))

        guard case .success(let identity?) = result else { return XCTFail("expected an identity") }
        XCTAssertEqual(identity.hash, source.hash)
        XCTAssertEqual(output.lines, ["Recalled Identity \(RNSUtilities.prettyhexrep(source.hash))"
                                      + " for destination \(RNSUtilities.prettyhexrep(destinationHash))"])
    }

    /// Python's `recall(h) or recall(h, from_identity_hash=True)` — the second form scans for
    /// an identity whose OWN hash matches, so a user can pass either kind of hash to `-i`.
    func testRecallByIdentityHash() throws {
        let transport = Transport()
        let source = Identity()
        transport.restore(identity: source, forDestination: Data(repeating: 0xCD, count: 16))

        let (resolver, output, _) = makeResolver(transport: transport)
        let result = resolver.resolve(source: .identityArgument(source.hexHash))

        guard case .success(let identity?) = result else { return XCTFail("expected an identity") }
        XCTAssertEqual(identity.hash, source.hash)
        // Here str(identity) == prettyhexrep(requested_hash), so the short form is printed.
        XCTAssertEqual(output.lines, ["Recalled Identity \(RNSUtilities.prettyhexrep(source.hash))"])
    }

    /// Python's destination-hash branch also scans locally-registered destinations
    /// (RNS/Identity.py:141-148), which Swift's plain dictionary lookup does not.
    func testRecallFallsBackToLocallyRegisteredDestinations() throws {
        let transport = Transport()
        let source = Identity()
        let destination = try Destination(identity: source, direction: .in, kind: .single,
                                          appName: "rns", aspects: ["id"])
        transport.register(destination: destination)

        let (resolver, _, _) = makeResolver(transport: transport)
        let result = resolver.resolve(source: .identityArgument(destination.hexHash))

        guard case .success(let identity?) = result else { return XCTFail("expected an identity") }
        XCTAssertEqual(identity.hash, source.hash)
    }

    func testUnknownHashWithoutRequestFails() {
        let transport = Transport()
        let (resolver, output, _) = makeResolver(transport: transport)
        let unknown = Data(repeating: 0x11, count: 16)

        let result = resolver.resolve(source: .identityArgument(RNIDEncoding.hexEncode(unknown)),
                                      allowNone: false, request: false)
        guard case .failure(let code) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(code, .noIdentity)
        XCTAssertEqual(output.lines, [
            "Could not recall Identity for \(RNSUtilities.prettyhexrep(unknown)).",
            "You can query the network for unknown Identities with the -R option."
        ])
    }

    func testUnknownHashWithAllowNoneAndNoRequestReturnsNil() {
        let transport = Transport()
        let (resolver, output, _) = makeResolver(transport: transport)

        let result = resolver.resolve(source: .identityArgument(String(repeating: "1", count: 32)),
                                      allowNone: true, request: false)
        guard case .success(let identity) = result else { return XCTFail("expected success") }
        XCTAssertNil(identity)
        XCTAssertTrue(output.lines.isEmpty)
    }

    /// Python DISCARDS `spin()`'s return value and re-invokes the predicate itself
    /// (rnid.py:259); a waiter that reports success must not be trusted on its own.
    func testRequestTimeoutReTestsThePredicate() {
        let transport = Transport()
        let waiter = InstantWaiter()
        let (resolver, output, _) = makeResolver(transport: transport, waiter: waiter)
        let unknown = Data(repeating: 0x22, count: 16)

        let result = resolver.resolve(source: .identityArgument(RNIDEncoding.hexEncode(unknown)),
                                      allowNone: false, request: true)
        guard case .failure(let code) = result else { return XCTFail("expected a failure") }
        XCTAssertEqual(code, .noIdentity)
        XCTAssertEqual(waiter.messages,
                       ["Requesting unknown Identity for \(RNSUtilities.prettyhexrep(unknown))"])
        XCTAssertEqual(output.lines.last, "Identity request timed out")
    }

    func testNonHashNonFileArgumentFallsThroughSilently() {
        let (resolver, output, _) = makeResolver()
        let result = resolver.resolve(source: .identityArgument("not-a-hash"), allowNone: true)
        guard case .success(let identity) = result else { return XCTFail("expected success") }
        XCTAssertNil(identity)
        XCTAssertTrue(output.lines.isEmpty)
    }

    // MARK: - -m / -M import ladder

    func testImportLadderAcceptsAllFourEncodings() throws {
        let source = Identity()
        let publicBlob = source.getPublicKey()
        let privateBlob = try XCTUnwrap(source.privateKeyBytes)

        let cases: [(String, String, Data, Bool)] = [
            ("/home/test/key.pub", "~/key.pub", publicBlob, false),
            ("/home/test/key.rid", "~/key.rid", privateBlob, true)
        ]

        for (storedPath, argument, blob, isPrivate) in cases {
            // (1) File — the EXPANDED path is printed.
            let (fileResolver, fileOutput, _) = makeResolver(files: [storedPath: blob])
            let fileResult = fileResolver.resolve(source: isPrivate ? .importPrivate(argument)
                                                                    : .importPublic(argument))
            guard case .success(let fromFile?) = fileResult else { return XCTFail("file import") }
            XCTAssertEqual(fromFile.hash, source.hash)
            XCTAssertEqual(fileOutput.lines, ["Reticulum Identity imported from \(storedPath)"])

            // (2) Hex — 128 characters.
            let hex = RNIDEncoding.hexEncode(blob)
            XCTAssertEqual(hex.count, 128)
            let (hexResolver, hexOutput, _) = makeResolver()
            let hexResult = hexResolver.resolve(source: isPrivate ? .importPrivate(hex) : .importPublic(hex))
            guard case .success(let fromHex?) = hexResult else { return XCTFail("hex import") }
            XCTAssertEqual(fromHex.hash, source.hash)
            XCTAssertEqual(hexOutput.lines, ["Reticulum Identity imported from hex input"])

            // (3) Base32 — 104 characters.
            let base32 = RNIDEncoding.base32Encode(blob)
            XCTAssertEqual(base32.count, 104)
            let (b32Resolver, b32Output, _) = makeResolver()
            let b32Result = b32Resolver.resolve(source: isPrivate ? .importPrivate(base32)
                                                                  : .importPublic(base32))
            guard case .success(let fromB32?) = b32Result else { return XCTFail("base32 import") }
            XCTAssertEqual(fromB32.hash, source.hash)
            XCTAssertEqual(b32Output.lines, ["Reticulum Identity imported from base32 input"])

            // (4) Base64 (url-safe) — 88 characters.
            let base64 = RNIDEncoding.base64URLEncode(blob)
            XCTAssertEqual(base64.count, 88)
            let (b64Resolver, b64Output, _) = makeResolver()
            let b64Result = b64Resolver.resolve(source: isPrivate ? .importPrivate(base64)
                                                                  : .importPublic(base64))
            guard case .success(let fromB64?) = b64Result else { return XCTFail("base64 import") }
            XCTAssertEqual(fromB64.hash, source.hash)
            XCTAssertEqual(b64Output.lines, ["Reticulum Identity imported from base64 input"])
        }
    }

    func testImportPublicProducesAPublicOnlyIdentity() {
        let source = Identity()
        let (resolver, _, _) = makeResolver()
        let result = resolver.resolve(source: .importPublic(RNIDEncoding.hexEncode(source.getPublicKey())))
        guard case .success(let identity?) = result else { return XCTFail("expected an identity") }
        XCTAssertFalse(identity.hasPrivateKey)
        XCTAssertEqual(identity.hash, source.hash)
    }

    func testImportFailureMessagesDifferBetweenPublicAndPrivate() {
        let (publicResolver, publicOutput, _) = makeResolver()
        let publicResult = publicResolver.resolve(source: .importPublic("!!!!"))
        guard case .failure(let publicCode) = publicResult else { return XCTFail("expected a failure") }
        XCTAssertEqual(publicCode, .invalidIdentity)
        XCTAssertEqual(publicOutput.lines,
                       ["Could not decode specified data to a valid public Reticulum Identity"])

        let (privateResolver, privateOutput, _) = makeResolver()
        let privateResult = privateResolver.resolve(source: .importPrivate("!!!!"))
        guard case .failure(let privateCode) = privateResult else { return XCTFail("expected a failure") }
        XCTAssertEqual(privateCode, .invalidIdentity)
        XCTAssertEqual(privateOutput.lines,
                       ["Could not decode specified data to a valid private Reticulum Identity"])
    }

    // MARK: - Constants

    func testHashStringLengthMatchesPython() {
        // Python: RNS.Reticulum.TRUNCATED_HASHLENGTH//8*2
        XCTAssertEqual(RNIDIdentityResolver.hashStringLength, 32)
        // Python: prvsize = pubsize = RNS.Identity.KEYSIZE//8
        XCTAssertEqual(RNIDIdentityResolver.keyBlobSize, 64)
    }
}
