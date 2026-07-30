import XCTest
@testable import ReticulumSwift

/// The `[reticulum]` section must be honoured — `bugs/030`, tasks 4.2 and 4.3.
///
/// Reading a key is not honouring it. `ConfigTemplateRoundTripTests` proves the parser no longer
/// discards these keys and that each changes the parsed result; this file proves the parsed
/// result reaches the thing that acts on it. The two halves are separate on purpose: `bugs/015`
/// was a correct, thoroughly-tested API with no caller, and a parser that fills a struct nobody
/// reads is the same defect wearing a different hat.
///
/// Global state note: these options are statics on `Reticulum`, matching Python's class
/// attributes. Every test restores them, so ordering cannot leak a configured value into an
/// unrelated suite.
final class ReticulumSectionConfigTests: XCTestCase {

    private var saved: Snapshot!
    private var tmpDirs: [URL] = []

    /// Everything `applyGlobalDefaults` can write, captured so it can be put back.
    private struct Snapshot {
        let useImplicitProof = Reticulum.useImplicitProof
        let linkMtuDiscovery = Reticulum.linkMtuDiscoveryEnabled
        let rpcKey = Reticulum.rpcKey_
        let instanceName = Reticulum.instanceName_
        let sharedInstanceType = Reticulum.sharedInstanceType_
        let forceBitrate = Reticulum.forceSharedInstanceBitrate_
        let arTarget = Reticulum.defaultArTarget_
        let arPenalty = Reticulum.defaultArPenalty_
        let arGrace = Reticulum.defaultArGrace_
        let egressControl = Reticulum.defaultEgressControl_
        let ecPrFreq = Reticulum.defaultEcPrFreq_
        let icMaxHeld = Reticulum.defaultIcMaxHeldAnnounces_
        let icBurstHold = Reticulum.defaultIcBurstHold_
        let icBurstFreqNew = Reticulum.defaultIcBurstFreqNew_
        let icBurstFreq = Reticulum.defaultIcBurstFreq_
        let icPrBurstFreqNew = Reticulum.defaultIcPrBurstFreqNew_
        let icPrBurstFreq = Reticulum.defaultIcPrBurstFreq_
        let icNewTime = Reticulum.defaultIcNewTime_
        let icBurstPenalty = Reticulum.defaultIcBurstPenalty_
        let icHeldRelease = Reticulum.defaultIcHeldReleaseInterval_

        func restore() {
            Reticulum.useImplicitProof = useImplicitProof
            Reticulum.linkMtuDiscoveryEnabled = linkMtuDiscovery
            Reticulum.rpcKey_ = rpcKey
            Reticulum.instanceName_ = instanceName
            Reticulum.sharedInstanceType_ = sharedInstanceType
            Reticulum.forceSharedInstanceBitrate_ = forceBitrate
            Reticulum.defaultArTarget_ = arTarget
            Reticulum.defaultArPenalty_ = arPenalty
            Reticulum.defaultArGrace_ = arGrace
            Reticulum.defaultEgressControl_ = egressControl
            Reticulum.defaultEcPrFreq_ = ecPrFreq
            Reticulum.defaultIcMaxHeldAnnounces_ = icMaxHeld
            Reticulum.defaultIcBurstHold_ = icBurstHold
            Reticulum.defaultIcBurstFreqNew_ = icBurstFreqNew
            Reticulum.defaultIcBurstFreq_ = icBurstFreq
            Reticulum.defaultIcPrBurstFreqNew_ = icPrBurstFreqNew
            Reticulum.defaultIcPrBurstFreq_ = icPrBurstFreq
            Reticulum.defaultIcNewTime_ = icNewTime
            Reticulum.defaultIcBurstPenalty_ = icBurstPenalty
            Reticulum.defaultIcHeldReleaseInterval_ = icHeldRelease
        }
    }

    override func setUp() {
        super.setUp()
        saved = Snapshot()
    }

    override func tearDown() {
        saved.restore()
        for dir in tmpDirs { try? FileManager.default.removeItem(at: dir) }
        tmpDirs = []
        super.tearDown()
    }

