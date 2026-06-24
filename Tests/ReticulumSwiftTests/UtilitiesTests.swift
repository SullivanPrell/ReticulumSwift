import XCTest
@testable import ReticulumSwift

/// Tests for RNS utility functions mirroring Python's `RNS.prettyhexrep()`,
/// `RNS.hexrep()`, `RNS.prettysize()` etc.
final class UtilitiesTests: XCTestCase {

    // MARK: - prettyhexrep

    func testPrettyHexRepEmpty() {
        let result = RNSUtilities.prettyhexrep(Data())
        XCTAssertEqual(result, "<>")
    }

    func testPrettyHexRepSingleByte() {
        let result = RNSUtilities.prettyhexrep(Data([0xAB]))
        XCTAssertEqual(result, "<ab>")
    }

    func testPrettyHexRepMatchesPython() {
        // Python: RNS.prettyhexrep(b'\xde\xad\xbe\xef') == '<deadbeef>'
        let result = RNSUtilities.prettyhexrep(Data([0xde, 0xad, 0xbe, 0xef]))
        XCTAssertEqual(result, "<deadbeef>")
    }

    func testPrettyHexRepDestinationHash() {
        let id = Identity()
        let hex = RNSUtilities.prettyhexrep(id.hash)
        XCTAssertTrue(hex.hasPrefix("<"))
        XCTAssertTrue(hex.hasSuffix(">"))
        // 16-byte hash = 32 hex chars + 2 angle brackets = 34 chars
        XCTAssertEqual(hex.count, 34)
    }

    // MARK: - hexrep (colon-delimited)

    func testHexRepEmpty() {
        let result = RNSUtilities.hexrep(Data())
        XCTAssertEqual(result, "")
    }

    func testHexRepSingleByte() {
        let result = RNSUtilities.hexrep(Data([0xAB]))
        XCTAssertEqual(result, "ab")
    }

    func testHexRepMultipleBytes() {
        // Python: RNS.hexrep(b'\xde\xad\xbe\xef') == 'de:ad:be:ef'
        let result = RNSUtilities.hexrep(Data([0xde, 0xad, 0xbe, 0xef]))
        XCTAssertEqual(result, "de:ad:be:ef")
    }

    func testHexRepNoDelimiter() {
        let result = RNSUtilities.hexrep(Data([0xde, 0xad, 0xbe, 0xef]), delimit: false)
        XCTAssertEqual(result, "deadbeef")
    }

    // MARK: - prettysize

    func testPrettySizeBytes() {
        // Values < 1024 → plain "B"
        XCTAssertTrue(RNSUtilities.prettysize(500).contains("B"))
    }

    func testPrettySizeKilobytes() {
        let result = RNSUtilities.prettysize(2048)
        XCTAssertTrue(result.contains("K"), "Expected KB, got: \(result)")
    }

    func testPrettySizeMegabytes() {
        let result = RNSUtilities.prettysize(2 * 1024 * 1024)
        XCTAssertTrue(result.contains("M"), "Expected MB, got: \(result)")
    }

    // MARK: - Data hex convenience

    func testDataHexStringRoundTrip() {
        let original = Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])
        let hex = original.hexString
        XCTAssertEqual(hex, "0123456789abcdef")
        let recovered = Data(hex: hex)
        XCTAssertEqual(recovered, original)
    }

    func testDataFromHexInvalid() {
        XCTAssertNil(Data(hex: "zz"))
        XCTAssertNil(Data(hex: "abc")) // odd length
    }
}
