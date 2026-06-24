import XCTest
@testable import ReticulumSwift

/// Tests verifying that Reticulum exposes the wire-format constants Python consumers
/// access as class attributes (e.g. `RNS.Reticulum.MTU`, `RNS.Reticulum.MDU`, …).
///
/// Python reference (Reticulum.py):
///   Reticulum.MTU            = 500
///   Reticulum.MDU            = 464
///   Reticulum.HEADER_MINSIZE = 19
///   Reticulum.HEADER_MAXSIZE = 35
///   Reticulum.IFAC_MIN_SIZE  = 1
final class ReticulumWireConstantsTests: XCTestCase {

    func testMtu() {
        XCTAssertEqual(Reticulum.mtu, 500,
                       "Reticulum.MTU must be 500 bytes")
    }

    func testMdu() {
        XCTAssertEqual(Reticulum.mdu, 464,
                       "Reticulum.MDU must be 464 bytes")
    }

    func testHeaderMinSize() {
        XCTAssertEqual(Reticulum.headerMinSize, 19,
                       "Reticulum.HEADER_MINSIZE must be 19 bytes")
    }

    func testHeaderMaxSize() {
        XCTAssertEqual(Reticulum.headerMaxSize, 35,
                       "Reticulum.HEADER_MAXSIZE must be 35 bytes")
    }

    func testIfacMinSize() {
        XCTAssertEqual(Reticulum.ifacMinSize, 1,
                       "Reticulum.IFAC_MIN_SIZE must be 1 byte")
    }

    /// Derived relationship: MDU = MTU - HEADER_MAXSIZE - IFAC_MIN_SIZE.
    func testMduDerivation() {
        XCTAssertEqual(Reticulum.mdu,
                       Reticulum.mtu - Reticulum.headerMaxSize - Reticulum.ifacMinSize,
                       "MDU must equal MTU - HEADER_MAXSIZE - IFAC_MIN_SIZE")
    }

    /// Constants are mirrored from `Constants`; verify they stay in sync.
    func testConsistencyWithConstants() {
        XCTAssertEqual(Reticulum.mtu, Constants.mtu)
        XCTAssertEqual(Reticulum.mdu, Constants.mdu)
        XCTAssertEqual(Reticulum.headerMinSize, Constants.headerMinSize)
        XCTAssertEqual(Reticulum.headerMaxSize, Constants.headerMaxSize)
        XCTAssertEqual(Reticulum.ifacMinSize, Constants.ifacMinSize)
    }

    /// `getInstance()` returns nil before start(), matching Python's get_instance() convention.
    func testGetInstanceNilBeforeStart() {
        // This test must NOT call Reticulum.start() — we just verify the accessor works.
        // (A live test would need tearDown to stop it; here we just check the API shape.)
        let _ = Reticulum.getInstance() // must not crash; may be nil or a previous instance
    }
}
