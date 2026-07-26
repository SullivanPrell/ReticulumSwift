import XCTest
@testable import ReticulumSwift

/// rnx constants and exit codes.
/// Python reference: RNS/Utilities/rnx.py — line numbers cited per assertion.
final class RNXConstantsTests: XCTestCase {

    func testDestinationNaming() {
        // Python: RNS.Destination(identity, IN, SINGLE, APP_NAME, "execute") — rnx.py:70
        XCTAssertEqual(RNXApp.appName, "rnx")
        XCTAssertEqual(RNXApp.aspect, "execute")
        // Python: register_request_handler(path="command", ...) — rnx.py:120
        XCTAssertEqual(RNXApp.requestPath, "command")
    }

    func testFileNames() {
        // Python: identity_path = RNS.Reticulum.identitypath+"/"+APP_NAME — rnx.py:53
        XCTAssertEqual(RNXApp.identityFileName, "rnx")
        // Python: allowed_file_name = "allowed_identities" — rnx.py:95
        XCTAssertEqual(RNXApp.allowedIdentitiesFileName, "allowed_identities")
        // Python: rnx.py:97-102, searched in this order.
        XCTAssertEqual(RNXApp.allowedIdentitiesSearchPaths,
                       ["/etc/rnx", "~/.config/rnx", "~/.rnx"])
    }

    func testTimeoutConstants() {
        // Python: remote_exec_grace = 2.0 — rnx.py:325
        XCTAssertEqual(RNXApp.remoteExecGrace, 2.0)
        // Python: timeout + link.rtt*4 + grace — rnx.py:388. NOT Link.TRAFFIC_TIMEOUT_FACTOR (6).
        XCTAssertEqual(RNXApp.rexecRttFactor, 4.0)
    }

    func testHashLength() {
        // Python: (RNS.Reticulum.TRUNCATED_HASHLENGTH//8)*2 — rnx.py:83, 330
        XCTAssertEqual(RNXApp.destinationHexLength, 32)
        XCTAssertEqual(RNXApp.destinationHexLength / 2, Constants.truncatedHashLength)
    }

    func testLogLevelClamp() {
        // Python clamps the requested loglevel to [LOG_CRITICAL, LOG_EXTREME] —
        // Reticulum.py:301-302. -qqqq lands on 0, and can never reach LOG_NONE (-1).
        XCTAssertEqual(RNXApp.minLogLevel, 0)
        XCTAssertEqual(RNXApp.maxLogLevel, 8)
        XCTAssertEqual(Reticulum.LogLevel(rawValue: RNXApp.minLogLevel), .critical)
        XCTAssertEqual(Reticulum.LogLevel(rawValue: RNXApp.maxLogLevel), .extreme)
    }

    func testSpinnerSymbols() {
        // Python: syms = "⢄⢂⢁⡁⡈⡐⡠" — rnx.py:256, 280
        XCTAssertEqual(RNXApp.spinnerSymbols.count, 7)
        let scalars = RNXApp.spinnerSymbols.map { $0.unicodeScalars.first!.value }
        XCTAssertEqual(scalars, [0x2884, 0x2882, 0x2881, 0x2841, 0x2848, 0x2850, 0x2860])
    }

    func testStatClearWidth() {
        // Python: the literal blank field at rnx.py:289 and rnx.py:294 is exactly 82 spaces.
        XCTAssertEqual(RNXApp.statClearWidth, 82)
    }

    func testExitCodes() {
        // Python calls exit(<int>) directly at each site; the line numbers are in the
        // RNXApp.Result doc comments.
        XCTAssertEqual(RNXApp.Result.ok.rawValue, 0)
        XCTAssertEqual(RNXApp.Result.argumentError.rawValue, 1)
        XCTAssertEqual(RNXApp.Result.usageError.rawValue, 2)
        XCTAssertEqual(RNXApp.Result.mirrorNoReturnCode.rawValue, 240)
        XCTAssertEqual(RNXApp.Result.invalidDestination.rawValue, 241)
        XCTAssertEqual(RNXApp.Result.pathNotFound.rawValue, 242)
        XCTAssertEqual(RNXApp.Result.linkFailed.rawValue, 243)
        XCTAssertEqual(RNXApp.Result.requestFailed.rawValue, 244)
        XCTAssertEqual(RNXApp.Result.noResult.rawValue, 245)
        XCTAssertEqual(RNXApp.Result.receiveFailed.rawValue, 246)
        XCTAssertEqual(RNXApp.Result.invalidResult.rawValue, 247)
        XCTAssertEqual(RNXApp.Result.remoteExecFailed.rawValue, 248)
        XCTAssertEqual(RNXApp.Result.noResponse.rawValue, 249)
        XCTAssertEqual(RNXApp.Result.allCases.count, 13)
    }

    func testHexDecoding() {
        XCTAssertEqual(RNXHex.decode("00ff"), Data([0x00, 0xFF]))
        // Python's bytes.fromhex accepts both cases.
        XCTAssertEqual(RNXHex.decode("AbCd"), Data([0xAB, 0xCD]))
        XCTAssertNil(RNXHex.decode("zz"))
        XCTAssertNil(RNXHex.decode("abc"))
    }
}
