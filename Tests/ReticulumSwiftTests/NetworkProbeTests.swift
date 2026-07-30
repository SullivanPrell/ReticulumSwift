import XCTest
import CryptoKit
@testable import ReticulumSwift

/// Tests for NetworkProbe constants and API.
/// Python reference: RNS/Utilities/rnprobe.py

final class NetworkProbeTests: XCTestCase {

    // MARK: - Constants

    func testDefaultProbeSize() {
        // Python: DEFAULT_PROBE_SIZE = 16
        XCTAssertEqual(NetworkProbe.defaultProbeSize, 16)
    }

    func testDefaultTimeout() {
        // Python: DEFAULT_TIMEOUT = 12
        XCTAssertEqual(NetworkProbe.defaultTimeout, 12)
    }

    func testAppName() {
        // rnprobe doesn't declare an APP_NAME but the utility is called "rnprobe"
        XCTAssertEqual(NetworkProbe.appName, "rnprobe")
    }

    // MARK: - Instantiation

    func testCanInstantiateWithTransport() {
        let t = Transport()
        let probe = NetworkProbe(transport: t)
        XCTAssertNotNil(probe)
    }

    func testDefaultSizeIsConfigurable() {
        let t = Transport()
        let probe = NetworkProbe(transport: t, defaultSize: 64)
        XCTAssertEqual(probe.size, 64)
    }

    func testDefaultSizeDefaultsToClass() {
        let t = Transport()
        let probe = NetworkProbe(transport: t)
        XCTAssertEqual(probe.size, NetworkProbe.defaultProbeSize)
    }

    func testDefaultTimeoutIsConfigurable() {
        let t = Transport()
        let probe = NetworkProbe(transport: t, timeout: 30)
        XCTAssertEqual(probe.timeout, 30)
    }

    func testDefaultTimeoutDefaultsToClass() {
        let t = Transport()
        let probe = NetworkProbe(transport: t)
        XCTAssertEqual(probe.timeout, NetworkProbe.defaultTimeout)
    }

    // MARK: - Terminal-control constants

    func testSpinnerGlyphs() {
        // Python: syms = "⢄⢂⢁⡁⡈⡐⡠" (rnprobe.py:86) — seven code points.
        XCTAssertEqual(NetworkProbe.spinnerGlyphs.count, 7)
        let scalars = NetworkProbe.spinnerGlyphs.map { $0.unicodeScalars.first!.value }
        // Verified with ord() against the Python source; guards against a copy-paste of
        // U+28A0 for the last glyph.
        XCTAssertEqual(scalars, [0x2884, 0x2882, 0x2881, 0x2841, 0x2848, 0x2850, 0x2860])
    }

    func testEraseWidths() {
        // Python: rnprobe.py:94 and :197 both hold a 58-space run …
        XCTAssertEqual(NetworkProbe.shortEraseWidth, 58,
                       "rnprobe.py:94 and :197 erase 58 columns")
        // … while rnprobe.py:143 holds 64. The discrepancy is Python's, and reproduced.
        XCTAssertEqual(NetworkProbe.longEraseWidth, 64,
                       "rnprobe.py:143 erases 64 columns")
    }

    func testPollInterval() {
        // Python: time.sleep(0.1) in both wait loops (rnprobe.py:88, 137)
        XCTAssertEqual(NetworkProbe.pollInterval, 0.1)
    }

    func testDestinationHexLength() {
        // Python: dest_len = (TRUNCATED_HASHLENGTH//8)*2 = 32 (rnprobe.py:58)
        XCTAssertEqual(NetworkProbe.destinationHexLength, 32)
    }

    func testExitCodeValues() {
        // Python: bare exit() / exit(1) / exit(2) / exit(3)
        XCTAssertEqual(NetworkProbe.Result.ok.rawValue, 0)
        XCTAssertEqual(NetworkProbe.Result.pathTimeout.rawValue, 1)
        XCTAssertEqual(NetworkProbe.Result.packetLoss.rawValue, 2)
        XCTAssertEqual(NetworkProbe.Result.mtuExceeded.rawValue, 3)
    }
}

// MARK: - Validation

/// Python reference: rnprobe.py:44-67 — everything before the Reticulum instance exists.
final class NetworkProbeValidationTests: XCTestCase {

    func testMissingFullNameMessage() {
        // Python: rnprobe.py:47
        XCTAssertEqual(NetworkProbe.ValidationError.missingFullName.message,
                       "The full destination name including application name aspects must be specified for the destination")
    }

    func testHashLengthMessage() {
        // Python: rnprobe.py:60, with dest_len and dest_len//2 interpolated.
        XCTAssertEqual(NetworkProbe.ValidationError.badHashLength.message,
                       "Destination length is invalid, must be 32 hexadecimal characters (16 bytes).")
    }

    func testHashHexMessage() {
        // Python: rnprobe.py:64
        XCTAssertEqual(NetworkProbe.ValidationError.badHashHex.message,
                       "Invalid destination entered. Check your input.")
    }

    func testShortHashRejected() {
        // Python: len(destination_hexhash) != dest_len → ValueError (rnprobe.py:59)
        XCTAssertThrowsError(try NetworkProbe.parseDestinationHash(String(repeating: "a", count: 31))) {
            XCTAssertEqual($0 as? NetworkProbe.ValidationError, .badHashLength)
        }
    }

    func testLongHashRejected() {
        XCTAssertThrowsError(try NetworkProbe.parseDestinationHash(String(repeating: "a", count: 33))) {
            XCTAssertEqual($0 as? NetworkProbe.ValidationError, .badHashLength)
        }
    }

    func testEmptyHashRejected() {
        XCTAssertThrowsError(try NetworkProbe.parseDestinationHash("")) {
            XCTAssertEqual($0 as? NetworkProbe.ValidationError, .badHashLength)
        }
    }

    func testNonHexRejected() {
        // Python: bytes.fromhex raises → re-raised as the "Invalid destination" ValueError.
        XCTAssertThrowsError(try NetworkProbe.parseDestinationHash("g1b2c3d4e5f60718293a4b5c6d7e8f90")) {
            XCTAssertEqual($0 as? NetworkProbe.ValidationError, .badHashHex)
        }
    }

    func testValidHashParsed() throws {
        let hex = "a1b2c3d4e5f60718293a4b5c6d7e8f90"
        let data = try NetworkProbe.parseDestinationHash(hex)
        XCTAssertEqual(data.count, 16)
        XCTAssertEqual(data.map { String(format: "%02x", $0) }.joined(), hex)
    }

    func testHashParseIsCaseInsensitive() throws {
        // Python: bytes.fromhex accepts upper case.
        let lower = try NetworkProbe.parseDestinationHash("a1b2c3d4e5f60718293a4b5c6d7e8f90")
        let upper = try NetworkProbe.parseDestinationHash("A1B2C3D4E5F60718293A4B5C6D7E8F90")
        XCTAssertEqual(lower, upper)
    }

    // MARK: app_and_aspects_from_name

    func testAppAndAspectsSimple() {
        let (app, aspects) = NetworkProbe.appAndAspects(fromFullName: "lxmf.delivery")
        XCTAssertEqual(app, "lxmf")
        XCTAssertEqual(aspects, ["delivery"])
    }

    func testAppAndAspectsTransportProbe() {
        let (app, aspects) = NetworkProbe.appAndAspects(fromFullName: "rnstransport.probe")
        XCTAssertEqual(app, "rnstransport")
        XCTAssertEqual(aspects, ["probe"])
    }

