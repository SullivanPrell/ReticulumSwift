import XCTest
@testable import ReticulumSwift

/// The other half of `bugs/025` — a configured per-interface attribute must take effect.
///
/// §1 of this change made `mode`, the three `announce_rate_*` values, `announce_cap`, `bitrate`,
/// `ingress_control` and the `ic_*` family settable, because Python mutates all of them at runtime
/// and this port had declared them get-only. That removed the compile-time blocker and left the
/// values with nowhere to come *from*: `synthesizeInterfaces` applied exactly two attributes,
/// `gravity` and `announces_to_internal`, and no other per-interface key was read anywhere in
/// `Sources/`.
///
/// Which is the same defect one step earlier, and the spec says so: "a configuration value with
/// nowhere to be written is indistinguishable from a configuration value that is never read, and
/// both are failures of this requirement."
///
/// Every assertion starts from a config **string** and ends at the interface the config path
/// produced. Nothing sets an attribute directly — that would prove the setters §1 added, which is
/// not what was missing.
final class PerInterfaceConfigTests: XCTestCase {

    private var tmpDirs: [URL] = []

    override func tearDown() {
        for dir in tmpDirs { try? FileManager.default.removeItem(at: dir) }
        tmpDirs = []
        super.tearDown()
    }

    /// One interface synthesised from a config block, through the real path.
    private func synthesise(_ body: String) throws -> any Interface {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("per-iface-\(UUID().uuidString)")
        tmpDirs.append(tmp)
        let reticulum = Reticulum(configuration: .init(storagePath: tmp.appendingPathComponent("storage"),
                                                      shareInstance: false))
        try reticulum.synthesizeInterfaces(from: ReticulumConfig.parse("""
        [interfaces]
          [[Configured Interface]]
            type = UDPInterface
            interface_enabled = True
        \(body)
        """))
        return try XCTUnwrap(reticulum.transport.interfaces.first,
                             "no interface synthesised from the config")
    }

    // MARK: - Mode

    /// The spec's first scenario. `Reticulum.py:737-769` accepts every alias, and
    /// `InterfaceMode(configName:)` already parses them — nothing read the key.
    func testInterfaceModeIsHonoured() throws {
        for (configured, expected): (String, InterfaceMode) in [
            ("full", .full),
            ("access_point", .accessPoint), ("accesspoint", .accessPoint), ("ap", .accessPoint),
            ("pointtopoint", .pointToPoint), ("ptp", .pointToPoint),
            ("roaming", .roaming),
            ("boundary", .boundary),
            ("gateway", .gateway), ("gw", .gateway),
            ("internal", .internal),
        ] {
            let iface = try synthesise("    interface_mode = \(configured)")
            XCTAssertEqual(iface.mode, expected,
                           """
                           interface_mode = \(configured) did not take effect — the interface \
                           reports \(iface.mode). Transport's announce and propagation rules \
                           branch on mode, so the whole block is inert (bugs/025).
                           """)
        }
    }

    /// Python accepts `mode` as well as `interface_mode` (`Reticulum.py:753-768`).
    func testModeAliasIsHonoured() throws {
        XCTAssertEqual(try synthesise("    mode = gateway").mode, .gateway)
    }

    /// Case-insensitive: Python lowercases the value before comparing (`Reticulum.py:737`).
    func testModeIsCaseInsensitive() throws {
        XCTAssertEqual(try synthesise("    interface_mode = Access_Point").mode, .accessPoint)
    }

    /// An unrecognised value leaves the default in place rather than throwing — Python's
    /// if/elif chain simply falls through with `interface_mode` still `MODE_FULL`.
    func testUnrecognisedModeLeavesTheDefault() throws {
        XCTAssertEqual(try synthesise("    interface_mode = nonsense").mode, .full)
    }

    // MARK: - Announce rate control

    func testAnnounceRateValuesAreHonoured() throws {
        let iface = try synthesise("""
            announce_rate_target = 3600
            announce_rate_grace = 3
            announce_rate_penalty = 7200
        """)
        XCTAssertEqual(iface.announceRateTarget, 3600)
        XCTAssertEqual(iface.announceRateGrace, 3)
        XCTAssertEqual(iface.announceRatePenalty, 7200)
    }

