import XCTest
@testable import ReticulumSwift

/// Tests for the `rnpath` port.
///
/// Python reference: `reference_implementations/reticulum/RNS/Utilities/rnpath.py`
/// (RNS 1.4.0). Golden strings come from running the installed `rnpath` and `RNS` on this
/// machine — the help block was captured under Python 3.11.3 with `COLUMNS=80`, and every
/// `pretty_date` / `hour_rate` value was read back from `RNS.Utilities.rnpath.pretty_date`
/// and Python's own `round`/`str` directly.

// MARK: - Fixtures

private let hashA = Data([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00, 0x11,
                          0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99])
private let hashB = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                          0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10])
private let hashC = Data(repeating: 0x5a, count: 16)

private let hexA = "aabbccddeeff00112233445566778899"
private let hexB = "0102030405060708090a0b0c0d0e0f10"

/// A fixed zone so `expires` renders deterministically wherever the suite runs.
private let utc = TimeZone(secondsFromGMT: 0)!

// MARK: - Constants

final class RNPathAppConstantsTests: XCTestCase {

    func testDestinationNames() {
        XCTAssertEqual(RNPathApp.appName, "rnpath")
        // Python: RNS.Destination(..., "rnstransport", "remote", "management") — rnpath.py:87
        XCTAssertEqual(RNPathApp.transportAppName, "rnstransport")
        XCTAssertEqual(RNPathApp.managementAspects, ["remote", "management"])
        XCTAssertEqual(RNPathApp.blackholeAspects, ["info", "blackhole"])
        XCTAssertEqual(RNPathApp.managementFullName, "rnstransport.remote.management")
        XCTAssertEqual(RNPathApp.blackholeFullName, "rnstransport.info.blackhole")
        XCTAssertEqual(RNPathApp.pathRequestPath, "/path")
        XCTAssertEqual(RNPathApp.blackholeListRequestPath, "/list")
        XCTAssertEqual(RNPathApp.commandTable, "table")
        XCTAssertEqual(RNPathApp.commandRates, "rates")
    }

    func testHashLengthUsesBytesNotBits() {
        // Python: dest_len = (RNS.Reticulum.TRUNCATED_HASHLENGTH//8)*2 == 32
        XCTAssertEqual(RNPathApp.hexHashLength, 32)
        // The trap this guards: Constants is in BYTES, the other two are in BITS.
        XCTAssertEqual(Constants.truncatedHashLength, 16)
        XCTAssertEqual(Reticulum.truncatedHashLength, 128)
        XCTAssertEqual(Identity.truncatedHashLength, 128)
    }

    func testClearStrings() {
        // Python: output_rst_str = "\r" + 58 spaces + "\r" (rnpath.py:42)
        XCTAssertEqual(RNPathApp.outputResetString.count, 60)
        XCTAssertTrue(RNPathApp.outputResetString.hasPrefix("\r"))
        XCTAssertTrue(RNPathApp.outputResetString.hasSuffix("\r"))
        XCTAssertEqual(RNPathApp.outputResetString.filter { $0 == " " }.count, 58)

        // Python: the DIFFERENT inline string at rnpath.py:465 and 476 — 55 spaces, not 58.
        XCTAssertEqual(RNPathApp.lineClearString.count, 57)
        XCTAssertEqual(RNPathApp.lineClearString.filter { $0 == " " }.count, 55)
        XCTAssertNotEqual(RNPathApp.lineClearString, RNPathApp.outputResetString)
    }

    func testSpinnerGlyphs() {
        // Python: syms = "⢄⢂⢁⡁⡈⡐⡠" (rnpath.py:453)
        XCTAssertEqual(RNPathApp.spinnerSymbols.count, 7)
        XCTAssertEqual(RNPathApp.spinnerSymbols, Array("\u{2884}\u{2882}\u{2881}\u{2841}\u{2848}\u{2850}\u{2860}"))
    }

    func testNumericConstants() {
        XCTAssertEqual(RNPathApp.reasonMaxLength, 64)          // Python: rmlen = 64
        XCTAssertEqual(RNPathApp.defaultTimeout, 15)           // Python: PATH_REQUEST_TIMEOUT
        XCTAssertEqual(RNPathApp.unknownHops, 128)             // Python: PATHFINDER_M
    }

    func testExitCodes() {
        XCTAssertEqual(RNPathApp.Result.ok.rawValue, 0)
        XCTAssertEqual(RNPathApp.Result.generalFailure.rawValue, 1)
        XCTAssertEqual(RNPathApp.Result.usageError.rawValue, 2)
        XCTAssertEqual(RNPathApp.Result.remoteFailure.rawValue, 10)
        XCTAssertEqual(RNPathApp.Result.remotePathTimeout.rawValue, 12)
        XCTAssertEqual(RNPathApp.Result.setupFailure.rawValue, 20)
        XCTAssertEqual(RNPathApp.Result.notImplemented.rawValue, 255)
    }

    func testVersionReportsThePackageVersionLikeEveryOtherUtility() {
        // Python: argparse version="rnpath {RNS._version.__version__}" (rnpath.py:484) —
        // the version of the software actually running. The Swift analogue is this port's
        // own release, and all nine utilities must answer identically, so that a version
        // pasted into a bug report identifies one build rather than nine.
        //
        // Reticulum.rnsProtocolVersion is a different fact — the RNS release this build is
        // wire-compatible with — and is deliberately NOT what --version reports.
        XCTAssertEqual(RNPathApp.versionString, "rnpath \(Reticulum.version)")
        XCTAssertNotEqual(Reticulum.rnsProtocolVersion, Reticulum.version)
    }
}

// MARK: - Hash parsing

final class RNPathParseTests: XCTestCase {

    func testParseHashWording() {
        // Python: rnpath.py:95 — used by -p/-B/-U, whose failures exit 20.
        XCTAssertThrowsError(try RNPathApp.parseHash("")) { error in
            XCTAssertEqual(error as? RNPathApp.ParseError, .invalidHashLength)
            XCTAssertEqual((error as? RNPathApp.ParseError)?.message,
                           "Hash length is invalid, must be 32 hexadecimal characters (16 bytes).")
        }
        XCTAssertThrowsError(try RNPathApp.parseHash(String(repeating: "a", count: 31))) { error in
            XCTAssertEqual(error as? RNPathApp.ParseError, .invalidHashLength)
        }
        // Python: rnpath.py:99
        XCTAssertThrowsError(try RNPathApp.parseHash(String(repeating: "z", count: 32))) { error in
            XCTAssertEqual(error as? RNPathApp.ParseError, .invalidHash)
            XCTAssertEqual((error as? RNPathApp.ParseError)?.message,
                           "Invalid hash entered. Check your input.")
        }
    }

    func testParseDestinationWording() {
        // Python: rnpath.py:247/249 — the -t/-r/-d/-x/default copies, whose failures exit 1.
        XCTAssertThrowsError(try RNPathApp.parseDestination("abc")) { error in
            XCTAssertEqual((error as? RNPathApp.ParseError)?.message,
                           "Destination length is invalid, must be 32 hexadecimal characters (16 bytes).")
        }
        XCTAssertThrowsError(try RNPathApp.parseDestination(String(repeating: "g", count: 32))) { error in
            XCTAssertEqual((error as? RNPathApp.ParseError)?.message,
                           "Invalid destination entered. Check your input.")
        }
    }

    func testValidHexRoundTrips() throws {
        XCTAssertEqual(try RNPathApp.parseHash(hexA), hashA)
        XCTAssertEqual(try RNPathApp.parseDestination(hexA), hashA)
        XCTAssertEqual(try RNPathApp.parseHash(hexA.uppercased()), hashA)
        XCTAssertEqual(try RNPathApp.parseHash(hexA).count, 16)
    }

    /// Regression guard: `Data(hex:)` delegates to `UInt8(_:radix: 16)`, which accepts a
    /// leading "+" where Python's `bytes.fromhex` does not.
    func testLeadingPlusIsRejected() {
        XCTAssertEqual(UInt8("+a", radix: 16), 10, "precondition: the Swift hole still exists")
        XCTAssertThrowsError(try RNPathApp.parseHash("+a" + String(repeating: "0", count: 30))) { error in
            XCTAssertEqual(error as? RNPathApp.ParseError, .invalidHash)
        }
        XCTAssertFalse(RNPathApp.isStrictHex("+a"))
        XCTAssertFalse(RNPathApp.isStrictHex("aa bb"))
        XCTAssertTrue(RNPathApp.isStrictHex("00ffAB"))
    }

    /// Python's `len()` counts code points, so the 32-character check must too.
    func testLengthIsCountedInUnicodeScalars() {
        let decomposed = "e\u{301}" + String(repeating: "a", count: 30)   // 31 Characters, 32 scalars
        XCTAssertEqual(decomposed.count, 31)
        XCTAssertEqual(decomposed.unicodeScalars.count, 32)
        // Passes the length gate (as Python would) and then fails on content.
        XCTAssertThrowsError(try RNPathApp.parseHash(decomposed)) { error in
            XCTAssertEqual(error as? RNPathApp.ParseError, .invalidHash)
        }
    }
}

// MARK: - pretty_date

final class RNPathPrettyDateTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func ago(_ seconds: Int) -> String {
        RNPathFormatter.prettyDate(Int(now.timeIntervalSince1970) - seconds, now: now)
    }

    /// Every value read back from the installed `RNS.Utilities.rnpath.pretty_date`.
    func testBoundaries() {
        XCTAssertEqual(ago(0), "0 seconds")
        XCTAssertEqual(ago(9), "9 seconds")
        XCTAssertEqual(ago(10), "10 seconds")
        XCTAssertEqual(ago(59), "59 seconds")
        XCTAssertEqual(ago(60), "1 minute")
        XCTAssertEqual(ago(69), "1 minute")
        // Python: int(70/60) == 1 with no singularisation — "1 minutes", sic.
        XCTAssertEqual(ago(70), "1 minutes")
        XCTAssertEqual(ago(7199), "119 minutes")
        XCTAssertEqual(ago(7200), "2 hours")
        XCTAssertEqual(ago(86399), "23 hours")
        XCTAssertEqual(ago(86400), "1 day")
        XCTAssertEqual(ago(172800), "2 days")
        XCTAssertEqual(ago(6 * 86400), "6 days")
        XCTAssertEqual(ago(7 * 86400), "1 weeks")
        XCTAssertEqual(ago(30 * 86400), "4 weeks")
        XCTAssertEqual(ago(31 * 86400), "1 months")
        XCTAssertEqual(ago(364 * 86400), "12 months")
        XCTAssertEqual(ago(365 * 86400), "1 years")
    }

    func testFutureTimestampsReturnEmpty() {
        // Python: day_diff < 0 → "". A whole-second future timestamp normalises to
        // days = -1, seconds = 86395.
        XCTAssertEqual(RNPathFormatter.prettyDate(Int(now.timeIntervalSince1970) + 5, now: now), "")
        // Sub-second future: timedelta normalises to days = -1, seconds = 86399.
        let stamp = Int(now.timeIntervalSince1970)
        XCTAssertEqual(RNPathFormatter.prettyDate(stamp,
                                                  now: Date(timeIntervalSince1970: Double(stamp) - 0.5)),
                       "")
        // …but a sub-second *past* offset is still "0 seconds", not "".
        XCTAssertEqual(RNPathFormatter.prettyDate(stamp,
                                                  now: Date(timeIntervalSince1970: Double(stamp) + 0.5)),
                       "0 seconds")
    }
}