    func testAppAndAspectsDeep() {
        let (app, aspects) = NetworkProbe.appAndAspects(fromFullName: "a.b.c.d")
        XCTAssertEqual(app, "a")
        XCTAssertEqual(aspects, ["b", "c", "d"])
    }

    func testAppAndAspectsNoAspects() {
        let (app, aspects) = NetworkProbe.appAndAspects(fromFullName: "lxmf")
        XCTAssertEqual(app, "lxmf")
        XCTAssertEqual(aspects, [])
    }

    func testAppAndAspectsEmptyString() {
        // Python: "".split(".") == [""] → ("", [])
        let (app, aspects) = NetworkProbe.appAndAspects(fromFullName: "")
        XCTAssertEqual(app, "")
        XCTAssertEqual(aspects, [])
    }

    func testAppAndAspectsKeepsEmptyComponents() {
        // Python (verified in the interpreter):
        //   'lxmf..delivery'.split('.') == ['lxmf', '', 'delivery']
        let (app, aspects) = NetworkProbe.appAndAspects(fromFullName: "lxmf..delivery")
        XCTAssertEqual(app, "lxmf")
        XCTAssertEqual(aspects, ["", "delivery"])
    }

    func testAppAndAspectsKeepsTrailingEmptyComponent() {
        // Python: 'lxmf.'.split('.') == ['lxmf', '']
        let (app, aspects) = NetworkProbe.appAndAspects(fromFullName: "lxmf.")
        XCTAssertEqual(app, "lxmf")
        XCTAssertEqual(aspects, [""])
    }

    func testValidateRunsBeforeAnyStack() {
        // Python: rnprobe.py:45-67 all executes before RNS.Reticulum(...) at :77, so these
        // are answerable with no network and no config directory.
        XCTAssertEqual(NetworkProbe.validate(options: NetworkProbe.Options()), .missingFullName)
        XCTAssertEqual(NetworkProbe.validate(options: NetworkProbe.Options(
            fullName: "lxmf.delivery", destinationHexhash: "aabb")), .badHashLength)
        XCTAssertEqual(NetworkProbe.validate(options: NetworkProbe.Options(
            fullName: "lxmf.delivery",
            destinationHexhash: String(repeating: "g", count: 32))), .badHashHex)
        XCTAssertNil(NetworkProbe.validate(options: NetworkProbe.Options(
            fullName: "lxmf.delivery",
            destinationHexhash: "a1b2c3d4e5f60718293a4b5c6d7e8f90")))
    }

    func testDestinationHelperGenuinelyDiffers() {
        // Paired negative assertion: Destination.appAndAspects DROPS empty components, so
        // reusing it would change the name hash and therefore the destination hash. If
        // someone "fixes" Destination this fails loudly, and the probe's own splitter can
        // then be retired deliberately rather than by accident.
        let (_, libraryAspects) = Destination.appAndAspects(fromFullName: "lxmf..delivery")
        XCTAssertEqual(libraryAspects, ["delivery"])
        let (_, probeAspects) = NetworkProbe.appAndAspects(fromFullName: "lxmf..delivery")
        XCTAssertNotEqual(libraryAspects, probeAspects)
    }
}

// MARK: - Formatting

/// Python reference: rnprobe.py:157-163 and :201-202. Every golden value below came from
/// CPython and must not be regenerated from the Swift implementation.
final class NetworkProbeFormattingTests: XCTestCase {

    func testPythonFloatStringKeepsOneFractionalDigit() {
        // Python str(float) is the shortest round-trip repr, never zero-padded, and always
        // keeps at least one fractional digit. String(format: "%.3f") would print "0.500".
        XCTAssertEqual(NetworkProbe.pythonFloatString(0.5), "0.5")
        XCTAssertEqual(NetworkProbe.pythonFloatString(1000.0), "1000.0")
        XCTAssertEqual(NetworkProbe.pythonFloatString(0.0), "0.0")
        XCTAssertEqual(NetworkProbe.pythonFloatString(123.457), "123.457")
        XCTAssertEqual(NetworkProbe.pythonFloatString(66.67), "66.67")
        XCTAssertEqual(NetworkProbe.pythonFloatString(100.0), "100.0")
        XCTAssertEqual(NetworkProbe.pythonFloatString(-2.5), "-2.5")
        XCTAssertEqual(NetworkProbe.pythonFloatString(-2.0), "-2.0")
        XCTAssertEqual(NetworkProbe.pythonFloatString(28.57), "28.57")
    }

    func testPythonIntString() {
        XCTAssertEqual(NetworkProbe.pythonIntString(-73), "-73")
        XCTAssertEqual(NetworkProbe.pythonIntString(0), "0")
    }

    func testPythonScalarStringPreservesIntFloatDistinction() {
        // The guard against RPCClient's asDouble-coercing helpers: a Python daemon returns
        // RSSI as an int (RNodeInterface.py:878) and SNR/quality as floats (:880, :890).
        XCTAssertEqual(NetworkProbe.pythonScalarString(.int(-73)), "-73")
        XCTAssertEqual(NetworkProbe.pythonScalarString(.int(0)), "0")
        XCTAssertEqual(NetworkProbe.pythonScalarString(.uint(73)), "73")
        XCTAssertEqual(NetworkProbe.pythonScalarString(.double(-2.5)), "-2.5")
        XCTAssertEqual(NetworkProbe.pythonScalarString(.double(-2.0)), "-2.0")
        XCTAssertEqual(NetworkProbe.pythonScalarString(.double(100.0)), "100.0")
        XCTAssertNil(NetworkProbe.pythonScalarString(.nil))
        XCTAssertNil(NetworkProbe.pythonScalarString(.string("x")))
    }

    func testRttString() {
        // Python: rnprobe.py:157-163, boundary at rtt >= 1.
        XCTAssertEqual(NetworkProbe.rttString(1.5), "1.5 seconds")
        XCTAssertEqual(NetworkProbe.rttString(1.0), "1.0 seconds")
        XCTAssertEqual(NetworkProbe.rttString(0.999), "999.0 milliseconds")
        XCTAssertEqual(NetworkProbe.rttString(0.0123456), "12.346 milliseconds")
        XCTAssertEqual(NetworkProbe.rttString(0.0005), "0.5 milliseconds")
        XCTAssertEqual(NetworkProbe.rttString(0.0875), "87.5 milliseconds")
    }

    func testLossValues() {
        // Python: loss = round((1-(replies/sent))*100, 2), rendered with str().
        func loss(_ sent: Int, _ replies: Int) -> String {
            NetworkProbe.pythonFloatString(
                NetworkProbe.pythonRound((1 - Double(replies) / Double(sent)) * 100, 2))
        }
        XCTAssertEqual(loss(1, 1), "0.0")
        XCTAssertEqual(loss(3, 2), "33.33")
        XCTAssertEqual(loss(4, 3), "25.0")
        XCTAssertEqual(loss(1, 0), "100.0")
        XCTAssertEqual(loss(7, 5), "28.57")
    }

