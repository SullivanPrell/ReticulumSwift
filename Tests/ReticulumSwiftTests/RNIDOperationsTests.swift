import XCTest
@testable import ReticulumSwift

/// Tests for every operation `rnid`'s `main()` dispatches to.
///
/// Python reference: RNS/Utilities/rnid.py. Everything runs through
/// ``RNIDMemoryFileSystem`` + ``RNIDCapturingOutput``, so no test touches disk or a network.
final class RNIDOperationsTests: XCTestCase {

    // MARK: - Fixtures

    private func makeOperations(identity: Identity?,
                                identityArgument: String? = nil,
                                options: RNIDApp.Options = RNIDApp.Options(),
                                files: [String: Data] = [:],
                                transport: Transport? = nil,
                                editor: RNIDEditor? = nil)
    -> (RNIDOperations, RNIDCapturingOutput, RNIDMemoryFileSystem) {
        let output = RNIDCapturingOutput()
        let fileSystem = RNIDMemoryFileSystem(files: files)
        let operations = RNIDOperations(identity: identity, identityArgument: identityArgument,
                                        options: options, output: output,
                                        fileSystem: fileSystem, transport: transport,
                                        editor: editor)
        return (operations, output, fileSystem)
    }

    /// An `.rfe` blob encrypted to `identity`.
    private func encryptedBlob(for identity: Identity, plaintext: Data) throws -> Data {
        let writer = RNIDDataWriter()
        try RNIDFileCrypto.encryptStream(identity: identity,
                                         reader: RNIDDataReader(plaintext), writer: writer)
        return writer.data
    }

    // MARK: - Result enum