// MARK: - announces/hour

final class RNPathHourRateTests: XCTestCase {

    /// Values read back from Python's own `round(c/h, 3)` + int-collapse + `str()`.
    func testVerifiedRates() {
        XCTAssertEqual(RNPathFormatter.hourRateString(count: 1, spanHours: 1.0), "1")
        XCTAssertEqual(RNPathFormatter.hourRateString(count: 3, spanHours: 1.0), "3")
        XCTAssertEqual(RNPathFormatter.hourRateString(count: 5, spanHours: 2.0), "2.5")
        XCTAssertEqual(RNPathFormatter.hourRateString(count: 1, spanHours: 3.0), "0.333")
        XCTAssertEqual(RNPathFormatter.hourRateString(count: 0, spanHours: 1.0), "0")
        XCTAssertEqual(RNPathFormatter.hourRateString(count: 7, spanHours: 3.0), "2.333")
        XCTAssertEqual(RNPathFormatter.hourRateString(count: 2, spanHours: 3.0), "0.667")
    }

    func testWholeValuesNeverCarryATrailingPointZero() {
        for count in 0...20 {
            let rendered = RNPathFormatter.hourRateString(count: count, spanHours: 1.0)
            XCTAssertFalse(rendered.contains("."), "\(count) rendered as \(rendered)")
        }
        // String(format: "%.3f") would produce "2.500" here; Python produces "2.5".
        XCTAssertNotEqual(RNPathFormatter.hourRateString(count: 5, spanHours: 2.0), "2.500")
    }
}

// MARK: - reason truncation

final class RNPathTruncateTests: XCTestCase {

    func testShortReasonsAreUnchanged() {
        let exact = String(repeating: "a", count: 64)
        XCTAssertEqual(RNPathFormatter.truncateReason(exact), exact)
        XCTAssertEqual(RNPathFormatter.truncateReason("short"), "short")
        XCTAssertEqual(RNPathFormatter.truncateReason(""), "")
    }

    func testLongReasonsAreTruncatedWithAnEllipsis() {
        let long = String(repeating: "b", count: 65)
        let truncated = RNPathFormatter.truncateReason(long)
        XCTAssertEqual(truncated, String(repeating: "b", count: 63) + "\u{2026}")
        XCTAssertEqual(truncated.unicodeScalars.count, 64)
    }

    /// Python slices by code point; a Character-based `prefix(63)` would keep 63 *pairs*.
    func testTruncationCountsUnicodeScalarsNotCharacters() {
        let combining = String(repeating: "e\u{301}", count: 70)   // 70 Characters, 140 scalars
        XCTAssertEqual(combining.count, 70)
        XCTAssertEqual(combining.unicodeScalars.count, 140)

        let truncated = RNPathFormatter.truncateReason(combining)
        // 63 scalars kept (splitting the 32nd pair) plus the ellipsis.
        XCTAssertEqual(truncated.unicodeScalars.count, 64)
        XCTAssertEqual(Array(truncated.unicodeScalars).last, "\u{2026}")
        XCTAssertEqual(Array(truncated.unicodeScalars)[62], "e")
    }
}

// MARK: - Path table rendering

final class RNPathPathLineTests: XCTestCase {

    private func entry(hops: UInt8, via: Data? = hashB) -> RNPathTableEntry {
        RNPathTableEntry(destinationHash: hashA, timestamp: 1_700_000_000, via: via,
                         hops: hops, expires: 0, interfaceName: "TCPInterface[Client on 1.2.3.4:4242]")
    }

    func testOneHopHasTheDoubleSpaceQuirk() {
        // Python: m_str is a SPACE when hops == 1 (rnpath.py:287), so the line reads
        // "is 1 hop  away via" with two spaces.
        XCTAssertTrue(RNPathFormatter.pathTableLine(entry(hops: 1)).contains("is 1 hop  away via"))
    }

    func testPluralHops() {
        XCTAssertTrue(RNPathFormatter.pathTableLine(entry(hops: 2)).contains("is 2 hops away via"))
        XCTAssertTrue(RNPathFormatter.pathTableLine(entry(hops: 0)).contains("is 0 hops away via"))
    }

    func testFullLineShape() {
        // Python: RNS.timestamp_str(0) → "1969-12-31 18:00:00" in US/Central; pinned to UTC
        // here so the assertion is machine-independent.
        let line = RNPathFormatter.pathTableLine(entry(hops: 3), timeZone: utc)
        XCTAssertEqual(line,
                       "<aabbccddeeff00112233445566778899> is 3 hops away via "
                       + "<0102030405060708090a0b0c0d0e0f10> on TCPInterface[Client on 1.2.3.4:4242] "
                       + "expires 1970-01-01 00:00:00")
    }

    /// Python's `via` is never None (Transport.py:1796 stores the destination hash itself
    /// for a direct peer), so a nil Swift `via` must render the destination hash.
    func testNilViaFallsBackToTheDestinationHash() {
        let line = RNPathFormatter.pathTableLine(entry(hops: 1, via: nil))
        XCTAssertTrue(line.contains("away via <aabbccddeeff00112233445566778899>"))
        XCTAssertFalse(line.contains("<>"))
        XCTAssertEqual(entry(hops: 1, via: nil).resolvedVia, hashA)
    }

    func testStableSortByInterfaceThenHops() {
        let a = RNPathTableEntry(destinationHash: hashA, timestamp: 0, via: nil, hops: 3,
                                 expires: 0, interfaceName: "BInterface")
        let b = RNPathTableEntry(destinationHash: hashB, timestamp: 0, via: nil, hops: 1,
                                 expires: 0, interfaceName: "BInterface")
        let c = RNPathTableEntry(destinationHash: hashC, timestamp: 0, via: nil, hops: 9,
                                 expires: 0, interfaceName: "AInterface")
        let sorted = RNPathTableEntry.sortedForDisplay([a, b, c])
        XCTAssertEqual(sorted.map(\.destinationHash), [hashC, hashB, hashA])
    }

    /// Python's `sorted` is stable, so equal keys keep their source order.
    func testSortIsStableWithinAGroup() {
        let entries = (0..<5).map { index in
            RNPathTableEntry(destinationHash: Data([UInt8(9 - index)] + Array(repeating: 0, count: 15)),
                             timestamp: 0, via: nil, hops: 2, expires: 0, interfaceName: "Iface")
        }
        XCTAssertEqual(RNPathTableEntry.sortedForDisplay(entries).map(\.destinationHash),
                       entries.map(\.destinationHash))
    }
}

// MARK: - Rate table rendering

final class RNPathRateLineTests: XCTestCase {

    private let now: TimeInterval = 1_700_000_000

    private func entry(violations: Int = 0,
                       blockedUntil: TimeInterval = 0,
                       timestamps: [TimeInterval]? = nil) -> RNPathRateEntry {
        RNPathRateEntry(destinationHash: hashA,
                        last: now - 30,
                        rateViolations: violations,
                        blockedUntil: blockedUntil,
                        timestamps: timestamps ?? [now - 3600, now - 1800, now - 30])
    }

    func testBaseLine() {
        let line = RNPathFormatter.rateLine(entry(), now: now)
        XCTAssertEqual(line,
                       "<aabbccddeeff00112233445566778899> last heard 30 seconds ago, "
                       // pretty_date(3600 ago) is "60 minutes" — Python's minutes branch
                       // runs all the way to 7200 seconds, verified against the live helper.
                       + "3 announces/hour in the last 60 minutes")
    }

    func testRateViolationPluralisation() {
        XCTAssertFalse(RNPathFormatter.rateLine(entry(violations: 0), now: now)!
            .contains("active rate violation"))
        XCTAssertTrue(RNPathFormatter.rateLine(entry(violations: 1), now: now)!
            .hasSuffix(", 1 active rate violation"))
        XCTAssertTrue(RNPathFormatter.rateLine(entry(violations: 2), now: now)!
            .hasSuffix(", 2 active rate violations"))
    }

    func testBlockedUntil() {
        XCTAssertFalse(RNPathFormatter.rateLine(entry(blockedUntil: now - 10), now: now)!
            .contains("new announces allowed in"))
        // Python: bli = now - (int(blocked_until) - now) — 600s ahead reads back as 600s past.
        XCTAssertTrue(RNPathFormatter.rateLine(entry(blockedUntil: now + 600), now: now)!
            .hasSuffix(", new announces allowed in 10 minutes"))
    }

    /// Python: span = max(now - timestamps[0], 3600.0) — the one-hour floor means a
    /// destination first heard 30 minutes ago still reports per hour, not per half-hour.
    func testSpanIsFlooredAtOneHour() {
        let recent = entry(timestamps: [now - 1800, now - 900])
        XCTAssertTrue(RNPathFormatter.rateLine(recent, now: now)!.contains("2 announces/hour"))
    }

    /// Python raises IndexError on `timestamps[0]`, prints two lines, and CONTINUES.
    func testEmptyTimestampsIsSignalledRatherThanRendered() {
        XCTAssertNil(RNPathFormatter.rateLine(entry(timestamps: []), now: now))
        XCTAssertEqual(RNPathFormatter.rateErrorLine(entry(timestamps: [])),
                       "Error while processing entry for <aabbccddeeff00112233445566778899>")
        XCTAssertEqual(RNPathFormatter.emptyTimestampsErrorMessage, "list index out of range")
    }

    func testSortedByLastIsStable() {
        let older = RNPathRateEntry(destinationHash: hashA, last: 100, rateViolations: 0,
                                    blockedUntil: 0, timestamps: [])
        let newer = RNPathRateEntry(destinationHash: hashB, last: 200, rateViolations: 0,
                                    blockedUntil: 0, timestamps: [])
        let tied = RNPathRateEntry(destinationHash: hashC, last: 100, rateViolations: 0,
                                   blockedUntil: 0, timestamps: [])
        XCTAssertEqual(RNPathRateEntry.sortedByLast([newer, older, tied]).map(\.destinationHash),
                       [hashA, hashC, hashB])
    }
}