    func testVerbosityMapping() {
        // Python: rnprobe.py:69-77 — both branches decrement, so loglevel = 3+(count-1).
        let expected: [(Int, Bool, Reticulum.LogLevel)] = [
            (0, false, .warning), (1, true, .notice), (2, true, .info),
            (3, true, .verbose), (4, true, .debug), (5, true, .pathing), (6, true, .extreme)
        ]
        for (verbosity, moreOutput, level) in expected {
            let options = NetworkProbe.Options(verbosity: verbosity)
            XCTAssertEqual(options.moreOutput, moreOutput, "verbosity \(verbosity)")
            XCTAssertEqual(options.logLevel, level, "verbosity \(verbosity)")
        }
    }

    func testVerbosityClampsToExtreme() {
        // A bare LogLevel(rawValue:) ?? .warning would make -vvvvvvv QUIETER than -vvvvvv,
        // because raw value 9 is out of range (LogLevel tops out at .extreme = 8).
        XCTAssertEqual(NetworkProbe.Options(verbosity: 7).logLevel, .extreme)
        XCTAssertEqual(NetworkProbe.Options(verbosity: 20).logLevel, .extreme)
    }

    func testEffectiveTimeoutPrecedence() {
        // Python: `timeout or DEFAULT_TIMEOUT + fht` parenthesises as
        // `timeout or (12 + fht)`, and 0/0.0 are falsy.
        XCTAssertEqual(NetworkProbe.effectiveTimeout(nil, firstHopTimeout: 6), 18)
        XCTAssertEqual(NetworkProbe.effectiveTimeout(0, firstHopTimeout: 6), 18)
        XCTAssertEqual(NetworkProbe.effectiveTimeout(4, firstHopTimeout: 6), 4)
        // A negative -t yields a deadline in the past: reproduced, not guarded.
        XCTAssertEqual(NetworkProbe.effectiveTimeout(-5, firstHopTimeout: 6), -5)
    }
}

// MARK: - Argument parsing

/// Python reference: rnprobe.py:209-249. Every expected string below was captured from the
/// installed Python `rnprobe` (RNS 1.4.0) on this machine.
final class NetworkProbeArgumentTests: XCTestCase {

    /// Byte-for-byte capture of `rnprobe --help`.
    private let expectedHelp = """
    usage: rnprobe [-h] [--config CONFIG] [-s SIZE] [-n PROBES] [-t seconds]
                   [-w seconds] [--version] [-v]
                   [full_name] [destination_hash]

    Reticulum Probe Utility

    positional arguments:
      full_name             full destination name in dotted notation
      destination_hash      hexadecimal hash of the destination

    options:
      -h, --help            show this help message and exit
      --config CONFIG       path to alternative Reticulum config directory
      -s SIZE, --size SIZE  size of probe packet payload in bytes
      -n PROBES, --probes PROBES
                            number of probes to send
      -t seconds, --timeout seconds
                            timeout before giving up
      -w seconds, --wait seconds
                            time between each probe
      --version             show program's version number and exit
      -v, --verbose

    """

    private let destHash = "a1b2c3d4e5f60718293a4b5c6d7e8f90"

    func testHelpTextIsByteExact() {
        XCTAssertEqual(NetworkProbe.Arguments.helpText, expectedHelp)
    }

    func testUsageTextIsByteExact() {
        XCTAssertEqual(NetworkProbe.Arguments.usageText, """
        usage: rnprobe [-h] [--config CONFIG] [-s SIZE] [-n PROBES] [-t seconds]
                       [-w seconds] [--version] [-v]
                       [full_name] [destination_hash]

        """)
    }

    func testUsageErrorText() {
        XCTAssertEqual(NetworkProbe.Arguments.usageErrorText("unrecognized arguments: --bogus"),
                       NetworkProbe.Arguments.usageText
                       + "rnprobe: error: unrecognized arguments: --bogus\n")
    }

    func testNoArgumentsPrintsHelp() {
        // Python: `if not args.destination_hash:` (rnprobe.py:231). Both positionals are
        // nargs='?', so an empty command line lands here.
        XCTAssertEqual(NetworkProbe.Arguments.parse(["rnprobe"]), .missingDestination)
    }

    func testSinglePositionalPrintsHelp() {
        // One positional binds to full_name; destination_hash stays nil.
        XCTAssertEqual(NetworkProbe.Arguments.parse(["rnprobe", "lxmf.delivery"]),
                       .missingDestination)
    }

    func testEmptyHashPrintsHelp() {
        // Python uses a FALSINESS test, so an explicitly empty hash takes the help path.
        XCTAssertEqual(NetworkProbe.Arguments.parse(["rnprobe", "lxmf.delivery", ""]),
                       .missingDestination)
    }

    func testHelpFlags() {
        XCTAssertEqual(NetworkProbe.Arguments.parse(["rnprobe", "-h"]), .help)
        XCTAssertEqual(NetworkProbe.Arguments.parse(["rnprobe", "--help"]), .help)
    }

    func testVersionFlag() {
        XCTAssertEqual(NetworkProbe.Arguments.parse(["rnprobe", "--version"]), .version)
    }

    func testFullInvocationShortSpellings() {
        let action = NetworkProbe.Arguments.parse([
            "rnprobe", "-s", "32", "-n", "3", "-t", "5.5", "-w", "0.25", "-vv",
            "--config", "/tmp/rc", "lxmf.delivery", destHash
        ])
        guard case .run(let options) = action else { return XCTFail("expected .run, got \(action)") }
        XCTAssertEqual(options.size, 32)
        XCTAssertEqual(options.probes, 3)
        XCTAssertEqual(options.timeout, 5.5)
        XCTAssertEqual(options.wait, 0.25)
        XCTAssertEqual(options.verbosity, 2)
        XCTAssertEqual(options.configDir, URL(fileURLWithPath: "/tmp/rc"))
        XCTAssertEqual(options.fullName, "lxmf.delivery")
        XCTAssertEqual(options.destinationHexhash, destHash)
    }

    func testLongSpellingsParseIdentically() {
        let short = NetworkProbe.Arguments.parse([
            "rnprobe", "-s", "32", "-n", "3", "-t", "5.5", "-w", "0.25", "-v",
            "lxmf.delivery", destHash
        ])
        let long = NetworkProbe.Arguments.parse([
            "rnprobe", "--size", "32", "--probes", "3", "--timeout", "5.5",
            "--wait", "0.25", "--verbose", "lxmf.delivery", destHash
        ])
        XCTAssertEqual(short, long)
    }

    func testInlineValueParses() {
        let action = NetworkProbe.Arguments.parse(["rnprobe", "--size=32", "lxmf.delivery", destHash])
        guard case .run(let options) = action else { return XCTFail("expected .run") }
        XCTAssertEqual(options.size, 32)
    }

    func testRepeatedAndBundledVerboseAgree() {
        let bundled = NetworkProbe.Arguments.parse(["rnprobe", "-vv", "lxmf.delivery", destHash])
        let repeated = NetworkProbe.Arguments.parse(["rnprobe", "-v", "-v", "lxmf.delivery", destHash])
        XCTAssertEqual(bundled, repeated)
        guard case .run(let options) = bundled else { return XCTFail("expected .run") }
        XCTAssertEqual(options.verbosity, 2)
    }

    func testEmptyConfigCollapsesToNil() {
        // Python: `if args.config:` is a truthiness test.
        let action = NetworkProbe.Arguments.parse(["rnprobe", "--config", "", "lxmf.delivery", destHash])
        guard case .run(let options) = action else { return XCTFail("expected .run") }
        XCTAssertNil(options.configDir)
    }

