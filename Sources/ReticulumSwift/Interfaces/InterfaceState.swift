import Foundation

/// Per-interface mutable configuration, held in one place so it can be written.
///
/// **Why this type exists.** Python mutates interface attributes at runtime — `Reticulum.py`
/// assigns `mode`, `announce_cap`, the three `announce_rate_*` values, `bitrate`,
/// `ingress_control`, `egress_control` and the nine `ic_*` tunables per interface at
/// `:900-941` (the `__apply_config` interface branch) and `:1092-1130` (`_add_interface`).
/// This port originally declared those as `{ get }`-only protocol requirements with blanket
/// extension defaults, so a value parsed out of a config file had nowhere to be written and
/// `iface.mode = …` did not compile for `any Interface`. Adding the config parser would have
/// fixed none of them. See `swift_devel/bugs/025-*.md`.
///
/// **Why a box rather than `{ get set }` requirements.** One stored property per conformer
/// instead of a dozen, so a newly added interface type gets the whole set for free rather than
/// silently omitting it — which is the mechanism that produced `bugs/022`. It also makes
/// spawned-interface inheritance a single call: Python copies nineteen attributes onto each
/// accepted client (`TCPInterface.py:594-641`, `BackboneInterface.py:467-485`,
/// `AutoInterface.py:559`), and `inherit(from:)` below is that copy, in one place, for all three.
///
/// **Thread safety.** Reads happen on Transport's outbound path; writes happen from the config
/// path and the spawn path (both before registration) and from per-packet ingress accounting.
/// Access is serialised with an `os_unfair_lock`, allocated once so the lock has a stable address.
public final class InterfaceState {

    // MARK: - Python class-constant defaults for the ic_* family
    //
    // Python declares these as class attributes on `Interface` and lets a config file override
    // them per interface (`Reticulum.py:656-697`). They live here as instance values with the
    // Python class values as defaults; `IngressControlState`'s `static let`s remain as the
    // canonical default source so there is exactly one place each number is written down.

    private var storage = Storage()

    private struct Storage {
        var mode: InterfaceMode = .full

        var announceCap: Double = Double(Reticulum.announceCap) / 100.0
        var announceRateTarget: TimeInterval?
        var announceRateGrace: Int = 0
        var announceRatePenalty: TimeInterval = 0

        var ingressControl: Bool = true
        var egressControl: Bool = false
        var ecPrFreq: Double = 5.0

        var icNewTime: TimeInterval = IngressControlState.icNewTime
        var icBurstFreqNew: Double = IngressControlState.icBurstFreqNew
        var icBurstFreq: Double = IngressControlState.icBurstFreq
        var icPrBurstFreqNew: Double = IngressControlState.icPrBurstFreqNew
        var icPrBurstFreq: Double = IngressControlState.icPrBurstFreq
        var icBurstHold: TimeInterval = IngressControlState.icBurstHold
        var icBurstPenalty: TimeInterval = IngressControlState.icBurstPenalty
        var icHeldReleaseInterval: TimeInterval = IngressControlState.icHeldReleaseInterval
        var icBurstMinSamples: Int = IngressControlState.icBurstMinSamples

        var gravity: Int = InterfaceMode.defaultGravity
        var bootstrapOnly: Bool = false
        var recursivePrs: Bool = false
        var announcesFromInternal: Bool = true
        var announcesToInternal: Bool?
        var wantsTunnel: Bool = false
        var tunnelID: Data?

        /// Python `interface.ifac_netname` (`Reticulum.py:955`) — the IFAC segment's name.
        ///
        /// Lives on the box rather than as a per-conformer stored property because it is a
        /// config value like the rest, it must be inherited by spawned interfaces alongside the
        /// key and size (`TCPInterface.py:594-641`), and `rnstatus` reports it. Nothing stored
        /// it before, so `InterfaceStatsPayload` hardcoded `ifac_netname` to nil (`bugs/015`).
        var ifacNetname: String?
    }

    private let lock: UnsafeMutablePointer<os_unfair_lock>

    public init() {
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    @inline(__always)
    private func read<T>(_ keyPath: KeyPath<Storage, T>) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return storage[keyPath: keyPath]
    }