// MARK: - Blackhole rendering

final class RNPathBlackholeLineTests: XCTestCase {

    private let now: TimeInterval = 1_700_000_000

    private func line(until: TimeInterval? = nil,
                      reason: String? = nil,
                      source: Data? = nil,
                      local: Data? = hashC) -> String {
        RNPathFormatter.blackholeLine(
            RNPathBlackholeEntry(identityHash: hashA, source: source, until: until, reason: reason),
            now: now, localTransportIdentityHash: local)
    }

    func testIndefinite() {
        XCTAssertEqual(line(), "<aabbccddeeff00112233445566778899> blackholed indefinitely")
        // Python tests `if until:` — a zero is falsy, so it is "indefinitely", not "for 0s".
        XCTAssertEqual(line(until: 0), "<aabbccddeeff00112233445566778899> blackholed indefinitely")
    }

    func testUntil() {
        // RNS.prettytime(3600) == "1h"
        XCTAssertTrue(line(until: now + 3600).hasSuffix("blackholed for 1h"))
        // max(0, until-now) clamps a lapsed entry; RNS.prettytime(0) == "0s"
        XCTAssertTrue(line(until: now - 500).hasSuffix("blackholed for 0s"))
    }

    func testReason() {
        XCTAssertTrue(line(reason: "spam").hasSuffix("indefinitely (spam)"))
        // An empty reason is falsy in Python, so nothing is appended.
        XCTAssertTrue(line(reason: "").hasSuffix("indefinitely"))
    }

    func testBySuffix() {
        // Python: no " by …" when the source is our own transport identity.
        XCTAssertFalse(line(source: hashC, local: hashC).contains(" by "))
        XCTAssertTrue(line(source: hashB, local: hashC)
            .hasSuffix(" by <0102030405060708090a0b0c0d0e0f10>"))
        // Divergence: Python calls prettyhexrep(None) and aborts the whole listing (exit 20).
        XCTAssertFalse(line(source: nil, local: hashC).contains(" by "))
        // Divergence: Python raises AttributeError on Transport.identity.hash when there is
        // no local transport identity; treating it as "never equal" keeps the suffix.
        XCTAssertTrue(line(source: hashB, local: nil).contains(" by "))
    }
}

final class RNPathBlackholeFilterTests: XCTestCase {

    private let now: TimeInterval = 1_700_000_000

    private func entry(reason: String? = "spam", source: Data? = hashB) -> RNPathBlackholeEntry {
        RNPathBlackholeEntry(identityHash: hashA, source: source, until: nil, reason: reason)
    }

    /// Python: filter_str = f"{hash} {until_str} {reason_str} {by_str}" (rnpath.py:192) —
    /// a space-join over fragments that already carry leading spaces.
    func testFilterStringDiffersFromThePrintedLine() {
        let filterString = RNPathFormatter.blackholeFilterString(
            entry(), now: now, localTransportIdentityHash: hashC)
        let printed = RNPathFormatter.blackholeLine(
            entry(), now: now, localTransportIdentityHash: hashC)

        XCTAssertNotEqual(filterString, printed)
        XCTAssertFalse(filterString.contains(" blackholed "))
        XCTAssertTrue(printed.contains(" blackholed "))
        // The double spaces the join produces.
        XCTAssertTrue(filterString.contains("indefinitely  (spam)"))
        XCTAssertTrue(filterString.contains("(spam)  by <"))
    }

    func testMatchingUsesTheFilterStringNotTheLine() {
        let filterString = RNPathFormatter.blackholeFilterString(
            entry(), now: now, localTransportIdentityHash: hashC)
        XCTAssertTrue(RNPathFormatter.filterMatches("spam", in: filterString))
        // A filter that only appears in the printed line must NOT keep the entry.
        XCTAssertFalse(RNPathFormatter.filterMatches("blackholed", in: filterString))
    }

    /// Python's `in` is a code-point test; Swift's `String.contains` matches canonically
    /// equivalent forms and would return true here.
    func testMatchingIsLiteralNotCanonical() {
        XCTAssertTrue("\u{e9}".contains("e\u{301}"), "precondition: Swift normalises by default")
        XCTAssertFalse(RNPathFormatter.filterMatches("e\u{301}", in: "\u{e9}"))
        XCTAssertTrue(RNPathFormatter.filterMatches("\u{e9}", in: "x\u{e9}y"))
    }
}

// MARK: - Filter source selection

final class RNPathFilterSourceTests: XCTestCase {

    /// Python: the FETCH source is chosen by `blackholed` first (rnpath.py:131) but the
    /// FILTER source by `remote_blackhole_list` (rnpath.py:194) — different flags.
    func testFilterSourceSplit() {
        var options = RNPathOptions()
        options.blackholed = true
        options.destination = "aaa"
        XCTAssertEqual(options.activeBlackholeFilter, "aaa")

        options = RNPathOptions()
        options.blackholedList = true
        options.destination = hexA
        options.listFilter = "bbb"
        XCTAssertEqual(options.activeBlackholeFilter, "bbb")

        // Both flags: fetch is local (-b wins), filter is the second positional (-p wins),
        // and the first positional is ignored entirely.
        options = RNPathOptions()
        options.blackholed = true
        options.blackholedList = true
        options.destination = "aaa"
        options.listFilter = "bbb"
        XCTAssertEqual(options.activeBlackholeFilter, "bbb")
    }
}

// MARK: - Help gate

final class RNPathRunnerHelpGateTests: XCTestCase {

    /// Python: `if not args.drop_announces and not args.table and not args.rates
    ///          and not args.destination and not args.drop_via and not args.blackholed:`
    func testEmptyOptionsPrintHelp() {
        XCTAssertTrue(RNPathOptions().shouldPrintHelp)
    }

    func testGuardedFlagsSuppressHelp() {
        for mutate in [{ (o: inout RNPathOptions) in o.table = true },
                       { o in o.rates = true },
                       { o in o.dropAnnounces = true },
                       { o in o.dropVia = true },
                       { o in o.blackholed = true },
                       { o in o.destination = hexA }] {
            var options = RNPathOptions()
            mutate(&options)
            XCTAssertFalse(options.shouldPrintHelp)
        }
    }

    /// These are all absent from the Python guard, so on their own they still print help.
    func testUnguardedFlagsStillPrintHelp() {
        for mutate in [{ (o: inout RNPathOptions) in o.blackhole = true },
                       { o in o.unblackhole = true },
                       { o in o.drop = true },
                       { o in o.blackholedList = true },
                       { o in o.json = true },
                       { o in o.maxHops = 3 },
                       { o in o.remote = hexA },
                       { o in o.verbosity = 2 }] {
            var options = RNPathOptions()
            mutate(&options)
            XCTAssertTrue(options.shouldPrintHelp)
        }
    }
}

// MARK: - MsgPack round-trips

final class RNPathModelCodecTests: XCTestCase {

    func testPathEntryRoundTrip() throws {
        for via in [hashB, nil] {
            let entry = RNPathTableEntry(destinationHash: hashA, timestamp: 1.5, via: via,
                                         hops: 2, expires: 9.0, interfaceName: "Iface[x]")
            let decoded = RNPathTableEntry.decode(try MsgPack.decode(MsgPack.encode(entry.msgpackValue())))
            XCTAssertEqual(decoded, entry)
        }
    }

    func testPathEntryKeyOrderMatchesPython() {
        // Python dict insertion order (Reticulum.py:1482-1485): hash, timestamp, via,
        // hops, expires, interface. Deliberately NOT the order Swift's RPCServer emits.
        guard case .map(let pairs) = RNPathTableEntry(destinationHash: hashA, timestamp: 0,
                                                      via: nil, hops: 0, expires: 0,
                                                      interfaceName: "").msgpackValue() else {
            return XCTFail("expected a map")
        }
        XCTAssertEqual(pairs.map { $0.0 },
                       [.string("hash"), .string("timestamp"), .string("via"),
                        .string("hops"), .string("expires"), .string("interface")])
    }

    func testRateEntryRoundTrip() throws {
        let entry = RNPathRateEntry(destinationHash: hashA, last: 1.5, rateViolations: 2,
                                    blockedUntil: 0, timestamps: [1.0, 2.0])
        let decoded = RNPathRateEntry.decode(try MsgPack.decode(MsgPack.encode(entry.msgpackValue())))
        XCTAssertEqual(decoded, entry)

        guard case .map(let pairs) = entry.msgpackValue() else { return XCTFail("expected a map") }
        XCTAssertEqual(pairs.map { $0.0 },
                       [.string("hash"), .string("last"), .string("rate_violations"),
                        .string("blocked_until"), .string("timestamps")])
    }

    /// Peers may encode integers as fixint (`.uint`), `.int` or `.uint`, and timestamps as
    /// integral values rather than doubles.
    func testDecodeToleratesIntegerEncodings() {
        let value = MsgPack.Value.map([
            (.string("hash"), .bytes(hashA)),
            (.string("timestamp"), .uint(7)),
            (.string("via"), .nil),
            (.string("hops"), .int(4)),
            (.string("expires"), .int(8)),
            (.string("interface"), .string("i")),
        ])
        let entry = RNPathTableEntry.decode(value)
        XCTAssertEqual(entry?.hops, 4)
        XCTAssertEqual(entry?.timestamp, 7)
        XCTAssertEqual(entry?.expires, 8)

        let rate = RNPathRateEntry.decode(.map([
            (.string("hash"), .bytes(hashA)),
            (.string("last"), .uint(3)),
            (.string("rate_violations"), .uint(0)),
            (.string("blocked_until"), .uint(0)),
            (.string("timestamps"), .array([.uint(1), .double(2.5)])),
        ]))
        XCTAssertEqual(rate?.timestamps, [1.0, 2.5])
    }