    func testSizeZeroAccepted() {
        // Python: os.urandom(0) returns b"" and the probe is legal.
        let action = NetworkProbe.Arguments.parse(["rnprobe", "-s", "0", "lxmf.delivery", destHash])
        guard case .run(let options) = action else { return XCTFail("expected .run") }
        XCTAssertEqual(options.size, 0)
    }

    // MARK: usage errors

    private func usageErrorDetail(_ argv: [String]) -> String? {
        guard case .usageError(let detail) = NetworkProbe.Arguments.parse(argv) else { return nil }
        return detail
    }

    func testInvalidIntValue() {
        XCTAssertEqual(usageErrorDetail(["rnprobe", "-s", "x", "lxmf.delivery", destHash]),
                       "argument -s/--size: invalid int value: 'x'")
    }

    func testUnrecognisedOptionIsPlural() {
        // argparse says "unrecognized arguments" (plural) even for one token; the house
        // ArgumentError.description says "unrecognized argument" and is deliberately unused.
        XCTAssertEqual(usageErrorDetail(["rnprobe", "--bogus"]),
                       "unrecognized arguments: --bogus")
    }

    func testExtraPositional() {
        XCTAssertEqual(usageErrorDetail(["rnprobe", "a", "b", "c"]),
                       "unrecognized arguments: c")
    }

    func testMissingOptionValue() {
        XCTAssertEqual(usageErrorDetail(["rnprobe", "-t"]),
                       "argument -t/--timeout: expected one argument")
    }

    func testProbeCountGuards() {
        // Swift-only: Python's `while probes:` raises ZeroDivisionError on 0 and loops
        // forever on a negative count.
        XCTAssertEqual(usageErrorDetail(["rnprobe", "-n", "0", "lxmf.delivery", destHash]),
                       "argument -n/--probes: must be at least 1")
        XCTAssertEqual(usageErrorDetail(["rnprobe", "-n", "-1", "lxmf.delivery", destHash]),
                       "argument -n/--probes: must be at least 1")
    }

    func testNegativeSizeGuard() {
        // Swift-only: os.urandom raises ValueError (not OSError), escaping rnprobe's
        // `except OSError` as a traceback.
        XCTAssertEqual(usageErrorDetail(["rnprobe", "-s", "-1", "lxmf.delivery", destHash]),
                       "argument -s/--size: must not be negative")
    }

    func testNegativeWaitGuard() {
        // Swift-only: time.sleep(negative) raises ValueError.
        XCTAssertEqual(usageErrorDetail(["rnprobe", "-w", "-1", "lxmf.delivery", destHash]),
                       "argument -w/--wait: must not be negative")
    }
}

// MARK: - run()

/// Python reference: rnprobe.py:44-206 — the whole of `program_setup`, byte for byte.
final class NetworkProbeRunTests: XCTestCase {

    /// A destination hash that really is the hash of ("lxmf", ["delivery"]) for `identity`,
    /// so the constructed and typed hashes agree and both printed hashes match.
    private func fixture() -> (identity: Identity, hex: String, pretty: String) {
        let identity = Identity()
        let hash = Destination.hash(identity: identity, appName: "lxmf", aspects: ["delivery"])
        return (identity,
                hash.map { String(format: "%02x", $0) }.joined(),
                RNSUtilities.prettyhexrep(hash))
    }

    private func makeProbe(_ network: MockProbeNetwork,
                           clock: MockProbeClock = MockProbeClock(),
                           entropy: MockProbeEntropy = MockProbeEntropy())
    -> (probe: NetworkProbe, output: CapturingProbeOutput,
        clock: MockProbeClock, entropy: MockProbeEntropy) {
        let output = CapturingProbeOutput()
        let probe = NetworkProbe(network: network, clock: clock, entropy: entropy, output: output)
        return (probe, output, clock, entropy)
    }

    private func options(_ hex: String,
                         size: Int? = nil,
                         probes: Int = 1,
                         wait: TimeInterval = 0,
                         verbosity: Int = 0) -> NetworkProbe.Options {
        NetworkProbe.Options(fullName: "lxmf.delivery", destinationHexhash: hex,
                             size: size, probes: probes, wait: wait, verbosity: verbosity)
    }

    // MARK: validation short-circuits

    func testMissingFullNamePrintsAndExitsZero() {
        let harness = makeProbe(MockProbeNetwork())
        let result = harness.probe.run(options: NetworkProbe.Options())
        XCTAssertEqual(result, .ok)   // Python: a bare exit()
        XCTAssertEqual(harness.output.stdout,
                       "The full destination name including application name aspects must be specified for the destination\n")
        XCTAssertEqual(harness.output.stderr, "")
    }

    func testBadHashPrintsAndExitsZero() {
        let harness = makeProbe(MockProbeNetwork())
        let result = harness.probe.run(options: options("aabb"))
        XCTAssertEqual(result, .ok)
        XCTAssertEqual(harness.output.stdout,
                       "Destination length is invalid, must be 32 hexadecimal characters (16 bytes).\n")
    }

    // MARK: happy path

