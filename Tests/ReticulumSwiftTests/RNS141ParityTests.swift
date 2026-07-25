import XCTest
@testable import ReticulumSwift

/// Parity tests for RNS 1.4.1 (Python 122f17fa..4631d78b, released 2026-07-24).
///
/// Covers: interface gravity, `announces_to_internal`, boundary-mode path
/// requests, link path re-balancing, request/response size caps, the ingress
/// burst-control fix, and the config surface that drives them.
final class RNS141ParityTests: XCTestCase {

    // MARK: - Helpers

    /// Minimal in-memory interface with real storage for the 1.4.1 properties.
    private final class StubInterface: Interface {
        let name: String
        var bitrate: Int = 1_000_000
        var isOnline: Bool = true
        var mode: InterfaceMode
        var gravity: Int = InterfaceMode.defaultGravity
        var announcesToInternal: Bool? = nil
        var announcesFromInternal: Bool = true
        var recursivePrs: Bool = false
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var rawInboundHandler: ((Data, any Interface) -> Void)?
        var ifacIdentity: Identity?
        var ifacKey: Data?
        var ifacSize: Int = 0
        var createdAt: Date
        var sent: [Packet] = []

        init(name: String, mode: InterfaceMode = .full, gravity: Int = 0,
             createdAt: Date = Date()) {
            self.name = name
            self.mode = mode
            self.gravity = gravity
            self.createdAt = createdAt
        }
        func send(_ packet: Packet) throws { sent.append(packet) }
        func start() throws {}
        func stop() { isOnline = false }
    }

    /// Feed an announce into Transport the way the wire does — through the
    /// interface's `inboundHandler`, which `register(interface:)` installs.
    private static func deliver(_ announce: Packet, on iface: any Interface) throws {
        let raw = try announce.pack()
        iface.inboundHandler?(try Packet.unpack(raw), iface)
    }

    // MARK: - Gravity: defaults and constants

    func testInterfaceGravityDefaultsToZero() {
        XCTAssertEqual(InterfaceMode.defaultGravity, 0,
                       "Python Interface.DEFAULT_GRAVITY = 0")
        XCTAssertEqual(StubInterface(name: "i").gravity, 0)
    }

    func testBoundarySearchModesMatchesPython() {
        XCTAssertEqual(InterfaceMode.boundarySearchModes, [.boundary, .gateway],
                       "Python Interface.BOUNDARY_SEARCH_MODES = [MODE_BOUNDARY, MODE_GATEWAY]")
    }

    // MARK: - Gravity: config plumbing

    func testDefaultGravityParsedFromReticulumSection() {
        let cfg = ReticulumConfig.parse("""
        [reticulum]
        default_gravity = 5
        """)
        XCTAssertEqual(cfg.reticulum.defaultGravity, 5)
    }

    func testNegativeGravityIsAccepted() {
        // Python parses with as_int and documents negative gravity as reducing
        // pathing affinity, so it must not be clamped at zero.
        let cfg = ReticulumConfig.parse("""
        [reticulum]
        default_gravity = -3
        """)
        XCTAssertEqual(cfg.reticulum.defaultGravity, -3)
    }

    func testPerInterfaceGravityOverridesDefault() {
        let cfg = ReticulumConfig.parse("""
        [reticulum]
        default_gravity = 4

        [interfaces]
          [[Preferred]]
            type = TCPClientInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4242
            gravity = 9
          [[Ordinary]]
            type = TCPClientInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4243
        """)
        XCTAssertEqual(cfg.interfaces.first { $0.name == "Preferred" }?.int("gravity"), 9)
        XCTAssertNil(cfg.interfaces.first { $0.name == "Ordinary" }?.int("gravity"),
                     "an interface without an explicit gravity must fall back to default_gravity")
    }

    func testAutoconnectInterfaceModeAliases() {
        // Python accepts every one of these spellings.
        let expected: [String: InterfaceMode] = [
            "full": .full, "access_point": .accessPoint, "accesspoint": .accessPoint,
            "ap": .accessPoint, "pointtopoint": .pointToPoint, "ptp": .pointToPoint,
            "roaming": .roaming, "boundary": .boundary, "gateway": .gateway,
            "gw": .gateway, "internal": .internal,
        ]
        for (name, mode) in expected {
            XCTAssertEqual(InterfaceMode(configName: name), mode, "alias \(name)")
            XCTAssertEqual(InterfaceMode(configName: name.uppercased()), mode,
                           "alias \(name) must be case-insensitive")
        }
        XCTAssertNil(InterfaceMode(configName: "not-a-mode"),
                     "an unknown mode leaves Python's default in place rather than erroring")
    }

    func testAutoconnectOptionsParsed() {
        let cfg = ReticulumConfig.parse("""
        [reticulum]
        autoconnect_interface_mode = boundary
        autoconnect_interface_gravity = 7
        autoconnect_announces_to_internal = yes
        """)
        XCTAssertEqual(cfg.reticulum.autoconnectInterfaceMode, .boundary)
        XCTAssertEqual(cfg.reticulum.autoconnectInterfaceGravity, 7)
        XCTAssertEqual(cfg.reticulum.autoconnectAnnouncesToInternal, true)
    }

