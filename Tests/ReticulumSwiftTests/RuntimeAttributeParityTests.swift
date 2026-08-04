import XCTest
@testable import ReticulumSwift

/// `fix-013 §7.8/§7.9`. The reference mutates interface attributes at runtime — `Reticulum`
/// writes config, `Transport` writes routing and rate state, the interfaces write their own
/// connection state. The audit's structural finding was that many of those were ported as
/// `{ get }`-only, which makes the write *impossible to express*: no amount of parser work can
/// fix `iface.mode = …` when `mode` has no setter.
///
/// This suite re-derives the check instead of hardcoding a pass-list: for every attribute the
/// sweep found the reference assigning, it asserts here that a Swift interface can actually be
/// written and read back. A future `{ get }`-only regression fails a test rather than passing
/// silently, and the deliberate omissions carry their reason in one place.
final class RuntimeAttributeParityTests: XCTestCase {

    /// Every attribute the §7.8 sweep classified as parity must round-trip through a live
    /// interface — **written through the protocol, read back off the concrete type**.
    ///
    /// That asymmetry is the whole point, and this suite got it wrong once: writing *and*
    /// reading through `any Interface` only ever exercises the protocol's `InterfaceState`
    /// storage, so a concrete type that shadows an attribute with a get-only property still
    /// passes — the write lands in the box and the read comes from the box, while every real
    /// consumer holding the concrete type sees the class's constant. Deliberately falsified by
    /// making `TCPClientInterface.gravity` get-only: the original form passed, this one fails.
    func testEveryRuntimeWrittenAttributeIsWritable() throws {
        let concrete = TCPClientInterface(name: "probe", host: "127.0.0.1", port: 4965)
        let iface: any Interface = concrete   // what `Reticulum.applyInterfaceConfiguration` holds

        // Reticulum.__apply_config / interface_post_init (`Reticulum.py:905-975`)
        iface.mode = .accessPoint;                    XCTAssertEqual(concrete.mode, .accessPoint)
        iface.gravity = 7;                            XCTAssertEqual(concrete.gravity, 7)
        iface.announceCap = 0.25;                     XCTAssertEqual(concrete.announceCap, 0.25)
        iface.bootstrapOnly = true;                   XCTAssertTrue(concrete.bootstrapOnly)
        iface.bitrate = 3_000_000;                    XCTAssertEqual(concrete.bitrate, 3_000_000)
        iface.ifacSize = 8;                           XCTAssertEqual(concrete.ifacSize, 8)
        iface.announceRateTarget = 30;                XCTAssertEqual(concrete.announceRateTarget, 30)
        iface.announceRateGrace = 3;                  XCTAssertEqual(concrete.announceRateGrace, 3)
        iface.announceRatePenalty = 60;               XCTAssertEqual(concrete.announceRatePenalty, 60)
        iface.ingressControl = false;                 XCTAssertFalse(concrete.ingressControl)
        iface.egressControl = false;                  XCTAssertFalse(concrete.egressControl)
        iface.ecPrFreq = 2.5;                         XCTAssertEqual(concrete.ecPrFreq, 2.5)
        iface.announcesFromInternal = false;          XCTAssertFalse(concrete.announcesFromInternal)
        iface.announcesToInternal = true;             XCTAssertEqual(concrete.announcesToInternal, true)
        iface.recursivePrs = true;                    XCTAssertTrue(concrete.recursivePrs)

        // Ingress control tunables (`Reticulum.py:942-953` → `InterfaceState`)
        let state = concrete.interfaceState
        state.icMaxHeldAnnounces = 42;                XCTAssertEqual(state.icMaxHeldAnnounces, 42)
        state.icBurstHold = 1.5;                      XCTAssertEqual(state.icBurstHold, 1.5)
        state.icBurstFreqNew = 3.5;                   XCTAssertEqual(state.icBurstFreqNew, 3.5)
        state.icBurstFreq = 12;                       XCTAssertEqual(state.icBurstFreq, 12)
        state.icPrBurstFreqNew = 0.5;                 XCTAssertEqual(state.icPrBurstFreqNew, 0.5)
        state.icPrBurstFreq = 0.75;                   XCTAssertEqual(state.icPrBurstFreq, 0.75)
        state.icNewTime = 600;                        XCTAssertEqual(state.icNewTime, 600)
        state.icBurstPenalty = 5;                     XCTAssertEqual(state.icBurstPenalty, 5)
        state.icHeldReleaseInterval = 30;             XCTAssertEqual(state.icHeldReleaseInterval, 30)

        // Transport-written routing and tunnel state
        iface.wantsTunnel = true;                     XCTAssertTrue(concrete.wantsTunnel)
        iface.tunnelID = Data(repeating: 0x5A, count: 32)
        XCTAssertEqual(concrete.tunnelID?.count, 32)

        // IFAC, written by `Reticulum.__apply_config` after key derivation
        // (`Reticulum.py:955-973`)
        let identity = Identity()
        iface.ifacIdentity = identity;                XCTAssertNotNil(concrete.ifacIdentity)
        iface.ifacKey = Data(repeating: 0x01, count: 64)
        XCTAssertEqual(concrete.ifacKey?.count, 64)

        // MTU, written by `optimise_mtu` (`Interface.py:205-217`)
        let mtuCapable = try XCTUnwrap(iface as? MtuAutoconfiguringInterface,
                                       "an AUTOCONFIGURE_MTU interface must have a settable "
                                       + "hwMtu — see OptimiseMtuTests")
        mtuCapable.hwMtu = 4_096
        XCTAssertEqual(concrete.hwMtu, 4_096)
    }

    /// The attributes the reference writes that this port has **no counterpart for**, each
    /// tied to a subsystem that is not implemented rather than to a missing setter.
    ///
    /// Kept as a test so the inventory cannot drift into folklore: when a subsystem lands, its
    /// entry here fails to describe reality and has to be updated deliberately. The gaps are
    /// recorded in `swift_devel/bugs/` — this is the index, not the analysis.
    func testTheKnownGapsAreStillTheKnownGaps() {
        // Interface discovery, publish side: Python's `Discovery.InterfaceAnnouncer` announces
        // an interface as a discoverable endpoint, carrying `discoverable`,
        // `discovery_name/latitude/longitude/height/bandwidth/frequency/modulation/
        // encrypt/stamp_value/announce_interval`, `reachable_on` and `discovery_publish_ifac`.
        // This port implements the *receive* side only, so none of those attributes exists.
        XCTAssertFalse(Reticulum.publishesInterfaceDiscovery,
                       """
                       the discovery publish side now exists — the eleven discovery_* \
                       attributes it carries need porting and this inventory entry needs \
                       replacing with real assertions
                       """)

        // Autoconnect: Python's `Discovery` dials discovered endpoints and monitors them,
        // writing `autoconnect_hash`, `autoconnect_source` and `autoconnect_down`. The policy
        // config keys parse here; nothing consumes them because the subsystem is absent.
        XCTAssertFalse(Reticulum.autoconnectsDiscoveredInterfaces,
                       "the autoconnect subsystem now exists — its three attributes need "
                       + "porting and this entry needs replacing")

        // `_force_bitrate`: Python's shared-instance startup applies
        // `force_shared_instance_bitrate` to the local interface and marks it forced
        // (`Reticulum.py:397-401`, `:424-428`), which `LocalInterface.py:234` then uses to
        // simulate latency. This port parses the config value into a static that nothing
        // reads. Tracked separately; the config key is honest about doing nothing today.
        XCTAssertNil(Reticulum.forceSharedInstanceBitrate(),
                     "an unconfigured stack must report no forced bitrate")
    }
}