    func testDeliveredProbeByteStream() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.0875)
        let harness = makeProbe(network)

        let result = harness.probe.run(options: options(f.hex))
        XCTAssertEqual(result, .ok)
        XCTAssertEqual(harness.output.stdout,
            "\rSent probe 1 (16 bytes) to \(f.pretty)   "
            + "\u{08}\u{08} \n"
            + "Valid reply from \(f.pretty)\nRound-trip time is 87.5 milliseconds over 1 hop\n\n"
            + "Sent 1, received 1, packet loss 0.0%\n")
        XCTAssertEqual(harness.output.stderr, "")
        XCTAssertEqual(harness.probe.outcomes.map(\.conclusion), [.delivered])
        XCTAssertFalse(harness.probe.outcomes[0].destinationHashMismatch)
    }

    // MARK: path phase

    func testPathRequestAndSpinner() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        // has_path is consulted once before the request, then once per loop iteration.
        network.pathAvailability = [false, false, false, false, true]
        network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        let harness = makeProbe(network)

        _ = harness.probe.run(options: options(f.hex))

        XCTAssertEqual(network.requestPathCalls, 1)
        let expectedPrefix = "Path to \(f.pretty) requested   "        // three trailing spaces
            + "\u{08}\u{08}\u{2884} \u{08}\u{08}\u{2882} \u{08}\u{08}\u{2881} "
        XCTAssertTrue(harness.output.stdout.hasPrefix(expectedPrefix),
                      "got: \(harness.output.stdout.debugDescription)")
        // Python sleeps BEFORE emitting each frame (rnprobe.py:88-89).
        XCTAssertEqual(harness.clock.sleeps, [0.1, 0.1, 0.1])
    }

    func testNoPathRequestWhenPathKnown() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        let harness = makeProbe(network)
        _ = harness.probe.run(options: options(f.hex))
        XCTAssertEqual(network.requestPathCalls, 0)
        XCTAssertFalse(harness.output.stdout.contains("Path to"))
    }

    func testPathTimeout() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.defaultHasPath = false
        let clock = MockProbeClock()
        clock.advancePerSleep = 10          // the deadline is now + 18, so two sleeps clear it
        let harness = makeProbe(network, clock: clock)

        let result = harness.probe.run(options: options(f.hex))
        XCTAssertEqual(result, .pathTimeout)
        XCTAssertTrue(harness.output.stdout.hasSuffix(
            "\r" + String(repeating: " ", count: 58) + "\rPath request timed out\n"))
        XCTAssertFalse(harness.output.stdout.contains("Sent probe"))
        XCTAssertEqual(network.transmitCalls, 0)
    }

    func testFirstHopTimeoutQueriedPerProbe() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        let harness = makeProbe(network)
        _ = harness.probe.run(options: options(f.hex, probes: 3))
        // Python: rnprobe.py:84 once for the path deadline, then :134 once per probe.
        XCTAssertEqual(network.firstHopTimeoutCalls, 4)
    }

    // MARK: MTU

    func testMtuErrorExitsThree() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.transmitError = NetworkProbe.SendError.mtuExceeded(size: 515)
        let harness = makeProbe(network)

        let result = harness.probe.run(options: options(f.hex, size: 400))
        XCTAssertEqual(result, .mtuExceeded)
        // Note "exceed", not "exceeds" — rnprobe's own wording, not the exception's.
        XCTAssertEqual(harness.output.stdout,
                       "Error: Probe packet size of 515 bytes exceed MTU of 500 bytes\n")
        XCTAssertFalse(harness.output.stdout.contains("Sent probe"))
        XCTAssertFalse(harness.output.stdout.contains("packet loss"))
    }

    // MARK: probe conclusions

    func testDeadlineExceededUses64Spaces() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.receipt = FakeProbeReceipt(status: .sent, rtt: nil)
        let clock = MockProbeClock()
        clock.advancePerSleep = 10
        let harness = makeProbe(network, clock: clock)

        let result = harness.probe.run(options: options(f.hex))
        XCTAssertEqual(result, .packetLoss)
        XCTAssertTrue(harness.output.stdout.contains(
            "\r" + String(repeating: " ", count: 64) + "\rProbe timed out\n"))
        // The deadline branch emits no \b\b spinner-clear line.
        XCTAssertFalse(harness.output.stdout.contains("\u{08}\u{08} \n"))
        XCTAssertTrue(harness.output.stdout.hasSuffix("Sent 1, received 0, packet loss 100.0%\n"))
        XCTAssertEqual(harness.probe.outcomes.map(\.conclusion), [.deadlineExceeded])
    }

    func testReceiptFailedUses58Spaces() {
        for status in [PacketReceipt.Status.failed, .culled] {
            let f = fixture()
            let network = MockProbeNetwork()
            network.identity = f.identity
            network.receipt = FakeProbeReceipt(status: status, rtt: nil)
            let harness = makeProbe(network)

            let result = harness.probe.run(options: options(f.hex))
            XCTAssertEqual(result, .packetLoss, "\(status)")
            // The clear line comes FIRST, then the 58-space variant.
            XCTAssertTrue(harness.output.stdout.contains(
                "\u{08}\u{08} \n\r" + String(repeating: " ", count: 58) + "\rProbe timed out\n"),
                "\(status): \(harness.output.stdout.debugDescription)")
            XCTAssertEqual(harness.probe.outcomes.map(\.conclusion), [.receiptFailed])
        }
    }

    // MARK: repeats

    func testRepeatProbesAndWait() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        let harness = makeProbe(network)

        let result = harness.probe.run(options: options(f.hex, probes: 3, wait: 0.5))
        XCTAssertEqual(result, .ok)
        for index in 1...3 {
            XCTAssertTrue(harness.output.stdout.contains("Sent probe \(index) (16 bytes) to "))
        }
        // Python: `if sent > 0: time.sleep(wait)` — N probes incur (N-1) waits.
        XCTAssertEqual(harness.clock.sleeps, [0.5, 0.5])
        XCTAssertEqual(harness.entropy.callCount, 3)
        XCTAssertEqual(Set(network.transmitted).count, 3, "each probe must carry fresh entropy")
        XCTAssertTrue(harness.output.stdout.hasSuffix("Sent 3, received 3, packet loss 0.0%\n"))
    }

    func testPartialLossArithmetic() {
        let cases: [(probes: Int, delivered: Int, summary: String, result: NetworkProbe.Result)] = [
            (1, 1, "Sent 1, received 1, packet loss 0.0%\n",   .ok),
            (3, 2, "Sent 3, received 2, packet loss 33.33%\n", .packetLoss),
            (4, 3, "Sent 4, received 3, packet loss 25.0%\n",  .packetLoss),
            (1, 0, "Sent 1, received 0, packet loss 100.0%\n", .packetLoss),
            (7, 5, "Sent 7, received 5, packet loss 28.57%\n", .packetLoss),
        ]
        for testCase in cases {
            let f = fixture()
            let network = MockProbeNetwork()
            network.identity = f.identity
            network.deliveredCount = testCase.delivered
            let harness = makeProbe(network)
            let result = harness.probe.run(options: options(f.hex, probes: testCase.probes))
            XCTAssertEqual(result, testCase.result, testCase.summary)
            XCTAssertTrue(harness.output.stdout.hasSuffix(testCase.summary),
                          "expected suffix \(testCase.summary.debugDescription)")
        }
    }

    // MARK: hop pluralisation

    func testHopPluralisation() {
        for (hops, expected) in [(1, "over 1 hop"), (2, "over 2 hops"),
                                 (0, "over 0 hops"), (Transport.pathfinderM, "over 128 hops")] {
            let f = fixture()
            let network = MockProbeNetwork()
            network.identity = f.identity
            network.hopCount = hops
            network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
            let harness = makeProbe(network)
            _ = harness.probe.run(options: options(f.hex))
            XCTAssertTrue(harness.output.stdout.contains(expected), "hops \(hops)")
        }
    }

    // MARK: -v annotation

    func testVerboseAnnotation() {
        let f = fixture()
        let nextHop = Data(repeating: 0x11, count: 16)
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.nextHopValue = nextHop
        network.interfaceDisplayName = "TCPInterface[Client on 10.0.0.1:4242]"
        network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        let harness = makeProbe(network)
        _ = harness.probe.run(options: options(f.hex, verbosity: 1))
        XCTAssertTrue(harness.output.stdout.contains(
            " via \(RNSUtilities.prettyhexrep(nextHop)) on TCPInterface[Client on 10.0.0.1:4242]"))
    }

    func testVerboseAnnotationOmitsMissingParts() {
        // A nil next hop drops " via "; the literal "None" and a Swift nil both drop " on ".
        let hop = Data(repeating: 0x11, count: 16)
        let cases: [(Data?, String?, String)] = [
            (nil, "eth0", " via "),
            (hop, "None", " on "),
            (hop, nil, " on ")
        ]
        for (nextHop, name, mustNotContain) in cases {
            let f = fixture()
            let network = MockProbeNetwork()
            network.identity = f.identity
            network.nextHopValue = nextHop
            network.interfaceDisplayName = name
            network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
            let harness = makeProbe(network)
            _ = harness.probe.run(options: options(f.hex, verbosity: 1))
            XCTAssertFalse(harness.output.stdout.contains(mustNotContain),
                           "\(String(describing: name)): \(harness.output.stdout.debugDescription)")
        }
    }

    func testNoAnnotationWithoutVerbose() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.nextHopValue = Data(repeating: 0x11, count: 16)
        network.interfaceDisplayName = "eth0"
        network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        let harness = makeProbe(network)
        _ = harness.probe.run(options: options(f.hex, verbosity: 0))
        XCTAssertFalse(harness.output.stdout.contains(" via "))
        XCTAssertFalse(harness.output.stdout.contains(" on "))
    }

    // MARK: reception stats

    func testSharedInstanceReceptionStats() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.isConnectedToSharedInstance = true
        network.rssi = .int(-73)
        network.snr = .double(-2.5)
        network.quality = .double(87.5)
        let receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        receipt.proofPacketFullHash = Data(repeating: 0x22, count: 32)
        network.receipt = receipt
        let harness = makeProbe(network)
        _ = harness.probe.run(options: options(f.hex))
        XCTAssertTrue(harness.output.stdout.contains(
            "over 1 hop [RSSI -73 dBm] [SNR -2.5 dB] [Link Quality 87.5%]\n"))
    }

    func testSharedInstanceReceptionStatsDropIndividualFragments() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.isConnectedToSharedInstance = true
        network.rssi = .int(0)
        network.snr = nil
        network.quality = .double(100.0)
        let receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        receipt.proofPacketFullHash = Data(repeating: 0x22, count: 32)
        network.receipt = receipt
        let harness = makeProbe(network)
        _ = harness.probe.run(options: options(f.hex))
        // .int(0) renders "0", not "0.0"; a missing SNR drops only its own fragment.
        XCTAssertTrue(harness.output.stdout.contains("[RSSI 0 dBm] [Link Quality 100.0%]"))
        XCTAssertFalse(harness.output.stdout.contains("SNR"))
    }

    func testSharedInstanceWithoutProofPacketEmitsNothing() {
        // Python raises AttributeError here (rnprobe.py:167); the port degrades quietly.
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.isConnectedToSharedInstance = true
        network.rssi = .int(-73)
        network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)   // no proof packet
        let harness = makeProbe(network)
        _ = harness.probe.run(options: options(f.hex))
        XCTAssertTrue(harness.output.stdout.contains("over 1 hop\n"))
        XCTAssertFalse(harness.output.stdout.contains("RSSI"))
    }

    func testLocalReceptionStatsOmitLinkQuality() {
        // Python's asymmetry: the non-shared branch reports RSSI and SNR only
        // (rnprobe.py:180-186).
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.isConnectedToSharedInstance = false
        network.quality = .double(87.5)
        let receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        receipt.hasProofPacket = true
        receipt.proofRssi = -73
        receipt.proofSnr = -2.5
        network.receipt = receipt
        let harness = makeProbe(network)
        _ = harness.probe.run(options: options(f.hex))
        // RSSI renders as an int even though Swift's Packet.rssi is a Float.
        XCTAssertTrue(harness.output.stdout.contains(" [RSSI -73 dBm] [SNR -2.5 dB]"))
        XCTAssertFalse(harness.output.stdout.contains("Link Quality"))
    }

    func testLocalReceptionStatsSuppressedWithoutProofPacket() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        let receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        receipt.hasProofPacket = false
        receipt.proofRssi = -73
        receipt.proofSnr = -2.5
        network.receipt = receipt
        let harness = makeProbe(network)
        _ = harness.probe.run(options: options(f.hex))
        XCTAssertFalse(harness.output.stdout.contains("RSSI"))
        XCTAssertFalse(harness.output.stdout.contains("SNR"))
    }

    // MARK: failure modes

    func testMissingIdentityExitsOne() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = nil
        let harness = makeProbe(network)
        let result = harness.probe.run(options: options(f.hex))
        XCTAssertEqual(result, .pathTimeout)
        XCTAssertEqual(harness.output.stdout, "")
        XCTAssertEqual(harness.output.stderr,
                       "Can't create outbound SINGLE destination without an identity\n")
        XCTAssertEqual(network.transmitCalls, 0)
    }

    func testDestinationHashMismatchIsSilentButRecorded() {
        // Python prints the TYPED hash on the Sent line and the CONSTRUCTED hash on the
        // reply line, and never warns. Reproduce the bytes; surface the mismatch on Outcome.
        let identity = Identity()
        let typed = Data(repeating: 0xAB, count: 16)
        let typedHex = typed.map { String(format: "%02x", $0) }.joined()
        let constructed = Destination.hash(identity: identity, appName: "lxmf", aspects: ["delivery"])
        let network = MockProbeNetwork()
        network.identity = identity
        network.receipt = FakeProbeReceipt(status: .delivered, rtt: 0.5)
        let harness = makeProbe(network)

        _ = harness.probe.run(options: options(typedHex))
        XCTAssertTrue(harness.output.stdout.contains(
            "Sent probe 1 (16 bytes) to \(RNSUtilities.prettyhexrep(typed))"))
        XCTAssertTrue(harness.output.stdout.contains(
            "Valid reply from \(RNSUtilities.prettyhexrep(constructed))"))
        XCTAssertTrue(harness.probe.outcomes[0].destinationHashMismatch)
    }

    // MARK: cancellation

    func testCancelDuringPathWait() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.defaultHasPath = false
        let clock = MockProbeClock()
        let harness = makeProbe(network, clock: clock)
        clock.onSleep = { [weak probe = harness.probe] c in
            if c.sleeps.count == 2 { probe?.cancel() }
        }

        let result = harness.probe.run(options: options(f.hex))
        XCTAssertEqual(result, .ok)                        // Python: bare exit() on Ctrl-C
        XCTAssertTrue(harness.output.stdout.hasSuffix("\n"))
        XCTAssertLessThan(clock.sleeps.count, 10)          // stopped promptly
        XCTAssertFalse(harness.output.stdout.contains("Path request timed out"))
    }

    func testCancelDuringReceiptWait() {
        let f = fixture()
        let network = MockProbeNetwork()
        network.identity = f.identity
        network.receipt = FakeProbeReceipt(status: .sent, rtt: nil)
        let clock = MockProbeClock()
        let harness = makeProbe(network, clock: clock)
        clock.onSleep = { [weak probe = harness.probe] c in
            if c.sleeps.count == 2 { probe?.cancel() }
        }

        let result = harness.probe.run(options: options(f.hex))
        XCTAssertEqual(result, .ok)
        XCTAssertTrue(harness.output.stdout.hasSuffix("\n"))
        XCTAssertFalse(harness.output.stdout.contains("packet loss"))
    }
}

