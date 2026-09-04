import Foundation

/// Per-interface announce and path-request frequency tracker.
///
/// Mirrors Python's `Interface.ia_freq_deque`, `oa_freq_deque`, `ip_freq_deque`,
/// `op_freq_deque` and the corresponding frequency methods
/// (`incoming_announce_frequency`, `outgoing_announce_frequency`, and so on).
///
/// Timestamps are stored in a capped circular array. Frequency is computed as:
///   n / (now - oldest), pruning the oldest sample if the span exceeds FREQ_DECAY.
public final class InterfaceFreqTracker {

    // MARK: - Python constants

    /// Announce frequency decay window (seconds).
    /// Mirrors Python: `AR_FREQ_DECAY = 1 / AR_MINFREQ_HZ = 1 / 0.1 = 10`.
    public static let arFreqDecay: Double = 10.0
    /// Path-request frequency decay window (seconds).
    /// Mirrors Python: `PR_FREQ_DECAY = 1 / PR_MINFREQ_HZ = 1 / 0.1 = 10`.
    public static let prFreqDecay: Double = 10.0
    /// Minimum number of samples in the deque before a non-zero frequency is returned.
    /// Mirrors Python: `IC_DEQUE_MIN_SAMPLE = 2`  (condition is `n > 2`).
    public static let minSamples: Int = 2
    /// Maximum samples retained per deque. Mirrors Python `IA_FREQ_SAMPLES = 48`.
    public static let maxSamples: Int = 48

    // MARK: - Timestamp deques

    private var ia: [TimeInterval] = []  // incoming announces
    private var oa: [TimeInterval] = []  // outgoing announces
    private var ip: [TimeInterval] = []  // incoming path requests
    private var op: [TimeInterval] = []  // outgoing path requests

    /// Guards the four deques. The tracker is recorded on inbound/outbound
    /// interface threads and read on the jobs/management threads; the frequency
    /// queries also prune (mutate) the deque, so reads and writes must be
    /// mutually exclusive. Self-contained—this lock never nests with any other.
    private let lock = NSLock()

    // MARK: - Record events

    public func recordIncomingAnnounce(at t: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock(); defer { lock.unlock() }
        append(t, to: &ia)
    }
    public func recordOutgoingAnnounce(at t: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock(); defer { lock.unlock() }
        append(t, to: &oa)
    }
    public func recordIncomingPathRequest(at t: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock(); defer { lock.unlock() }
        append(t, to: &ip)
    }
    public func recordOutgoingPathRequest(at t: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock(); defer { lock.unlock() }
        append(t, to: &op)
    }

    // MARK: - Frequency queries

    /// Mirrors Python's `Interface.incoming_announce_frequency()`.
    public func incomingAnnounceFrequency(now: TimeInterval = Date().timeIntervalSince1970) -> Double {
        lock.lock(); defer { lock.unlock() }
        return frequency(&ia, decay: Self.arFreqDecay, minCount: Self.minSamples, now: now)
    }
    /// Mirrors Python's `Interface.outgoing_announce_frequency()`.
    /// Note: Python uses `> 1` (not `> IC_DEQUE_MIN_SAMPLE`) for outgoing.
    public func outgoingAnnounceFrequency(now: TimeInterval = Date().timeIntervalSince1970) -> Double {
        lock.lock(); defer { lock.unlock() }
        return frequency(&oa, decay: Self.arFreqDecay, minCount: 1, now: now)
    }
    /// Mirrors Python's `Interface.incoming_pr_frequency()`.
    public func incomingPathRequestFrequency(now: TimeInterval = Date().timeIntervalSince1970) -> Double {
        lock.lock(); defer { lock.unlock() }
        return frequency(&ip, decay: Self.prFreqDecay, minCount: Self.minSamples, now: now)
    }
    /// Mirrors Python's `Interface.outgoing_pr_frequency(preemptive:)`.
    ///
    /// RNS 1.5.1 added `preemptive`, which counts the request the caller is *about to send*
    /// (`n = len(self.op_freq_deque)+(1 if preemptive else 0)`, `Interface.py:380`). The
    /// egress limiter asks what the frequency becomes once it authorizes this request, so a
    /// stream sitting exactly on the threshold is stopped rather than allowed to cross it.
    ///
    /// The extra sample lands in the numerator only. Python's minimum-count guard on the next
    /// line reads the real deque length, so a lone recorded request still reports zero and the
    /// first path request on an interface can't limit itself.
    public func outgoingPathRequestFrequency(preemptive: Bool = false,
                                             now: TimeInterval = Date().timeIntervalSince1970) -> Double {
        lock.lock(); defer { lock.unlock() }
        return frequency(&op, decay: Self.prFreqDecay, minCount: 1, now: now,
                         extraSamples: preemptive ? 1 : 0)
    }

    // MARK: - Test helpers

    /// Number of recorded incoming-announce samples (for testing the max-cap logic).
    public var incomingAnnounceSampleCount: Int { lock.lock(); defer { lock.unlock() }; return ia.count }
    /// Number of recorded outgoing path-request samples.
    public var outgoingPathRequestSampleCount: Int { lock.lock(); defer { lock.unlock() }; return op.count }

    // MARK: - Private

    /// Callers must hold `lock`.
    private func append(_ t: TimeInterval, to deque: inout [TimeInterval]) {
        deque.append(t)
        if deque.count > Self.maxSamples { deque.removeFirst() }
    }

    /// Python-equivalent frequency computation.
    /// Returns 0 when `n <= minCount` or `span <= 0`.
    /// Prunes the oldest sample when span exceeds `decay`.
    /// Callers must hold `lock`.
    private func frequency(_ deque: inout [TimeInterval],
                           decay: Double,
                           minCount: Int,
                           now: TimeInterval,
                           extraSamples: Int = 0) -> Double {
        // `minCount` is checked against the recorded count, `extraSamples` only reaches the
        // numerator—matching Python, where `n` is incremented on line 380 but the guard on
        // line 381 re-reads `len(self.op_freq_deque)`.
        guard deque.count > minCount else { return 0 }
        let n = deque.count + extraSamples
        let oldest = deque[0]
        let span = now - oldest
        if span > decay { deque.removeFirst() }
        guard span > 0 else { return 0 }
        return Double(n) / span
    }
}
