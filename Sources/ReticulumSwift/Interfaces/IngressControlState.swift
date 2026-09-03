import Foundation

/// Per-interface ingress burst control state.
///
/// Mirrors Python's per-interface ingress control fields
/// (`ic_burst_active`, `ic_burst_activated`, `ic_held_release`, etc.)
/// and the held-announce table (`held_announces`).
public struct IngressControlState {

    // MARK: - Python class constants (Interface.IC_*)

    /// Interface is considered "new" for its first 2 hours.
    /// Mirrors Python `Interface.IC_NEW_TIME = 2*60*60`.
    public static let icNewTime: TimeInterval = 2 * 60 * 60
    /// Announce burst frequency threshold for new interfaces (Hz).
    /// Mirrors Python `Interface.IC_BURST_FREQ_NEW = 3`.
    public static let icBurstFreqNew: Double = 3.0
    /// Announce burst frequency threshold for established interfaces (Hz).
    /// Mirrors Python `Interface.IC_BURST_FREQ = 10`.
    public static let icBurstFreq: Double = 10.0
    /// Path-request burst threshold for new interfaces (Hz).
    /// Mirrors Python `Interface.IC_PR_BURST_FREQ_NEW = 3`.
    public static let icPrBurstFreqNew: Double = 3.0
    /// Path-request burst threshold for established interfaces (Hz).
    /// Mirrors Python `Interface.IC_PR_BURST_FREQ = 8`.
    public static let icPrBurstFreq: Double = 8.0
    /// Seconds the burst must stay below threshold before deactivating.
    /// Mirrors Python `Interface.IC_BURST_HOLD = 15`.
    public static let icBurstHold: TimeInterval = 15.0
    /// Penalty delay before held announces are released after burst ends.
    /// Mirrors Python `Interface.IC_BURST_PENALTY = 15`.
    public static let icBurstPenalty: TimeInterval = 15.0
    /// Interval between individual held-announce releases (seconds).
    /// Mirrors Python `Interface.IC_HELD_RELEASE_INTERVAL = 5`.
    public static let icHeldReleaseInterval: TimeInterval = 5.0

    /// Minimum samples in the frequency deque before an *egress* path-request burst may be
    /// declared. `Interface.EC_BURST_MIN_SAMPLES = 2` (`Interface.py:85`).
    ///
    /// RNS 1.5.1 renamed this from `IC_BURST_MIN_SAMPLES` and dropped it from 6 to 2. The
    /// rename is upstream conceding what the single remaining read site already showed — it
    /// only ever gated `should_egress_limit_pr`, never anything on the ingress side. The value
    /// change means a burst of two outbound path requests is now enough to throttle: at six,
    /// a node could emit five requests at any rate whatsoever before the limiter could speak.
    ///
    /// It now coincides numerically with `InterfaceFreqTracker.minSamples` (Python's
    /// `IC_DEQUE_MIN_SAMPLE`), but the two remain separate knobs measuring different things —
    /// one is "enough samples to throttle egress", the other "enough samples for a frequency to
    /// mean anything". Conflating them was the 1.4.1 bug (commit 48388756); they are equal
    /// today by coincidence, not by identity.
    ///
    /// Deliberately **not** per-interface, unlike the tunables around it: Python reads it as the
    /// class constant `self.EC_BURST_MIN_SAMPLES` (`:246`) and exposes no config key for it.
    public static let ecBurstMinSamples: Int = 2

    /// Consecutive qualifying evaluations a path-request burst must survive before its flag may
    /// clear. Python has no named constant — it writes the literal `3` at both
    /// `Interface.py:221` and `:232`.
    ///
    /// This is a second, coarser layer on top of the hold windows: even once both have elapsed
    /// and the frequency has fallen, three more quiet looks are required. Any single busy
    /// evaluation refills it, so it measures an unbroken run of quiet, not elapsed time.
    public static let icPrBurstCooldown: Int = 3
    /// Maximum number of held announces per interface.
    /// Mirrors Python `Interface.MAX_HELD_ANNOUNCES = 256`.
    public static let maxHeldAnnounces: Int = 256

    // MARK: - Mutable state

    var burstActive: Bool = false
    var burstActivated: TimeInterval = 0
    /// When the announce flood was last observed at or above threshold.
    /// `ic_burst_sustained` (`Interface.py:132`), added in RNS 1.5.1.
    ///
    /// `burstActivated` alone measured the wrong end of the event: a flood running for minutes
    /// cleared its own flag fifteen seconds after it *began*, mid-flood. Refreshing this on
    /// every above-threshold evaluation moves the hold window onto the flood's trailing edge.
    var burstSustained: TimeInterval = 0
    var heldRelease: TimeInterval = 0

    var prBurstActive: Bool = false
    var prBurstActivated: TimeInterval = 0
    /// The path-request equivalent of ``burstSustained`` (`ic_pr_burst_sustained`).
    var prBurstSustained: TimeInterval = 0
    /// Remaining consecutive quiet evaluations before the path-request burst flag may clear
    /// (`ic_pr_burst_cooldown`). Starts at ``IngressControlState/icPrBurstCooldown``.
    var prBurstCooldown: Int = 0

    /// Held announce packets keyed by destination hash. Capped at `maxHeldAnnounces`.
    var heldAnnounces: [Data: Packet] = [:]
}