    /// The bridging init must convert Dates to epoch seconds and resolve the interface's
    /// short config name to its display name — before sorting, since that string is the key.
    func testBridgingFromTransportEntry() {
        let transport = Transport()
        let interface = UDPInterface(name: "Bridge", listenPort: 0)
        transport.register(interface: interface)
        defer { transport.deregister(interface: interface) }

        // `via` is non-optional: Python's path_table never stores None there, falling back
        // to the destination's own hash for a directly-heard announce.
        let source = Transport.PathTableEntry(destinationHash: hashA, via: hashA, hops: 1,
                                              interfaceName: "Bridge",
                                              lastHeard: Date(timeIntervalSince1970: 10),
                                              expires: Date(timeIntervalSince1970: 20))
        let bridged = RNPathTableEntry(source, resolvingNamesWith: transport)
        XCTAssertEqual(bridged.timestamp, 10)
        XCTAssertEqual(bridged.expires, 20)
        XCTAssertEqual(bridged.interfaceName, interface.displayName)

        // With no transport to resolve against, the stored short name is kept.
        XCTAssertEqual(RNPathTableEntry(source, resolvingNamesWith: nil).interfaceName, "Bridge")
    }
}

final class RNPathBlackholeDecodeTests: XCTestCase {

    func testFullEntryShape() {
        let value = MsgPack.Value.map([
            (.bytes(hashA), .map([(.string("source"), .bytes(hashB)),
                                  (.string("until"),  .double(42)),
                                  (.string("reason"), .string("abuse"))])),
        ])
        let entries = RNPathBlackholeEntry.decodeList(value)
        XCTAssertEqual(entries?.count, 1)
        XCTAssertEqual(entries?.first?.identityHash, hashA)
        XCTAssertEqual(entries?.first?.source, hashB)
        XCTAssertEqual(entries?.first?.until, 42)
        XCTAssertEqual(entries?.first?.reason, "abuse")
    }

    func testNilAndMissingFields() {
        let value = MsgPack.Value.map([
            (.bytes(hashA), .map([(.string("source"), .nil), (.string("until"), .nil)])),
        ])
        let entry = RNPathBlackholeEntry.decodeList(value)?.first
        XCTAssertNil(entry?.source)
        XCTAssertNil(entry?.until)
        XCTAssertNil(entry?.reason)
    }

    /// Defensive: a stale peer sending the old `{hash: true}` shape must not crash or drop
    /// the entry, even though Swift's RPCServer no longer emits it.
    func testLegacyBooleanShape() {
        let entries = RNPathBlackholeEntry.decodeList(.map([(.bytes(hashA), .bool(true))]))
        XCTAssertEqual(entries?.count, 1)
        XCTAssertNil(entries?.first?.until)
    }

    func testNonMapResponseIsRejected() {
        // Python: `if type(response) == dict:` — an array is not a dict.
        XCTAssertNil(RNPathBlackholeEntry.decodeList(.array([])))
        // …but an EMPTY map IS a dict, and is accepted.
        XCTAssertEqual(RNPathBlackholeEntry.decodeList(.map([]))?.count, 0)
    }

    func testWireOrderIsPreserved() {
        let entries = RNPathBlackholeEntry.decodeList(.map([
            (.bytes(hashC), .map([])), (.bytes(hashA), .map([])), (.bytes(hashB), .map([])),
        ]))
        XCTAssertEqual(entries?.map(\.identityHash), [hashC, hashA, hashB])
    }
}

// MARK: - Remote payloads and destination hashes

final class RNPathRemotePayloadTests: XCTestCase {

    func testTablePayloadHasThreeElements() {
        // Python: data = ["table", destination_hash, max_hops] (rnpath.py:260)
        let payload = RNPathRemoteClient.pathRequestPayload(command: "table",
                                                            destinationHash: hashA, maxHops: 3)
        XCTAssertEqual(payload, .array([.string("table"), .bytes(hashA), .uint(3)]))

        let empty = RNPathRemoteClient.pathRequestPayload(command: "table",
                                                          destinationHash: nil, maxHops: nil)
        XCTAssertEqual(empty, .array([.string("table"), .nil, .nil]))
    }

    /// Python: data = ["rates", destination_hash] — TWO elements, no max_hops (rnpath.py:313).
    func testRatesPayloadHasTwoElements() {
        let payload = RNPathRemoteClient.pathRequestPayload(command: "rates",
                                                            destinationHash: hashA,
                                                            maxHops: nil,
                                                            includeMaxHops: false)
        guard case .array(let elements) = payload else { return XCTFail("expected an array") }
        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(payload, .array([.string("rates"), .bytes(hashA)]))
    }
}

final class RNPathDestinationHashTests: XCTestCase {

    /// Python: Destination.hash_from_name_and_identity(full_name, identity_hash_bytes)
    /// = SHA256( SHA256(full_name)[:10] ‖ identity_hash )[:16].
    func testRawHashDerivationMatchesTheDocumentedDigest() {
        for (purpose, appAspects) in [(RNPathRemoteClient.Purpose.management, RNPathApp.managementAspects),
                                      (.blackhole, RNPathApp.blackholeAspects)] {
            let expected = Hashes.truncatedHash(
                Destination.computeNameHash(appName: "rnstransport", aspects: appAspects) + hashA)
            XCTAssertEqual(RNPathRemoteClient.destinationHash(purpose: purpose, identityHash: hashA),
                           expected)
        }
    }

    /// Cross-check: driving the raw-bytes path with a real Identity's hash must agree with
    /// the Identity-based overload, proving the two derivations cannot drift.
    func testAgreesWithTheIdentityBasedOverload() {
        let identity = Identity()
        XCTAssertEqual(
            RNPathRemoteClient.destinationHash(purpose: .management, identityHash: identity.hash),
            Destination.hash(fromFullName: RNPathApp.managementFullName, identity: identity))
        XCTAssertEqual(
            RNPathRemoteClient.destinationHash(purpose: .blackhole, identityHash: identity.hash),
            Destination.hash(fromFullName: RNPathApp.blackholeFullName, identity: identity))
    }

    /// The same destination `BlackholeUpdater` builds (Discovery.swift), so the two client
    /// paths cannot diverge.
    func testAgreesWithTheDiscoveryBlackholeDestination() throws {
        let identity = Identity()
        let destination = try Destination(identity: identity, direction: .out, kind: .single,
                                          appName: "rnstransport", aspects: ["info", "blackhole"])
        XCTAssertEqual(RNPathRemoteClient.destinationHash(purpose: .blackhole,
                                                         identityHash: identity.hash),
                       destination.hash)
    }
}

// MARK: - JSON

final class RNPathJSONTests: XCTestCase {

