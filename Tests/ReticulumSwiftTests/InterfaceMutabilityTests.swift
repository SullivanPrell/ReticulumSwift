import XCTest
@testable import ReticulumSwift

/// `bugs/025` — Python mutates interface attributes at runtime; this port declared them
/// `{ get }`-only with blanket extension defaults, so a parsed config value has nowhere to be
/// written. Adding the missing config parser fixes none of them, because `iface.mode = …` does not
/// compile for `any Interface`.
///
/// Python assigns all of these per interface at `RNS/Reticulum.py:900-941` (the `__apply_config`
/// interface branch) and `:1092-1130` (`_add_interface`).
///
/// Every assertion here runs over `InterfaceConformers.everyConcreteInterface()` rather than a
/// test double. That is deliberate: the mode-dependent Transport tests pass today because their
/// mock declares its own stored `mode`, while no *real* interface can be anything but `.full`.
/// **A test double that can do something the real type cannot is not a test of the real type.**
final class InterfaceMutabilityTests: XCTestCase {

    /// Python: `interface.mode = …` (`Reticulum.py:910`). Every mode alias in
    /// `Reticulum.py:737-769` must be reachable on every interface type.
    func testModeIsSettableOnEveryInterface() throws {
        for iface in try InterfaceConformers.everyConcreteInterface() {
            let type = String(describing: type(of: iface))
            XCTAssertEqual(iface.mode, .full, "\(type): default mode should be .full")

            iface.mode = .gateway
            XCTAssertEqual(iface.mode, .gateway,
                           "\(type): mode must be settable — a config value with nowhere to go is "
                           + "indistinguishable from a config key that is never read")

            iface.mode = .accessPoint
            XCTAssertEqual(iface.mode, .accessPoint, "\(type): mode must stay settable")
        }
    }

    /// Python: `interface.announce_rate_target / _grace / _penalty` (`Reticulum.py:900-941`).
    /// Without these, Transport's announce rate-limiting code is dead on every real interface.
    func testAnnounceRateControlIsSettableOnEveryInterface() throws {
        for iface in try InterfaceConformers.everyConcreteInterface() {
            let type = String(describing: type(of: iface))
            XCTAssertNil(iface.announceRateTarget, "\(type): default target should be nil")

            iface.announceRateTarget = 3600
            iface.announceRateGrace = 3
            iface.announceRatePenalty = 7200

            XCTAssertEqual(iface.announceRateTarget, 3600, "\(type): announceRateTarget")
            XCTAssertEqual(iface.announceRateGrace, 3, "\(type): announceRateGrace")
            XCTAssertEqual(iface.announceRatePenalty, 7200, "\(type): announceRatePenalty")
        }
    }

    /// Python: `interface.ingress_control` / `egress_control` / `EC_PR_FREQ`.
    func testIngressAndEgressControlAreSettableOnEveryInterface() throws {
        for iface in try InterfaceConformers.everyConcreteInterface() {
            let type = String(describing: type(of: iface))
            XCTAssertTrue(iface.ingressControl, "\(type): ingress control defaults on, per Python")
            XCTAssertFalse(iface.egressControl, "\(type): egress control defaults off, per Python")

            iface.ingressControl = false
            iface.egressControl = true
            iface.ecPrFreq = 12.5

            XCTAssertFalse(iface.ingressControl, "\(type): ingressControl must be settable")
            XCTAssertTrue(iface.egressControl, "\(type): egressControl must be settable")
            XCTAssertEqual(iface.ecPrFreq, 12.5, "\(type): ecPrFreq must be settable")
        }
    }

    /// Python: `interface.bitrate = …` (`Reticulum.py:1092-1130`), and it is copied onto every
    /// spawned sub-interface (`TCPInterface.py:594-641`).
    func testBitrateIsSettableOnEveryInterface() throws {
        for iface in try InterfaceConformers.everyConcreteInterface() {
            let type = String(describing: type(of: iface))
            iface.bitrate = 1_234_567
            XCTAssertEqual(iface.bitrate, 1_234_567, "\(type): bitrate must be settable")
        }
    }

    /// The no-op-setter half of the same defect, and arguably the worse half: these are declared
    /// `{ get set }` but the `Interface` extension supplies `set { }` (`Interface.swift:281-309`),
    /// so on any type that does not override them the assignment **compiles and is silently
    /// discarded**. `bootstrapOnly` is stored by 2 of 19 conformers, so 17 of them accept the
    /// write and drop it.
    func testDeclaredSettablePropertiesActuallyStoreTheirValue() throws {
        for iface in try InterfaceConformers.everyConcreteInterface() {
            let type = String(describing: type(of: iface))

            iface.bootstrapOnly = true
            XCTAssertTrue(iface.bootstrapOnly,
                          "\(type): bootstrapOnly is declared settable — a no-op setter that "
                          + "silently discards the value is worse than a get-only property, "
                          + "because it compiles")

            iface.recursivePrs = true
            XCTAssertTrue(iface.recursivePrs, "\(type): recursivePrs must store its value")

            iface.announcesFromInternal = false
            XCTAssertFalse(iface.announcesFromInternal,
                           "\(type): announcesFromInternal must store its value")

            iface.announcesToInternal = true
            XCTAssertEqual(iface.announcesToInternal, true,
                           "\(type): announcesToInternal must store its value")

            iface.gravity = 42
            XCTAssertEqual(iface.gravity, 42, "\(type): gravity must store its value")

            iface.wantsTunnel = true
            XCTAssertTrue(iface.wantsTunnel, "\(type): wantsTunnel must store its value")
        }
    }

    /// Python's IFAC defaults are per interface class, not one global value: the radio and serial
    /// classes declare 8 (`RNodeInterface.py:110`, `RNodeMultiInterface.py:137`,
    /// `SerialInterface.py:53`, `KISSInterface.py:63`, `AX25KISSInterface.py:70`) where
    /// TCP/UDP/Auto/Backbone/I2P/Weave declare 16. Applied at `Reticulum.py:918` / `:1110`.
    ///
    /// If wrong, IFAC-protected LoRa/serial links between Swift and Python drop 100% of traffic
    /// while reporting Up.
    ///
    /// `BLEMeshInterface` has no Python counterpart; it is a low-bandwidth radio interface and
    /// already declared 8 deliberately, so it belongs with the radio family.
    func testDefaultIfacSizeIsPerInterfaceClass() throws {
        let expectEight: Set<String> = [
            "RNodeInterface", "RNodeMultiInterface", "RNodeSubInterface",
            "SerialInterface", "KISSInterface", "AX25KISSInterface",
            "BLEMeshInterface",
        ]

        for iface in try InterfaceConformers.everyConcreteInterface() {
            let type = String(describing: type(of: iface))
            let expected = expectEight.contains(type) ? 8 : 16
            XCTAssertEqual(iface.ifacSize, expected,
                           "\(type): default IFAC size must match the Python class default "
                           + "(\(expected)), not one global constant")
        }
    }
}
