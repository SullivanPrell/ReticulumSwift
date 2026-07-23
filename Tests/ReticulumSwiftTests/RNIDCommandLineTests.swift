import XCTest
@testable import ReticulumSwift

/// Tests for `rnid`'s command-line surface: flag spellings, `nargs` semantics,
/// `validate_args` and the generated help text.
///
/// Python reference: RNS/Utilities/rnid.py — the `argparse` block (:106-153) and
/// `validate_args` (:86-102).
final class RNIDCommandLineTests: XCTestCase {

    // MARK: - nargs="*"

    /// The empty-list quirk: Python's bare `-e` yields `[]`, which is *falsy*, so the
    /// operation is skipped entirely AND contributes nothing to `validate_args`' tally.
    func testBareVariadicFlagYieldsAnEmptyList() throws {
        let invocation = try RNIDCommandLine.parse(["-e"])
        XCTAssertEqual(invocation.encrypt, [])
        XCTAssertFalse(invocation.truthy(invocation.encrypt))
        XCTAssertFalse(invocation.operationRequiresIdentity)
    }

    func testAbsentVariadicFlagIsNil() throws {
        let invocation = try RNIDCommandLine.parse([])
        XCTAssertNil(invocation.encrypt)
        XCTAssertNil(invocation.decrypt)
        XCTAssertNil(invocation.validate)
        XCTAssertNil(invocation.sign)
    }

    func testVariadicCollectsUntilTheNextOption() throws {
        let invocation = try RNIDCommandLine.parse(["-e", "a.txt", "b.txt", "-f"])
        XCTAssertEqual(invocation.encrypt, ["a.txt", "b.txt"])
        XCTAssertTrue(invocation.force)
    }

    // MARK: - nargs="?"

    func testBareAnnounceUsesTheConst() throws {
        // Python: const=DEFAULT_ASPECTS
        let invocation = try RNIDCommandLine.parse(["-a"])
        XCTAssertEqual(invocation.announce, "rns.id")
    }

    func testAnnounceWithAnExplicitValue() throws {
        let invocation = try RNIDCommandLine.parse(["-a", "my.app.aspect"])
        XCTAssertEqual(invocation.announce, "my.app.aspect")
    }

    /// `-S` has const NO_MESSAGE (the int 1) in Python; here a bare `-S` records "provided
    /// with no value", which means "open $EDITOR".
    func testBareSignMessageIsProvidedWithNoValue() throws {
        let invocation = try RNIDCommandLine.parse(["-S"])
        XCTAssertNil(invocation.signMessage)
        XCTAssertTrue(invocation.signMessageProvided)
        XCTAssertTrue(invocation.signMessageTruthy)
    }

    /// `-S ""` stores the empty string, which is FALSY in Python.
    func testEmptySignMessageIsFalsy() throws {
        let invocation = try RNIDCommandLine.parse(["-S", ""])
        XCTAssertEqual(invocation.signMessage, "")
        XCTAssertFalse(invocation.signMessageTruthy)
    }

    /// Python: a bare `-E` yields the int NO_META and then crashes in `expanduser`.
    func testBareEmbedMetaIsFlagged() throws {
        let invocation = try RNIDCommandLine.parse(["-E"])
        XCTAssertTrue(invocation.embedMetaWithoutPath)
        XCTAssertNil(invocation.embedMeta)
        XCTAssertTrue(invocation.operationOptions.embedMetaWithoutPath)
    }

    /// `--meta-spec` has NO const, so a bare `--meta-spec` yields None in Python too.
    func testBareMetaSpecYieldsNoValue() throws {
        let invocation = try RNIDCommandLine.parse(["--meta-spec"])
        XCTAssertNil(invocation.metaSpec)
    }

    // MARK: - Defaults

    func testTimeoutDefaultsToPathRequestTimeout() throws {
        // Python: default=RNS.Transport.PATH_REQUEST_TIMEOUT
        XCTAssertEqual(try RNIDCommandLine.parse([]).timeout, Transport.pathRequestTimeout)
        XCTAssertEqual(try RNIDCommandLine.parse(["-t", "2.5"]).timeout, 2.5)
    }

    func testCountedVerbosityFlags() throws {
        let invocation = try RNIDCommandLine.parse(["-vvv", "-q"])
        XCTAssertEqual(invocation.verbose, 3)
        XCTAssertEqual(invocation.quiet, 1)
    }

