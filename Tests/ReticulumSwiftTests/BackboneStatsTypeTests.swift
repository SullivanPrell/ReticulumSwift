import XCTest
@testable import ReticulumSwift

/// The stats `type` field is what a Python `rnstatus -j` attached to a Swift shared instance
/// dumps verbatim, and consumers key on it. Python instantiates `BackboneClientInterface` for
/// any *dialing* backbone config (`Reticulum.py:994-1000`; the class literally named
/// `BackboneInterface`, `BackboneInterface.py:51`, is the listener) — so a dialing interface
/// must never report the listener's class name.
final class BackboneStatsTypeTests: XCTestCase {
    func testADialingBackboneReportsTheClientClassName() {
        let iface = BackboneInterface(name: "Uplink", host: "10.0.0.1", port: 4242)
        XCTAssertEqual(iface.statsTypeName, "BackboneClientInterface",
                       """
                       a dialing backbone interface reported the Python LISTENER's class name — \
                       any consumer keying on ifstats["type"] mis-classifies it \
                       (Reticulum.py:1472 emits type(interface).__name__, and the identical \
                       config on Python constructs BackboneClientInterface)
                       """)
        XCTAssertEqual(iface.displayName, "BackboneInterface[Uplink/10.0.0.1:4242]",
                       "the human-facing name keeps Python's client __str__ form — the stats "
                       + "type and the display name are different contracts, and the override "
                       + "must not leak into this one")
    }
}
