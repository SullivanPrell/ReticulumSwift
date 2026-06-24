import XCTest
@testable import ReticulumSwift

/// Tests for Interface.Mode constants, discoverPathsFor set, and PR-specific
/// ingress/egress burst control.
///
/// Python reference:
///   Interface.MODE_FULL          = 0x01
///   Interface.MODE_POINT_TO_POINT= 0x02
///   Interface.MODE_ACCESS_POINT  = 0x03
///   Interface.MODE_ROAMING       = 0x04
///   Interface.MODE_BOUNDARY      = 0x05
///   Interface.MODE_GATEWAY       = 0x06
///   Interface.DISCOVER_PATHS_FOR = [MODE_ACCESS_POINT, MODE_GATEWAY, MODE_ROAMING]
///   Interface.EC_PR_FREQ         = 5  (egress path-request frequency cap, Hz)
final class InterfaceModeTests: XCTestCase {

    // MARK: - Mode raw values

    func testModeFull() {
        XCTAssertEqual(InterfaceMode.full.rawValue, 0x01)
    }
    func testModePointToPoint() {
        XCTAssertEqual(InterfaceMode.pointToPoint.rawValue, 0x02)
    }
    func testModeAccessPoint() {
        XCTAssertEqual(InterfaceMode.accessPoint.rawValue, 0x03)
    }
    func testModeRoaming() {
        XCTAssertEqual(InterfaceMode.roaming.rawValue, 0x04)
    }
    func testModeBoundary() {
        XCTAssertEqual(InterfaceMode.boundary.rawValue, 0x05)
    }
    func testModeGateway() {
        XCTAssertEqual(InterfaceMode.gateway.rawValue, 0x06)
    }

    // MARK: - discoverPathsFor

    func testDiscoverPathsForContainsAccessPoint() {
        XCTAssertTrue(InterfaceMode.discoverPathsFor.contains(.accessPoint))
    }
    func testDiscoverPathsForContainsGateway() {
        XCTAssertTrue(InterfaceMode.discoverPathsFor.contains(.gateway))
    }
    func testDiscoverPathsForContainsRoaming() {
        XCTAssertTrue(InterfaceMode.discoverPathsFor.contains(.roaming))
    }
    func testDiscoverPathsForExcludesFull() {
        XCTAssertFalse(InterfaceMode.discoverPathsFor.contains(.full))
    }
    func testDiscoverPathsForExcludesPointToPoint() {
        XCTAssertFalse(InterfaceMode.discoverPathsFor.contains(.pointToPoint))
    }
    func testDiscoverPathsForExcludesBoundary() {
        XCTAssertFalse(InterfaceMode.discoverPathsFor.contains(.boundary))
    }

    // MARK: - Default mode on Interface

    func testDefaultModeIsFull() {
        let iface = ModeTestInterface(name: "default")
        XCTAssertEqual(iface.mode, .full)
    }

    // MARK: - shouldIngressLimitPR: quiet interface

    func testShouldIngressLimitPRFalseWhenQuiet() {
        let t = Transport()
        let iface = ModeTestInterface(name: "quiet", createdAt: Date())
        t.register(interface: iface)
        let limited = t.shouldIngressLimitPR(on: iface, now: Date().timeIntervalSince1970)
        XCTAssertFalse(limited, "quiet interface must not trigger PR ingress limiting")
    }

    // MARK: - shouldIngressLimitPR: activates on high frequency

    func testShouldIngressLimitPRActivatesOnFlood() {
        let t = Transport()
        // Use a createdAt far in the past so it's "established" (threshold = 8 Hz).
        let old = Date(timeIntervalSinceNow: -10_000)
        let iface = ModeTestInterface(name: "flood", createdAt: old)
        t.register(interface: iface)

        let base: TimeInterval = Date().timeIntervalSince1970
        // Established threshold = 8 Hz. Send 20 PRs in 1 second = 20 Hz.
        for i in 0..<20 {
            t.notifyIncomingPathRequest(on: iface, at: base - 1.0 + Double(i) * 0.05)
        }
        let limited = t.shouldIngressLimitPR(on: iface, now: base)
        XCTAssertTrue(limited, "high-frequency PRs must activate PR ingress burst limiting")
    }