// MARK: - Crypto and wire format

/// The stub this port replaced sent its payload in PLAINTEXT, which builds, passes every
/// constant test and is 100% non-functional against real nodes. These tests exist to make
/// that regression impossible.
final class NetworkProbeCryptoTests: XCTestCase {

    private func makeStack(_ identity: Identity, hops: UInt8 = 1)
    -> (transport: Transport, iface: CapturingInterface, destinationHash: Data) {
        let transport = Transport()
        let iface = CapturingInterface()
        transport.register(interface: iface)
        let destinationHash = Destination.hash(identity: identity,
                                               appName: "lxmf", aspects: ["delivery"])
        transport.restore(identity: identity, forDestination: destinationHash)
        transport.restore(path: Transport.PathEntry(destinationHash: destinationHash,
                                                    nextHopInterface: iface,
                                                    hops: hops,
                                                    lastHeard: Date(),
                                                    identityHash: identity.hash),
                          forDestination: destinationHash)
        return (transport, iface, destinationHash)
    }

    private func runOneProbe(size: Int, identity: Identity, entropy: MockProbeEntropy)
    -> (iface: CapturingInterface, output: CapturingProbeOutput) {
        let stack = makeStack(identity)
        let hex = stack.destinationHash.map { String(format: "%02x", $0) }.joined()
        let clock = MockProbeClock()
        clock.advancePerSleep = 100         // clear the per-probe deadline in one iteration
        let output = CapturingProbeOutput()
        let probe = NetworkProbe(network: TransportProbeNetwork(transport: stack.transport),
                                 clock: clock, entropy: entropy, output: output)
        probe.run(options: NetworkProbe.Options(fullName: "lxmf.delivery",
                                                destinationHexhash: hex, size: size))
        return (stack.iface, output)
    }