    func testHiddenFlagsStillParse() throws {
        // Python declares -I/-O with help=argparse.SUPPRESS. -I is entirely dead; -O only
        // silences library logging.
        let invocation = try RNIDCommandLine.parse(["-O"])
        XCTAssertTrue(invocation.stdout)
    }

    // MARK: - op_requires_identity

    /// `args.hash` and `args.validate` are deliberately ABSENT from Python's
    /// `op_requires_identity`, which is why they are dispatched with `identity or
    /// args.identity` and must work with an unresolved bare hex string.
    func testHashAndValidateDoNotRequireAnIdentity() throws {
        XCTAssertFalse(try RNIDCommandLine.parse(["-H", "rns.id"]).operationRequiresIdentity)
        XCTAssertFalse(try RNIDCommandLine.parse(["-V", "a.txt"]).operationRequiresIdentity)
        XCTAssertTrue(try RNIDCommandLine.parse(["-s", "a.txt"]).operationRequiresIdentity)
        XCTAssertTrue(try RNIDCommandLine.parse(["-p"]).operationRequiresIdentity)
        XCTAssertTrue(try RNIDCommandLine.parse(["-w", "out"]).operationRequiresIdentity)
    }

    // MARK: - validate_args

    func testTwoOperationsAreRejected() throws {
        let invocation = try RNIDCommandLine.parse(["-e", "a.txt", "-s", "b.txt"])
        XCTAssertEqual(invocation.argumentValidation, .failed(
            "This utility currently only supports one of the encrypt, decrypt, sign or verify operations per invocation"))
    }

    /// A bare `-e` is falsy, so `rnid -e -s file` passes the tally.
    func testEmptyOperationListsDoNotCountTowardTheTally() throws {
        let invocation = try RNIDCommandLine.parse(["-e", "-s", "file"])
        XCTAssertEqual(invocation.argumentValidation, .ok)
    }

    func testIdentitySourceGroupIsMutuallyExclusive() throws {
        let invocation = try RNIDCommandLine.parse(["-i", "abc", "-g", "new.rid"])
        XCTAssertEqual(invocation.argumentValidation, .failed(
            "The -i, -g, -m and -M args are mutually exclusive"))
    }

    func testEncodingFlagsAreMutuallyExclusive() throws {
        let invocation = try RNIDCommandLine.parse(["-b", "-B"])
        // The message names "--hex" and "--base256" although the flags are -F and -U.
        XCTAssertEqual(invocation.argumentValidation, .failed(
            "The -b, -B, --hex and --base256 args are mutually exclusive"))
    }

    func testSingleFlagsFromEachGroupAreAccepted() throws {
        XCTAssertEqual(try RNIDCommandLine.parse(["-s", "a", "-b", "-i", "abc"]).argumentValidation, .ok)
    }

    // MARK: - Output format ladder

    func testOutputFormatLadderOrder() {
        // Python: base32 → base64 → base256 → hex → bin.
        XCTAssertEqual(RNIDApp.outputFormat(base32: true, base64: true, base256: true, hex: true), .base32)
        XCTAssertEqual(RNIDApp.outputFormat(base32: false, base64: true, base256: true, hex: true), .base64)
        XCTAssertEqual(RNIDApp.outputFormat(base32: false, base64: false, base256: true, hex: true), .base256)
        XCTAssertEqual(RNIDApp.outputFormat(base32: false, base64: false, base256: false, hex: true), .hex)
        XCTAssertEqual(RNIDApp.outputFormat(base32: false, base64: false, base256: false, hex: false), .bin)
    }

    // MARK: - Aspect splitting

    /// Pins Python's `str.split(".")` semantics, which PRESERVE empty components.
    func testSplitAspectsPreservesEmptyComponents() {
        XCTAssertEqual(RNIDApp.splitAspects("rns.id"), ["rns", "id"])
        XCTAssertEqual(RNIDApp.splitAspects("rns"), ["rns"])
        XCTAssertEqual(RNIDApp.splitAspects("rns."), ["rns", ""])
        XCTAssertEqual(RNIDApp.splitAspects("a..b"), ["a", "", "b"])
    }

    /// The existing library helper is explicitly the WRONG tool here — asserted so nobody
    /// refactors `-a`/`-H` back onto it.
    func testDestinationAppAndAspectsCollapsesEmptyComponents() {
        let collapsed = Destination.appAndAspects(fromFullName: "rns.")
        XCTAssertEqual(collapsed.appName, "rns")
        XCTAssertEqual(collapsed.aspects, [])
    }

