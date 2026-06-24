import XCTest
@testable import ReticulumSwift

/// Tests for RNS formatting utilities:
///   - RNS.prettysize() — SI prefix (1000-based, matching Python)
///   - RNS.prettyspeed()
///   - RNS.prettyb256rep() / RNS.b256rep()
///   - RNS.prettyfrequency()
///   - RNS.prettydistance()
final class PrettyFormatTests: XCTestCase {

    // MARK: - prettysize (1000-based, matching Python)

    func testPrettySizeZeroBytes() {
        // Python: 0 < 1000 and unit="" → "0 B"
        XCTAssertEqual(RNSUtilities.prettysize(0), "0 B")
    }

    func testPrettySizeSmallBytes() {
        // Python: 500 < 1000 → "500 B"
        XCTAssertEqual(RNSUtilities.prettysize(500), "500 B")
    }

    func testPrettySizeOneKilobyte() {
        // Python: 1000 / 1000 = 1.0, unit K → "1.00 KB"
        XCTAssertEqual(RNSUtilities.prettysize(1000), "1.00 KB")
    }

    func testPrettySize2KB() {
        // Python: 2000 / 1000 = 2.0 → "2.00 KB"
        XCTAssertEqual(RNSUtilities.prettysize(2000), "2.00 KB")
    }

    func testPrettySizeMegabyte() {
        // Python: 1_000_000 / 1000 / 1000 = 1.0 → "1.00 MB"
        XCTAssertEqual(RNSUtilities.prettysize(1_000_000), "1.00 MB")
    }

    func testPrettySizeGigabyte() {
        // Python: 1_000_000_000 → "1.00 GB"
        XCTAssertEqual(RNSUtilities.prettysize(1_000_000_000), "1.00 GB")
    }

    func testPrettySizeIntOverload() {
        XCTAssertEqual(RNSUtilities.prettysize(1000), "1.00 KB")
    }

    // MARK: - prettyspeed

    func testPrettySpeedBps() {
        // 100 bps: prettysize(100/8, 'b') + 'ps'
        // But Python: prettysize(12.5, 'b') → num*=8 = 100, < 1000 → "100 bps"
        XCTAssertEqual(RNSUtilities.prettyspeed(100), "100 bps")
    }

    func testPrettySpeedKbps() {
        // 1000 bps: prettysize(125, 'b') → 125*8=1000, >=1000 → 1.00 → "1.00 Kbps"
        XCTAssertEqual(RNSUtilities.prettyspeed(1000), "1.00 Kbps")
    }

    func testPrettySpeedMbps() {
        // 1_000_000 bps → "1.00 Mbps"
        XCTAssertEqual(RNSUtilities.prettyspeed(1_000_000), "1.00 Mbps")
    }

    // MARK: - b256rep

    func testB256RepFirstEntry() {
        // Python: b256[0] = "a"
        XCTAssertEqual(RNSUtilities.b256rep(0), "a")
    }

    func testB256RepSecondEntry() {
        // Python: b256[1] = "b"
        XCTAssertEqual(RNSUtilities.b256rep(1), "b")
    }

    func testB256RepNumeral() {
        // Python: b256[27] = "0" (0x1B = decimal 27)
        XCTAssertEqual(RNSUtilities.b256rep(27), "0")
    }

    func testB256RepCapitalA() {
        // Python: b256[32] = "A" (0x20 = decimal 32)
        XCTAssertEqual(RNSUtilities.b256rep(32), "A")
    }

    // MARK: - prettyb256rep

    func testPrettyB256RepEmpty() {
        // Python: "<" + "" + ">" = "<>"
        XCTAssertEqual(RNSUtilities.prettyb256rep(Data()), "<>")
    }

    func testPrettyB256RepSingleByte() {
        // byte 0 → b256[0] = "a", so "<a>"
        XCTAssertEqual(RNSUtilities.prettyb256rep(Data([0])), "<a>")
    }

    func testPrettyB256RepTwoBytes() {
        // [0, 1] → b256[0]+b256[1] = "ab" → "<ab>"
        XCTAssertEqual(RNSUtilities.prettyb256rep(Data([0, 1])), "<ab>")
    }

    func testPrettyB256RepLength() {
        // 16-byte destination hash → 16 chars between angle brackets
        let hash = Data(repeating: 0, count: 16)
        let result = RNSUtilities.prettyb256rep(hash)
        XCTAssertEqual(result.count, 18) // 16 chars + 2 brackets
        XCTAssertTrue(result.hasPrefix("<"))
        XCTAssertTrue(result.hasSuffix(">"))
    }

    func testPrettyB256RepFullAlphabet() {
        // All 256 bytes should be representable
        let all256 = Data(0...255)
        let result = RNSUtilities.prettyb256rep(all256)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.hasPrefix("<"))
        XCTAssertTrue(result.hasSuffix(">"))
    }

    // MARK: - prettyfrequency

    func testPrettyFrequencyZero() {
        // Python: if hz == 0: return "0 Hz"
        XCTAssertEqual(RNSUtilities.prettyfrequency(0), "0 Hz")
    }

    func testPrettyFrequency868MHz() {
        // 868_000_000 Hz → num = 868e6 * 1e6 = 8.68e14 µHz
        // → /1000 → mHz → /1000 → Hz → /1000 → KHz → /1000 → 868 MHz
        XCTAssertEqual(RNSUtilities.prettyfrequency(868_000_000), "868.00 MHz")
    }

    func testPrettyFrequency915MHz() {
        XCTAssertEqual(RNSUtilities.prettyfrequency(915_000_000), "915.00 MHz")
    }

    func testPrettyFrequency1Hz() {
        // 1 Hz → num = 1e6 µHz → /1000 = 1000 mHz → /1000 = 1 Hz
        XCTAssertEqual(RNSUtilities.prettyfrequency(1), "1.00 Hz")
    }

    func testPrettyFrequency1KHz() {
        // 1000 Hz → 1 KHz
        XCTAssertEqual(RNSUtilities.prettyfrequency(1000), "1.00 KHz")
    }

    func testPrettyFrequency1GHz() {
        XCTAssertEqual(RNSUtilities.prettyfrequency(1_000_000_000), "1.00 GHz")
    }

    func testPrettyFrequencyLPFMode() {
        // lpf=true: num starts at hz directly (no *1e6), units start at ""
        XCTAssertEqual(RNSUtilities.prettyfrequency(500, lpf: true), "500.00 Hz")
    }

    // MARK: - prettydistance

    func testPrettyDistanceOneMicron() {
        // 0.000001 m = 1 µm
        XCTAssertEqual(RNSUtilities.prettydistance(0.000001), "1.00 µm")
    }

    func testPrettyDistanceOneMillimeter() {
        // 0.001 m = 1 mm
        XCTAssertEqual(RNSUtilities.prettydistance(0.001), "1.00 mm")
    }

    func testPrettyDistanceOneMeter() {
        // 1.0 m
        XCTAssertEqual(RNSUtilities.prettydistance(1.0), "1.00 m")
    }

    func testPrettyDistanceOneKilometer() {
        // 1000 m = 1 km
        XCTAssertEqual(RNSUtilities.prettydistance(1000), "1.00 Km")
    }

    func testPrettyDistanceTenCentimeters() {
        // 0.1 m = 10 cm
        XCTAssertEqual(RNSUtilities.prettydistance(0.1), "10.00 cm")
    }
}
