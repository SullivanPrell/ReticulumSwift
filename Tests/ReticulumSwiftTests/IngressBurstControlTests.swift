import XCTest
@testable import ReticulumSwift

/// Tests for per-interface ingress burst control.
///
/// Mirrors Python's `Interface.should_ingress_limit()`, `Interface.hold_announce()`,
/// and `Interface.process_held_announces()`.
///
/// Python constants (Interface class):
///   IC_NEW_TIME              = 2*60*60  (7200 s — interface is "new" for first 2 hours)
///   IC_BURST_FREQ_NEW        = 3        Hz — burst threshold for new interfaces
///   IC_BURST_FREQ            = 10       Hz — burst threshold for established interfaces
///   IC_PR_BURST_FREQ_NEW     = 3        Hz
///   IC_PR_BURST_FREQ         = 8        Hz
///   IC_BURST_HOLD            = 15       s — hold duration before deactivating burst
///   IC_BURST_PENALTY         = 15       s — penalty delay before releasing held announces
///   IC_HELD_RELEASE_INTERVAL = 5        s — interval between individual held releases
///   MAX_HELD_ANNOUNCES       = 256
final class IngressBurstControlTests: XCTestCase {

    // MARK: - Constants

    func testIcNewTimeConstant() {
        XCTAssertEqual(IngressControlState.icNewTime, 7200.0, accuracy: 0.001)
    }
    func testIcBurstFreqNewConstant() {
        XCTAssertEqual(IngressControlState.icBurstFreqNew, 3.0, accuracy: 0.001)
    }
    func testIcBurstFreqConstant() {
        XCTAssertEqual(IngressControlState.icBurstFreq, 10.0, accuracy: 0.001)
    }
    func testIcBurstHoldConstant() {
        XCTAssertEqual(IngressControlState.icBurstHold, 15.0, accuracy: 0.001)
    }
    func testIcBurstPenaltyConstant() {
        XCTAssertEqual(IngressControlState.icBurstPenalty, 15.0, accuracy: 0.001)
    }
    func testIcHeldReleaseIntervalConstant() {
        XCTAssertEqual(IngressControlState.icHeldReleaseInterval, 5.0, accuracy: 0.001)
    }
    func testMaxHeldAnnouncesConstant() {
        XCTAssertEqual(IngressControlState.maxHeldAnnounces, 256)
    }

    // MARK: - shouldIngressLimit: no burst below threshold

    func testShouldIngressLimitFalseWhenQuiet() {
        let t = Transport()
        let iface = makeInterface(name: "quiet", createdAt: Date())
        t.register(interface: iface)

        // No announces recorded → frequency = 0 < threshold → should NOT limit
        let limited = t.shouldIngressLimit(on: iface, now: Date().timeIntervalSince1970)
        XCTAssertFalse(limited, "quiet interface must not be ingress-limited")
    }

    // MARK: - shouldIngressLimit: activates when frequency exceeds threshold

    func testShouldIngressLimitActivatesOnHighFrequency() {
        let t = Transport()
        // Use a "mature" interface (age > IC_NEW_TIME) so threshold is IC_BURST_FREQ (10 Hz).
        let createdAt = Date(timeIntervalSinceNow: -(IngressControlState.icNewTime + 1))
        let iface = makeInterface(name: "busy", createdAt: createdAt)
        t.register(interface: iface)

        let base: TimeInterval = 1000
        // Inject enough announces to push frequency well above 10 Hz.
        // 60 announces in 1 second = 60 Hz >> 10 Hz threshold.
        for i in 0..<60 { t.notifyIncomingAnnounce(on: iface, at: base + Double(i) * 0.016) }

        let limited = t.shouldIngressLimit(on: iface, now: base + 1.0)
        XCTAssertTrue(limited, "high-frequency announce stream must activate ingress limiting")
    }

    // MARK: - shouldIngressLimit: new interface uses lower threshold

