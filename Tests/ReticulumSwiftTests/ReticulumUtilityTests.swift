import XCTest
@testable import ReticulumSwift

/// Tests for Python-parity module-level utility functions exposed as static
/// methods on `Reticulum`.
///
/// Python reference (RNS/__init__.py):
///   RNS.rand()               — secure random float in [0, 1)
///   RNS.version()            — semantic version string
///   RNS.sl(level)            — should-log predicate: loglevel >= level
///   RNS.phyparams()          — print physical-layer parameters (no return value)
///   RNS.loglevelname(level)  — human-readable level name
final class ReticulumUtilityTests: XCTestCase {

    // MARK: - rand()

    func testRandReturnsBetweenZeroAndOne() {
        let r = Reticulum.rand()
        XCTAssertGreaterThanOrEqual(r, 0.0, "rand() must be >= 0")
        XCTAssertLessThan(r, 1.0, "rand() must be < 1.0")
    }

    func testRandProducesDifferentValues() {
        // With a cryptographically random source, two calls should almost never
        // produce the same 64-bit double.  The probability is ~2^-52 per call pair.
        let a = Reticulum.rand()
        let b = Reticulum.rand()
        XCTAssertNotEqual(a, b, "consecutive rand() calls must differ")
    }

    func testRandDistributionSpansRange() {
        // 1000 samples should include values both below and above 0.5.
        let samples = (0..<1000).map { _ in Reticulum.rand() }
        XCTAssertTrue(samples.contains { $0 < 0.5 }, "rand() should produce values < 0.5")
        XCTAssertTrue(samples.contains { $0 > 0.5 }, "rand() should produce values > 0.5")
    }

    // MARK: - version (property, mirrors Python RNS.version())

    func testVersionReturnsNonEmptyString() {
        // Python: RNS.version() → Swift: Reticulum.version (static property)
        XCTAssertFalse(Reticulum.version.isEmpty, "version must return a non-empty string")
    }

    func testVersionIsSemanticVersionFormat() {
        // Should be X.Y or X.Y.Z
        let parts = Reticulum.version.split(separator: ".")
        XCTAssertGreaterThanOrEqual(parts.count, 2,
                                    "version should be semver (at least X.Y)")
    }

    // MARK: - sl(level:) — should-log predicate

    func testSlReturnsTrueWhenLevelAtOrBelowGlobal() {
        let saved = Reticulum.globalLogLevel
        defer { Reticulum.globalLogLevel = saved }

        Reticulum.globalLogLevel = .notice  // 3
        XCTAssertTrue(Reticulum.sl(level: .critical), "critical (0) <= notice (3) → should log")
        XCTAssertTrue(Reticulum.sl(level: .notice),   "notice == notice → should log")
    }

    func testSlReturnsFalseWhenLevelAboveGlobal() {
        let saved = Reticulum.globalLogLevel
        defer { Reticulum.globalLogLevel = saved }

        Reticulum.globalLogLevel = .notice  // 3
        XCTAssertFalse(Reticulum.sl(level: .debug),   "debug (6) > notice (3) → should not log")
        XCTAssertFalse(Reticulum.sl(level: .extreme), "extreme (8) > notice (3) → should not log")
    }

    func testSlDefaultLevelIsNotice() {
        // Python: def sl(level=3) → default is LOG_NOTICE
        let saved = Reticulum.globalLogLevel
        defer { Reticulum.globalLogLevel = saved }

        Reticulum.globalLogLevel = .notice
        XCTAssertTrue(Reticulum.sl(),
                      "sl() with no argument must use default .notice and return true at notice level")
    }

    func testSlReturnsFalseAtNoneLevel() {
        let saved = Reticulum.globalLogLevel
        defer { Reticulum.globalLogLevel = saved }

        Reticulum.globalLogLevel = .none
        XCTAssertFalse(Reticulum.sl(level: .critical),
                       "LOG_NONE disables all logging; sl() must return false")
    }

    // MARK: - phyparams()

    func testPhyparamsReturnsDict() {
        // Python phyparams() prints; Swift returns [String: Any] for introspection.
        let p = Reticulum.phyparams()
        XCTAssertFalse(p.isEmpty, "phyparams() must return a non-empty dictionary")
    }

    func testPhyparamsContainsExpectedKeys() {
        let p = Reticulum.phyparams()
        XCTAssertNotNil(p["mtu"],          "phyparams must include 'mtu'")
        XCTAssertNotNil(p["linkMdu"],      "phyparams must include 'linkMdu'")
        XCTAssertNotNil(p["linkCurve"],    "phyparams must include 'linkCurve'")
        XCTAssertNotNil(p["ecPubKeySize"], "phyparams must include 'ecPubKeySize'")
        XCTAssertNotNil(p["keySize"],      "phyparams must include 'keySize'")
    }

    func testPhyparamsMtuMatchesReticulumMtu() {
        let p = Reticulum.phyparams()
        XCTAssertEqual(p["mtu"] as? Int, Reticulum.mtu,
                       "phyparams mtu must match Reticulum.mtu")
    }

    func testPhyparamsLinkCurveIsString() {
        let p = Reticulum.phyparams()
        XCTAssertNotNil(p["linkCurve"] as? String,
                        "phyparams linkCurve must be a String")
    }

    // MARK: - loglevelname()

    func testLoglevelnameCritical() {
        XCTAssertEqual(Reticulum.loglevelname(.critical), "[Critical]")
    }
    func testLoglevelnamError() {
        XCTAssertEqual(Reticulum.loglevelname(.error), "[Error]   ")
    }
    func testLoglevelNameNotice() {
        XCTAssertEqual(Reticulum.loglevelname(.notice), "[Notice]  ")
    }
    func testLoglevelNameExtreme() {
        // Python uses "[Extra]" for LOG_EXTREME
        XCTAssertEqual(Reticulum.loglevelname(.extreme), "[Extra]   ")
    }
    func testLoglevelNamePathing() {
        // Python: loglevelname(LOG_PATHING) == "[Pathing] "
        XCTAssertEqual(Reticulum.loglevelname(.pathing), "[Pathing] ")
    }
}
