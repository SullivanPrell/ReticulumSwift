import XCTest
@testable import ReticulumSwift

/// Tests for utility functions present in Python RNS.__init__ but previously absent in Swift:
///   - timestampStr(_:)           → RNS.timestamp_str(time_s)
///   - preciseTimestampStr(_:)    → RNS.precise_timestamp_str()
///   - b256ToByte(_:)             → RNS.b256_to_byte(point)
///   - b256ToBytes(_:)            → RNS.b256_to_bytes(b256rep)

final class UtilitiesMissingTests: XCTestCase {

    // MARK: - timestampStr

    func testTimestampStrReturnsNonEmptyString() {
        let s = RNSUtilities.timestampStr(0)
        XCTAssertFalse(s.isEmpty, "timestampStr(0) should return a non-empty string")
    }

    func testTimestampStrContainsYear() {
        // epoch 0 → 1970-01-01 in the formatter
        let s = RNSUtilities.timestampStr(0)
        // The format is "%Y-%m-%d %H:%M:%S" — year field must be present.
        let hasYearDigits = s.range(of: #"\d{4}"#, options: .regularExpression) != nil
        XCTAssertTrue(hasYearDigits, "timestampStr result should contain a 4-digit year")
    }

    func testTimestampStrMatchesExpectedFormat() {
        // A known POSIX timestamp: 2026-01-01 00:00:00 UTC = 1767225600
        // We can't assert the exact hour because it depends on locale TZ,
        // but we can assert the format yyyy-mm-dd hh:mm:ss.
        let s = RNSUtilities.timestampStr(1_767_225_600)
        let pattern = #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#
        XCTAssertNotNil(s.range(of: pattern, options: .regularExpression),
                        "timestampStr should match yyyy-mm-dd hh:mm:ss, got: \(s)")
    }

    // MARK: - preciseTimestampStr

    func testPreciseTimestampStrReturnsNonEmptyString() {
        let s = RNSUtilities.preciseTimestampStr()
        XCTAssertFalse(s.isEmpty)
    }

    func testPreciseTimestampStrContainsMilliseconds() {
        // Python logtimefmt_p = "%H:%M:%S.%f" → HH:MM:SS.mmm
        let s = RNSUtilities.preciseTimestampStr()
        let pattern = #"^\d{2}:\d{2}:\d{2}\.\d{3}$"#
        XCTAssertNotNil(s.range(of: pattern, options: .regularExpression),
                        "preciseTimestampStr should match HH:MM:SS.mmm, got: \(s)")
    }

    // MARK: - b256ToByte

    func testB256ToByteFirstCharacter() {
        // Python b256 alphabet starts with "a" at index 0.
        let b = RNSUtilities.b256ToByte("a")
        XCTAssertEqual(b, 0, "b256ToByte('a') should be 0")
    }

    func testB256ToByteKnownValue() {
        // "b" is index 1 in the Python b256 alphabet.
        let b = RNSUtilities.b256ToByte("b")
        XCTAssertEqual(b, 1)
    }

    func testB256ToByteInvalidCharacterReturnsNil() {
        // A character not in the alphabet should return nil.
        let b = RNSUtilities.b256ToByte("!")
        XCTAssertNil(b)
    }

    func testB256ToByteRoundTrip() {
        // b256rep(byte) → string, then b256ToByte(char) → byte
        for i: UInt8 in 0...255 {
            let ch = RNSUtilities.b256Alphabet[Int(i)]
            let back = RNSUtilities.b256ToByte(Character(ch))
            XCTAssertEqual(back, i, "b256 round-trip failed for byte \(i)")
        }
    }

    // MARK: - b256ToBytes

    func testB256ToBytesEmptyStringReturnsEmptyData() {
        let d = RNSUtilities.b256ToBytes("")
        XCTAssertEqual(d, Data())
    }

    func testB256ToBytesKnownValue() {
        // Build a 4-char b256 string for bytes [0,1,2,3]
        let alphabet = RNSUtilities.b256Alphabet
        let s = String([Character(alphabet[0]), Character(alphabet[1]),
                        Character(alphabet[2]), Character(alphabet[3])])
        let d = RNSUtilities.b256ToBytes(s)
        XCTAssertEqual(d, Data([0, 1, 2, 3]))
    }

    func testB256ToBytesRoundTripDataToString() {
        // b256rep(data) → string, then b256ToBytes → original data
        let original = Data([10, 20, 30, 0, 255, 128])
        let encoded = RNSUtilities.b256rep(original)
        let decoded = RNSUtilities.b256ToBytes(encoded)
        XCTAssertEqual(decoded, original, "b256ToBytes round-trip failed")
    }

    func testB256ToBytesInvalidCharacterReturnsNil() {
        let d = RNSUtilities.b256ToBytes("\0invalid")
        XCTAssertNil(d)
    }
}