    /// `announce_rate_target` must be `> 0` to be accepted; grace and penalty `>= 0`
    /// (`Reticulum.py:820-829`).
    func testOutOfRangeAnnounceRateValuesAreIgnored() throws {
        let iface = try synthesise("""
            announce_rate_target = 0
            announce_rate_grace = -1
            announce_rate_penalty = -5
        """)
        XCTAssertNil(iface.announceRateTarget, "a target of 0 is rejected, leaving rate control off")
        XCTAssertEqual(iface.announceRateGrace, 0)
        XCTAssertEqual(iface.announceRatePenalty, 0)
    }

    /// A target with no grace or penalty gets both defaulted to 0 (`Reticulum.py:831-832`), so a
    /// config that sets only the target is complete rather than half-configured.
    func testATargetAloneDefaultsGraceAndPenaltyToZero() throws {
        let iface = try synthesise("    announce_rate_target = 1800")
        XCTAssertEqual(iface.announceRateTarget, 1800)
        XCTAssertEqual(iface.announceRateGrace, 0)
        XCTAssertEqual(iface.announceRatePenalty, 0)
    }

    // MARK: - Announce cap

    /// The config value is a percentage in `(0, 100]` and is divided by 100
    /// (`Reticulum.py:834-837`).
    func testAnnounceCapIsReadAsAPercentage() throws {
        XCTAssertEqual(try synthesise("    announce_cap = 5").announceCap, 0.05, accuracy: 1e-9)
    }

    func testOutOfRangeAnnounceCapIsIgnored() throws {
        let expected = Double(Reticulum.announceCap) / 100.0
        XCTAssertEqual(try synthesise("    announce_cap = 0").announceCap, expected, accuracy: 1e-9)
        XCTAssertEqual(try synthesise("    announce_cap = 101").announceCap, expected, accuracy: 1e-9)
    }

    // MARK: - Bitrate

    /// A configured bitrate replaces the class guess, if it is at least `MINIMUM_BITRATE`
    /// (`Reticulum.py:815-816`). It matters beyond reporting: announce capacity and resource
    /// timings are derived from it.
    func testConfiguredBitrateIsHonoured() throws {
        XCTAssertEqual(try synthesise("    bitrate = 4242000").bitrate, 4_242_000)
    }

    func testBitrateBelowTheMinimumIsIgnored() throws {
        let iface = try synthesise("    bitrate = 1")
        XCTAssertNotEqual(iface.bitrate, 1,
                          "below MINIMUM_BITRATE (\(Reticulum.minimumBitrate)), Python leaves the "
                          + "class guess in place")
    }

    // MARK: - Ingress / egress control

    func testIngressControlCanBeDisabled() throws {
        XCTAssertFalse(try synthesise("    ingress_control = False").ingressControl)
        XCTAssertTrue(try synthesise("    ingress_control = True").ingressControl)
        XCTAssertTrue(try synthesise("    listen_port = 4970").ingressControl,
                      "Python's default is True (Reticulum.py:789)")
    }

    func testEgressControlAndFrequencyAreHonoured() throws {
        let iface = try synthesise("""
            egress_control = True
            ec_pr_freq = 9.5
        """)
        XCTAssertTrue(iface.egressControl)
        XCTAssertEqual(iface.ecPrFreq, 9.5, accuracy: 1e-9)
    }