    // MARK: - announces_to_internal

    func testAnnouncesToInternalOverridesBoundaryBlock() {
        // Baseline (RNS 1.3.7 behaviour): internal outbound blocks a boundary next hop.
        XCTAssertFalse(Transport.shouldForwardAnnounce(
            outboundMode: .internal, nextHopMode: .boundary))

        // RNS 1.4.1: the next-hop interface opting in unblocks it.
        XCTAssertTrue(Transport.shouldForwardAnnounce(
            outboundMode: .internal, nextHopMode: .boundary,
            nextHopAnnouncesToInternal: true))

        // Only an explicit true counts — Python tests `== True`, so nil/false
        // both keep the block.
        XCTAssertFalse(Transport.shouldForwardAnnounce(
            outboundMode: .internal, nextHopMode: .boundary,
            nextHopAnnouncesToInternal: false))
        XCTAssertFalse(Transport.shouldForwardAnnounce(
            outboundMode: .internal, nextHopMode: .boundary,
            nextHopAnnouncesToInternal: nil))
    }

    func testAnnouncesToInternalDoesNotAffectOtherOutboundModes() {
        // The flag is only consulted in the MODE_INTERNAL outbound branch.
        XCTAssertFalse(Transport.shouldForwardAnnounce(
            outboundMode: .roaming, nextHopMode: .boundary,
            nextHopAnnouncesToInternal: true),
            "roaming outbound still blocks a boundary next hop")
        XCTAssertFalse(Transport.shouldForwardAnnounce(
            outboundMode: .accessPoint, nextHopMode: .gateway,
            nextHopAnnouncesToInternal: true),
            "AP outbound is never used for relayed announces")
    }

    func testAnnouncesToInternalParsedPerInterface() {
        let cfg = ReticulumConfig.parse("""
        [interfaces]
          [[Edge]]
            type = TCPClientInterface
            enabled = yes
            target_host = 127.0.0.1
            target_port = 4242
            announces_to_internal = yes
        """)
        XCTAssertEqual(cfg.interfaces.first?.bool("announces_to_internal"), true)
    }

    // MARK: - Gravity: path-table takeover

    /// The same announce arriving later on a higher-gravity interface must
    /// replace the existing path entry.
    func testHigherGravityInterfaceTakesOverPath() throws {
        let t = Transport()
        let low  = StubInterface(name: "low",  gravity: 0)
        let high = StubInterface(name: "high", gravity: 10)
        t.register(interface: low)
        t.register(interface: high)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "grav", aspects: ["test"])
        let announce = try Announce.make(for: dest)