    func testResultHasNineteenCases() {
        // Python defines 19 R_* constants, R_OK…R_INTERRUPTED.
        XCTAssertEqual(RNIDApp.Result.allCases.count, 19)
        let expected: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 250, 251, 252, 253, 254, 255]
        XCTAssertEqual(RNIDApp.Result.allCases.map { $0.rawValue }, expected)
        // R_NO_SIG_FILE (1) is defined at rnid.py:65 but NEVER returned — kept for parity.
        XCTAssertEqual(RNIDApp.Result.noSigFile.rawValue, 1)
    }

    // MARK: - -p / -x / -X

    func testPrintIdentityInformationColumnAlignment() {
        let identity = Identity()
        let (operations, output, _) = makeOperations(identity: identity)
        XCTAssertEqual(operations.printIdentityInformation(), .ok)
        XCTAssertEqual(output.lines, [
            "Identity Hash : " + RNSUtilities.prettyhexrep(identity.hash),
            "Public Key    : " + RNSUtilities.hexrep(identity.getPublicKey(), delimit: false),
            "Private Key   : Hidden"
        ])
    }

    func testPrintIdentityInformationWithPrintPrivate() throws {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.printPrivate = true
        let (operations, output, _) = makeOperations(identity: identity, options: options)
        XCTAssertEqual(operations.printIdentityInformation(), .ok)
        XCTAssertEqual(output.lines.count, 3)
        XCTAssertEqual(output.lines[2],
                       "Private Key   : " + RNSUtilities.hexrep(try XCTUnwrap(identity.privateKeyBytes),
                                                                delimit: false))
    }

    func testPrintIdentityOmitsThePrivateLineForAPublicOnlyIdentity() throws {
        let publicOnly = try Identity(publicKeyBytes: Identity().getPublicKey())
        let (operations, output, _) = makeOperations(identity: publicOnly)
        XCTAssertEqual(operations.printIdentityInformation(), .ok)
        XCTAssertEqual(output.lines.count, 2)
        XCTAssertFalse(output.text.contains("Private Key"))
    }

    /// `-U`/`--base256` is NOT honoured by `-p`, `-x` or `-X`; those fall through to hex.
    func testBase256IsNotHonouredByTheKeyPrinters() {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.outputFormat = .base256
        let (operations, output, _) = makeOperations(identity: identity, options: options)
        XCTAssertEqual(operations.exportPublicIdentity(), .ok)
        XCTAssertEqual(output.lines,
                       ["Public Identity Keys  : " + RNSUtilities.hexrep(identity.getPublicKey(),
                                                                         delimit: false)])
    }

    func testExportLabelsAre22CharactersWide() throws {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.outputFormat = .base64
        let (operations, output, _) = makeOperations(identity: identity, options: options)
        XCTAssertEqual(operations.exportPublicIdentity(), .ok)
        XCTAssertEqual(operations.exportPrivateIdentity(), .ok)
        XCTAssertEqual(output.lines, [
            "Public Identity Keys  : " + RNIDEncoding.base64URLEncode(identity.getPublicKey()),
            "Private Identity Keys : " + RNIDEncoding.base64URLEncode(try XCTUnwrap(identity.privateKeyBytes))
        ])
    }

    func testExportPrivateFailsForAPublicOnlyIdentity() throws {
        let publicOnly = try Identity(publicKeyBytes: Identity().getPublicKey())
        let (operations, output, _) = makeOperations(identity: publicOnly)
        XCTAssertEqual(operations.exportPrivateIdentity(), .noPrvKey)
        XCTAssertEqual(output.lines, ["Identity doesn't hold a private key, cannot export"])
    }

    // MARK: - -H / --hash

    func testPrintHashInformationWithAResolvedIdentity() throws {
        let identity = Identity()
        let transport = Transport()
        let (operations, output, _) = makeOperations(identity: identity, transport: transport)
        XCTAssertEqual(operations.printHashInformation(aspects: "rns.id"), .ok)

        let expectedHash = try XCTUnwrap(RNIDDestinationHash.hash(fromFullName: "rns.id",
                                                                  identityHash: identity.hash))
        let destination = try Destination(identity: identity, direction: .out, kind: .single,
                                          appName: "rns", aspects: ["id"])
        XCTAssertEqual(output.lines, [
            "The rns.id destination for this Identity is " + RNSUtilities.prettyhexrep(expectedHash),
            "The full destination specifier is <\(destination.fullName):\(destination.hexHash)>"
        ])
        // Python's Destination.__init__ registers with Transport; Swift's does not, so the
        // port registers explicitly.
        XCTAssertNotNil(transport.registeredDestinations[destination.hash])
    }

    /// `-H` is dispatched with `identity or args.identity`, so a bare hex hash must work.
    func testPrintHashInformationWithABareHexHash() throws {
        let hex = String(repeating: "ab", count: 16)
        let (operations, output, _) = makeOperations(identity: nil, identityArgument: hex)
        XCTAssertEqual(operations.printHashInformation(aspects: "rns.id"), .ok)

        let expectedHash = try XCTUnwrap(RNIDDestinationHash.hash(
            fromFullName: "rns.id", identityHash: try XCTUnwrap(RNIDEncoding.hexDecode(hex))))
        // No Destination object exists, so the second line is omitted.
        XCTAssertEqual(output.lines,
                       ["The rns.id destination for this Identity is "
                        + RNSUtilities.prettyhexrep(expectedHash)])
    }

    func testPrintHashInformationRejectsBadIdentityArguments() {
        let (noIdentity, noIdentityOutput, _) = makeOperations(identity: nil)
        XCTAssertEqual(noIdentity.printHashInformation(aspects: "rns.id"), .invalidIdentity)
        XCTAssertEqual(noIdentityOutput.lines, ["Invalid identity"])

        let (shortHash, shortOutput, _) = makeOperations(identity: nil, identityArgument: "abcd")
        XCTAssertEqual(shortHash.printHashInformation(aspects: "rns.id"), .invalidIdentity)
        XCTAssertEqual(shortOutput.lines, ["Invalid identity hash length"])

        let (badHex, badOutput, _) = makeOperations(identity: nil,
                                                    identityArgument: String(repeating: "z", count: 32))
        XCTAssertEqual(badHex.printHashInformation(aspects: "rns.id"), .invalidIdentity)
        XCTAssertTrue(badOutput.lines[0].hasPrefix("Invalid identity: "))
    }

    // MARK: - -a / --announce

    func testAnnounceRejectsASingleBareToken() {
        let (operations, output, _) = makeOperations(identity: Identity(), transport: Transport())
        // Python: `if not len(aspects) > 1`.
        XCTAssertEqual(operations.announce(aspects: "rns"), .invalidAspects)
        XCTAssertEqual(output.lines, ["Invalid destination aspects specified"])
    }

    /// Python's `str.split(".")` keeps empty components, so `"rns."` yields `['rns','']` and
    /// PASSES the `len > 1` gate. `Destination.appAndAspects` would collapse it and reject.
    func testAnnounceAcceptsATrailingDot() throws {
        let transport = Transport()
        let (operations, output, _) = makeOperations(identity: Identity(), transport: transport)
        XCTAssertNotEqual(operations.announce(aspects: "rns."), .invalidAspects)
        XCTAssertTrue(output.lines.contains { $0.hasPrefix("Announcing rns. destination ") })
    }

    func testAnnounceRequiresAPrivateKey() throws {
        let publicOnly = try Identity(publicKeyBytes: Identity().getPublicKey())
        let (operations, output, _) = makeOperations(identity: publicOnly, transport: Transport())
        XCTAssertEqual(operations.announce(aspects: "rns.id"), .noPrvKey)
        XCTAssertEqual(output.lines, ["Cannot announce this destination, since the private key is not held"])
    }

    // MARK: - -s / --sign

    func testSignWritesAModernRSG() throws {
        let identity = Identity()
        let payload = Data("contents".utf8)
        let (operations, output, fileSystem) = makeOperations(identity: identity,
                                                              files: ["/home/test/doc.txt": payload])
        XCTAssertEqual(operations.sign(paths: ["~/doc.txt"]), .ok)

        let rsg = try XCTUnwrap(fileSystem.files["/home/test/doc.txt.rsg"])
        XCTAssertEqual(rsg.count, 224)
        XCTAssertEqual(output.lines,
                       ["Signed file /home/test/doc.txt with " + RNSUtilities.prettyhexrep(identity.hash)])

        // Round-trip through validate.
        let (validator, validatorOutput, _) = makeOperations(identity: identity,
                                                             files: fileSystem.files)
        XCTAssertEqual(validator.validate(paths: ["/home/test/doc.txt"]), .ok)
        XCTAssertEqual(validatorOutput.lines,
                       ["Signature is valid, the file /home/test/doc.txt was signed by "
                        + RNSUtilities.prettyhexrep(identity.hash)])
    }

    func testSignRawWritesTheLegacy64ByteFormat() throws {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.raw = true
        let (operations, _, fileSystem) = makeOperations(identity: identity, options: options,
                                                         files: ["doc.txt": Data("contents".utf8)])
        XCTAssertEqual(operations.sign(paths: ["doc.txt"]), .ok)

        let rsg = try XCTUnwrap(fileSystem.files["doc.txt.rsg"])
        XCTAssertEqual(rsg.count, 64)
        XCTAssertTrue(RSG.isLegacyFormat(rsg))

        // Legacy validation needs an explicit Identity — a bare hash is not enough.
        let (validator, validatorOutput, _) = makeOperations(identity: identity, files: fileSystem.files)
        XCTAssertEqual(validator.validate(paths: ["doc.txt"]), .ok)
        XCTAssertEqual(validatorOutput.lines,
                       ["Signature is valid, the file doc.txt was signed by "
                        + RNSUtilities.prettyhexrep(identity.hash)])
    }

    func testLegacyValidationWithoutAnIdentityFails() throws {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.raw = true
        let (signer, _, fileSystem) = makeOperations(identity: identity, options: options,
                                                     files: ["doc.txt": Data("contents".utf8)])
        XCTAssertEqual(signer.sign(paths: ["doc.txt"]), .ok)

        let (validator, output, _) = makeOperations(identity: nil,
                                                    identityArgument: identity.hexHash,
                                                    files: fileSystem.files)
        XCTAssertEqual(validator.validate(paths: ["doc.txt"]), .noIdentity)
        XCTAssertEqual(output.lines.first,
                       "Cannot validate legacy rsg signatures without an explicit required identity")
    }

    func testSignTextOutputPrintsArmourAndWritesNothing() throws {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.outputFormat = .base64
        let (operations, output, fileSystem) = makeOperations(identity: identity, options: options,
                                                              files: ["doc.txt": Data("x".utf8)])
        XCTAssertEqual(operations.sign(paths: ["doc.txt"]), .ok)
        XCTAssertNil(fileSystem.files["doc.txt.rsg"])
        XCTAssertTrue(output.lines[0].hasPrefix("\n" + RSGArmour.header))
        XCTAssertTrue(output.lines[0].hasSuffix(RSGArmour.footer + "\n"))
    }

    func testSignGates() throws {
        let identity = Identity()
        let publicOnly = try Identity(publicKeyBytes: identity.getPublicKey())

        let (noKey, noKeyOutput, _) = makeOperations(identity: publicOnly,
                                                     files: ["doc.txt": Data("x".utf8)])
        XCTAssertEqual(noKey.sign(paths: ["doc.txt"]), .noPrvKey)
        XCTAssertEqual(noKeyOutput.lines.first,
                       "Cannot sign \"doc.txt\", the identity does not hold a private key")

        let (missing, missingOutput, _) = makeOperations(identity: identity)
        XCTAssertEqual(missing.sign(paths: ["doc.txt"]), .noFile)
        XCTAssertEqual(missingOutput.lines.first, "The file \"doc.txt\" does not exist")

        let (exists, existsOutput, _) = makeOperations(
            identity: identity,
            files: ["doc.txt": Data("x".utf8), "doc.txt.rsg": Data(count: 224)])
        XCTAssertEqual(exists.sign(paths: ["doc.txt"]), .fileExists)
        XCTAssertEqual(existsOutput.lines.first,
                       "The signature file \"doc.txt.rsg\" already exists, not overwriting")
    }

    /// QUIRK: the overwrite guard is gated on `output == "bin"`, so `-s file --raw -b` still
    /// overwrites the .rsg without asking — `--raw` always writes binary regardless.
    func testRawWithATextFormatSkipsTheOverwriteGuard() {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.raw = true
        options.outputFormat = .base64
        let (operations, _, fileSystem) = makeOperations(
            identity: identity,
            options: options,
            files: ["doc.txt": Data("x".utf8), "doc.txt.rsg": Data(count: 224)])
        XCTAssertEqual(operations.sign(paths: ["doc.txt"]), .ok)
        XCTAssertEqual(fileSystem.files["doc.txt.rsg"]?.count, 64)
    }

    func testSignListRecursionReportsSequenceErrors() {
        let identity = Identity()
        let (operations, output, _) = makeOperations(identity: identity,
                                                     files: ["a.txt": Data("a".utf8)])
        // The second path does not exist, so the recursion aborts.
        XCTAssertEqual(operations.sign(paths: ["a.txt", "missing.txt"]), .noFile)
        XCTAssertEqual(output.lines.last, "The file \"missing.txt\" does not exist")
    }

    // MARK: - -V / --validate

    func testValidateReportsMissingTargetsAndSignatures() {
        let identity = Identity()
        let (missingTarget, missingTargetOutput, _) = makeOperations(identity: identity)
        XCTAssertEqual(missingTarget.validate(paths: ["doc.txt"]), .noFile)
        XCTAssertEqual(missingTargetOutput.lines.first,
                       "The validation target \"doc.txt\" does not exist")

        let (missingSig, missingSigOutput, _) = makeOperations(identity: identity,
                                                               files: ["doc.txt": Data("x".utf8)])
        XCTAssertEqual(missingSig.validate(paths: ["doc.txt"]), .noFile)
        XCTAssertEqual(missingSigOutput.lines.first, "No signature file exists for \"doc.txt\"")
    }

    func testValidateReportsAnInvalidSignature() throws {
        let identity = Identity()
        let (signer, _, fileSystem) = makeOperations(identity: identity,
                                                     files: ["doc.txt": Data("x".utf8)])
        XCTAssertEqual(signer.sign(paths: ["doc.txt"]), .ok)

        var tamperedFiles = fileSystem.files
        tamperedFiles["doc.txt"] = Data("y".utf8)
        let (validator, output, _) = makeOperations(identity: identity, files: tamperedFiles)
        XCTAssertEqual(validator.validate(paths: ["doc.txt"]), .invalidSignature)
        XCTAssertEqual(output.lines.first,
                       "Invalid signature doc.txt.rsg for file doc.txt"
                       + "\nThis file was NOT signed by " + RNSUtilities.prettyhexrep(identity.hash))
    }

    /// `-V` lowercases before testing `.rsg`/`.rsm`, so mixed-case names work.
    func testValidateExtensionCheckIsCaseInsensitive() throws {
        let identity = Identity()
        let payload = Data("x".utf8)
        let (signer, _, fileSystem) = makeOperations(identity: identity, files: ["FILE": payload])
        XCTAssertEqual(signer.sign(paths: ["FILE"]), .ok)

        var files = fileSystem.files
        files["FILE.RSG"] = files.removeValue(forKey: "FILE.rsg")
        let (validator, output, _) = makeOperations(identity: identity, files: files)
        // "FILE.RSG" is recognised as a signature file, so the target becomes "FILE".
        XCTAssertEqual(validator.validate(paths: ["FILE.RSG"]), .ok)
        XCTAssertEqual(output.lines.first,
                       "Signature is valid, the file FILE was signed by "
                       + RNSUtilities.prettyhexrep(identity.hash))
    }

    // MARK: - -S / --sign-message and .rsm display

    private func makeRSM(signer: Identity,
                         message: Data,
                         extraMeta: [(String, MsgPack.Value)]) throws -> Data {
        var meta: [(String, MsgPack.Value)] = [
            ("signer", .bytes(signer.hash)),
            ("pubkey", .bytes(signer.getPublicKey()))
        ]
        meta.append(contentsOf: extraMeta)
        let signedData = RSG.SignedData(hashType: "sha256", hash: Hashes.fullHash(message),
                                        meta: meta, message: message)
        let envelope = signedData.envelope()
        return try signer.sign(envelope) + envelope
    }

    func testSignMessageWritesAnRSMAndValidatesIt() throws {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.write = "~/out"
        let (operations, output, fileSystem) = makeOperations(identity: identity, options: options)
        XCTAssertEqual(operations.signMessage("hello world"), .ok)

        XCTAssertNotNil(fileSystem.files["/home/test/out.rsm"])
        XCTAssertEqual(output.lines,
                       ["Message signed with " + RNSUtilities.prettyhexrep(identity.hash)
                        + " saved to /home/test/out.rsm"])

        let (validator, validatorOutput, _) = makeOperations(identity: identity, files: fileSystem.files)
        XCTAssertEqual(validator.validate(paths: ["/home/test/out.rsm"]), .ok)
        XCTAssertEqual(validatorOutput.lines, [
            "\nSignature is valid, the following message was signed by "
            + RNSUtilities.prettyhexrep(identity.hash) + ":\n",
            "hello world"
        ])
    }

    /// Without `--meta`: a blank line, the "following message" line, a blank line, the body —
    /// with no "RSM Metadata", "Validation" or "Message" headers.
    func testRSMDisplayWithoutMeta() throws {
        let identity = Identity()
        let rsm = try makeRSM(signer: identity, message: Data("body text".utf8), extraMeta: [])
        let (operations, output, _) = makeOperations(identity: identity, files: ["m.rsm": rsm])
        XCTAssertEqual(operations.validate(paths: ["m.rsm"]), .ok)
        XCTAssertEqual(output.lines, [
            "\nSignature is valid, the following message was signed by "
            + RNSUtilities.prettyhexrep(identity.hash) + ":\n",
            "body text"
        ])
        XCTAssertFalse(output.text.contains("RSM Metadata"))
        XCTAssertFalse(output.text.contains("Validation"))
    }

    /// With `--meta`: the full metadata dump, including the type-tag quirks.
    func testRSMDisplayWithMeta() throws {
        let identity = Identity()
        let long = String(repeating: "L", count: 200)
        let extras: [(String, MsgPack.Value)] = [
            ("text", .string("plain")),
            ("blob", .bytes(Data([0xDE, 0xAD]))),
            ("list", .array([.string("a"), .string("b")])),
            ("count", .int(7)),
            ("ratio", .double(1.5)),
            ("flag", .bool(true)),
            ("nothing", .nil),
            ("note", .nil),
            ("long", .string(long)),
            ("section", .map([(.string("inner"), .string("value"))]))
        ]
        let rsm = try makeRSM(signer: identity, message: Data("body".utf8), extraMeta: extras)

        var options = RNIDApp.Options()
        options.showMeta = true
        let (operations, output, _) = makeOperations(identity: identity, options: options,
                                                     files: ["m.rsm": rsm])
        XCTAssertEqual(operations.validate(paths: ["m.rsm"]), .ok)

        let leadIn = "s  long="
        XCTAssertEqual(output.lines, [
            "RSM Metadata\n============\n",
            "b  signer=" + RNSUtilities.hexrep(identity.hash, delimit: false),
            "b  pubkey=" + RNSUtilities.hexrep(identity.getPublicKey(), delimit: false).prefix(64),
            String(repeating: " ", count: "b  pubkey=".count)
                + RNSUtilities.hexrep(identity.getPublicKey(), delimit: false).suffix(64),
            "s  text=plain",
            "b  blob=dead",
            "l  list=['a', 'b']",
            "i  count=7",
            "f  ratio=1.5",
            // bool renders with "u", NOT "i": in Python `type(True) == int` is False.
            "u  flag=True",
            "N  nothing=None",
            // A "note" key whose value is None is skipped entirely.
            leadIn + String(repeating: "L", count: 64),
            String(repeating: " ", count: leadIn.count) + String(repeating: "L", count: 64),
            String(repeating: " ", count: leadIn.count) + String(repeating: "L", count: 64),
            String(repeating: " ", count: leadIn.count) + String(repeating: "L", count: 8),
            "d  section:",
            "s    inner=value",
            "\nValidation\n==========",
            "\nSignature is valid, the message was signed by "
            + RNSUtilities.prettyhexrep(identity.hash) + "\n",
            "Message\n=======\n",
            "body"
        ])
    }

    func testSignMessageGates() throws {
        let identity = Identity()

        let (noWrite, noWriteOutput, _) = makeOperations(identity: identity)
        XCTAssertEqual(noWrite.signMessage("hi"), .invalidArgs)
        XCTAssertEqual(noWriteOutput.lines, ["No write path specified"])

        var options = RNIDApp.Options()
        options.write = "out"
        let (noIdentity, noIdentityOutput, _) = makeOperations(identity: nil, options: options)
        XCTAssertEqual(noIdentity.signMessage("hi"), .noIdentity)
        XCTAssertEqual(noIdentityOutput.lines, ["Cannot sign, no working identity available"])

        let publicOnly = try Identity(publicKeyBytes: identity.getPublicKey())
        let (noKey, noKeyOutput, _) = makeOperations(identity: publicOnly, options: options)
        XCTAssertEqual(noKey.signMessage("hi"), .noPrvKey)
        XCTAssertEqual(noKeyOutput.lines, ["Cannot sign, the identity does not hold a private key"])

        var bothOptions = options
        bothOptions.read = "in.txt"
        let (both, bothOutput, _) = makeOperations(identity: identity, options: bothOptions)
        XCTAssertEqual(both.signMessage("hi"), .invalidArgs)
        XCTAssertEqual(bothOutput.lines,
                       ["Both an input file and command-line provided message was specified, aborting"])
    }

    /// DIVERGENCE: a bare `-E` crashes Python with an uncaught `TypeError` from
    /// `os.path.expanduser(2)` (shell exit 1); this port reports R_INVALID_ARGS (250).
    func testBareEmbedMetaReportsInvalidArgs() {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.write = "out"
        options.embedMetaWithoutPath = true
        let (operations, _, _) = makeOperations(identity: identity, options: options)
        XCTAssertEqual(operations.signMessage("hi"), .invalidArgs)
    }

    func testEmbedMetaLoadsAndAnnouncesTheSpec() throws {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.write = "out"
        options.embedMeta = "meta.cfg"
        let files: [String: Data] = [
            "meta.cfg": Data("name = pkg\nport = 4242\n".utf8),
            "meta.cfg.spec": Data("port = integer\n".utf8)
        ]
        let (operations, output, fileSystem) = makeOperations(identity: identity, options: options,
                                                              files: files)
        XCTAssertEqual(operations.signMessage("hi"), .ok)
        XCTAssertEqual(output.lines.first, "Embedding metadata from meta.cfg using spec from meta.cfg.spec")

        let rsm = try XCTUnwrap(fileSystem.files["out.rsm"])
        let decoded = try RSG.SignedData.decode(
            envelope: rsm.subdata(in: RSG.signatureLength..<rsm.count))
        XCTAssertEqual(decoded.meta.map { $0.0 }, ["signer", "pubkey", "name", "port"])
        XCTAssertEqual(decoded.metaValue("port"), .int(4242))
    }

    func testEmbedMetaMissingFile() {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.write = "out"
        options.embedMeta = "meta.cfg"
        let (operations, output, _) = makeOperations(identity: identity, options: options)
        XCTAssertEqual(operations.signMessage("hi"), .noFile)
        XCTAssertEqual(output.lines, ["Metadata file meta.cfg does not exist"])
    }

    /// `-S`'s `.rsm` suffix test is CASE-SENSITIVE, unlike `-V`'s.
    func testSignMessageAppendsRSMEvenToAnUppercaseSuffix() {
        let identity = Identity()
        var options = RNIDApp.Options()
        options.write = "x.RSM"
        let (operations, _, fileSystem) = makeOperations(identity: identity, options: options)
        XCTAssertEqual(operations.signMessage("hi"), .ok)
        XCTAssertNotNil(fileSystem.files["x.RSM.rsm"])
    }

    func testSignMessageUsesTheEditorForABareInvocation() throws {
        final class StubEditor: RNIDEditor {
            func composeMessage() throws -> Data { Data("from editor".utf8) }
        }
        let identity = Identity()
        var options = RNIDApp.Options()
        options.write = "out"
        let (operations, _, fileSystem) = makeOperations(identity: identity, options: options,
                                                         editor: StubEditor())
        XCTAssertEqual(operations.signMessage(nil), .ok)

        let rsm = try XCTUnwrap(fileSystem.files["out.rsm"])
        let decoded = try RSG.SignedData.decode(
            envelope: rsm.subdata(in: RSG.signatureLength..<rsm.count))
        XCTAssertEqual(decoded.message, Data("from editor".utf8))
    }

    func testValidateMessageWithoutAnEmbeddedMessage() throws {
        let identity = Identity()
        let signedData = RSG.SignedData(hashType: "sha256", hash: Hashes.fullHash(Data()),
                                        meta: [("signer", .bytes(identity.hash)),
                                               ("pubkey", .bytes(identity.getPublicKey()))],
                                        message: nil)
        let envelope = signedData.envelope()
        let rsm = try identity.sign(envelope) + envelope

        let (operations, output, _) = makeOperations(identity: identity, files: ["m.rsm": rsm])
        XCTAssertEqual(operations.validate(paths: ["m.rsm"]), .invalidSignature)
        XCTAssertEqual(output.lines.first, "No embedded message in m.rsm")
    }

    /// An undecodable RSM envelope surfaces as R_UNKNOWN_ERROR (254), NOT R_INVALID_SIGNATURE:
    /// Python's `"message" in None` raises a TypeError the outer handler catches.
    func testUndecodableRSMIsAnUnknownError() {
        let identity = Identity()
        let rsm = Data(repeating: 0xC1, count: 100)
        let (operations, output, _) = makeOperations(identity: identity, files: ["m.rsm": rsm])
        XCTAssertEqual(operations.validate(paths: ["m.rsm"]), .unknownError)
        XCTAssertTrue(output.lines.first?.hasPrefix("Error while validating m.rsm: ") ?? false)
    }

    // MARK: - -e / --encrypt

    func testEncryptRoundTrip() throws {
        let identity = Identity()
        let payload = Data("secret contents".utf8)
        let (encryptor, encryptOutput, fileSystem) = makeOperations(identity: identity,
                                                                     files: ["doc.txt": payload])
        XCTAssertEqual(encryptor.encrypt(paths: ["doc.txt"]), .ok)
        XCTAssertNotNil(fileSystem.files["doc.txt.rfe"])
        XCTAssertEqual(encryptOutput.lines.last,
                       "\nFile doc.txt encrypted for " + RNSUtilities.prettyhexrep(identity.hash)
                       + " to doc.txt.rfe")

        var files = fileSystem.files
        files.removeValue(forKey: "doc.txt")
        let (decryptor, decryptOutput, decryptedFS) = makeOperations(identity: identity, files: files)
        XCTAssertEqual(decryptor.decrypt(paths: ["doc.txt.rfe"]), .ok)
        XCTAssertEqual(decryptedFS.files["doc.txt"], payload)
        XCTAssertEqual(decryptOutput.lines.last, "\nFile doc.txt.rfe decrypted to doc.txt")
    }

    func testEncryptWithNoIdentity() {
        let (operations, output, _) = makeOperations(identity: nil, files: ["doc.txt": Data()])
        XCTAssertEqual(operations.encrypt(paths: ["doc.txt"]), .noIdentity)
        XCTAssertEqual(output.lines.first, "Cannot encrypt \"doc.txt\", no identity specified")
    }

    func testEncryptWorksWithAPublicOnlyIdentity() throws {
        let publicOnly = try Identity(publicKeyBytes: Identity().getPublicKey())
        let (operations, _, fileSystem) = makeOperations(identity: publicOnly,
                                                         files: ["doc.txt": Data("x".utf8)])
        XCTAssertEqual(operations.encrypt(paths: ["doc.txt"]), .ok)
        XCTAssertNotNil(fileSystem.files["doc.txt.rfe"])
    }

    func testEncryptGates() {
        let identity = Identity()
        let (missing, missingOutput, _) = makeOperations(identity: identity)
        XCTAssertEqual(missing.encrypt(paths: ["doc.txt"]), .noFile)
        XCTAssertEqual(missingOutput.lines.first, "The file \"doc.txt\" does not exist")

        let (exists, existsOutput, _) = makeOperations(
            identity: identity, files: ["doc.txt": Data("x".utf8), "doc.txt.rfe": Data()])
        XCTAssertEqual(exists.encrypt(paths: ["doc.txt"]), .fileExists)
        XCTAssertEqual(existsOutput.lines.first,
                       "The encryption output file \"doc.txt.rfe\" already exists, not overwriting")
    }

    /// Encrypt's progress print fires even on the terminating iteration; decrypt's does not.
    func testEmptyInputProgressAsymmetry() throws {
        let identity = Identity()
        let (encryptor, encryptOutput, encryptFS) = makeOperations(identity: identity,
                                                                    files: ["empty": Data()])
        XCTAssertEqual(encryptor.encrypt(paths: ["empty"]), .ok)
        XCTAssertEqual(encryptOutput.partials, ["\rWrote 0 B to empty.rfe   "])
        XCTAssertEqual(encryptFS.files["empty.rfe"], Data())

        let (decryptor, decryptOutput, _) = makeOperations(identity: identity,
                                                           files: ["empty.rfe": Data()])
        XCTAssertEqual(decryptor.decrypt(paths: ["empty.rfe"]), .ok)
        XCTAssertEqual(decryptOutput.partials, [])
    }

    // MARK: - -d / --decrypt

    func testDecryptRequiresTheRFEExtensionCaseSensitively() {
        let identity = Identity()
        let (operations, output, _) = makeOperations(identity: identity, files: ["doc.RFE": Data()])
        // Python uses a CASE-SENSITIVE endswith here, unlike validate's checks.
        XCTAssertEqual(operations.decrypt(paths: ["doc.RFE"]), .invalidFile)
        XCTAssertEqual(output.lines.first,
                       "The file doc.RFE does not appear to be a Reticulum encrypted file")
    }

    func testDecryptRejectsAnEmptyDerivedOutputName() {
        let identity = Identity()
        let (operations, output, _) = makeOperations(identity: identity)
        XCTAssertEqual(operations.decrypt(paths: [".rfe"]), .invalidFile)
        XCTAssertEqual(output.lines.first, "Invalid output filename")
    }

    func testDecryptRequiresAPrivateKey() throws {
        let identity = Identity()
        let publicOnly = try Identity(publicKeyBytes: identity.getPublicKey())
        let blob = try encryptedBlob(for: identity, plaintext: Data("x".utf8))
        let (operations, output, _) = makeOperations(identity: publicOnly, files: ["doc.rfe": blob])
        XCTAssertEqual(operations.decrypt(paths: ["doc.rfe"]), .noPrvKey)
        XCTAssertEqual(output.lines.first,
                       "Cannot decrypt \"doc.rfe\", the identity does not hold a private key")
    }

    func testDecryptWithTheWrongIdentity() throws {
        let alice = Identity()
        let bob = Identity()
        let blob = try encryptedBlob(for: alice, plaintext: Data("x".utf8))
        let (operations, output, _) = makeOperations(identity: bob, files: ["doc.rfe": blob])
        XCTAssertEqual(operations.decrypt(paths: ["doc.rfe"]), .decryptFailed)
        XCTAssertEqual(output.lines.first, "The provided identity could not decrypt the file")
    }

    // MARK: - Path-expansion asymmetry

    /// `-e`'s `-w` output path is used RAW (rnid.py:862) while `-d`'s IS expanded (:907).
    func testEncryptWriteIsUnexpandedButDecryptWriteIsExpanded() throws {
        let identity = Identity()

        var encryptOptions = RNIDApp.Options()
        encryptOptions.write = "~/out.rfe"
        let (encryptor, _, encryptFS) = makeOperations(identity: identity, options: encryptOptions,
                                                        files: ["doc.txt": Data("x".utf8)])
        XCTAssertEqual(encryptor.encrypt(paths: ["doc.txt"]), .ok)
        XCTAssertNotNil(encryptFS.files["~/out.rfe"])
        XCTAssertNil(encryptFS.files["/home/test/out.rfe"])

        var decryptOptions = RNIDApp.Options()
        decryptOptions.write = "~/out.bin"
        let blob = try encryptedBlob(for: identity, plaintext: Data("x".utf8))
        let (decryptor, _, decryptFS) = makeOperations(identity: identity, options: decryptOptions,
                                                        files: ["doc.rfe": blob])
        XCTAssertEqual(decryptor.decrypt(paths: ["doc.rfe"]), .ok)
        XCTAssertNotNil(decryptFS.files["/home/test/out.bin"])
        XCTAssertNil(decryptFS.files["~/out.bin"])
    }

    // MARK: - -w / --write

    func testWriteIdentityDefaultsToThePublicKeyWithAForcedSuffix() {
        let identity = Identity()
        let (operations, output, fileSystem) = makeOperations(identity: identity)
        XCTAssertEqual(operations.writeIdentity(path: "~/out", exportPrivate: false), .ok)
        XCTAssertEqual(fileSystem.files["/home/test/out.pub"], identity.getPublicKey())
        XCTAssertEqual(output.lines, ["Wrote public identity to /home/test/out.pub"])
    }

    /// The `.pub` check is case-INSENSITIVE, so no second suffix is appended.
    func testWriteIdentityDoesNotDoubleUpAnUppercaseSuffix() {
        let identity = Identity()
        let (operations, _, fileSystem) = makeOperations(identity: identity)
        XCTAssertEqual(operations.writeIdentity(path: "out.PUB", exportPrivate: false), .ok)
        XCTAssertNotNil(fileSystem.files["out.PUB"])
        XCTAssertNil(fileSystem.files["out.PUB.pub"])
    }

    func testWriteIdentityWithExportPrivateWritesTheRawBlob() throws {
        let identity = Identity()
        let (operations, output, fileSystem) = makeOperations(identity: identity)
        XCTAssertEqual(operations.writeIdentity(path: "out.rid", exportPrivate: true), .ok)
        XCTAssertEqual(fileSystem.files["out.rid"], identity.privateKeyBytes)
        XCTAssertEqual(output.lines, ["Wrote private identity to out.rid"])
    }

    func testWriteIdentityRefusesToOverwrite() {
        let identity = Identity()
        let (operations, output, _) = makeOperations(identity: identity,
                                                     files: ["out.rid": Data(count: 64)])
        XCTAssertEqual(operations.writeIdentity(path: "out.rid", exportPrivate: true), .fileExists)
        XCTAssertEqual(output.lines, ["File out.rid already exists, not overwriting"])
    }

    /// Python's `R_NO_PUBKEY` (3) and `R_NO_KEYS` (5) branches are structurally unreachable in
    /// Swift, because `Identity.publicKeyBytes` is non-optional — every Identity holds a
    /// public key. They are kept for source parity and deliberately have no test.
    func testEveryIdentityHoldsAPublicKey() throws {
        let publicOnly = try Identity(publicKeyBytes: Identity().getPublicKey())
        XCTAssertEqual(publicOnly.getPublicKey().count, 64)
    }
}