    func testNewInterfaceUsesLowerBurstFreqNew() {
        let t = Transport()
        // New interface (age < IC_NEW_TIME): threshold = IC_BURST_FREQ_NEW = 3 Hz.
        let iface = makeInterface(name: "new-iface", createdAt: Date())
        t.register(interface: iface)

        let base: TimeInterval = 1000
        // 20 announces in 1 second = 20 Hz >> 3 Hz threshold.
        for i in 0..<20 { t.notifyIncomingAnnounce(on: iface, at: base + Double(i) * 0.05) }

        let limited = t.shouldIngressLimit(on: iface, now: base + 1.0)
        XCTAssertTrue(limited, "new interface must activate burst at IC_BURST_FREQ_NEW (3 Hz)")
    }

    // MARK: - shouldIngressLimit: burst stays active until hold elapses

    func testBurstStaysActiveDuringHoldPeriod() {
        let t = Transport()
        let createdAt = Date(timeIntervalSinceNow: -(IngressControlState.icNewTime + 1))
        let iface = makeInterface(name: "hold", createdAt: createdAt)
        t.register(interface: iface)

        let base: TimeInterval = 1000
        // Trigger burst.
        for i in 0..<60 { t.notifyIncomingAnnounce(on: iface, at: base + Double(i) * 0.016) }
        _ = t.shouldIngressLimit(on: iface, now: base + 1.0)  // activate burst

        // Now frequency drops (no more announces). Check immediately — still in burst hold.
        let stillLimited = t.shouldIngressLimit(on: iface, now: base + 2.0)
        XCTAssertTrue(stillLimited, "burst must remain active during IC_BURST_HOLD window")
    }

    // MARK: - shouldIngressLimit: deactivates after hold period

    func testBurstDeactivatesAfterHoldPeriod() {
        let t = Transport()
        let createdAt = Date(timeIntervalSinceNow: -(IngressControlState.icNewTime + 1))
        let iface = makeInterface(name: "deactivate", createdAt: createdAt)
        t.register(interface: iface)

        let base: TimeInterval = 1000
        // Trigger burst.
        for i in 0..<60 { t.notifyIncomingAnnounce(on: iface, at: base + Double(i) * 0.016) }
        _ = t.shouldIngressLimit(on: iface, now: base + 1.0)  // activate

        // After hold period + a margin, frequency has dropped and burst should deactivate.
        // IC_BURST_HOLD = 15 s. Query at base + 20 (no new announces → low freq).
        let nowAfterHold = base + 20.0
        // Inject 3 samples at nowAfterHold - 5, -4, -3 (low rate ≈ 1 Hz < 10 Hz threshold)
        t.notifyIncomingAnnounce(on: iface, at: nowAfterHold - 5)
        t.notifyIncomingAnnounce(on: iface, at: nowAfterHold - 4)
        t.notifyIncomingAnnounce(on: iface, at: nowAfterHold - 3)

        let deactivated = t.shouldIngressLimit(on: iface, now: nowAfterHold)
        XCTAssertFalse(deactivated,
            "burst must deactivate when frequency drops and IC_BURST_HOLD has elapsed")
    }

    // MARK: - holdAnnounce stores packet

    func testHoldAnnounceStoresPacket() throws {
        let t = Transport()
        let iface = makeInterface(name: "holder", createdAt: Date())
        t.register(interface: iface)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "test", aspects: ["hold"])
        let pkt = try Announce.make(for: dest)
        let decoded = try Announce.validate(pkt)