    func testPayloadIsEncrypted() throws {
        let identity = Identity()
        let entropy = MockProbeEntropy()
        let run = runOneProbe(size: 16, identity: identity, entropy: entropy)

        let packet = try XCTUnwrap(run.iface.sent.first)
        let plaintext = entropy.produced[0]
        XCTAssertEqual(plaintext.count, 16)
        XCTAssertNotEqual(packet.data, plaintext, "the probe payload must not go out in the clear")
        XCTAssertEqual(try identity.decrypt(packet.data), plaintext)
        // 32 (ephemeral X25519 pub) + 16 (IV) + 32 (AES-CBC over PKCS7 — a 16-byte
        // plaintext pads to a FULL extra block) + 32 (HMAC-SHA256)
        XCTAssertEqual(packet.data.count, 112)
        XCTAssertEqual(try packet.pack().count, 19 + 112)   // HEADER_1 is 19 bytes
    }

    func testCiphertextSizesForOtherPayloads() throws {
        for (size, ciphertext) in [(0, 96), (32, 128)] {
            let identity = Identity()
            let entropy = MockProbeEntropy()
            let run = runOneProbe(size: size, identity: identity, entropy: entropy)
            let packet = try XCTUnwrap(run.iface.sent.first)
            XCTAssertEqual(packet.data.count, ciphertext, "size \(size)")
            XCTAssertEqual(try packet.pack().count, 19 + ciphertext, "size \(size)")
            XCTAssertEqual(try identity.decrypt(packet.data).count, size)
        }
    }

    func testRatchetIsUsed() throws {
        // Python: Destination.encrypt selects Identity.get_ratchet(self.hash) and passes it
        // to identity.encrypt (Destination.py:594-600).
        let identity = Identity()
        let stack = makeStack(identity)
        let ratchetPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let ratchetPrivate = ratchetPrivateKey.rawRepresentation
        let ratchetPublic = ratchetPrivateKey.publicKey.rawRepresentation
        stack.transport.restore(ratchet: ratchetPublic, forDestination: stack.destinationHash)

        let hex = stack.destinationHash.map { String(format: "%02x", $0) }.joined()
        let clock = MockProbeClock(); clock.advancePerSleep = 100
        let entropy = MockProbeEntropy()
        let probe = NetworkProbe(network: TransportProbeNetwork(transport: stack.transport),
                                 clock: clock, entropy: entropy, output: CapturingProbeOutput())
        probe.run(options: NetworkProbe.Options(fullName: "lxmf.delivery", destinationHexhash: hex))

        let packet = try XCTUnwrap(stack.iface.sent.first)
        let result = try identity.decrypt(packet.data,
                                          ratchetPrivateKeys: [ratchetPrivate],
                                          enforceRatchets: true)
        XCTAssertEqual(result.plaintext, entropy.produced[0])
        XCTAssertNotNil(result.ratchetID, "the probe must be encrypted to the ratchet")

        // Negative guard: Destination.encrypt is ratchet-BLIND, so swapping it in would
        // silently drop ratchet parity. Assert that it genuinely does not use the ratchet.
        let destination = try Destination(identity: identity, direction: .out, kind: .single,
                                          appName: "lxmf", aspects: ["delivery"])
        let blind = try destination.encrypt(entropy.produced[0])
        XCTAssertThrowsError(try identity.decrypt(blind,
                                                  ratchetPrivateKeys: [ratchetPrivate],
                                                  enforceRatchets: true))
    }

    func testMtuBoundary() throws {
        // A HEADER_1 non-IFAC probe: 399 packs to exactly 499 and passes; 400 pads to a
        // full extra block and packs to 515.
        let run399 = runOneProbe(size: 399, identity: Identity(), entropy: MockProbeEntropy())
        let packet = try XCTUnwrap(run399.iface.sent.first)
        XCTAssertEqual(try packet.pack().count, 499)

        let run400 = runOneProbe(size: 400, identity: Identity(), entropy: MockProbeEntropy())
        XCTAssertTrue(run400.iface.sent.isEmpty, "an oversize probe must never reach an interface")
        XCTAssertEqual(run400.output.stdout,
                       "Error: Probe packet size of 515 bytes exceed MTU of 500 bytes\n")
    }

    func testRawByteCountIsOneShortOfPacked() throws {
        // Documents the library bug the stub's MTU guard rested on: rawByteCount omits the
        // one-byte context field. Enforce the MTU through pack(), never through this.
        let packet = Packet(destinationType: .single, packetType: .data,
                            destinationHash: Data(repeating: 0x01, count: 16),
                            data: Data(repeating: 0x02, count: 100))
        XCTAssertEqual(packet.rawByteCount, try packet.pack().count - 1)
    }

    // MARK: single-shot send()

    func testSendEncryptsPayload() throws {
        let identity = Identity()
        let transport = Transport()
        let iface = CapturingInterface()
        transport.register(interface: iface)
        let destination = try Destination(identity: identity, direction: .out, kind: .single,
                                          appName: "lxmf", aspects: ["delivery"])
        let entropy = MockProbeEntropy()
        let probe = NetworkProbe(transport: transport, entropy: entropy)
        _ = probe.send(to: destination)

        let packet = try XCTUnwrap(iface.sent.first)
        XCTAssertEqual(entropy.produced[0].count, 16)
        XCTAssertNotEqual(packet.data, entropy.produced[0])
        XCTAssertEqual(try identity.decrypt(packet.data), entropy.produced[0])
    }

    func testSendRejectsOversizePayload() throws {
        let identity = Identity()
        let transport = Transport()
        let iface = CapturingInterface()
        transport.register(interface: iface)
        let destination = try Destination(identity: identity, direction: .out, kind: .single,
                                          appName: "lxmf", aspects: ["delivery"])
        let probe = NetworkProbe(transport: transport, entropy: MockProbeEntropy())
        XCTAssertNil(probe.send(to: destination, size: 400))
        XCTAssertTrue(iface.sent.isEmpty)
    }

    func testSendReturnsNilWithoutIdentity() throws {
        let transport = Transport()
        let destination = try Destination(identity: nil, direction: .in, kind: .plain,
                                          appName: "lxmf", aspects: ["delivery"])
        let probe = NetworkProbe(transport: transport, entropy: MockProbeEntropy())
        XCTAssertNil(probe.send(to: destination))
    }
}

// MARK: - PacketReceipt.proofPacket

/// Python: `PacketReceipt.proof_packet` is populated only through
/// `validate_proof_packet` → `validate_proof(proof, proof_packet)` (Packet.py:427-431).
final class NetworkProbeProofPacketTests: XCTestCase {

    private func provedReceipt(withPacket packet: Packet?) throws -> PacketReceipt {
        let identity = Identity()
        let hash = Hashes.fullHash(Data(repeating: 0x5A, count: 32))
        let receipt = PacketReceipt(packetHash: hash, peerIdentity: identity, timeout: 60)
        let signature = try identity.sign(hash)
        XCTAssertTrue(receipt.validateExplicitProof(hash + signature, packet: packet))
        return receipt
    }