    private func scratchDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rns-section-\(UUID().uuidString)")
        tmpDirs.append(dir)
        return dir
    }

    private func apply(_ body: String) {
        Reticulum.applyGlobalDefaults(ReticulumConfig.parse("[reticulum]\n\(body)\n").reticulum)
    }

    /// A started instance whose `[reticulum]` section is exactly `body`.
    ///
    /// The config must be written to disk rather than applied in memory: `start()` creates a
    /// default config when none exists and applies *that*, so an in-memory `enable_transport`
    /// would be overwritten by the default's `False` before any interface is built.
    private func startedInstance(_ body: String) throws -> Reticulum {
        let dir = scratchDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configURL = dir.appendingPathComponent("config")
        try "[reticulum]\n\(body)\n".write(to: configURL, atomically: true, encoding: .utf8)
        let reticulum = Reticulum(configuration: .init(
            storagePath: dir.appendingPathComponent("storage"),
            configPath: configURL, shareInstance: false))
        try reticulum.start()
        return reticulum
    }

    // MARK: - The production path, not just the seam

    /// A config file on disk, through `Reticulum.start()`, reaches the globals.
    ///
    /// The one assertion here that `applyGlobalDefaults` cannot make for itself. Every other test
    /// in this file drives that function directly for economy; if `applyConfig` ever stops
    /// calling it, this is what notices.
    func testAConfigFileOnDiskReachesTheGlobalsThroughStart() throws {
        let dir = scratchDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configURL = dir.appendingPathComponent("config")
        try """
        [reticulum]
        enable_transport = no
        use_implicit_proof = no
        link_mtu_discovery = no
        instance_name = from_disk
        shared_instance_type = tcp
        rpc_key = 0102030405060708
        ic_burst_freq = 9.5
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let reticulum = Reticulum(configuration: .init(
            storagePath: dir.appendingPathComponent("storage"),
            configPath: configURL,
            shareInstance: false))
        try reticulum.start()
        defer { reticulum.stop() }

        XCTAssertFalse(Reticulum.useImplicitProof)
        XCTAssertFalse(Reticulum.linkMtuDiscoveryEnabled)
        XCTAssertEqual(Reticulum.instanceName(), "from_disk")
        XCTAssertEqual(Reticulum.sharedInstanceType_, "tcp")
        XCTAssertEqual(Reticulum.rpcKey_, Data([1, 2, 3, 4, 5, 6, 7, 8]))
        XCTAssertEqual(Reticulum.defaultIcBurstFreq(), 9.5)
    }

    // MARK: - Instance identity and shared-instance controls

    func testInstanceNameIsHonoured() {
        XCTAssertEqual(Reticulum.instanceName(), "default", "Python's default is 'default'")
        apply("instance_name = alternate")
        XCTAssertEqual(Reticulum.instanceName(), "alternate")
    }

    func testSharedInstanceTypeAcceptsOnlyTheTwoPythonAccepts() {
        // `Reticulum.py:479-484` takes "tcp" and "unix" and ignores anything else.
        apply("shared_instance_type = TCP")
        XCTAssertEqual(Reticulum.sharedInstanceType_, "tcp", "matched case-insensitively, stored lowered")

        Reticulum.sharedInstanceType_ = nil
        apply("shared_instance_type = smoke_signals")
        XCTAssertNil(Reticulum.sharedInstanceType_, "an unrecognised value must leave it unset")
    }

    func testForceSharedInstanceBitrateIsHonoured() {
        apply("force_shared_instance_bitrate = 1000000")
        XCTAssertEqual(Reticulum.forceSharedInstanceBitrate_, 1_000_000)
    }

    // MARK: - Proof and MTU policy

    func testUseImplicitProofIsHonouredInBothDirections() {
        // Python assigns both ways here (`Reticulum.py:568-571`).
        apply("use_implicit_proof = no")
        XCTAssertFalse(Reticulum.shouldUseImplicitProof())
        apply("use_implicit_proof = yes")
        XCTAssertTrue(Reticulum.shouldUseImplicitProof())
    }

    /// Spec scenario: "MTU discovery can be disabled".
    ///
    /// A documented divergence, not an oversight. Python assigns only on `True`
    /// (`Reticulum.py:537-539`) against a default that is already `True` (`:105`), so
    /// `link_mtu_discovery = no` cannot disable anything in the reference. Every neighbouring
    /// option in the same chain assigns both directions, and the spec requires this one to. It is
    /// local policy — a node that declines to raise a link's MTU is indistinguishable to a peer
    /// from one that never offered a larger MTU — so honouring it cannot break interop.
    func testLinkMtuDiscoveryCanBeDisabled() {
        XCTAssertTrue(Reticulum.linkMtuDiscovery(), "default matches Python's LINK_MTU_DISCOVERY")
        apply("link_mtu_discovery = no")
        XCTAssertFalse(Reticulum.linkMtuDiscovery())
        apply("link_mtu_discovery = yes")
        XCTAssertTrue(Reticulum.linkMtuDiscovery())
    }

    // MARK: - Global defaults reaching interfaces

    /// The `ic_*` and egress values are what every interface *starts* from, because Python reads
    /// them in `Interface.__init__` (`Interface.py:126-136`). Asserted on a freshly constructed
    /// interface, not on the globals — reading the globals back would prove only that the parser
    /// filled a struct.
    func testConfiguredIngressAndEgressDefaultsReachANewInterface() {
        apply("""
        egress_control = yes
        ec_pr_freq = 11.5
        ic_max_held_announces = 42
        ic_burst_hold = 12.5
        ic_burst_freq_new = 13.5
        ic_burst_freq = 14.5
        ic_pr_burst_freq_new = 15.5
        ic_pr_burst_freq = 16.5
        ic_new_time = 17.5
        ic_burst_penalty = 18.5
        ic_held_release_interval = 19.5
        """)

        let interface = UDPInterface(name: "probe", listenPort: nil,
                                     forwardHost: nil, forwardPort: nil)
        XCTAssertTrue(interface.egressControl)
        XCTAssertEqual(interface.ecPrFreq, 11.5)

        let state = interface.interfaceState
        XCTAssertEqual(state.icMaxHeldAnnounces, 42)
        XCTAssertEqual(state.icBurstHold, 12.5)
        XCTAssertEqual(state.icBurstFreqNew, 13.5)
        XCTAssertEqual(state.icBurstFreq, 14.5)
        XCTAssertEqual(state.icPrBurstFreqNew, 15.5)
        XCTAssertEqual(state.icPrBurstFreq, 16.5)
        XCTAssertEqual(state.icNewTime, 17.5)
        XCTAssertEqual(state.icBurstPenalty, 18.5)
        XCTAssertEqual(state.icHeldReleaseInterval, 19.5)
    }

    /// A per-interface block still wins over the global default. Both halves matter: the global
    /// sets the starting point, the block overrides it (`Reticulum.py:942-953`).
    func testAPerInterfaceBlockOverridesTheGlobalDefault() {
        apply("ic_burst_freq = 14.5")

        let interface = UDPInterface(name: "probe", listenPort: nil,
                                     forwardHost: nil, forwardPort: nil)
        XCTAssertEqual(interface.interfaceState.icBurstFreq, 14.5, "global default first")

        Reticulum.applyInterfaceConfiguration(to: interface, from: .init(
            name: "probe", type: "UDPInterface", enabled: true,
            parameters: ["ic_burst_freq": "3.25"]))
        XCTAssertEqual(interface.interfaceState.icBurstFreq, 3.25, "the block must win")
    }

    /// Python's `x or DEFAULT` treats a configured zero as absent (`Reticulum.py:1154-1185`), so
    /// `ic_burst_freq = 0` falls back to the class constant rather than taking effect.
    /// Replicated because an operator moving a working Python config to a Swift node must get
    /// the same tuning, and because the guard that accepts the value (`if v >= 0`) and the
    /// accessor that discards it are four hundred lines apart in the reference.
    func testAConfiguredZeroFallsBackToTheClassConstantAsPythonDoes() {
        apply("ic_burst_freq = 0")
        XCTAssertEqual(Reticulum.defaultIcBurstFreq(), IngressControlState.icBurstFreq)
    }

    /// A negative value is rejected at the parse guard (`if v >= 0`), leaving the default.
    func testANegativeValueIsRejected() {
        apply("ic_burst_freq = -1")
        XCTAssertNil(ReticulumConfig.parse("[reticulum]\nic_burst_freq = -1\n").reticulum.icBurstFreq)
        XCTAssertEqual(Reticulum.defaultIcBurstFreq(), IngressControlState.icBurstFreq)
    }

    // MARK: - Announce-rate defaults

    /// `default_ar_*` is the announce-rate policy an interface inherits when its own block is
    /// silent — and only when transport is enabled (`Reticulum.py:854-857`). Without the
    /// application half these keys would parse into a value no interface ever reads, which is
    /// the defect, not the fix.
    func testDefaultAnnounceRatesReachAnInterfaceWhenTransportIsEnabled() throws {
        let reticulum = try startedInstance("""
        enable_transport = yes
        default_ar_target = 3600
        default_ar_penalty = 7200
        default_ar_grace = 5
        """)
        defer { reticulum.stop() }
        XCTAssertTrue(Reticulum.transportEnabled(), "the gate this scenario turns on")

        let interface = UDPInterface(name: "probe", listenPort: nil,
                                     forwardHost: nil, forwardPort: nil)
        Reticulum.applyInterfaceConfiguration(to: interface, from: .init(
            name: "probe", type: "UDPInterface", enabled: true, parameters: [:]))

        XCTAssertEqual(interface.announceRateTarget, 3600)
        XCTAssertEqual(interface.announceRatePenalty, 7200)
        XCTAssertEqual(interface.announceRateGrace, 5)
    }

    /// The transport gate is part of the requirement, not an accident: a non-transport node
    /// applies no default announce rate at all.
    func testDefaultAnnounceRatesAreNotAppliedWhenTransportIsDisabled() throws {
        let reticulum = try startedInstance("""
        enable_transport = no
        default_ar_target = 3600
        """)
        defer { reticulum.stop() }
        XCTAssertFalse(Reticulum.transportEnabled())

        let interface = UDPInterface(name: "probe", listenPort: nil,
                                     forwardHost: nil, forwardPort: nil)
        Reticulum.applyInterfaceConfiguration(to: interface, from: .init(
            name: "probe", type: "UDPInterface", enabled: true, parameters: [:]))

        XCTAssertNil(interface.announceRateTarget)
    }

    /// Python maps a configured `0` target to "no announce-rate target" rather than to a target
    /// of zero (`Reticulum.py:643-645`), which would rate-limit everything to nothing.
    func testAZeroAnnounceRateTargetMeansNoTarget() {
        apply("default_ar_target = 0")
        XCTAssertNil(Reticulum.defaultArTarget())
    }

    // MARK: - Network identity

    /// `network_identity` names a file that is loaded if present and generated if not
    /// (`Reticulum.py:513-534`), then handed to Transport so discovery announces are signed
    /// with it.
    func testNetworkIdentityIsGeneratedThenReloadedFromTheConfiguredPath() throws {
        let dir = scratchDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let identityPath = dir.appendingPathComponent("network_identity")
        let configURL = dir.appendingPathComponent("config")
        try "[reticulum]\nnetwork_identity = \(identityPath.path)\n"
            .write(to: configURL, atomically: true, encoding: .utf8)

        let first = Reticulum(configuration: .init(
            storagePath: dir.appendingPathComponent("storage-1"),
            configPath: configURL, shareInstance: false))
        try first.start()
        let generated = try XCTUnwrap(first.transport.networkIdentity,
                                      "no network identity was set from the configured path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: identityPath.path),
                      "the identity must be persisted, or the next start generates a different one")
        first.stop()

        // A second instance must adopt the *same* identity, which is the entire point of the
        // option: several transport nodes sharing one network identity.
        let second = Reticulum(configuration: .init(
            storagePath: dir.appendingPathComponent("storage-2"),
            configPath: configURL, shareInstance: false))
        try second.start()
        defer { second.stop() }
        XCTAssertEqual(second.transport.networkIdentity?.hash, generated.hash)
    }

    // MARK: - RPC key (task 4.3)

    /// Spec: "a utility presenting the configured key authenticates, and a utility presenting
    /// the key derived from the transport identity does not".
    func testAConfiguredRPCKeyReplacesTheDerivedOne() throws {
        let dir = scratchDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let configured = Data([0xde, 0xad, 0xbe, 0xef, 0x01, 0x02, 0x03, 0x04])
        let configURL = dir.appendingPathComponent("config")
        try "[reticulum]\nrpc_key = \(RNSUtilities.hexrep(configured, delimit: false))\n"
            .write(to: configURL, atomically: true, encoding: .utf8)

        let reticulum = Reticulum(configuration: .init(
            storagePath: dir.appendingPathComponent("storage"),
            configPath: configURL, shareInstance: false))
        try reticulum.start()
        defer { reticulum.stop() }

        let identity = try XCTUnwrap(reticulum.transport.internalIdentity)
        let derived = Identity.fullHash(try XCTUnwrap(identity.getPrivateKey()))

        XCTAssertEqual(reticulum.rpcAuthenticationKey(), configured,
                       "the configured key must be the one utilities authenticate against")
        XCTAssertNotEqual(reticulum.rpcAuthenticationKey(), derived,
                          "the derived key must no longer be accepted once one is configured")
    }

    /// With no `rpc_key`, the derived key remains the fallback, matching the reference.
    func testTheDerivedRPCKeyRemainsTheFallback() throws {
        let dir = scratchDirectory()
        let reticulum = Reticulum(configuration: .init(
            storagePath: dir.appendingPathComponent("storage"), shareInstance: false))
        try reticulum.start()
        defer { reticulum.stop() }

        let identity = try XCTUnwrap(reticulum.transport.internalIdentity)
        let derived = Identity.fullHash(try XCTUnwrap(identity.getPrivateKey()))
        XCTAssertEqual(reticulum.rpcAuthenticationKey(), derived)
    }

    /// Python logs and falls back to the derived key when the hex will not decode
    /// (`Reticulum.py:494-499`). A malformed key must not become a *working* key made of
    /// whatever decoded, and must not silently look like an absent one either.
    func testAMalformedRPCKeyFallsBackButStaysDistinguishableFromAbsent() {
        let parsed = ReticulumConfig.parse("[reticulum]\nrpc_key = nothexatall\n").reticulum
        XCTAssertNil(parsed.rpcKey, "a value that will not decode must not become a key")
        XCTAssertTrue(parsed.rpcKeySpecified, "but the operator did specify one, and got it wrong")
    }
}