        t.holdAnnounce(pkt, destinationHash: decoded.destinationHash, on: iface)
        XCTAssertEqual(t.heldAnnounceCount(for: iface), 1,
            "held announces count must be 1 after holding one packet")
    }

    // MARK: - holdAnnounce caps at maxHeldAnnounces

    func testHoldAnnounceCapsAtMax() throws {
        let t = Transport()
        let iface = makeInterface(name: "cap-test", createdAt: Date())
        t.register(interface: iface)

        // Insert more than MAX_HELD_ANNOUNCES distinct destinations.
        for i in 0..<(IngressControlState.maxHeldAnnounces + 10) {
            let destHash = Hashes.truncatedHash(Data("dest\(i)".utf8))
            let fakePacket = Packet(
                destinationType: .single,
                packetType: .announce,
                destinationHash: destHash,
                data: Data(count: 10)
            )
            t.holdAnnounce(fakePacket, destinationHash: destHash, on: iface)
        }
        XCTAssertLessThanOrEqual(t.heldAnnounceCount(for: iface),
            IngressControlState.maxHeldAnnounces,
            "held announces must be capped at MAX_HELD_ANNOUNCES")
    }

    // MARK: - processHeldAnnounces releases lowest-hop announce

    func testProcessHeldAnnouncesReleasesLowestHop() throws {
        let t = Transport()
        let identity = Identity()
        let dest1 = try Destination(identity: identity, direction: .in, kind: .single,
                                    appName: "test", aspects: ["a"])
        t.ownerIdentity = identity
        t.register(destination: dest1)

        let iface = makeInterface(name: "releaser", createdAt: Date())
        t.register(interface: iface)

        // Hold two announces with different hop counts.
        var pktLow = Packet(destinationType: .single, packetType: .announce,
                            destinationHash: Data(repeating: 0x11, count: 16), data: Data(count: 4))
        pktLow.hops = 1
        var pktHigh = Packet(destinationType: .single, packetType: .announce,
                             destinationHash: Data(repeating: 0x22, count: 16), data: Data(count: 4))
        pktHigh.hops = 5

        t.holdAnnounce(pktLow,  destinationHash: pktLow.destinationHash,  on: iface)
        t.holdAnnounce(pktHigh, destinationHash: pktHigh.destinationHash, on: iface)
        XCTAssertEqual(t.heldAnnounceCount(for: iface), 2)

        // Force heldRelease to the past so processing can release immediately.
        t.forceHeldRelease(for: iface, to: Date().timeIntervalSince1970 - 1)

        let released = t.processHeldAnnounces(for: iface, now: Date().timeIntervalSince1970)
        // Should release exactly one announce (the lowest-hop one).
        XCTAssertEqual(t.heldAnnounceCount(for: iface), 1,
            "processHeldAnnounces must release exactly one announce per call")
        XCTAssertEqual(released?.destinationHash, pktLow.destinationHash,
            "lowest-hop announce must be released first")
    }

    // MARK: - processHeldAnnounces respects heldRelease timer

    func testProcessHeldAnnouncesRespectsTimer() throws {
        let t = Transport()
        let iface = makeInterface(name: "timer", createdAt: Date())
        t.register(interface: iface)

        let fakeHash = Data(repeating: 0xAB, count: 16)
        let pkt = Packet(destinationType: .single, packetType: .announce,
                         destinationHash: fakeHash, data: Data(count: 4))
        t.holdAnnounce(pkt, destinationHash: fakeHash, on: iface)

        // heldRelease is in the future — nothing should be released.
        t.forceHeldRelease(for: iface, to: Date().timeIntervalSince1970 + 100)
        let released = t.processHeldAnnounces(for: iface, now: Date().timeIntervalSince1970)
        XCTAssertNil(released, "held announce must not be released before heldRelease timer")
        XCTAssertEqual(t.heldAnnounceCount(for: iface), 1)
    }

    // MARK: - ingressControl = false bypasses all limiting

    func testIngressControlFalseBypassesLimiting() {
        let t = Transport()
        let iface = makeInterface(name: "no-ic", createdAt: Date(), ingressControl: false)
        t.register(interface: iface)

        let base: TimeInterval = 1000
        // Flood with announces.
        for i in 0..<100 { t.notifyIncomingAnnounce(on: iface, at: base + Double(i) * 0.01) }

        let limited = t.shouldIngressLimit(on: iface, now: base + 1.0)
        XCTAssertFalse(limited,
            "interface with ingressControl=false must never be ingress-limited")
    }

    // MARK: - Helpers

    final class TestInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var createdAt: Date
        var ingressControl: Bool
        init(name: String, createdAt: Date, ingressControl: Bool = true) {
            self.name = name
            self.createdAt = createdAt
            self.ingressControl = ingressControl
        }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {}
    }

    private func makeInterface(name: String,
                               createdAt: Date,
                               ingressControl: Bool = true) -> TestInterface {
        TestInterface(name: name, createdAt: createdAt, ingressControl: ingressControl)
    }
}