    /// The two splitters therefore compute DIFFERENT destination hashes.
    func testEmptyAspectChangesTheDestinationHash() throws {
        let identityHash = Data(repeating: 0x01, count: 16)
        let withEmpty = try XCTUnwrap(RNIDDestinationHash.hash(fromFullName: "rns.",
                                                                identityHash: identityHash))
        let without = try XCTUnwrap(RNIDDestinationHash.hash(identityHash: identityHash,
                                                              appName: "rns", aspects: []))
        XCTAssertNotEqual(withEmpty, without)
    }

    func testDestinationHashRejectsAWrongLengthIdentityHash() {
        // Python raises TypeError("Invalid material supplied for destination hash calculation").
        XCTAssertNil(RNIDDestinationHash.hash(identityHash: Data(count: 8), appName: "rns", aspects: ["id"]))
    }

    /// The raw-bytes form must agree with the Identity form for the same identity.
    func testDestinationHashMatchesTheIdentityOverload() {
        let identity = Identity()
        XCTAssertEqual(RNIDDestinationHash.hash(identityHash: identity.hash,
                                                appName: "rns", aspects: ["id"]),
                       Destination.hash(identity: identity, appName: "rns", aspects: ["id"]))
    }

    // MARK: - Help text

    func testVersionText() {
        XCTAssertEqual(RNIDCommandLine.versionText, "rnid \(Reticulum.version)")
    }

    /// The exact usage block the installed Python `rnid --help` prints at 80 columns.
    func testUsageBlockMatchesArgparse() {
        let expected = """
        usage: rnid [-h] [--config path] [-i rid] [-g path] [-m rid] [-M rid] [-x]
                    [-X] [-v] [-q] [-a [aspects]] [-H aspects] [-d [file ...]]
                    [-e [file ...]] [-V [path ...]] [-s [path ...]] [-S [text]]
                    [-E [path]] [--meta-spec [path]] [--raw] [-w path] [-r path] [-f]
                    [-R] [-N] [-t seconds] [-p] [-P] [-B] [-b] [-U] [-F] [--meta]
                    [--version]
        """
        XCTAssertTrue(RNIDCommandLine.helpText.hasPrefix(expected),
                      "usage block did not match:\n" + RNIDCommandLine.helpText)
    }

    /// Spot-checks the three layout rules that are easy to get wrong: the 24-column help
    /// position, the wrap-to-next-line rule for long invocations, and metavar repetition.
    func testOptionListLayout() {
        let lines = RNIDCommandLine.helpText.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        XCTAssertTrue(lines.contains("  -h, --help            show this help message and exit"))
        XCTAssertTrue(lines.contains("  --config path         path to alternative Reticulum config directory"))
        // 22 characters > the 20-character action width, so the help starts on the next line.
        XCTAssertTrue(lines.contains("  -i rid, --identity rid"))
        XCTAssertTrue(lines.contains("                        hexadecimal Reticulum identity or destination hash, or"))
        XCTAssertTrue(lines.contains("                        path to Identity file"))
        // Exactly 20 characters, so it stays on one line.
        XCTAssertTrue(lines.contains("  -r path, --read path  input file path for operations with optional file"))
        XCTAssertTrue(lines.contains("  -t seconds            identity request timeout before giving up"))
        XCTAssertTrue(lines.contains("  -a [aspects], --announce [aspects]"))
        XCTAssertTrue(lines.contains("  -d [file ...], --decrypt [file ...]"))
    }

    func testSuppressedFlagsAreAbsentFromHelp() {
        // Python: help=argparse.SUPPRESS hides -I/-O from both usage and the option list.
        XCTAssertFalse(RNIDCommandLine.helpText.contains("--stdin"))
        XCTAssertFalse(RNIDCommandLine.helpText.contains("--stdout"))
        XCTAssertFalse(RNIDCommandLine.helpText.contains("[-I]"))
        XCTAssertFalse(RNIDCommandLine.helpText.contains("[-O]"))
    }

    func testDescriptionSitsBetweenUsageAndOptions() {
        XCTAssertTrue(RNIDCommandLine.helpText.contains(
            "\n\nReticulum Identity & Encryption Utility\n\noptions:\n"))
    }
}