    func testPathTableJSON() {
        let entries = [
            RNPathTableEntry(destinationHash: hashA, timestamp: 1.5, via: hashB,
                             hops: 2, expires: 9.0, interfaceName: "TCPInterface[x]"),
            // A nil via must serialise as the destination hash, never null.
            RNPathTableEntry(destinationHash: hashB, timestamp: 0.0, via: nil,
                             hops: 1, expires: 2.25, interfaceName: "LocalInterface[1]"),
        ]
        XCTAssertEqual(RNPathFormatter.pathTableJSON(entries),
            #"[{"hash": "aabbccddeeff00112233445566778899", "timestamp": 1.5, "via": "0102030405060708090a0b0c0d0e0f10", "hops": 2, "expires": 9.0, "interface": "TCPInterface[x]"}, "#
          + #"{"hash": "0102030405060708090a0b0c0d0e0f10", "timestamp": 0.0, "via": "0102030405060708090a0b0c0d0e0f10", "hops": 1, "expires": 2.25, "interface": "LocalInterface[1]"}]"#)
    }

    func testEmptyTableRendersAsAnEmptyArray() {
        XCTAssertEqual(RNPathFormatter.pathTableJSON([]), "[]")
        XCTAssertEqual(RNPathFormatter.rateTableJSON([]), "[]")
    }

    func testRateTableJSON() {
        let entry = RNPathRateEntry(destinationHash: hashA, last: 1.5, rateViolations: 0,
                                    blockedUntil: 0.0, timestamps: [1.0, 2.0])
        XCTAssertEqual(RNPathFormatter.rateTableJSON([entry]),
            #"[{"hash": "aabbccddeeff00112233445566778899", "last": 1.5, "rate_violations": 0, "blocked_until": 0.0, "timestamps": [1.0, 2.0]}]"#)
    }

    /// Python's `json.dumps` prints integral floats with the `.0`, unlike an Int.
    func testIntegralFloatsKeepTheirPointZero() {
        XCTAssertEqual(RNPathFormatter.jsonNumber(9.0), "9.0")
        XCTAssertEqual(RNPathFormatter.jsonNumber(0.0), "0.0")
        XCTAssertEqual(RNPathFormatter.jsonNumber(1.5), "1.5")
        // Shortest round-trip repr, matching Python — this exact value appears in the
        // captured `rnpath -t -j` reference output.
        XCTAssertEqual(RNPathFormatter.jsonNumber(1784759441.9780102), "1784759441.9780102")
    }

    /// Python's json.dumps defaults to ensure_ascii=True.
    func testStringEscaping() {
        XCTAssertEqual(RNPathFormatter.jsonString("a\"b\\c"), #""a\"b\\c""#)
        XCTAssertEqual(RNPathFormatter.jsonString("tab\there"), #""tab\there""#)
        // ensure_ascii=True escapes every non-ASCII scalar, and anything above the BMP
        // becomes a surrogate pair. Verified against Python's own json.dumps.
        let bs = "\\"
        XCTAssertEqual(RNPathFormatter.jsonString("æ"), "\"" + bs + "u00e6\"")
        XCTAssertEqual(RNPathFormatter.jsonString("\u{1F600}"), "\"" + bs + "ud83d" + bs + "ude00\"")
    }
}

// MARK: - Response decoding

final class RNPathRemoteDecodeTests: XCTestCase {

    private func nativeResponse(_ value: MsgPack.Value) -> Data {
        // Link.handleIncomingResponse strips the [request_id, response] envelope and hands
        // back the response bytes; a Python server embeds a NATIVE value there.
        MsgPack.encode(value)
    }

    private func legacyResponse(_ value: MsgPack.Value) -> Data {
        // The shape Swift's own /path handler produces: msgpack bin wrapping msgpack.
        MsgPack.encode(.bytes(MsgPack.encode(value)))
    }

    private var sampleTable: MsgPack.Value {
        .array([RNPathTableEntry(destinationHash: hashA, timestamp: 1, via: hashB,
                                 hops: 2, expires: 3, interfaceName: "i").msgpackValue()])
    }

    func testDecodesBothWireShapes() {
        XCTAssertEqual(RNPathRemoteClient.decodePathTable(nativeResponse(sampleTable))?.count, 1)
        XCTAssertEqual(RNPathRemoteClient.decodePathTable(legacyResponse(sampleTable))?.count, 1)
        XCTAssertEqual(RNPathRemoteClient.decodePathTable(nativeResponse(sampleTable))?.first?.hops, 2)
    }

    func testDecodesRateTable() {
        let value = MsgPack.Value.array([
            RNPathRateEntry(destinationHash: hashA, last: 5, rateViolations: 1,
                            blockedUntil: 0, timestamps: [1, 2]).msgpackValue(),
        ])
        XCTAssertEqual(RNPathRemoteClient.decodeRateTable(nativeResponse(value))?.first?.rateViolations, 1)
    }

    func testDecodesBlackholeList() {
        let value = MsgPack.Value.map([
            (.bytes(hashA), .map([(.string("source"), .bytes(hashB)),
                                  (.string("until"), .nil),
                                  (.string("reason"), .string("r"))])),
        ])
        XCTAssertEqual(RNPathRemoteClient.decodeBlackholeList(nativeResponse(value))?.first?.reason, "r")
        // A non-map response is Python's `type(response) != dict`.
        XCTAssertNil(RNPathRemoteClient.decodeBlackholeList(nativeResponse(.array([]))))
    }

    func testTeardownReasonsMapToPythonExitCodes() {
        XCTAssertEqual(RNPathRemoteClient.RemoteError.pathRequestTimedOut.result, .remotePathTimeout)
        XCTAssertEqual(RNPathRemoteClient.RemoteError.linkTimedOut.result, .remoteFailure)
        XCTAssertEqual(RNPathRemoteClient.RemoteError.linkClosedByServer.result, .remoteFailure)
        XCTAssertEqual(RNPathRemoteClient.RemoteError.linkClosedUnexpectedly.result, .remoteFailure)
        XCTAssertEqual(RNPathRemoteClient.RemoteError.unknownIdentity.result, .setupFailure)

        XCTAssertEqual(RNPathRemoteClient.RemoteError.pathRequestTimedOut.message, "Path request timed out")
        XCTAssertEqual(RNPathRemoteClient.RemoteError.linkTimedOut.message, "The link timed out, exiting now")
        XCTAssertEqual(RNPathRemoteClient.RemoteError.linkClosedByServer.message,
                       "The link was closed by the server, exiting now")
        XCTAssertEqual(RNPathRemoteClient.RemoteError.linkClosedUnexpectedly.message,
                       "Link closed unexpectedly, exiting now")
    }
}

// MARK: - Management source selection

final class RNPathManagementSourceSelectionTests: XCTestCase {

    /// The single highest-value integration decision: choosing wrong makes `-b`/`-t`/`-r`
    /// silently report the *client's* empty tables while a daemon owns the real ones.
    func testRoleSelection() {
        XCTAssertEqual(RNPathApp.managementSourceKind(role: .localClient, hasRPC: true), .rpc)
        XCTAssertEqual(RNPathApp.managementSourceKind(role: .sharedInstance, hasRPC: true), .local)
        XCTAssertEqual(RNPathApp.managementSourceKind(role: .standalone, hasRPC: false), .local)
        // Fallback: attached as a client, but no RPC channel could be built.
        XCTAssertEqual(RNPathApp.managementSourceKind(role: .localClient, hasRPC: false), .local)
    }

    func testRPCTriStateDecoding() {
        // Python's rpc_loop returns True / None / False verbatim, and -B/-U print three
        // distinct messages from it.
        XCTAssertEqual(RPCManagementSource.triState(.bool(true)), true)
        XCTAssertNil(RPCManagementSource.triState(.nil))
        XCTAssertEqual(RPCManagementSource.triState(.bool(false)), false)
        XCTAssertEqual(RPCManagementSource.triState(.int(0)), false)
    }
}

// MARK: - Runner: shared mock

/// Records calls and returns scripted results, so every runner branch is drivable with no
/// terminal, no stack and no network.
private final class MockManagementSource: RNPathManagementSource {

    var localTransportIdentityHash: Data?

    var paths: [RNPathTableEntry] = []
    var rates: [RNPathRateEntry] = []
    var blackholes: [RNPathBlackholeEntry] = []

    var dropPathResult = true
    var dropAllViaResult = 1
    var blackholeResult: Bool?? = .some(true)
    var unblackholeResult: Bool?? = .some(true)
    var nextHopResult: Data?
    var nextHopInterfaceResult: String?

    var blackholeError: Error?
    var pathTableError: Error?
    var blackholeFetchError: Error?

    /// Ordered log, so "was the banner printed before the call?" is assertable.
    var calls: [String] = []
    var recordedMaxHops: UInt8??
    var recordedUntil: TimeInterval??
    var recordedReason: String??

    func pathTable(maxHops: UInt8?) throws -> [RNPathTableEntry] {
        calls.append("pathTable")
        recordedMaxHops = .some(maxHops)
        if let pathTableError { throw pathTableError }
        return maxHops.map { limit in paths.filter { $0.hops <= limit } } ?? paths
    }

    func rateTable() throws -> [RNPathRateEntry] {
        calls.append("rateTable")
        return rates
    }

    func blackholedIdentities() throws -> [RNPathBlackholeEntry] {
        calls.append("blackholedIdentities")
        if let blackholeFetchError { throw blackholeFetchError }
        return blackholes
    }

    func dropPath(_ destinationHash: Data) throws -> Bool {
        calls.append("dropPath")
        return dropPathResult
    }

    func dropAllVia(_ transportHash: Data) throws -> Int {
        calls.append("dropAllVia")
        return dropAllViaResult
    }

    func dropAnnounceQueues() throws {
        calls.append("dropAnnounceQueues")
    }

    func blackholeIdentity(_ identityHash: Data, until: TimeInterval?, reason: String?) throws -> Bool? {
        calls.append("blackholeIdentity")
        recordedUntil = .some(until)
        recordedReason = .some(reason)
        if let blackholeError { throw blackholeError }
        return blackholeResult ?? nil
    }

    func unblackholeIdentity(_ identityHash: Data) throws -> Bool? {
        calls.append("unblackholeIdentity")
        if let blackholeError { throw blackholeError }
        return unblackholeResult ?? nil
    }

    func nextHop(for destinationHash: Data) throws -> Data? {
        calls.append("nextHop")
        return nextHopResult
    }

    func nextHopInterfaceName(for destinationHash: Data) throws -> String? {
        calls.append("nextHopInterfaceName")
        return nextHopInterfaceResult
    }
}

private final class MockPathResolver: RNPathPathResolver {
    var pathKnown = true
    var hops: UInt8? = 2
    var requestedPaths: [Data] = []

    func hasPath(to destinationHash: Data) -> Bool { pathKnown }
    func requestPath(for destinationHash: Data) { requestedPaths.append(destinationHash) }
    func hopsTo(_ destinationHash: Data) -> UInt8? { hops }
}

/// Collects both sinks, so gating and ordering can be asserted.
private final class OutputRecorder {
    var lines: [String] = []
    var progress: [String] = []
    var spinner: [String] = []
}

private func makeRunner(_ options: RNPathOptions,
                        management: MockManagementSource,
                        recorder: OutputRecorder,
                        resolver: RNPathPathResolver? = nil,
                        remoteLinkPresent: Bool = false,
                        remoteRequest: RNPathRunner.RemoteRequestHandler? = nil,
                        blackholeListFetch: RNPathRunner.BlackholeListFetcher? = nil,
                        now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> RNPathRunner {
    RNPathRunner(options: options,
                 management: management,
                 resolver: resolver,
                 remoteLinkPresent: remoteLinkPresent,
                 remoteRequest: remoteRequest,
                 blackholeListFetch: blackholeListFetch,
                 now: { now },
                 sleep: { _ in },
                 output: { recorder.lines.append($0) },
                 progress: { recorder.progress.append($0) },
                 spinner: { recorder.spinner.append($0) })
}

// MARK: - Runner: path table

final class RNPathRunnerTableTests: XCTestCase {

    private func fixture() -> MockManagementSource {
        let management = MockManagementSource()
        management.paths = [
            RNPathTableEntry(destinationHash: hashA, timestamp: 0, via: hashB, hops: 3,
                             expires: 0, interfaceName: "TCPInterface[b]"),
            RNPathTableEntry(destinationHash: hashB, timestamp: 0, via: hashB, hops: 1,
                             expires: 0, interfaceName: "TCPInterface[b]"),
            RNPathTableEntry(destinationHash: hashC, timestamp: 0, via: hashB, hops: 5,
                             expires: 0, interfaceName: "AInterface[a]"),
        ]
        return management
    }

    func testLocalSortingIsByInterfaceThenHops() {
        var options = RNPathOptions()
        options.table = true
        let management = fixture()
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder).run(), .ok)
        XCTAssertEqual(recorder.lines.count, 3)
        XCTAssertTrue(recorder.lines[0].contains("AInterface[a]"))
        XCTAssertTrue(recorder.lines[1].contains("is 1 hop  away"))
        XCTAssertTrue(recorder.lines[2].contains("is 3 hops away"))
    }

    func testDestinationFilterSuppressesOtherRows() {
        var options = RNPathOptions()
        options.table = true
        options.destination = hexB
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: fixture(), recorder: recorder).run(), .ok)
        XCTAssertEqual(recorder.lines.count, 1)
        XCTAssertTrue(recorder.lines[0].hasPrefix("<0102030405060708090a0b0c0d0e0f10>"))
    }

    func testUnmatchedFilterReportsNoPathKnown() {
        var options = RNPathOptions()
        options.table = true
        options.destination = String(repeating: "0", count: 32)
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: fixture(), recorder: recorder).run(),
                       .generalFailure)
        XCTAssertEqual(recorder.lines, ["No path known"])
    }

    /// Python quirk: the positional filter is NOT applied in JSON mode for the local case,
    /// but max_hops IS.
    func testJSONModeIgnoresTheDestinationFilterButHonoursMaxHops() {
        var options = RNPathOptions()
        options.table = true
        options.json = true
        options.destination = hexB
        options.maxHops = 3
        let management = fixture()
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder).run(), .ok)
        XCTAssertEqual(recorder.lines.count, 1)
        // Both 3-hop and 1-hop rows survive; the 5-hop row is filtered by max_hops.
        XCTAssertTrue(recorder.lines[0].contains("aabbccddeeff00112233445566778899"))
        XCTAssertTrue(recorder.lines[0].contains("0102030405060708090a0b0c0d0e0f10"))
        XCTAssertFalse(recorder.lines[0].contains(String(repeating: "5a", count: 16)))
        XCTAssertEqual(management.recordedMaxHops, .some(.some(3)))
    }

    func testMalformedDestinationExitsOne() {
        var options = RNPathOptions()
        options.table = true
        options.destination = "nope"
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: fixture(), recorder: recorder).run(),
                       .generalFailure)
        XCTAssertEqual(recorder.lines,
                       ["Destination length is invalid, must be 32 hexadecimal characters (16 bytes)."])
    }

    /// Python: `if response:` — an empty remote table is falsy and reported as a failure,
    /// indistinguishably from an ACL rejection or a request timeout.
    func testEmptyRemoteTableIsTreatedAsAFailure() {
        var options = RNPathOptions()
        options.table = true
        let recorder = OutputRecorder()

        let runner = makeRunner(options, management: fixture(), recorder: recorder,
                                remoteLinkPresent: true,
                                remoteRequest: { _, _ in MsgPack.encode(.array([])) })
        XCTAssertEqual(runner.run(), .remoteFailure)
        XCTAssertEqual(recorder.lines, ["The remote request failed. Likely authentication failure."])
    }

    func testRemoteTableIsNotResorted() {
        var options = RNPathOptions()
        options.table = true
        let recorder = OutputRecorder()
        let response = MsgPack.encode(.array([
            RNPathTableEntry(destinationHash: hashA, timestamp: 0, via: hashB, hops: 9,
                             expires: 0, interfaceName: "ZInterface").msgpackValue(),
            RNPathTableEntry(destinationHash: hashB, timestamp: 0, via: hashB, hops: 1,
                             expires: 0, interfaceName: "AInterface").msgpackValue(),
        ]))

        let runner = makeRunner(options, management: fixture(), recorder: recorder,
                                remoteLinkPresent: true,
                                remoteRequest: { path, value in
                                    XCTAssertEqual(path, "/path")
                                    XCTAssertEqual(value, .array([.string("table"), .nil, .nil]))
                                    return response
                                })
        XCTAssertEqual(runner.run(), .ok)
        // rnpath.py:254's sort is inside the local branch only.
        XCTAssertTrue(recorder.lines[0].contains("ZInterface"))
        XCTAssertTrue(recorder.lines[1].contains("AInterface"))
        // rnpath.py:265 emits the clear string on the success path, UNGATED.
        XCTAssertTrue(recorder.progress.contains(RNPathApp.outputResetString))
        XCTAssertTrue(recorder.progress.contains("Sending request... "))
    }
}