    /// Each of the nine `ic_*` tunables Python reads per interface (`Reticulum.py:791-813`).
    func testEveryIngressControlTunableIsHonoured() throws {
        let iface = try synthesise("""
            ic_max_held_announces = 42
            ic_burst_hold = 11.5
            ic_burst_freq_new = 1.25
            ic_burst_freq = 2.5
            ic_pr_burst_freq_new = 3.75
            ic_pr_burst_freq = 4.25
            ic_new_time = 60.5
            ic_burst_penalty = 90.25
            ic_held_release_interval = 7.75
        """)
        XCTAssertEqual(iface.interfaceState.icMaxHeldAnnounces, 42)
        XCTAssertEqual(iface.interfaceState.icBurstHold, 11.5, accuracy: 1e-9)
        XCTAssertEqual(iface.interfaceState.icBurstFreqNew, 1.25, accuracy: 1e-9)
        XCTAssertEqual(iface.interfaceState.icBurstFreq, 2.5, accuracy: 1e-9)
        XCTAssertEqual(iface.interfaceState.icPrBurstFreqNew, 3.75, accuracy: 1e-9)
        XCTAssertEqual(iface.interfaceState.icPrBurstFreq, 4.25, accuracy: 1e-9)
        XCTAssertEqual(iface.interfaceState.icNewTime, 60.5, accuracy: 1e-9)
        XCTAssertEqual(iface.interfaceState.icBurstPenalty, 90.25, accuracy: 1e-9)
        XCTAssertEqual(iface.interfaceState.icHeldReleaseInterval, 7.75, accuracy: 1e-9)
    }

    /// The spec's per-interface scenario: two interfaces in one config with different values must
    /// not affect each other. §1 made the `ic_*` set per-interface; this asserts a *config* can
    /// actually produce two different ones, which is the only way the requirement is observable.
    func testTwoInterfacesInOneConfigKeepTheirOwnValues() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("per-iface-pair-\(UUID().uuidString)")
        tmpDirs.append(tmp)
        let reticulum = Reticulum(configuration: .init(storagePath: tmp.appendingPathComponent("storage"),
                                                      shareInstance: false))
        try reticulum.synthesizeInterfaces(from: ReticulumConfig.parse("""
        [interfaces]
          [[Strict]]
            type = UDPInterface
            interface_enabled = True
            interface_mode = access_point
            ingress_control = True
            ic_burst_freq = 1.5
            announce_cap = 2
          [[Loose]]
            type = UDPInterface
            interface_enabled = True
            interface_mode = gateway
            ingress_control = False
            ic_burst_freq = 9.5
            announce_cap = 20
        """))

        let byName = Dictionary(uniqueKeysWithValues:
            reticulum.transport.interfaces.map { ($0.name, $0) })
        let strict = try XCTUnwrap(byName["Strict"])
        let loose = try XCTUnwrap(byName["Loose"])

