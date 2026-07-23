import XCTest
@testable import ReticulumSwift

/// Golden-value tests for ``UtilityFormatting``.
///
/// Every expected string below was produced by running the Python helper itself —
/// `size_str` (rnstatus.py:42), `speed_str` (rnstatus.py:760) and `pretty_date`
/// (rnpath.py:528) — so these pin byte-identical output rather than a Swift
/// approximation of it.
final class UtilityFormattingTests: XCTestCase {

    // MARK: - size_str

    func testSizeStr_baseUnitHasNoDecimals() {
        // Python: if unit == "": "%.0f %s%s"
        XCTAssertEqual(UtilityFormatting.sizeStr(0), "0 B")
        XCTAssertEqual(UtilityFormatting.sizeStr(500), "500 B")
        XCTAssertEqual(UtilityFormatting.sizeStr(999), "999 B")
    }

    func testSizeStr_prefixedUnitsHaveTwoDecimals() {
        XCTAssertEqual(UtilityFormatting.sizeStr(1000), "1.00 KB")
        XCTAssertEqual(UtilityFormatting.sizeStr(1500), "1.50 KB")
        XCTAssertEqual(UtilityFormatting.sizeStr(1_000_000), "1.00 MB")
        XCTAssertEqual(UtilityFormatting.sizeStr(2_500_000_000), "2.50 GB")
    }

    func testSizeStr_isDecimalNotBinary() {
        // 1 MiB is 1.05 MB on a 1000-based scale — not "1.00 MB".
        XCTAssertEqual(UtilityFormatting.sizeStr(1_048_576), "1.05 MB")
    }

    func testSizeStr_bitSuffixMultipliesByEight() {
        // Python: if suffix == 'b': num *= 8
        XCTAssertEqual(UtilityFormatting.sizeStr(500, suffix: "b"), "4.00 Kb")
        XCTAssertEqual(UtilityFormatting.sizeStr(1000, suffix: "b"), "8.00 Kb")
        XCTAssertEqual(UtilityFormatting.sizeStr(0, suffix: "b"), "0 b")
    }

    func testSizeStr_negativeValues() {
        XCTAssertEqual(UtilityFormatting.sizeStr(-1500), "-1.50 KB")
    }

    func testSizeStr_yottaBranchOmitsTheSpace() {
        // Python's fall-through is "%.2f%s%s" — the only branch without a space.
        // Reproduced deliberately; "fixing" it would diverge from rnstatus output.
        XCTAssertEqual(UtilityFormatting.sizeStr(1e24), "1.00YB")
        XCTAssertEqual(UtilityFormatting.sizeStr(1e24, suffix: "b"), "8.00Yb")
    }

    func testSizeStr_intOverload() {
        XCTAssertEqual(UtilityFormatting.sizeStr(1500 as Int), "1.50 KB")
    }

    // MARK: - speed_str

    func testSpeedStr_baseUnitStillHasTwoDecimals() {
        // Unlike size_str, speed_str formats the base unit with decimals too.
        XCTAssertEqual(UtilityFormatting.speedStr(0), "0.00 bps")
        XCTAssertEqual(UtilityFormatting.speedStr(500), "500.00 bps")
        XCTAssertEqual(UtilityFormatting.speedStr(999), "999.00 bps")
    }

    func testSpeedStr_bitsUseLowercaseKilo() {
        // Python: units = ['','k','M',...] for bps. This differs from
        // RNSUtilities.prettyspeed, which produces an uppercase "K".
        XCTAssertEqual(UtilityFormatting.speedStr(1000), "1.00 kbps")
        XCTAssertEqual(UtilityFormatting.speedStr(1500), "1.50 kbps")
    }

    func testSpeedStr_higherPrefixesAreUppercase() {
        XCTAssertEqual(UtilityFormatting.speedStr(1_000_000), "1.00 Mbps")
        XCTAssertEqual(UtilityFormatting.speedStr(2_500_000_000), "2.50 Gbps")
    }

    func testSpeedStr_byteSuffixDividesByEightAndUsesUppercaseKilo() {
        // Python: if suffix == 'Bps': num /= 8; units = ['','K','M',...]
        XCTAssertEqual(UtilityFormatting.speedStr(500, suffix: "Bps"), "62.50 Bps")
        XCTAssertEqual(UtilityFormatting.speedStr(1000, suffix: "Bps"), "125.00 Bps")
        XCTAssertEqual(UtilityFormatting.speedStr(1_000_000, suffix: "Bps"), "125.00 KBps")
        XCTAssertEqual(UtilityFormatting.speedStr(2_500_000_000, suffix: "Bps"), "312.50 MBps")
    }

    func testSpeedStr_divergesFromLibraryPrettyspeed() {
        // Guards the reason this type exists at all: the library helper is not a
        // drop-in replacement for the utility-local one.
        XCTAssertEqual(UtilityFormatting.speedStr(1500), "1.50 kbps")
        XCTAssertNotEqual(RNSUtilities.prettyspeed(1500), UtilityFormatting.speedStr(1500))
    }

    // MARK: - pretty_date

    private let now: TimeInterval = 1_700_000_000

    private func ago(_ seconds: TimeInterval) -> String {
        UtilityFormatting.prettyDate(now - seconds, now: now)
    }

    func testPrettyDate_seconds() {
        XCTAssertEqual(ago(0), "0 seconds")
        XCTAssertEqual(ago(5), "5 seconds")
        XCTAssertEqual(ago(9), "9 seconds")
        XCTAssertEqual(ago(30), "30 seconds")
        XCTAssertEqual(ago(59), "59 seconds")
    }

    func testPrettyDate_oneMinuteWindow() {
        // Python has a peculiar 60..<70 window that reports "1 minute" flat.
        XCTAssertEqual(ago(60), "1 minute")
        XCTAssertEqual(ago(69), "1 minute")
    }

    func testPrettyDate_minutesRunToTwoHours() {
        // Python: if second_diff < 7200: minutes — so 90 minutes is "90 minutes",
        // not "1 hour".
        XCTAssertEqual(ago(70), "1 minutes")
        XCTAssertEqual(ago(600), "10 minutes")
        XCTAssertEqual(ago(5400), "90 minutes")
        XCTAssertEqual(ago(7199), "119 minutes")
    }

    func testPrettyDate_hours() {
        XCTAssertEqual(ago(7200), "2 hours")
        XCTAssertEqual(ago(36000), "10 hours")
    }

    func testPrettyDate_days() {
        XCTAssertEqual(ago(86_400), "1 day")
        XCTAssertEqual(ago(86_400 * 3), "3 days")
        XCTAssertEqual(ago(86_400 * 6), "6 days")
    }

    func testPrettyDate_weeksMonthsYears() {
        XCTAssertEqual(ago(86_400 * 7), "1 weeks")
        XCTAssertEqual(ago(86_400 * 30), "4 weeks")
        XCTAssertEqual(ago(86_400 * 31), "1 months")
        XCTAssertEqual(ago(86_400 * 200), "6 months")
        XCTAssertEqual(ago(86_400 * 365), "1 years")
        XCTAssertEqual(ago(86_400 * 800), "2 years")
    }

    func testPrettyDate_futureTimestampIsEmpty() {
        // Python: if day_diff < 0: return ''
        XCTAssertEqual(UtilityFormatting.prettyDate(now + 86_400 * 2, now: now), "")
    }
}