// MARK: - Runner: rates

final class RNPathRunnerRatesTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ hash: Data, last: TimeInterval) -> RNPathRateEntry {
        RNPathRateEntry(destinationHash: hash, last: last, rateViolations: 0, blockedUntil: 0,
                        timestamps: [last - 3600, last])
    }

    func testOutputIsAscendingByLast() {
        var options = RNPathOptions()
        options.rates = true
        let management = MockManagementSource()
        let base = now.timeIntervalSince1970
        management.rates = [entry(hashA, last: base - 10),
                            entry(hashB, last: base - 500),
                            entry(hashC, last: base - 100)]
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder, now: now).run(), .ok)
        XCTAssertTrue(recorder.lines[0].hasPrefix("<0102"))
        XCTAssertTrue(recorder.lines[1].hasPrefix("<5a5a"))
        XCTAssertTrue(recorder.lines[2].hasPrefix("<aabb"))
    }

    /// Python: `if len(table) == 0: print(...)` and then simply *returns* — main()'s
    /// sys.exit(0) runs, so this is not a failure.
    func testEmptyTableExitsZero() {
        var options = RNPathOptions()
        options.rates = true
        let recorder = OutputRecorder()
        XCTAssertEqual(makeRunner(options, management: MockManagementSource(), recorder: recorder).run(), .ok)
        XCTAssertEqual(recorder.lines, ["No information available"])
    }

    /// …but the same message after a filter matched nothing exits 1.
    func testFilteredToNothingExitsOne() {
        var options = RNPathOptions()
        options.rates = true
        options.destination = String(repeating: "0", count: 32)
        let management = MockManagementSource()
        management.rates = [entry(hashA, last: now.timeIntervalSince1970)]
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder, now: now).run(),
                       .generalFailure)
        XCTAssertEqual(recorder.lines, ["No information available"])
    }

    /// Python's `len(table) == 0` check lives inside the non-JSON else branch, so `-r -j`
    /// on an empty table prints `[]`.
    func testJSONModeOnAnEmptyTablePrintsAnEmptyArray() {
        var options = RNPathOptions()
        options.rates = true
        options.json = true
        let recorder = OutputRecorder()
        XCTAssertEqual(makeRunner(options, management: MockManagementSource(), recorder: recorder).run(), .ok)
        XCTAssertEqual(recorder.lines, ["[]"])
    }

    /// An entry with an empty `timestamps` list takes Python's two-line except branch and
    /// the loop CONTINUES with the remaining entries.
    func testEmptyTimestampsDoesNotAbortTheLoop() {
        var options = RNPathOptions()
        options.rates = true
        let management = MockManagementSource()
        let base = now.timeIntervalSince1970
        management.rates = [
            RNPathRateEntry(destinationHash: hashA, last: base - 5, rateViolations: 0,
                            blockedUntil: 0, timestamps: []),
            entry(hashB, last: base),
        ]
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder, now: now).run(), .ok)
        XCTAssertEqual(recorder.lines.count, 3)
        XCTAssertEqual(recorder.lines[0], "Error while processing entry for <aabbccddeeff00112233445566778899>")
        XCTAssertEqual(recorder.lines[1], "list index out of range")
        XCTAssertTrue(recorder.lines[2].hasPrefix("<0102"))
    }

    /// Python: ["rates", destination_hash] — no max_hops element.
    func testRemoteRatesPayloadHasNoMaxHops() {
        var options = RNPathOptions()
        options.rates = true
        options.maxHops = 4
        let recorder = OutputRecorder()
        var seen: MsgPack.Value?

        let response = MsgPack.encode(.array([entry(hashA, last: now.timeIntervalSince1970).msgpackValue()]))
        let runner = makeRunner(options, management: MockManagementSource(), recorder: recorder,
                                remoteLinkPresent: true,
                                remoteRequest: { _, value in seen = value; return response },
                                now: now)
        XCTAssertEqual(runner.run(), .ok)
        XCTAssertEqual(seen, .array([.string("rates"), .nil]))
    }
}

// MARK: - Runner: drops

final class RNPathRunnerDropTests: XCTestCase {

    func testDropPathSuccessAndFailure() {
        for (result, expectedLine, expectedCode) in [
            (true,  "Dropped path to <aabbccddeeff00112233445566778899>", RNPathApp.Result.ok),
            (false, "Unable to drop path to <aabbccddeeff00112233445566778899>. Does it exist?",
             RNPathApp.Result.generalFailure),
        ] {
            var options = RNPathOptions()
            options.drop = true
            options.destination = hexA
            let management = MockManagementSource()
            management.dropPathResult = result
            let recorder = OutputRecorder()

            XCTAssertEqual(makeRunner(options, management: management, recorder: recorder).run(),
                           expectedCode)
            XCTAssertEqual(recorder.lines, [expectedLine])
        }
    }

    /// Python: `if reticulum.drop_all_via(hash):` — an Int, and 0 is falsy.
    func testDropAllViaTreatsZeroAsFailure() {
        for (count, expectedCode) in [(3, RNPathApp.Result.ok), (0, RNPathApp.Result.generalFailure)] {
            var options = RNPathOptions()
            options.dropVia = true
            options.destination = hexA
            let management = MockManagementSource()
            management.dropAllViaResult = count
            let recorder = OutputRecorder()

            XCTAssertEqual(makeRunner(options, management: management, recorder: recorder).run(),
                           expectedCode)
            if count == 0 {
                XCTAssertEqual(recorder.lines,
                               ["Unable to drop paths via <aabbccddeeff00112233445566778899>. "
                                + "Does the transport instance exist?"])
            } else {
                XCTAssertEqual(recorder.lines, ["Dropped all paths via <aabbccddeeff00112233445566778899>"])
            }
        }
    }

    /// Python prints the banner BEFORE calling drop_announce_queues (rnpath.py:386-387).
    func testDropAnnounceQueuesPrintsBeforeCalling() {
        var options = RNPathOptions()
        options.dropAnnounces = true
        let management = MockManagementSource()
        let recorder = OutputRecorder()
        var order: [String] = []

        let runner = RNPathRunner(options: options, management: management,
                                  now: { Date(timeIntervalSince1970: 0) },
                                  sleep: { _ in },
                                  output: { line in
                                      order.append("out:\(line)")
                                      recorder.lines.append(line)
                                  })
        XCTAssertEqual(runner.run(), .ok)
        XCTAssertEqual(recorder.lines, ["Dropping announce queues on all interfaces..."])
        XCTAssertEqual(order.first, "out:Dropping announce queues on all interfaces...")
        XCTAssertEqual(management.calls, ["dropAnnounceQueues"])
    }

    func testDropModesRejectABadDestinationWithExitOne() {
        for mutate in [{ (o: inout RNPathOptions) in o.drop = true },
                       { o in o.dropVia = true }] {
            var options = RNPathOptions()
            mutate(&options)
            options.destination = "zz"
            let recorder = OutputRecorder()
            XCTAssertEqual(makeRunner(options, management: MockManagementSource(), recorder: recorder).run(),
                           .generalFailure)
            XCTAssertEqual(recorder.lines,
                           ["Destination length is invalid, must be 32 hexadecimal characters (16 bytes)."])
        }
    }
}

// MARK: - Runner: blackhole

final class RNPathRunnerBlackholeTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testBlackholeTriStateMessages() {
        let cases: [(Bool??, String)] = [
            (.some(true),  "Blackholed identity \(hexA)"),
            (.some(nil),   "Identity \(hexA) already blackholed"),
            (.some(false), "Could not blackhole identity \(hexA)"),
        ]
        for (result, expected) in cases {
            var options = RNPathOptions()
            options.blackhole = true
            options.destination = hexA
            let management = MockManagementSource()
            management.blackholeResult = result
            let recorder = OutputRecorder()

            // All three exit 0 in Python.
            XCTAssertEqual(makeRunner(options, management: management, recorder: recorder).run(), .ok)
            // The confirmations echo the RAW hex as typed, not prettyhexrep.
            XCTAssertEqual(recorder.lines, [expected])
            XCTAssertFalse(recorder.lines[0].contains("<"))
        }
    }

    func testUnblackholeTriStateMessages() {
        let cases: [(Bool??, String)] = [
            (.some(true),  "Lifted blackhole for identity \(hexA)"),
            (.some(nil),   "Identity \(hexA) not blackholed"),
            (.some(false), "Could not unblackhole identity \(hexA)"),
        ]
        for (result, expected) in cases {
            var options = RNPathOptions()
            options.unblackhole = true
            options.destination = hexA
            let management = MockManagementSource()
            management.unblackholeResult = result
            let recorder = OutputRecorder()

            XCTAssertEqual(makeRunner(options, management: management, recorder: recorder).run(), .ok)
            XCTAssertEqual(recorder.lines, [expected])
        }
    }

    /// Python: `until = time.time()+duration*60*60 if blackhole_duration else None` —
    /// `--duration` is in HOURS, and 0 is falsy.
    func testDurationIsInHoursAndZeroMeansIndefinite() {
        var options = RNPathOptions()
        options.blackhole = true
        options.destination = hexA
        options.blackholeDuration = 2
        options.blackholeReason = "abuse"
        let management = MockManagementSource()
        let recorder = OutputRecorder()

        _ = makeRunner(options, management: management, recorder: recorder, now: now).run()
        XCTAssertEqual(management.recordedUntil, .some(.some(now.timeIntervalSince1970 + 7200)))
        XCTAssertEqual(management.recordedReason, .some(.some("abuse")))

        options.blackholeDuration = 0
        let second = MockManagementSource()
        _ = makeRunner(options, management: second, recorder: OutputRecorder(), now: now).run()
        XCTAssertEqual(second.recordedUntil, .some(.none))
    }

    func testBlackholeErrorsExitTwenty() {
        var options = RNPathOptions()
        options.blackhole = true
        options.destination = hexA
        let management = MockManagementSource()
        management.blackholeError = RPCClientError.authenticationFailed
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder).run(),
                       .setupFailure)
        XCTAssertTrue(recorder.lines[0].hasPrefix("Could not blackhole identity: "))
    }

    /// A bad hash for -B is caught by the same try, so it reports the "Could not blackhole"
    /// wrapper rather than the bare parse message — and exits 20, not 1.
    func testBadHashIsWrappedInTheBlackholeMessage() {
        var options = RNPathOptions()
        options.blackhole = true
        options.destination = "short"
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: MockManagementSource(), recorder: recorder).run(),
                       .setupFailure)
        XCTAssertEqual(recorder.lines,
                       ["Could not blackhole identity: Hash length is invalid, must be 32 "
                        + "hexadecimal characters (16 bytes)."])
    }

    func testListingRendersAndFilters() {
        var options = RNPathOptions()
        options.blackholed = true
        let management = MockManagementSource()
        management.localTransportIdentityHash = hashC
        management.blackholes = [
            RNPathBlackholeEntry(identityHash: hashA, source: hashB, until: nil, reason: "spam"),
            RNPathBlackholeEntry(identityHash: hashB, source: hashC, until: nil, reason: nil),
        ]
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder, now: now).run(), .ok)
        XCTAssertEqual(recorder.lines.count, 2)
        XCTAssertEqual(recorder.lines[0],
                       "<aabbccddeeff00112233445566778899> blackholed indefinitely (spam) "
                       + "by <0102030405060708090a0b0c0d0e0f10>")
        // Source == our own transport identity, so no " by " suffix.
        XCTAssertEqual(recorder.lines[1], "<0102030405060708090a0b0c0d0e0f10> blackholed indefinitely")

        // Filtering runs against filter_str, so "spam" keeps only the first entry…
        options.destination = "spam"
        let filtered = OutputRecorder()
        XCTAssertEqual(makeRunner(options, management: management, recorder: filtered, now: now).run(), .ok)
        XCTAssertEqual(filtered.lines.count, 1)

        // …and " blackholed " — which is only in the printed line — matches nothing.
        options.destination = "blackholed"
        let none = OutputRecorder()
        XCTAssertEqual(makeRunner(options, management: management, recorder: none, now: now).run(), .ok)
        XCTAssertTrue(none.lines.isEmpty)
    }

    /// Python: `if not blackholed_list:` catches both None and an empty dict, prints
    /// ungated and exits 20.
    func testEmptyListExitsTwenty() {
        var options = RNPathOptions()
        options.blackholed = true
        let recorder = OutputRecorder()
        XCTAssertEqual(makeRunner(options, management: MockManagementSource(), recorder: recorder).run(),
                       .setupFailure)
        XCTAssertEqual(recorder.lines, ["No blackholed identity data available"])
    }

    func testFetchFailureExitsTwenty() {
        var options = RNPathOptions()
        options.blackholed = true
        let management = MockManagementSource()
        management.blackholeFetchError = RPCClientError.connectionClosed
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder).run(),
                       .setupFailure)
        XCTAssertTrue(recorder.lines[0].hasPrefix("Could not get blackholed identities from RNS instance: "))
    }

    /// Python's `-p` accepts an EMPTY dict (it is still a dict) and then falls through to
    /// "No blackholed identity data available" + exit 20 — not the exit-10 failure path.
    func testRemoteEmptyMapIsSuccessThenEmpty() {
        var options = RNPathOptions()
        options.blackholedList = true
        options.destination = hexA
        let recorder = OutputRecorder()

        let runner = makeRunner(options, management: MockManagementSource(), recorder: recorder,
                                blackholeListFetch: { [] })
        XCTAssertEqual(runner.run(), .setupFailure)
        XCTAssertEqual(recorder.lines, ["No blackholed identity data available"])
    }

    /// A non-dict response is Python's exit-10 branch, with the shorter message.
    func testRemoteNonMapResponseExitsTen() {
        var options = RNPathOptions()
        options.blackholedList = true
        options.destination = hexA
        let recorder = OutputRecorder()

        let runner = makeRunner(options, management: MockManagementSource(), recorder: recorder,
                                blackholeListFetch: { nil })
        XCTAssertEqual(runner.run(), .remoteFailure)
        XCTAssertEqual(recorder.lines, ["The remote request failed."])
    }

    func testRemoteListBadHashExitsTwentyWithTheBareMessage() {
        var options = RNPathOptions()
        options.blackholedList = true
        options.destination = "nope"
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: MockManagementSource(), recorder: recorder,
                                  blackholeListFetch: { [] }).run(), .setupFailure)
        XCTAssertEqual(recorder.lines,
                       ["Hash length is invalid, must be 32 hexadecimal characters (16 bytes)."])
    }

    /// -b wins the FETCH even when -p is also given, while -p wins the FILTER.
    func testCombinedFlagsFetchLocallyButFilterOnTheSecondPositional() {
        var options = RNPathOptions()
        options.blackholed = true
        options.blackholedList = true
        options.destination = "ignored"
        options.listFilter = "spam"
        let management = MockManagementSource()
        management.blackholes = [
            RNPathBlackholeEntry(identityHash: hashA, source: nil, until: nil, reason: "spam"),
            RNPathBlackholeEntry(identityHash: hashB, source: nil, until: nil, reason: "other"),
        ]
        let recorder = OutputRecorder()

        var fetched = false
        let runner = makeRunner(options, management: management, recorder: recorder,
                                blackholeListFetch: { fetched = true; return [] }, now: now)
        XCTAssertEqual(runner.run(), .ok)
        XCTAssertFalse(fetched, "the fetch must be local — rnpath.py:131's if/elif")
        XCTAssertEqual(management.calls, ["blackholedIdentities"])
        XCTAssertEqual(recorder.lines.count, 1)
        XCTAssertTrue(recorder.lines[0].contains("(spam)"))
    }
}

// MARK: - Runner: not-implemented remote modes

final class RNPathRunnerNotImplementedTests: XCTestCase {

    /// Every mode's exact "not implemented" wording, including the two irregular ones.
    func testRemoteModeMessages() {
        let cases: [(String, (inout RNPathOptions) -> Void)] = [
            ("Listing blackholed identities on remote instances not yet implemented",
             { $0.blackholed = true }),
            ("Blackholing identity on remote instances not yet implemented",
             { $0.blackhole = true; $0.destination = hexA }),
            // sic — -U reuses the -B wording verbatim (rnpath.py:228).
            ("Blackholing identity on remote instances not yet implemented",
             { $0.unblackhole = true; $0.destination = hexA }),
            ("Dropping announce queues on remote instances not yet implemented",
             { $0.dropAnnounces = true }),
            ("Dropping path on remote instances not yet implemented",
             { $0.drop = true; $0.destination = hexA }),
            // sic — "yet not implemented" word order (rnpath.py:414).
            ("Dropping all paths via specific transport instance on remote instances yet not implemented",
             { $0.dropVia = true; $0.destination = hexA }),
            // sic — no "yet" at all in the default mode (rnpath.py:435).
            ("Requesting paths on remote instances not implemented",
             { $0.destination = hexA }),
        ]

        for (expected, mutate) in cases {
            var options = RNPathOptions()
            mutate(&options)
            let recorder = OutputRecorder()

            let runner = makeRunner(options, management: MockManagementSource(), recorder: recorder,
                                    remoteLinkPresent: true)
            XCTAssertEqual(runner.run(), .notImplemented, expected)
            XCTAssertEqual(recorder.lines, [expected])
            XCTAssertEqual(recorder.progress, [RNPathApp.outputResetString])
        }
    }

    /// `no_output` gates the failure-path messages, as Python's `if not no_output:` does.
    func testNoOutputSuppressesTheMessageButNotTheExitCode() {
        var options = RNPathOptions()
        options.blackholed = true
        options.noOutput = true
        let recorder = OutputRecorder()

        let runner = makeRunner(options, management: MockManagementSource(), recorder: recorder,
                                remoteLinkPresent: true)
        XCTAssertEqual(runner.run(), .notImplemented)
        XCTAssertTrue(recorder.lines.isEmpty)
        XCTAssertTrue(recorder.progress.isEmpty)
    }
}

// MARK: - Runner: default path-request mode

final class RNPathRunnerPathRequestTests: XCTestCase {