        XCTAssertEqual(strict.mode, .accessPoint)
        XCTAssertEqual(loose.mode, .gateway)
        XCTAssertTrue(strict.ingressControl)
        XCTAssertFalse(loose.ingressControl)
        XCTAssertEqual(strict.interfaceState.icBurstFreq, 1.5, accuracy: 1e-9)
        XCTAssertEqual(loose.interfaceState.icBurstFreq, 9.5, accuracy: 1e-9)
        XCTAssertEqual(strict.announceCap, 0.02, accuracy: 1e-9)
        XCTAssertEqual(loose.announceCap, 0.20, accuracy: 1e-9)
    }

    // MARK: - The values are read, not merely stored

    /// Task 1.3 of this change moved the `ic_*` tunables onto `InterfaceState` and its tests
    /// asserted the values by **reading the box back**. Transport's decision path went on reading
    /// `IngressControlState`'s statics, so the per-interface values were written and never
    /// consulted: inert, in precisely the way `bugs/025` describes. Found while writing the parser
    /// — and the parser would have been pointless without this, since it would have filled a box
    /// nothing reads.
    ///
    /// So this asserts through **behaviour**: two interfaces configured with different
    /// `ic_burst_freq`, fed the identical announce stream, must reach different ingress-limiting
    /// decisions. Reading the box back cannot distinguish that.
    func testConfiguredIngressThresholdChangesTheLimitingDecision() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("per-iface-ic-\(UUID().uuidString)")
        tmpDirs.append(tmp)
        let reticulum = Reticulum(configuration: .init(storagePath: tmp.appendingPathComponent("storage"),
                                                      shareInstance: false))
        // Both the new-interface and mature thresholds are set to the same value on each
        // interface, so the age branch cannot decide the outcome. The synthesised interfaces'
        // `createdAt` is real wall-clock time while the announce timeline below is a synthetic
        // 1000, which makes `age` negative and selects the *new* threshold — a detail worth
        // pinning down rather than working around with a fabricated `ic_new_time`.
        try reticulum.synthesizeInterfaces(from: ReticulumConfig.parse("""
        [interfaces]
          [[Tolerant]]
            type = UDPInterface
            interface_enabled = True
            listen_port = 4980
            ic_burst_freq = 500
            ic_burst_freq_new = 500
          [[Twitchy]]
            type = UDPInterface
            interface_enabled = True
            listen_port = 4981
            ic_burst_freq = 2
            ic_burst_freq_new = 2
        """))

        let byName = Dictionary(uniqueKeysWithValues:
            reticulum.transport.interfaces.map { ($0.name, $0) })
        let tolerant = try XCTUnwrap(byName["Tolerant"])
        let twitchy = try XCTUnwrap(byName["Twitchy"])

        // The identical stream: 60 announces across one second — 60 Hz.
        let base: TimeInterval = 1000
        for iface in [tolerant, twitchy] {
            for i in 0..<60 {
                reticulum.transport.notifyIncomingAnnounce(on: iface, at: base + Double(i) * 0.016)
            }
        }

        XCTAssertFalse(reticulum.transport.shouldIngressLimit(on: tolerant, now: base + 1.0),
                       """
                       60 Hz did not stay under a configured burst frequency of 500, which means the \
                       decision is not reading the interface's own value. Before this task \
                       Transport read IngressControlState's static 10 Hz for every interface, so \
                       the configured value was stored and ignored (bugs/025).
                       """)
        XCTAssertTrue(reticulum.transport.shouldIngressLimit(on: twitchy, now: base + 1.0),
                      "60 Hz must exceed a configured burst frequency of 2")
    }

    /// The same for the path-request threshold, which reads a different pair of tunables
    /// (`ic_pr_burst_freq_new` / `ic_pr_burst_freq`).
    func testConfiguredPathRequestThresholdChangesTheLimitingDecision() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("per-iface-pr-\(UUID().uuidString)")
        tmpDirs.append(tmp)
        let reticulum = Reticulum(configuration: .init(storagePath: tmp.appendingPathComponent("storage"),
                                                      shareInstance: false))
        try reticulum.synthesizeInterfaces(from: ReticulumConfig.parse("""
        [interfaces]
          [[TolerantPR]]
            type = UDPInterface
            interface_enabled = True
            listen_port = 4982
            ic_pr_burst_freq = 500
            ic_pr_burst_freq_new = 500
          [[TwitchyPR]]
            type = UDPInterface
            interface_enabled = True
            listen_port = 4983
            ic_pr_burst_freq = 2
            ic_pr_burst_freq_new = 2
        """))

        let byName = Dictionary(uniqueKeysWithValues:
            reticulum.transport.interfaces.map { ($0.name, $0) })
        let tolerant = try XCTUnwrap(byName["TolerantPR"])
        let twitchy = try XCTUnwrap(byName["TwitchyPR"])

        let base: TimeInterval = 1000
        for iface in [tolerant, twitchy] {
            for i in 0..<60 {
                reticulum.transport.notifyIncomingPathRequest(on: iface, at: base + Double(i) * 0.016)
            }
        }

        XCTAssertFalse(reticulum.transport.shouldIngressLimitPR(on: tolerant, now: base + 1.0))
        XCTAssertTrue(reticulum.transport.shouldIngressLimitPR(on: twitchy, now: base + 1.0))
    }

    // MARK: - The remaining boxed flags

    func testBootstrapOnlyAndRecursivePrsAreHonoured() throws {
        let iface = try synthesise("""
            bootstrap_only = True
            recursive_prs = True
        """)
        XCTAssertTrue(iface.bootstrapOnly)
        XCTAssertTrue(iface.recursivePrs)
    }

    func testAnnouncesFromInternalCanBeDisabled() throws {
        XCTAssertFalse(try synthesise("    announces_from_internal = False").announcesFromInternal)
        XCTAssertTrue(try synthesise("    listen_port = 4971").announcesFromInternal,
                      "Python's default is True (Reticulum.py:851)")
    }
}