    func testProofPacketRecordedWhenSupplied() throws {
        var proof = Packet(destinationType: .single, packetType: .proof,
                           destinationHash: Data(repeating: 0x01, count: 16),
                           data: Data(repeating: 0x02, count: 96))
        proof.rssi = -73
        proof.snr = -2.5
        let receipt = try provedReceipt(withPacket: proof)
        XCTAssertTrue(receipt.hasProofPacket)
        XCTAssertEqual(receipt.proofRssi, -73)
        XCTAssertEqual(receipt.proofSnr, -2.5)
        XCTAssertEqual(receipt.proofPacketFullHash?.count, 32)
        XCTAssertEqual(receipt.proofPacketTruncatedHash,
                       receipt.proofPacketFullHash?.prefix(Constants.truncatedHashLength))
    }

    func testProofPacketStaysNilWhenAbsent() throws {
        // Matches Python: a proof that arrives without a Packet legitimately leaves
        // proof_packet as None, and rnprobe's local branch then prints no PHY stats.
        let receipt = try provedReceipt(withPacket: nil)
        XCTAssertFalse(receipt.hasProofPacket)
        XCTAssertNil(receipt.proofRssi)
        XCTAssertNil(receipt.proofPacketFullHash)
    }

    func testPhyCacheAcceptsFullAndTruncatedHash() throws {
        // Python keys its PHY caches by the FULL 32-byte packet hash while Swift caches by
        // the truncated one, so a Python rnprobe querying a Swift daemon must still resolve.
        let transport = Transport()
        let iface = CapturingInterface()
        transport.register(interface: iface)
        var packet = Packet(destinationType: .single, packetType: .data,
                            destinationHash: Data(repeating: 0x07, count: 16),
                            data: Data(repeating: 0x08, count: 40))
        packet.rssi = -73
        iface.inboundHandler?(packet, iface)

        let full = try packet.packetHash()
        XCTAssertEqual(transport.getPacketRssi(packetHash: full), -73)
        XCTAssertEqual(transport.getPacketRssi(packetHash: try packet.truncatedPacketHash()), -73)
    }
}

// MARK: - Helpers

/// Scripted clock. `sleep` advances virtual time by the slept interval, or by
/// `advancePerSleep` when a test wants a deadline to expire quickly.
private final class MockProbeClock: ProbeClock {
    var time: TimeInterval = 0
    var advancePerSleep: TimeInterval?
    private(set) var sleeps: [TimeInterval] = []
    var onSleep: ((MockProbeClock) -> Void)?

    func now() -> TimeInterval { time }

    func sleep(_ interval: TimeInterval) {
        sleeps.append(interval)
        time += advancePerSleep ?? interval
        onSleep?(self)
    }
}

/// Deterministic entropy: each call returns a distinct, reproducible pattern so repeated
/// probes can be told apart without depending on a CSPRNG.
private final class MockProbeEntropy: ProbeEntropy {
    private(set) var callCount = 0
    private(set) var produced: [Data] = []

    func randomBytes(_ count: Int) -> Data {
        callCount += 1
        let seed = UInt8(truncatingIfNeeded: callCount)
        let data = Data((0..<count).map { UInt8(truncatingIfNeeded: $0) ^ seed })
        produced.append(data)
        return data
    }
}

/// Captures stdout and stderr as raw strings, control characters included.
private final class CapturingProbeOutput: ProbeOutput {
    private(set) var stdout = ""
    private(set) var stderr = ""
    private(set) var flushes = 0
    func write(_ text: String) { stdout += text }
    func writeError(_ text: String) { stderr += text }
    func flush() { flushes += 1 }
}

private final class FakeProbeReceipt: ProbeReceipt {
    var status: PacketReceipt.Status
    var rtt: TimeInterval?
    var packetHash = Data(repeating: 0x33, count: 32)
    var truncatedHash: Data { packetHash.prefix(Constants.truncatedHashLength) }
    var hasProofPacket = false
    var proofRssi: Float?
    var proofSnr: Float?
    var proofPacketFullHash: Data? {
        didSet { if proofPacketFullHash != nil { hasProofPacket = true } }
    }
    var proofPacketTruncatedHash: Data? {
        proofPacketFullHash?.prefix(Constants.truncatedHashLength)
    }

    init(status: PacketReceipt.Status = .sent, rtt: TimeInterval? = nil) {
        self.status = status
        self.rtt = rtt
    }
}

private final class MockProbeNetwork: ProbeNetwork {
    /// Consumed one entry per `hasPath` call, then `defaultHasPath` forever.
    var pathAvailability: [Bool] = []
    var defaultHasPath = true
    private(set) var hasPathCalls = 0
    private(set) var requestPathCalls = 0

    var identity: Identity? = Identity()
    var ratchet: Data?

    /// Returned by every `transmit`; ignored when `deliveredCount` is set.
    var receipt: FakeProbeReceipt?
    /// When non-nil, the first N probes are delivered and the rest fail.
    var deliveredCount: Int?
    var transmitError: Error?
    private(set) var transmitCalls = 0
    private(set) var transmitted: [Data] = []

    var hopCount = 1
    var nextHopValue: Data?
    var interfaceDisplayName: String?
    var firstHop: TimeInterval = 6
    private(set) var firstHopTimeoutCalls = 0
    var isConnectedToSharedInstance = false
    var rssi: MsgPack.Value?
    var snr: MsgPack.Value?
    var quality: MsgPack.Value?

    func hasPath(to destinationHash: Data) -> Bool {
        defer { hasPathCalls += 1 }
        return hasPathCalls < pathAvailability.count
            ? pathAvailability[hasPathCalls]
            : defaultHasPath
    }

    func requestPath(for destinationHash: Data) { requestPathCalls += 1 }

    func recallIdentity(for destinationHash: Data) -> Identity? { identity }

    func currentRatchetKey(for destinationHash: Data) -> Data? { ratchet }

    func transmit(ciphertext: Data, to destinationHash: Data) throws -> (any ProbeReceipt)? {
        if let transmitError { throw transmitError }
        transmitCalls += 1
        transmitted.append(ciphertext)
        if let deliveredCount {
            return FakeProbeReceipt(status: transmitCalls <= deliveredCount ? .delivered : .failed,
                                    rtt: 0.5)
        }
        return receipt
    }

    func hops(to destinationHash: Data) -> Int { hopCount }
    func nextHop(to destinationHash: Data) -> Data? { nextHopValue }
    func nextHopInterfaceDisplayName(for destinationHash: Data) -> String? { interfaceDisplayName }

    func firstHopTimeout(for destinationHash: Data) -> TimeInterval {
        firstHopTimeoutCalls += 1
        return firstHop
    }

    func packetRSSI(packetHash: Data) -> MsgPack.Value? { rssi }
    func packetSNR(packetHash: Data) -> MsgPack.Value? { snr }
    func packetQ(packetHash: Data) -> MsgPack.Value? { quality }
}

/// Records outbound packets instead of putting them on a wire. Same shape as the
/// `LoopbackInterface` pattern already used elsewhere in this test target.
private final class CapturingInterface: Interface {
    var name: String = "capture"
    var bitrate: Int = 0
    var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    private(set) var sent: [Packet] = []
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws { sent.append(packet) }
}
