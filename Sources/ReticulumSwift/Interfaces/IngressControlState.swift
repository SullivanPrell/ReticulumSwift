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
    /// Maximum number of held announces per interface.
    /// Mirrors Python `Interface.MAX_HELD_ANNOUNCES = 256`.
    public static let maxHeldAnnounces: Int = 256

    // MARK: - Mutable state

    var burstActive: Bool = false
    var burstActivated: TimeInterval = 0
    var heldRelease: TimeInterval = 0

    var prBurstActive: Bool = false
    var prBurstActivated: TimeInterval = 0

    /// Held announce packets keyed by destination hash. Capped at `maxHeldAnnounces`.
    var heldAnnounces: [Data: Packet] = [:]
}
