//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

/// Per-interface mutable configuration, held in one place so it can be written.
///
/// **Why this type exists.** Python mutates interface attributes at runtime—`Reticulum.py`
/// assigns `mode`, `announce_cap`, the three `announce_rate_*` values, `bitrate`,
/// `ingress_control`, `egress_control` and the nine `ic_*` tunables per interface at
/// `:900-941` (the `__apply_config` interface branch) and `:1092-1130` (`_add_interface`).
/// This port originally declared those as `{ get }`-only protocol requirements with blanket
/// extension defaults, so a value parsed out of a config file had nowhere to be written and
/// `iface.mode = …` didn't compile for `any Interface`. Adding the config parser would have
/// fixed none of them. See `swift_devel/bugs/025-*.md`.
///
/// **Why a box rather than `{ get set }` requirements.** One stored property per conformer
/// instead of a dozen, so a newly added interface type gets the whole set for free rather than
/// silently omitting it—which is the mechanism that produced `bugs/022`. It also makes
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

    // Python reads these from `Reticulum._default_*()` in `Interface.__init__`
    // (`Interface.py:126-136`), so the `[reticulum]` section sets what every interface
    // *starts* from and a per-interface block overrides it. They were hardcoded here, so the
    // global half of `bugs/030` had nowhere to land even once the parser read it—the same
    // "configuration value with nowhere to be written" shape as `bugs/025`. Each accessor
    // falls back to the `IngressControlState` constant holding the Python class value, so
    // the numbers are still written down exactly once.
    var egressControl: Bool = Reticulum.defaultEgressControl()
    var ecPrFreq: Double = Reticulum.defaultEcPrFreq()

    var icNewTime: TimeInterval = Reticulum.defaultIcNewTime()
    var icBurstFreqNew: Double = Reticulum.defaultIcBurstFreqNew()
    var icBurstFreq: Double = Reticulum.defaultIcBurstFreq()
    var icPrBurstFreqNew: Double = Reticulum.defaultIcPrBurstFreqNew()
    var icPrBurstFreq: Double = Reticulum.defaultIcPrBurstFreq()
    var icBurstHold: TimeInterval = Reticulum.defaultIcBurstHold()
    var icBurstPenalty: TimeInterval = Reticulum.defaultIcBurstPenalty()
    var icHeldReleaseInterval: TimeInterval = Reticulum.defaultIcHeldReleaseInterval()
    /// Python reads this as the class constant `EC_BURST_MIN_SAMPLES` (`Interface.py:85`,
    /// `:246`) and exposes no config key for it, so it stays a constant here too.
    ///
    /// RNS 1.5.1
    /// renamed it from `IC_BURST_MIN_SAMPLES`, the single read site having always been the
    /// egress limiter.
    var ecBurstMinSamples: Int = IngressControlState.ecBurstMinSamples
    /// Python `interface.ic_max_held_announces` (`Interface.py:126`, config key at
    /// `Reticulum.py:791-792`)—a per-interface instance value, not a class constant.
    ///
    /// This port had it the other way round: `IngressControlState.maxHeldAnnounces` was a
    /// global `static let 256` that no config could reach, while `ecBurstMinSamples`—which
    /// Python reads as the class constant `self.EC_BURST_MIN_SAMPLES` (`Interface.py:85`,
    /// `:246`) and exposes no config key for—was the per-interface one. So an operator could
    /// configure the tunable Python doesn't expose and not the one it does. Found while
    /// writing the per-interface parser; `ecBurstMinSamples` stays on the box, harmlessly.
    var icMaxHeldAnnounces: Int = Reticulum.defaultIcMaxHeldAnnounces()

    var gravity: Int = InterfaceMode.defaultGravity
    var bootstrapOnly: Bool = false
    var recursivePrs: Bool = false
    var announcesFromInternal: Bool = true
    var announcesToInternal: Bool?
    var wantsTunnel: Bool = false
    var tunnelID: Data?

    /// Python `interface.ifac_netname` (`Reticulum.py:955`)—the IFAC segment's name.
    ///
    /// Lives on the box rather than as a per-conformer stored property because it's a
    /// config value like the rest, spawned interfaces must inherit it alongside the
    /// key and size (`TCPInterface.py:594-641`), and `rnstatus` reports it. Nothing stored
    /// it before, so `InterfaceStatsPayload` hardcoded `ifac_netname` to nil (`bugs/015`).
    var ifacNetname: String?

    /// Python `interface.ifac_netkey` (`Reticulum.py:990`)—the segment's raw passphrase,
    /// kept alongside the derived key because `publish_ifac` puts it in the discovery
    /// announce (`Discovery.py:204`).
    ///
    /// This port derived the key and dropped the
    /// passphrase, so there was nothing to publish.
    var ifacNetkey: String?

    // MARK: Interface discovery, publish side
    //
    // Python declares `discoverable` and `last_discovery_announce` in
    // `Interface.__init__` (`Interface.py:118-119`) and assigns the other fifteen per
    // interface in `Reticulum.interface_post_init` (`Reticulum.py:953-967`). They're
    // runtime-mutated—`Discovery.py:86` writes `last_discovery_announce` on every
    // announce, and `:127-129` overwrites the three location values from the
    // `location_cmd` script's output—so they belong on the box rather than being
    // `{ get }`-only, which is the `bugs/025` shape.
    //
    // None of them is inherited by a spawned client; see `inherit(from:)`.

    var discoverable: Bool = false
    var lastDiscoveryAnnounce: TimeInterval = 0
    var discoveryAnnounceInterval: TimeInterval?
    var discoveryPublishIfac: Bool = false
    var reachableOn: String?
    var discoveryName: String?
    var discoveryLxmfAddress: Data?
    var discoveryEncrypt: Bool = false
    var discoveryStampValue: Int?
    var discoveryLocation: String?
    var discoveryLatitude: Double?
    var discoveryLongitude: Double?
    var discoveryHeight: Double?
    var discoveryFrequency: Int?
    var discoveryBandwidth: Int?
    var discoveryModulation: Int?
    var discoveryChannel: Int?

    // Autoconnect bookkeeping. Python creates these three attributes on the interface object
    // at dial time (`Discovery.py:765-766`, `:628`) and tests for them with `hasattr`, so a
    // nil `autoconnectHash` is what "not auto-connected" means here.
    var autoconnectHash: Data?
    var autoconnectSource: String?
    var autoconnectDown: TimeInterval?
  }

  private let lock: UnsafeMutablePointer<os_unfair_lock>

  /// Creates a state block holding the default values.
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

  /// Fraction of interface capacity announces may consume, for example, `0.02` for 2%.
  ///
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

  // Note: `bitrate` is deliberately **not** held here. Several interfaces derive theirs—`RNodeInterface`
  // computes it from spreading factor, bandwidth and coding rate—and that
  // computation must stay in force when no config value is supplied. It's instead a settable
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
  /// Python: `Interface.EC_BURST_MIN_SAMPLES`.
  public var ecBurstMinSamples: Int {
    get { read(\.ecBurstMinSamples) }
    set { write(\.ecBurstMinSamples, newValue) }
  }

  /// Python: `interface.ic_max_held_announces`—how many announces this interface holds
  /// during an ingress burst before dropping them.
  public var icMaxHeldAnnounces: Int {
    get { read(\.icMaxHeldAnnounces) }
    set { write(\.icMaxHeldAnnounces, newValue) }
  }

  // MARK: - Routing and announce-propagation flags
  //
  // These were previously `{ get set }` protocol requirements with `set { }` no-op extension
  // defaults, which is worse than get-only: the assignment compiles and is silently discarded
  // on every type that doesn't override it. only 2 of 19 conformers stored `bootstrapOnly`.

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

  /// Python: `interface.ifac_netname` (`Reticulum.py:955`)—the name of the IFAC segment this
  /// interface is on, reported by `rnstatus`.
  ///
  /// See `bugs/015`.
  public var ifacNetname: String? {
    get { read(\.ifacNetname) }
    set { write(\.ifacNetname, newValue) }
  }

  /// Python: `interface.ifac_netkey` (`Reticulum.py:990`)—the segment's passphrase, as
  /// configured.
  ///
  /// Held for `publish_ifac`, which puts it in the discovery announce so a peer
  /// can generate a config entry that joins the segment. Never reported by `rnstatus`.
  public var ifacNetkey: String? {
    get { read(\.ifacNetkey) }
    set { write(\.ifacNetkey, newValue) }
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

  // MARK: - Interface discovery, publish side

  /// Python: `interface.discoverable` (`Interface.py:118`, config key at `Reticulum.py:901`).
  ///
  /// Announcing an interface as a discoverable endpoint needs both this and
  /// `supportsDiscovery`, which is a per-type capability rather than a config choice.
  public var discoverable: Bool {
    get { read(\.discoverable) }
    set { write(\.discoverable, newValue) }
  }

  /// Python: `interface.last_discovery_announce` (`Interface.py:119`), stamped by the
  /// announcer before it builds the payload (`Discovery.py:86`).
  public var lastDiscoveryAnnounce: TimeInterval {
    get { read(\.lastDiscoveryAnnounce) }
    set { write(\.lastDiscoveryAnnounce, newValue) }
  }

  /// Python: `interface.discovery_announce_interval`, seconds between announces.
  ///
  /// The config
  /// key is `announce_interval` in *minutes* with a five-minute floor, defaulting to six
  /// hours (`Reticulum.py:905-909`).
  public var discoveryAnnounceInterval: TimeInterval? {
    get { read(\.discoveryAnnounceInterval) }
    set { write(\.discoveryAnnounceInterval, newValue) }
  }

  /// Python: `interface.discovery_publish_ifac`—publish this interface's IFAC network name
  /// and key in the announce, so a peer can generate a working config entry
  /// (`Discovery.py:203-205`).
  public var discoveryPublishIfac: Bool {
    get { read(\.discoveryPublishIfac) }
    set { write(\.discoveryPublishIfac, newValue) }
  }

  /// Python: `interface.reachable_on`—the hostname or address peers should dial.
  ///
  /// Either a
  /// literal, or a path to an executable printing one (`Discovery.py:159-176`).
  public var reachableOn: String? {
    get { read(\.reachableOn) }
    set { write(\.reachableOn, newValue) }
  }

  /// Python: `interface.discovery_name`, the operator-facing name in the announce.
  public var discoveryName: String? {
    get { read(\.discoveryName) }
    set { write(\.discoveryName, newValue) }
  }

  /// Python: `interface.discovery_lxmf_address`—the operator's LXMF address, published as
  /// `OP_ADDR` (`Discovery.py:147`).
  ///
  /// A truncated destination hash, so 16 bytes here.
  public var discoveryLxmfAddress: Data? {
    get { read(\.discoveryLxmfAddress) }
    set { write(\.discoveryLxmfAddress, newValue) }
  }

  /// Python: `interface.discovery_encrypt`—encrypt the announce payload to the network
  /// identity, so only nodes holding it can read the endpoint (`Discovery.py:217-224`).
  public var discoveryEncrypt: Bool {
    get { read(\.discoveryEncrypt) }
    set { write(\.discoveryEncrypt, newValue) }
  }

  /// Python: `interface.discovery_stamp_value`—proof-of-work cost for this interface's
  /// announces, falling back to `InterfaceAnnouncer.DEFAULT_STAMP_VALUE` of 16.
  public var discoveryStampValue: Int? {
    get { read(\.discoveryStampValue) }
    set { write(\.discoveryStampValue, newValue) }
  }

  /// Python: `interface.discovery_location`—path to an executable printing
  /// `latitude,longitude,height`, evaluated per announce (`Discovery.py:110-134`).
  public var discoveryLocation: String? {
    get { read(\.discoveryLocation) }
    set { write(\.discoveryLocation, newValue) }
  }

  /// Python: `interface.discovery_latitude`, degrees in `[-90, 90]`.
  public var discoveryLatitude: Double? {
    get { read(\.discoveryLatitude) }
    set { write(\.discoveryLatitude, newValue) }
  }

  /// Python: `interface.discovery_longitude`, degrees in `[-180, 180]`.
  public var discoveryLongitude: Double? {
    get { read(\.discoveryLongitude) }
    set { write(\.discoveryLongitude, newValue) }
  }

  /// Python: `interface.discovery_height`, metres in `[-4000, 1e6]`.
  public var discoveryHeight: Double? {
    get { read(\.discoveryHeight) }
    set { write(\.discoveryHeight, newValue) }
  }

  /// Python: `interface.discovery_frequency`, Hz. Published for the radio interface types.
  public var discoveryFrequency: Int? {
    get { read(\.discoveryFrequency) }
    set { write(\.discoveryFrequency, newValue) }
  }

  /// Python: `interface.discovery_bandwidth`, Hz.
  public var discoveryBandwidth: Int? {
    get { read(\.discoveryBandwidth) }
    set { write(\.discoveryBandwidth, newValue) }
  }

  /// Python: `interface.discovery_modulation`, read with `as_int` (`Reticulum.py:921`).
  public var discoveryModulation: Int? {
    get { read(\.discoveryModulation) }
    set { write(\.discoveryModulation, newValue) }
  }

  /// Python: `interface.discovery_channel`.
  ///
  /// Weave's announce branch reads it
  /// (`Discovery.py:194`) and no config key writes it, so it stays whatever the interface
  /// itself sets.
  public var discoveryChannel: Int? {
    get { read(\.discoveryChannel) }
    set { write(\.discoveryChannel, newValue) }
  }

  /// The endpoint hash this interface was auto-connected for, or nil when it was configured
  /// by hand.
  ///
  /// Python: `interface.autoconnect_hash` (`Discovery.py:765`).
  public var autoconnectHash: Data? {
    get { read(\.autoconnectHash) }
    set { write(\.autoconnectHash, newValue) }
  }

  /// The network identity whose announce this endpoint was discovered from, as undelimited
  /// hex.
  ///
  /// Python: `interface.autoconnect_source` (`Discovery.py:766`).
  public var autoconnectSource: String? {
    get { read(\.autoconnectSource) }
    set { write(\.autoconnectSource, newValue) }
  }

  /// When this auto-connected interface was first seen offline, or nil while it is up.
  ///
  /// Python: `interface.autoconnect_down` (`Discovery.py:628`).
  public var autoconnectDown: TimeInterval? {
    get { read(\.autoconnectDown) }
    set { write(\.autoconnectDown, newValue) }
  }

  // MARK: - Spawned-interface inheritance

  /// Copy every inheritable attribute from a parent interface's state onto this one.
  ///
  /// Python does this explicitly for each accepted connection—`TCPInterface.py:594-641`
  /// copies nineteen attributes, and `BackboneInterface.py:467-485`, `AutoInterface.py:559`
  /// and `I2PInterface.py:846` carry the same block. Having it here means all three spawn
  /// paths inherit the same set, and a value added to `InterfaceState` is inherited without
  /// anyone remembering to extend three copies of the list.
  ///
  /// `tunnelID` and `wantsTunnel` are deliberately **not** inherited: a tunnel belongs to the
  /// specific connection that established it, and Python doesn't copy them either.
  /// Per-instance fallback storage for conformers that don't declare their own
  /// `interfaceState`.
  ///
  /// Every interface this library ships declares one explicitly—that's the intended form and
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

  /// Adopts the inheritable fields of `parent`.
  public func inherit(from parent: InterfaceState) {
    os_unfair_lock_lock(parent.lock)
    var incoming = parent.storage
    os_unfair_lock_unlock(parent.lock)

    // Per-connection, not inherited.
    incoming.wantsTunnel = false
    incoming.tunnelID = nil

    // Per-endpoint, not inherited. Python's spawn block copies nineteen attributes
    // (`TCPInterface.py:594-641`) and no discovery attribute is among them: a spawned
    // client is one accepted connection on the parent's listener, not a separately
    // reachable endpoint. Inheriting `discoverable` would announce the parent's
    // `reachable_on` once per connected peer.
    incoming.discoverable = false
    incoming.lastDiscoveryAnnounce = 0
    incoming.discoveryAnnounceInterval = nil
    incoming.discoveryPublishIfac = false
    incoming.reachableOn = nil
    incoming.discoveryName = nil
    incoming.discoveryLxmfAddress = nil
    incoming.discoveryEncrypt = false
    incoming.discoveryStampValue = nil
    incoming.discoveryLocation = nil
    incoming.discoveryLatitude = nil
    incoming.discoveryLongitude = nil
    incoming.discoveryHeight = nil
    incoming.discoveryFrequency = nil
    incoming.discoveryBandwidth = nil
    incoming.discoveryModulation = nil
    incoming.discoveryChannel = nil
    incoming.autoconnectHash = nil
    incoming.autoconnectSource = nil
    incoming.autoconnectDown = nil

    os_unfair_lock_lock(lock)
    storage = incoming
    os_unfair_lock_unlock(lock)
  }
}
