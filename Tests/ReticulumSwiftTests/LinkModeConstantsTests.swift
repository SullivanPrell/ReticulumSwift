import XCTest
@testable import ReticulumSwift

/// Tests verifying Link cipher mode constants match Python reference.
/// Python: Link.MODE_AES128_CBC = 0x00, MODE_AES256_CBC = 0x01, etc.
final class LinkModeConstantsTests: XCTestCase {

    func testModeAes128Cbc() {
        // Python: MODE_AES128_CBC = 0x00
        XCTAssertEqual(Link.modeAes128Cbc, 0x00)
    }

    func testModeAes256Cbc() {
        // Python: MODE_AES256_CBC = 0x01
        XCTAssertEqual(Link.modeAes256Cbc, 0x01)
    }

    func testModeAes256Gcm() {
        // Python: MODE_AES256_GCM = 0x02
        XCTAssertEqual(Link.modeAes256Gcm, 0x02)
    }

    func testModeOtpReserved() {
        // Python: MODE_OTP_RESERVED = 0x03
        XCTAssertEqual(Link.modeOtpReserved, 0x03)
    }

    func testModePqReserved1() {
        // Python: MODE_PQ_RESERVED_1 = 0x04
        XCTAssertEqual(Link.modePqReserved1, 0x04)
    }

    func testModePqReserved2() {
        // Python: MODE_PQ_RESERVED_2 = 0x05
        XCTAssertEqual(Link.modePqReserved2, 0x05)
    }

    func testModePqReserved3() {
        // Python: MODE_PQ_RESERVED_3 = 0x06
        XCTAssertEqual(Link.modePqReserved3, 0x06)
    }

    func testModePqReserved4() {
        // Python: MODE_PQ_RESERVED_4 = 0x07
        XCTAssertEqual(Link.modePqReserved4, 0x07)
    }

    func testDefaultModeIsAes256Cbc() {
        // Python: MODE_DEFAULT = MODE_AES256_CBC = 0x01
        XCTAssertEqual(Link.defaultMode, Link.modeAes256Cbc)
    }

    func testEnabledModesContainsAes256Cbc() {
        // Python: ENABLED_MODES = [MODE_AES256_CBC]
        XCTAssertTrue(Link.enabledModes.contains(Link.modeAes256Cbc))
    }

    func testEnabledModesDoesNotContainAes128Cbc() {
        XCTAssertFalse(Link.enabledModes.contains(Link.modeAes128Cbc))
    }

    func testMtuByteMask() {
        // Python: MTU_BYTEMASK = 0x1FFFFF
        XCTAssertEqual(Link.mtuByteMask, 0x1FFFFF)
    }

    func testModeByteMask() {
        // Python: MODE_BYTEMASK = 0xE0
        XCTAssertEqual(Link.modeByteMask, 0xE0)
    }

    func testTrafficTimeoutMinMs() {
        // Python: TRAFFIC_TIMEOUT_MIN_MS = 5
        XCTAssertEqual(Link.trafficTimeoutMinMs, 5)
    }

    func testWatchdogMaxSleep() {
        // Python: WATCHDOG_MAX_SLEEP = 5
        XCTAssertEqual(Link.watchdogMaxSleep, 5.0)
    }

    func testModeDescriptionAes256Cbc() {
        // Python: MODE_DESCRIPTIONS[MODE_AES256_CBC] = "AES_256_CBC"
        XCTAssertEqual(Link.modeDescriptions[Link.modeAes256Cbc], "AES_256_CBC")
    }

    func testModeDescriptionAes128Cbc() {
        XCTAssertEqual(Link.modeDescriptions[Link.modeAes128Cbc], "AES_128_CBC")
    }

    func testModeDescriptionAllEight() {
        XCTAssertEqual(Link.modeDescriptions.count, 8)
    }
}