        try Self.deliver(announce, on: low)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "low",
                       "first announce establishes the path")

        // Exactly the same announce (same random blob → same emission timebase)
        // arriving on the higher-gravity interface.
        try Self.deliver(announce, on: high)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "high",
                       "a same-timebase announce on a higher-gravity interface must take the path")
    }

    func testLowerGravityInterfaceDoesNotTakeOverPath() throws {
        let t = Transport()
        let high = StubInterface(name: "high", gravity: 10)
        let low  = StubInterface(name: "low",  gravity: 0)
        t.register(interface: high)
        t.register(interface: low)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "grav", aspects: ["test2"])
        let announce = try Announce.make(for: dest)

        try Self.deliver(announce, on: high)
        try Self.deliver(announce, on: low)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "high",
                       "gravity must be strictly greater to displace an existing path")
    }

    func testEqualGravityDoesNotTakeOverPath() throws {
        let t = Transport()
        let a = StubInterface(name: "a", gravity: 4)
        let b = StubInterface(name: "b", gravity: 4)
        t.register(interface: a)
        t.register(interface: b)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "grav", aspects: ["test3"])
        let announce = try Announce.make(for: dest)

        try Self.deliver(announce, on: a)
        try Self.deliver(announce, on: b)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "a",
                       "Python's comparison is `announce_gravity <= current_gravity → should_add = False`")
    }

    /// A gravity takeover must NOT reset the path's responsiveness state —
    /// Python's gravity branch is the one that omits `mark_path_unknown_state`.
    func testGravitySwapPreservesPathState() throws {
        let t = Transport()
        let low  = StubInterface(name: "low",  gravity: 0)
        let high = StubInterface(name: "high", gravity: 10)
        t.register(interface: low)
        t.register(interface: high)

        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "grav", aspects: ["state"])
        let announce = try Announce.make(for: dest)

        try Self.deliver(announce, on: low)
        _ = t.markPathResponsive(for: dest.hash)
        XCTAssertFalse(t.pathIsUnresponsive(to: dest.hash), "precondition")

        try Self.deliver(announce, on: high)
        XCTAssertEqual(t.paths[dest.hash]?.nextHopInterfaceName, "high")
        XCTAssertFalse(t.pathIsUnresponsive(to: dest.hash),
                       "a gravity swap keeps the known-good responsiveness state")
    }

    // MARK: - Spawned-interface gravity inheritance

    func testTCPServerSpawnedClientInheritsGravity() {
        let server = TCPServerInterface(name: "srv", port: 0)
        server.gravity = 12
        let client = TCPServerClientInterface(name: "srv/1", parentServer: server)
        XCTAssertEqual(client.gravity, 12,
                       "Python: spawned_interface.gravity = self.gravity")
    }

    // MARK: - Ingress burst control (commit 48388756)

    func testEgressLimitRequiresBurstMinSamples() {
        XCTAssertEqual(IngressControlState.icBurstMinSamples, 6,
                       "Python Interface.IC_BURST_MIN_SAMPLES = 6")
        XCTAssertEqual(InterfaceFreqTracker.minSamples, 2,
                       "Python Interface.IC_DEQUE_MIN_SAMPLE = 2")
        XCTAssertNotEqual(IngressControlState.icBurstMinSamples,
                          InterfaceFreqTracker.minSamples,
                          "the two thresholds are distinct; conflating them was the bug")
    }

    // MARK: - Link path re-balancing

    func testAllowLinkPathRebalanceDefaultsTrue() {
        XCTAssertTrue(Transport.allowLinkPathRebalance,
                      "Python Transport.ALLOW_LINK_PATH_REBALANCE = True")
    }


    // MARK: - Destination.max_request_size

    func testMaxRequestSizeDefaultsToNil() throws {
        let dest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                   appName: "sz", aspects: ["a"])
        XCTAssertNil(dest.maxRequestSize, "Python: self.max_request_size = None")
    }

    func testSetMaxRequestSizeAcceptsZeroAndPositive() throws {
        let dest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                   appName: "sz", aspects: ["b"])
        try dest.setMaxRequestSize(0)
        XCTAssertEqual(dest.maxRequestSize, 0)
        try dest.setMaxRequestSize(4096)
        XCTAssertEqual(dest.maxRequestSize, 4096)
    }

    func testSetMaxRequestSizeRejectsNegative() throws {
        let dest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                   appName: "sz", aspects: ["c"])
        XCTAssertThrowsError(try dest.setMaxRequestSize(-1),
                             "Python raises ValueError for a negative maximum") { error in
            XCTAssertEqual(error as? Destination.DestinationError, .invalidMaxRequestSize)
        }
    }

    // MARK: - RequestReceipt.max_response_size

    func testRequestReceiptMaxResponseSizeDefaultsToNil() {
        let r = RequestReceipt(requestID: Data(repeating: 1, count: 16),
                               path: "/x", requestSize: 10)
        XCTAssertNil(r.maxResponseSize)
    }

    func testResponseRejectedConcludesAsFailure() {
        let r = RequestReceipt(requestID: Data(repeating: 1, count: 16),
                               path: "/x", requestSize: 10, maxResponseSize: 16)
        var failure: String?
        r.onFailed = { reason, _ in failure = reason }
        r.responseRejected()
        guard case .failed = r.status else {
            return XCTFail("an over-size response must fail the receipt, not deliver it")
        }
        XCTAssertNotNil(failure, "Python's response_rejected() runs the failed callback")
    }

    // MARK: - Log level

    func testExtremeLogLevelIsEight() {
        XCTAssertEqual(Reticulum.LogLevel.extreme.rawValue, 8,
                       "RNS 1.4.1 raised the config loglevel cap from 7 to 8 so LOG_EXTREME is reachable")
    }

    // MARK: - Channel sequence window (commit a29a0871)

    func testChannelRejectsFarFutureSequence() throws {
        let ch = Channel(outlet: MockChannelOutlet())
        try ch.registerMessageType(PingMessage.self)

        var delivered = 0
        ch.addMessageHandler { _ in delivered += 1; return true }

        // A far-future sequence must be dropped outright rather than buffered.
        // Observable behaviour: after dropping it, filling the whole window
        // 0..<WINDOW_MAX delivers exactly WINDOW_MAX messages — the out-of-window
        // frame is not sitting in the ring waiting to be delivered as well.
        ch.receive(Self.frame(seq: UInt16(Channel.WINDOW_MAX + 1), value: 0x01))
        XCTAssertEqual(delivered, 0, "an out-of-window frame delivers nothing on arrival")

        for s in 0..<Channel.WINDOW_MAX {
            ch.receive(Self.frame(seq: UInt16(s), value: 0x02))
        }
        XCTAssertEqual(delivered, Channel.WINDOW_MAX,
                       "the dropped far-future frame must not be buffered; only the in-window run delivers")
    }

    private static func frame(seq: UInt16, value: UInt8) -> Data {
        Data([0x00, 0x01, UInt8(seq >> 8), UInt8(seq & 0xFF), 0x00, 0x01, value])
    }
}