    @inline(__always)
    private func write<T>(_ keyPath: WritableKeyPath<Storage, T>, _ value: T) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        storage[keyPath: keyPath] = value
    }

    // MARK: - Mode

    /// Python: `interface.mode`, assigned at `Reticulum.py:910`.
    public var mode: InterfaceMode {
        get { read(\.mode) }
        set { write(\.mode, newValue) }
    }

    // MARK: - Announce rate control

    /// Fraction of interface capacity announces may consume, e.g. `0.02` for 2%.
    /// Python: `announce_cap = Reticulum.ANNOUNCE_CAP/100.0` (`Reticulum.py:834-837`, `:912`),
    /// where the config value is a percentage in `(0, 100]`.
    public var announceCap: Double {
        get { read(\.announceCap) }
        set { write(\.announceCap, newValue) }
    }

    /// Python: `interface.announce_rate_target`. `nil` disables rate limiting.
    public var announceRateTarget: TimeInterval? {
        get { read(\.announceRateTarget) }
        set { write(\.announceRateTarget, newValue) }
    }

    /// Python: `interface.announce_rate_grace`.
    public var announceRateGrace: Int {
        get { read(\.announceRateGrace) }
        set { write(\.announceRateGrace, newValue) }
    }

    /// Python: `interface.announce_rate_penalty`.
    public var announceRatePenalty: TimeInterval {
        get { read(\.announceRatePenalty) }
        set { write(\.announceRatePenalty, newValue) }
    }

    // Note: `bitrate` is deliberately **not** held here. Several interfaces derive theirs —
    // `RNodeInterface` computes it from spreading factor, bandwidth and coding rate — and that
    // computation must stay in force when no config value is supplied. It is instead a settable
    // requirement on `Interface`, stored by each conformer, and copied explicitly by the spawn
    // paths (Python does the same: `bitrate` is a class attribute the config may overwrite).

    // MARK: - Ingress / egress control

    /// Python: `interface.ingress_control` (default `True`).
    public var ingressControl: Bool {
        get { read(\.ingressControl) }
        set { write(\.ingressControl, newValue) }
    }

    /// Python: `interface.egress_control` (default `False`).
    public var egressControl: Bool {
        get { read(\.egressControl) }
        set { write(\.egressControl, newValue) }
    }

    /// Python: `interface.EC_PR_FREQ = 5`.
    public var ecPrFreq: Double {
        get { read(\.ecPrFreq) }
        set { write(\.ecPrFreq, newValue) }
    }

    /// Python: `Interface.IC_NEW_TIME`.
    public var icNewTime: TimeInterval {
        get { read(\.icNewTime) }
        set { write(\.icNewTime, newValue) }
    }
    /// Python: `Interface.IC_BURST_FREQ_NEW`.
    public var icBurstFreqNew: Double {
        get { read(\.icBurstFreqNew) }
        set { write(\.icBurstFreqNew, newValue) }
    }
    /// Python: `Interface.IC_BURST_FREQ`.
    public var icBurstFreq: Double {
        get { read(\.icBurstFreq) }
        set { write(\.icBurstFreq, newValue) }
    }
    /// Python: `Interface.IC_PR_BURST_FREQ_NEW`.
    public var icPrBurstFreqNew: Double {
        get { read(\.icPrBurstFreqNew) }
        set { write(\.icPrBurstFreqNew, newValue) }
    }
    /// Python: `Interface.IC_PR_BURST_FREQ`.
    public var icPrBurstFreq: Double {
        get { read(\.icPrBurstFreq) }
        set { write(\.icPrBurstFreq, newValue) }
    }
    /// Python: `Interface.IC_BURST_HOLD`.
    public var icBurstHold: TimeInterval {
        get { read(\.icBurstHold) }
        set { write(\.icBurstHold, newValue) }
    }
    /// Python: `Interface.IC_BURST_PENALTY`.
    public var icBurstPenalty: TimeInterval {
        get { read(\.icBurstPenalty) }
        set { write(\.icBurstPenalty, newValue) }
    }
    /// Python: `Interface.IC_HELD_RELEASE_INTERVAL`.
    public var icHeldReleaseInterval: TimeInterval {
        get { read(\.icHeldReleaseInterval) }
        set { write(\.icHeldReleaseInterval, newValue) }
    }
    /// Python: `Interface.IC_BURST_MIN_SAMPLES`.
    public var icBurstMinSamples: Int {
        get { read(\.icBurstMinSamples) }
        set { write(\.icBurstMinSamples, newValue) }
    }

    // MARK: - Routing and announce-propagation flags
    //
    // These were previously `{ get set }` protocol requirements with `set { }` no-op extension
    // defaults, which is worse than get-only: the assignment compiles and is silently discarded
    // on every type that does not override it. `bootstrapOnly` was stored by 2 of 19 conformers.

    /// Python: `interface.gravity` (RNS 1.4.1, `DEFAULT_GRAVITY = 0`).
    public var gravity: Int {
        get { read(\.gravity) }
        set { write(\.gravity, newValue) }
    }

    /// Python: `interface.bootstrap_only`.
    public var bootstrapOnly: Bool {
        get { read(\.bootstrapOnly) }
        set { write(\.bootstrapOnly, newValue) }
    }

    /// Python: `interface.ifac_netname` (`Reticulum.py:955`) — the name of the IFAC segment this
    /// interface is on, reported by `rnstatus`. See `bugs/015`.
    public var ifacNetname: String? {
        get { read(\.ifacNetname) }
        set { write(\.ifacNetname, newValue) }
    }

    /// Python: `interface.recursive_prs` (RNS 1.3.6).
    public var recursivePrs: Bool {
        get { read(\.recursivePrs) }
        set { write(\.recursivePrs, newValue) }
    }

    /// Python: `interface.announces_from_internal` (RNS 1.3.7, default `True`).
    public var announcesFromInternal: Bool {
        get { read(\.announcesFromInternal) }
        set { write(\.announcesFromInternal, newValue) }
    }

    /// Python: `interface.announces_to_internal` (RNS 1.4.1, default `None`).
    public var announcesToInternal: Bool? {
        get { read(\.announcesToInternal) }
        set { write(\.announcesToInternal, newValue) }
    }

    /// Python: `interface.wants_tunnel`.
    public var wantsTunnel: Bool {
        get { read(\.wantsTunnel) }
        set { write(\.wantsTunnel, newValue) }
    }

    /// Python: `interface.tunnel_id`.
    public var tunnelID: Data? {
        get { read(\.tunnelID) }
        set { write(\.tunnelID, newValue) }
    }

    // MARK: - Spawned-interface inheritance

    /// Copy every inheritable attribute from a parent interface's state onto this one.
    ///
    /// Python does this explicitly for each accepted connection — `TCPInterface.py:594-641`
    /// copies nineteen attributes, and `BackboneInterface.py:467-485`, `AutoInterface.py:559`
    /// and `I2PInterface.py:846` carry the same block. Having it here means all three spawn
    /// paths inherit the same set, and a value added to `InterfaceState` is inherited without
    /// anyone remembering to extend three copies of the list.
    ///
    /// `tunnelID` and `wantsTunnel` are deliberately **not** inherited: a tunnel belongs to the
    /// specific connection that established it, and Python does not copy them either.
    /// Per-instance fallback storage for conformers that do not declare their own
    /// `interfaceState`.
    ///
    /// Every interface this library ships declares one explicitly — that is the intended form and
    /// keeps the value on the object itself. This table exists so that a conformer defined
    /// elsewhere (a test double, or a downstream interface) still gets **real per-instance state**
    /// rather than failing to compile or, worse, silently sharing a global.
    ///
    /// The keys are held weakly, so an interface's state is released with the interface.
    static let fallbackStorage = FallbackStore()

    final class FallbackStore {
        private let table = NSMapTable<AnyObject, InterfaceState>.weakToStrongObjects()
        private let lock = NSLock()

        func state(for owner: AnyObject) -> InterfaceState {
            lock.lock()
            defer { lock.unlock() }
            if let existing = table.object(forKey: owner) { return existing }
            let fresh = InterfaceState()
            table.setObject(fresh, forKey: owner)
            return fresh
        }
    }

    public func inherit(from parent: InterfaceState) {
        os_unfair_lock_lock(parent.lock)
        var incoming = parent.storage
        os_unfair_lock_unlock(parent.lock)

        // Per-connection, not inherited.
        incoming.wantsTunnel = false
        incoming.tunnelID = nil

        os_unfair_lock_lock(lock)
        storage = incoming
        os_unfair_lock_unlock(lock)
    }
}