    // MARK: - shouldIngressLimitPR: new interface uses lower threshold

    func testShouldIngressLimitPRNewInterfaceLowerThreshold() {
        let t = Transport()
        // New interface (just created): threshold = 3 Hz. 10 PRs in 1 second = 10 Hz > 3.
        let iface = ModeTestInterface(name: "new", createdAt: Date())
        t.register(interface: iface)

        let base: TimeInterval = Date().timeIntervalSince1970
        for i in 0..<10 {
            t.notifyIncomingPathRequest(on: iface, at: base - 1.0 + Double(i) * 0.1)
        }
        let limited = t.shouldIngressLimitPR(on: iface, now: base)
        XCTAssertTrue(limited, "new interface must activate PR burst at lower threshold (3 Hz)")
    }

    // MARK: - shouldIngressLimitPR: false when ingressControl disabled

    func testShouldIngressLimitPRFalseWithIngressControlDisabled() {
        let t = Transport()
        let iface = ModeTestInterface(name: "no-ic", createdAt: Date(), ingressControl: false)
        t.register(interface: iface)

        let base: TimeInterval = Date().timeIntervalSince1970
        for i in 0..<20 {
            t.notifyIncomingPathRequest(on: iface, at: base - 1.0 + Double(i) * 0.05)
        }
        let limited = t.shouldIngressLimitPR(on: iface, now: base)
        XCTAssertFalse(limited, "ingressControl=false must never PR-ingress-limit")
    }

    // MARK: - shouldEgressLimitPR: quiet interface

    func testShouldEgressLimitPRFalseWhenQuiet() {
        let t = Transport()
        let iface = ModeTestInterface(name: "eq", createdAt: Date(), egressControl: true)
        t.register(interface: iface)
        let limited = t.shouldEgressLimitPR(on: iface, now: Date().timeIntervalSince1970)
        XCTAssertFalse(limited, "quiet interface must not be egress-PR-limited")
    }

    // MARK: - shouldEgressLimitPR: activates above EC_PR_FREQ (5 Hz)

    func testShouldEgressLimitPRActivatesOnFlood() {
        let t = Transport()
        let iface = ModeTestInterface(name: "eflood", createdAt: Date(), egressControl: true)
        t.register(interface: iface)

        let base: TimeInterval = Date().timeIntervalSince1970
        // EC_PR_FREQ = 5 Hz. Send 20 outgoing PRs in 1 second = 20 Hz.
        for i in 0..<20 {
            t.notifyOutgoingPathRequest(on: iface, at: base - 1.0 + Double(i) * 0.05)
        }
        let limited = t.shouldEgressLimitPR(on: iface, now: base)
        XCTAssertTrue(limited, "high-frequency outgoing PRs must activate egress PR limiting")
    }

    // MARK: - shouldEgressLimitPR: false when egressControl disabled

    func testShouldEgressLimitPRFalseWithEgressControlDisabled() {
        let t = Transport()
        let iface = ModeTestInterface(name: "no-ec", createdAt: Date(), egressControl: false)
        t.register(interface: iface)

        let base: TimeInterval = Date().timeIntervalSince1970
        for i in 0..<20 {
            t.notifyOutgoingPathRequest(on: iface, at: base - 1.0 + Double(i) * 0.05)
        }
        let limited = t.shouldEgressLimitPR(on: iface, now: base)
        XCTAssertFalse(limited, "egressControl=false must never egress-PR-limit")
    }

    // MARK: - Helpers

    final class ModeTestInterface: Interface {
        var name: String
        var bitrate: Int = 100_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var createdAt: Date
        var ingressControl: Bool
        var egressControl: Bool
        var mode: InterfaceMode = .full

        init(name: String, createdAt: Date = Date(), ingressControl: Bool = true, egressControl: Bool = false) {
            self.name = name
            self.createdAt = createdAt
            self.ingressControl = ingressControl
            self.egressControl = egressControl
        }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }
}
