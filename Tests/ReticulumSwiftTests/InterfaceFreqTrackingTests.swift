import XCTest
@testable import ReticulumSwift

/// Tests for per-interface announce and path-request frequency tracking.
/// Mirrors Python's Interface frequency deques (ia_freq_deque, oa_freq_deque, ip_freq_deque, op_freq_deque)
/// and the corresponding frequency methods.
///
/// Python constants:
///   AR_MINFREQ_HZ = 0.1  →  AR_FREQ_DECAY = 10.0 s
///   PR_MINFREQ_HZ = 0.1  →  PR_FREQ_DECAY = 10.0 s
///   IC_DEQUE_MIN_SAMPLE  = 2  (need > 2 samples to return non-zero)
///   IA_FREQ_SAMPLES      = 48 (deque max length)
final class InterfaceFreqTrackingTests: XCTestCase {

    // MARK: - Constants

    func testArFreqDecayConstant() {
        XCTAssertEqual(InterfaceFreqTracker.arFreqDecay, 10.0, accuracy: 0.001,
            "AR_FREQ_DECAY = 1/AR_MINFREQ_HZ = 1/0.1 = 10")
    }

    func testPrFreqDecayConstant() {
        XCTAssertEqual(InterfaceFreqTracker.prFreqDecay, 10.0, accuracy: 0.001,
            "PR_FREQ_DECAY = 1/PR_MINFREQ_HZ = 1/0.1 = 10")
    }

    func testMinSamplesConstant() {
        XCTAssertEqual(InterfaceFreqTracker.minSamples, 2,
            "IC_DEQUE_MIN_SAMPLE = 2 — need > 2 samples to compute non-zero frequency")
    }

    func testMaxSamplesConstant() {
        XCTAssertEqual(InterfaceFreqTracker.maxSamples, 48,
            "IA_FREQ_SAMPLES = OA_FREQ_SAMPLES = IP_FREQ_SAMPLES = OP_FREQ_SAMPLES = 48")
    }

    // MARK: - Zero before min samples

    func testIncomingAnnounceFrequencyZeroWithFewSamples() {
        let t = InterfaceFreqTracker()
        // Python: `if not n > IC_DEQUE_MIN_SAMPLE: return 0`
        // With 0 or 1 or 2 samples → 0
        XCTAssertEqual(t.incomingAnnounceFrequency(), 0.0)
        t.recordIncomingAnnounce(at: 0)
        XCTAssertEqual(t.incomingAnnounceFrequency(now: 1), 0.0)
        t.recordIncomingAnnounce(at: 1)
        XCTAssertEqual(t.incomingAnnounceFrequency(now: 2), 0.0)
    }

    func testOutgoingAnnounceFrequencyZeroWithFewSamples() {
        let t = InterfaceFreqTracker()
        // Python outgoing: `if not len(deque) > 1: return 0`  (threshold = 1, not IC_DEQUE_MIN_SAMPLE)
        XCTAssertEqual(t.outgoingAnnounceFrequency(), 0.0)
        t.recordOutgoingAnnounce(at: 0)
        XCTAssertEqual(t.outgoingAnnounceFrequency(now: 1), 0.0)
    }

    // MARK: - Non-zero frequency with enough samples

    func testIncomingAnnounceFrequencyNonZero() {
        let t = InterfaceFreqTracker()
        // 3 announces at t=0,1,2; now=2 → n=3, span=2, freq=1.5 Hz
        t.recordIncomingAnnounce(at: 0)
        t.recordIncomingAnnounce(at: 1)
        t.recordIncomingAnnounce(at: 2)
        let freq = t.incomingAnnounceFrequency(now: 2)
        XCTAssertEqual(freq, 1.5, accuracy: 0.01)
    }

    func testOutgoingAnnounceFrequencyNonZero() {
        let t = InterfaceFreqTracker()
        // 2 outgoing at t=0,2; now=2 → n=2, span=2, freq=1.0 Hz
        t.recordOutgoingAnnounce(at: 0)
        t.recordOutgoingAnnounce(at: 2)
        let freq = t.outgoingAnnounceFrequency(now: 2)
        XCTAssertEqual(freq, 1.0, accuracy: 0.01)
    }

    func testIncomingPathRequestFrequencyNonZero() {
        let t = InterfaceFreqTracker()
        t.recordIncomingPathRequest(at: 0)
        t.recordIncomingPathRequest(at: 1)
        t.recordIncomingPathRequest(at: 2)
        let freq = t.incomingPathRequestFrequency(now: 2)
        XCTAssertEqual(freq, 1.5, accuracy: 0.01)
    }

    func testOutgoingPathRequestFrequencyNonZero() {
        let t = InterfaceFreqTracker()
        t.recordOutgoingPathRequest(at: 0)
        t.recordOutgoingPathRequest(at: 2)
        let freq = t.outgoingPathRequestFrequency(now: 2)
        XCTAssertEqual(freq, 1.0, accuracy: 0.01)
    }

    // MARK: - Max samples cap

    func testMaxSamplesCapPreservesNewest() {
        let t = InterfaceFreqTracker()
        // Insert 50 samples — only last 48 kept.
        for i in 0..<50 { t.recordIncomingAnnounce(at: Double(i)) }
        XCTAssertLessThanOrEqual(t.incomingAnnounceSampleCount, InterfaceFreqTracker.maxSamples)
    }

    // MARK: - Span zero guard

    func testZeroSpanReturnsZero() {
        let t = InterfaceFreqTracker()
        // All at exact same timestamp.
        t.recordIncomingAnnounce(at: 5)
        t.recordIncomingAnnounce(at: 5)
        t.recordIncomingAnnounce(at: 5)
        XCTAssertEqual(t.incomingAnnounceFrequency(now: 5), 0.0,
            "span == 0 must return 0 to avoid division by zero")
    }

    // MARK: - Transport integration

    func testTransportRecordsIncomingAnnounce() throws {
        let t = Transport()
        final class TestInterface: Interface {
            var name = "freq-test"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestInterface()
        t.register(interface: iface)

        let freq0 = t.incomingAnnounceFrequency(for: iface)
        XCTAssertEqual(freq0, 0.0, "no announces yet → 0")

        // Simulate 3 incoming announces with explicit timestamps spread over 1 second.
        let base: TimeInterval = 1000
        t.notifyIncomingAnnounce(on: iface, at: base)
        t.notifyIncomingAnnounce(on: iface, at: base + 0.3)
        t.notifyIncomingAnnounce(on: iface, at: base + 0.6)

        // Query at base+0.6 — 3 samples over 0.6s → freq = 5 Hz.
        let freq = t.incomingAnnounceFrequency(for: iface)
        XCTAssertGreaterThan(freq, 0.0, "3 announces spread over 0.6 s → non-zero frequency")
    }

    func testTransportRecordsOutgoingAnnounce() throws {
        let t = Transport()
        final class TestInterface: Interface {
            var name = "freq-test2"; var bitrate = 0; var isOnline = true
            var inboundHandler: ((Packet, any Interface) -> Void)?
            func start() throws {}; func stop() {}
            func send(_ packet: Packet) throws {}
        }
        let iface = TestInterface()
        t.register(interface: iface)

        let base: TimeInterval = 2000
        t.notifyOutgoingAnnounce(on: iface, at: base)
        t.notifyOutgoingAnnounce(on: iface, at: base + 0.5)

        let freq = t.outgoingAnnounceFrequency(for: iface)
        XCTAssertGreaterThan(freq, 0.0)
    }
}