    func testPathFoundLine() {
        var options = RNPathOptions()
        options.destination = hexA
        let management = MockManagementSource()
        management.nextHopResult = hashB
        management.nextHopInterfaceResult = "TCPInterface[peer]"
        let resolver = MockPathResolver()
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder,
                                  resolver: resolver).run(), .ok)
        XCTAssertEqual(recorder.lines, [
            "\rPath found, destination <aabbccddeeff00112233445566778899> is 2 hops away via "
            + "<0102030405060708090a0b0c0d0e0f10> on TCPInterface[peer]",
        ])
        // Path already known → no request, no spinner.
        XCTAssertTrue(resolver.requestedPaths.isEmpty)
        XCTAssertTrue(recorder.spinner.isEmpty)
    }

    /// Unlike the -t branch, one hop here renders with NO trailing space.
    func testSingleHopHasNoPluralAndNoExtraSpace() {
        var options = RNPathOptions()
        options.destination = hexA
        let management = MockManagementSource()
        management.nextHopResult = hashB
        management.nextHopInterfaceResult = "i"
        let resolver = MockPathResolver()
        resolver.hops = 1
        let recorder = OutputRecorder()

        _ = makeRunner(options, management: management, recorder: recorder, resolver: resolver).run()
        XCTAssertTrue(recorder.lines[0].contains("is 1 hop away via"))
    }

    /// Python's hops_to returns PATHFINDER_M (128) for an unknown destination.
    func testUnknownHopCountFallsBackTo128() {
        var options = RNPathOptions()
        options.destination = hexA
        let management = MockManagementSource()
        management.nextHopResult = hashB
        management.nextHopInterfaceResult = "i"
        let resolver = MockPathResolver()
        resolver.hops = nil
        let recorder = OutputRecorder()

        _ = makeRunner(options, management: management, recorder: recorder, resolver: resolver).run()
        XCTAssertTrue(recorder.lines[0].contains("is 128 hops away"))
    }

    /// Python's local get_next_hop_if_name is str(...), so an unknown interface is the
    /// literal string "None".
    func testUnknownInterfaceRendersAsTheLiteralNone() {
        var options = RNPathOptions()
        options.destination = hexA
        let management = MockManagementSource()
        management.nextHopResult = hashB
        management.nextHopInterfaceResult = nil
        let recorder = OutputRecorder()

        _ = makeRunner(options, management: management, recorder: recorder,
                       resolver: MockPathResolver()).run()
        XCTAssertTrue(recorder.lines[0].hasSuffix(" on None"))
    }

    /// Python's next hop is never None for a known path (Transport.py:1796 stores the
    /// destination hash itself for a direct peer), so a nil Swift next hop substitutes it
    /// rather than reporting invalid path data.
    func testNilNextHopFallsBackToTheDestinationHash() {
        var options = RNPathOptions()
        options.destination = hexA
        let management = MockManagementSource()
        management.nextHopResult = nil
        management.nextHopInterfaceResult = "i"
        let recorder = OutputRecorder()

        XCTAssertEqual(makeRunner(options, management: management, recorder: recorder,
                                  resolver: MockPathResolver()).run(), .ok)
        XCTAssertTrue(recorder.lines[0].contains("away via <aabbccddeeff00112233445566778899>"))
        XCTAssertFalse(recorder.lines[0].contains("Invalid path data"))
    }

    func testNoPathRequestsThenSpinsThenReportsNotFound() {
        var options = RNPathOptions()
        options.destination = hexA
        options.timeout = 0.3
        let resolver = MockPathResolver()
        resolver.pathKnown = false
        let recorder = OutputRecorder()

        // `now` is fixed, so the deadline never elapses on wall time; drive the loop with a
        // clock that advances instead.
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let runner = RNPathRunner(options: options,
                                  management: MockManagementSource(),
                                  resolver: resolver,
                                  now: { clock },
                                  sleep: { _ in clock = clock.addingTimeInterval(0.1) },
                                  output: { recorder.lines.append($0) },
                                  progress: { recorder.progress.append($0) },
                                  spinner: { recorder.spinner.append($0) })

        XCTAssertEqual(runner.run(), .generalFailure)
        XCTAssertEqual(resolver.requestedPaths, [hashA])
        // Python: two literal trailing spaces plus argparse's end=" " → three.
        XCTAssertEqual(recorder.progress,
                       ["Path to <aabbccddeeff00112233445566778899> requested   "])
        XCTAssertFalse(recorder.spinner.isEmpty)
        XCTAssertTrue(recorder.spinner[0].hasPrefix("\u{8}\u{8}"))
        XCTAssertTrue(recorder.spinner[0].contains("\u{2884}"))
        // Python: "\r" + 55 spaces + "\r" + "Path not found"
        XCTAssertEqual(recorder.lines, [RNPathApp.lineClearString + "Path not found"])
    }

    func testMalformedDestinationExitsOne() {
        var options = RNPathOptions()
        options.destination = "zz"
        let recorder = OutputRecorder()
        XCTAssertEqual(makeRunner(options, management: MockManagementSource(), recorder: recorder,
                                  resolver: MockPathResolver()).run(), .generalFailure)
        XCTAssertEqual(recorder.lines,
                       ["Destination length is invalid, must be 32 hexadecimal characters (16 bytes)."])
    }
}

// MARK: - Argument parsing and help text

final class RNPathArgumentParsingTests: XCTestCase {

    /// Mirrors the declarations in Sources/rnpath/main.swift.
    private func makeParser() -> ArgumentParser {
        var parser = ArgumentParser(program: RNPathApp.appName,
                                    overview: "Reticulum Path Management Utility")
        parser.option(["--config"], metavar: "CONFIG", help: "path to alternative Reticulum config directory")
        parser.flag(["--version"], help: "show program's version number and exit")
        parser.flag(["-t", "--table"], help: "show all known paths")
        parser.option(["-m", "--max"], metavar: "hops", help: "maximum hops to filter path table by")
        parser.flag(["-r", "--rates"], help: "show announce rate info")
        parser.flag(["-d", "--drop"], help: "remove the path to a destination")
        parser.flag(["-D", "--drop-announces"], help: "drop all queued announces")
        parser.flag(["-x", "--drop-via"], help: "drop all paths via specified transport instance")
        parser.option(["-w"], metavar: "seconds", help: "timeout before giving up")
        parser.option(["-R"], metavar: "hash", help: "transport identity hash of remote instance to manage")
        parser.option(["-i"], metavar: "path", help: "path to identity used for remote management")
        parser.option(["-W"], metavar: "seconds", help: "timeout before giving up on remote queries")
        parser.flag(["-b", "--blackholed"], help: "list blackholed identities")
        parser.flag(["-B", "--blackhole"], help: "blackhole identity")
        parser.flag(["-U", "--unblackhole"], help: "unblackhole identity")
        parser.option(["--duration"], metavar: "DURATION", help: "duration of blackhole enforcement in hours")
        parser.option(["--reason"], metavar: "REASON", help: "reason for blackholing identity")
        parser.flag(["-p", "--blackholed-list"], help: "view published blackhole list for remote transport instance")
        parser.flag(["-j", "--json"], help: "output in JSON format")
        parser.counted(["-v", "--verbose"], help: "")
        return parser
    }

    func testCountedVerbosity() throws {
        XCTAssertEqual(try makeParser().parse(["-vv"]).count("--verbose"), 2)
        XCTAssertEqual(try makeParser().parse(["-v", "-v"]).count("--verbose"), 2)
        XCTAssertEqual(try makeParser().parse([]).count("--verbose"), 0)
    }

    func testShortAndLongSpellingsShareAValue() throws {
        XCTAssertEqual(try makeParser().parse(["-m", "3"]).int("--max"), 3)
        XCTAssertEqual(try makeParser().parse(["--max", "3"]).int("--max"), 3)
        XCTAssertEqual(try makeParser().parse(["-t"]).flag("--table"), true)
        XCTAssertEqual(try makeParser().parse(["--table"]).flag("--table"), true)
        // -B and -b are distinct flags — case matters.
        let parsed = try makeParser().parse(["-B"])
        XCTAssertTrue(parsed.flag("--blackhole"))
        XCTAssertFalse(parsed.flag("--blackholed"))
    }

    func testConfigAcceptsBothSpellings() throws {
        XCTAssertEqual(try makeParser().parse(["--config=/tmp/x"]).value("--config"), "/tmp/x")
        XCTAssertEqual(try makeParser().parse(["--config", "/tmp/x"]).value("--config"), "/tmp/x")
    }

    func testPositionalsFillInOrder() throws {
        let parsed = try makeParser().parse([hexA, "filter"])
        XCTAssertEqual(parsed.positionals, [hexA, "filter"])
    }

    func testOptionTerminatorAndErrors() throws {
        XCTAssertEqual(try makeParser().parse(["--", "-t"]).positionals, ["-t"])
        XCTAssertThrowsError(try makeParser().parse(["--nope"]))
        XCTAssertThrowsError(try makeParser().parse(["-m"]))
    }

    /// The literal must stay byte-identical to argparse's own 80-column rendering — the
    /// captured `rnpath --help` from Python 3.11.3.
    func testHelpTextMatchesArgparse() {
        let expected = """
        usage: rnpath [-h] [--config CONFIG] [--version] [-t] [-m hops] [-r] [-d] [-D]
                      [-x] [-w seconds] [-R hash] [-i path] [-W seconds] [-b] [-B]
                      [-U] [--duration DURATION] [--reason REASON] [-p] [-j] [-v]
                      [destination] [list_filter]

        Reticulum Path Management Utility

        positional arguments:
          destination           hexadecimal hash of the destination
          list_filter           filter for remote blackhole list view

        options:
          -h, --help            show this help message and exit
          --config CONFIG       path to alternative Reticulum config directory
          --version             show program's version number and exit
          -t, --table           show all known paths
          -m hops, --max hops   maximum hops to filter path table by
          -r, --rates           show announce rate info
          -d, --drop            remove the path to a destination
          -D, --drop-announces  drop all queued announces
          -x, --drop-via        drop all paths via specified transport instance
          -w seconds            timeout before giving up
          -R hash               transport identity hash of remote instance to manage
          -i path               path to identity used for remote management
          -W seconds            timeout before giving up on remote queries
          -b, --blackholed      list blackholed identities
          -B, --blackhole       blackhole identity
          -U, --unblackhole     unblackhole identity
          --duration DURATION   duration of blackhole enforcement in hours
          --reason REASON       reason for blackholing identity
          -p, --blackholed-list
                                view published blackhole list for remote transport
                                instance
          -j, --json            output in JSON format
          -v, --verbose
        """
        XCTAssertEqual(RNPathApp.helpText, expected)
        // No trailing newline: main() adds it, and the no-mode gate wraps it in blank lines.
        XCTAssertFalse(RNPathApp.helpText.hasSuffix("\n"))
    }

    /// Python: loglevel = 3 + verbosity, clamped into the LogLevel range.
    func testVerbosityMapsToLogLevel() {
        XCTAssertEqual(Reticulum.LogLevel(rawValue: min(max(3 + 0, 0), 8)), .notice)
        XCTAssertEqual(Reticulum.LogLevel(rawValue: min(max(3 + 1, 0), 8)), .info)
        XCTAssertEqual(Reticulum.LogLevel(rawValue: min(max(3 + 3, 0), 8)), .debug)
        XCTAssertEqual(Reticulum.LogLevel(rawValue: min(max(3 + 99, 0), 8)), .extreme)
    }
}
