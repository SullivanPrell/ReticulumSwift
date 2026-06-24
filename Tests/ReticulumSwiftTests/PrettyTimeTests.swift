import XCTest
@testable import ReticulumSwift

/// Tests for RNS.prettytime() and RNS.prettyshorttime() matching Python reference output.
final class PrettyTimeTests: XCTestCase {

    // MARK: - prettytime basic cases

    func testZeroSeconds() {
        XCTAssertEqual(RNSUtilities.prettytime(0), "0s")
    }

    func testOneSecond() {
        XCTAssertEqual(RNSUtilities.prettytime(1), "1s")
    }

    func testFractionalSecond() {
        // Python: round(1.5, 2) = 1.5; str(1.5) = "1.5"
        XCTAssertEqual(RNSUtilities.prettytime(1.5), "1.5s")
    }

    func testTwoDecimalSecond() {
        // Python: round(1.23, 2) = 1.23; str(1.23) = "1.23"
        XCTAssertEqual(RNSUtilities.prettytime(1.23), "1.23s")
    }

    func testOneMinute() {
        XCTAssertEqual(RNSUtilities.prettytime(60), "1m")
    }

    func testOneMinuteOneSecond() {
        XCTAssertEqual(RNSUtilities.prettytime(61), "1m and 1s")
    }

    func testTwoMinutes() {
        XCTAssertEqual(RNSUtilities.prettytime(120), "2m")
    }

    func testOneHour() {
        XCTAssertEqual(RNSUtilities.prettytime(3600), "1h")
    }

    func testOneHourOneMinute() {
        XCTAssertEqual(RNSUtilities.prettytime(3660), "1h and 1m")
    }

    func testOneHourOneMinuteOneSecond() {
        XCTAssertEqual(RNSUtilities.prettytime(3661), "1h, 1m and 1s")
    }

    func testOneDay() {
        XCTAssertEqual(RNSUtilities.prettytime(86400), "1d")
    }

    func testOneDayOneHour() {
        XCTAssertEqual(RNSUtilities.prettytime(90000), "1d and 1h")
    }

    func testOneDayOneHourOneMinuteOneSecond() {
        XCTAssertEqual(RNSUtilities.prettytime(90061), "1d, 1h, 1m and 1s")
    }

    // MARK: - prettytime negative

    func testNegativeSeconds() {
        XCTAssertEqual(RNSUtilities.prettytime(-5), "-5s")
    }

    func testNegativeMinutes() {
        XCTAssertEqual(RNSUtilities.prettytime(-61), "-1m and 1s")
    }

    // MARK: - prettytime verbose

    func testVerboseOneSecond() {
        XCTAssertEqual(RNSUtilities.prettytime(1, verbose: true), "1 second")
    }

    func testVerboseTwoSeconds() {
        XCTAssertEqual(RNSUtilities.prettytime(2, verbose: true), "2 seconds")
    }

    func testVerboseOneMinute() {
        XCTAssertEqual(RNSUtilities.prettytime(60, verbose: true), "1 minute")
    }

    func testVerboseTwoMinutes() {
        XCTAssertEqual(RNSUtilities.prettytime(120, verbose: true), "2 minutes")
    }

    func testVerboseOneHour() {
        XCTAssertEqual(RNSUtilities.prettytime(3600, verbose: true), "1 hour")
    }

    func testVerboseTwoHours() {
        XCTAssertEqual(RNSUtilities.prettytime(7200, verbose: true), "2 hours")
    }

    func testVerboseOneDay() {
        XCTAssertEqual(RNSUtilities.prettytime(86400, verbose: true), "1 day")
    }

    func testVerboseTwoDays() {
        XCTAssertEqual(RNSUtilities.prettytime(172800, verbose: true), "2 days")
    }

    func testVerboseOneMinuteOneSecond() {
        XCTAssertEqual(RNSUtilities.prettytime(61, verbose: true), "1 minute and 1 second")
    }

    // MARK: - prettytime compact

    func testCompactOnlyTopTwo() {
        // compact=True limits to 2 components
        // 1h 1m 1s → "1h and 1m" (top 2 only)
        XCTAssertEqual(RNSUtilities.prettytime(3661, compact: true), "1h and 1m")
    }

    func testCompactSecondsAreInt() {
        // compact=True: seconds = int(time), so 1.9 → 1
        XCTAssertEqual(RNSUtilities.prettytime(1.9, compact: true), "1s")
    }

    func testCompactSingleComponent() {
        XCTAssertEqual(RNSUtilities.prettytime(60, compact: true), "1m")
    }

    // MARK: - prettyshorttime basic cases

    func testShortTimeZero() {
        XCTAssertEqual(RNSUtilities.prettyshorttime(0), "0us")
    }

    func testShortTimeOneMicrosecond() {
        // 1e-6 seconds = 1 µs
        XCTAssertEqual(RNSUtilities.prettyshorttime(1e-6), "1µs")
    }

    func testShortTimeOneMillisecond() {
        // 1e-3 seconds = 1 ms
        XCTAssertEqual(RNSUtilities.prettyshorttime(1e-3), "1ms")
    }

    func testShortTimeOneSecond() {
        XCTAssertEqual(RNSUtilities.prettyshorttime(1.0), "1s")
    }

    func testShortTimeOneSecondOneMs() {
        // 1.001 seconds = 1s and 1ms
        XCTAssertEqual(RNSUtilities.prettyshorttime(1.001), "1s and 1ms")
    }

    func testShortTimeOneMsAndMicros() {
        // 0.0015 seconds = 1ms and 500µs
        XCTAssertEqual(RNSUtilities.prettyshorttime(0.0015), "1ms and 500µs")
    }

    func testShortTimeNegative() {
        XCTAssertEqual(RNSUtilities.prettyshorttime(-0.001), "-1ms")
    }

    // MARK: - prettyshorttime verbose

    func testShortTimeVerboseOneMs() {
        XCTAssertEqual(RNSUtilities.prettyshorttime(1e-3, verbose: true), "1 millisecond")
    }

    func testShortTimeVerboseTwoMs() {
        XCTAssertEqual(RNSUtilities.prettyshorttime(2e-3, verbose: true), "2 milliseconds")
    }

    func testShortTimeVerboseOneMicrosecond() {
        XCTAssertEqual(RNSUtilities.prettyshorttime(1e-6, verbose: true), "1 microsecond")
    }

    func testShortTimeVerboseTwoMicroseconds() {
        XCTAssertEqual(RNSUtilities.prettyshorttime(2e-6, verbose: true), "2 microseconds")
    }

    // MARK: - prettyshorttime compact

    func testShortTimeCompactOnlyTopTwo() {
        // 1s 1ms 500µs → compact → "1s and 1ms"
        XCTAssertEqual(RNSUtilities.prettyshorttime(1.0015, compact: true), "1s and 1ms")
    }
}
