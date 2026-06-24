import XCTest
@testable import ReticulumSwift

/// Tests for interface-mode-aware announce forwarding.
///
/// Python reference rule in Transport.outbound()
/// (packet.attached_interface == None branch for ANNOUNCE packets):
///
///   ACCESS_POINT outbound → always block
///     AP-mode interfaces are last-mile for clients; backbone announces
///     are not pushed to clients via the AP outbound.
///
///   ROAMING outbound → block if next-hop mode is ROAMING or BOUNDARY
///     Prevents roaming-segment announces from ping-ponging.
///
///   BOUNDARY outbound → block if next-hop mode is ROAMING
///     Prevents roaming traffic from crossing boundary interfaces.
///     (BOUNDARY→BOUNDARY, BOUNDARY←AP, BOUNDARY←FULL are all fine.)
///
///   FULL / GATEWAY / POINT_TO_POINT outbound → always forward.
final class AnnounceModeForwardingTests: XCTestCase {

    // MARK: - Helpers

    final class ModeInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        var mode: InterfaceMode
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []

        init(name: String, mode: InterfaceMode = .full) {
            self.name = name
            self.mode = mode
        }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    private func injectAnnounce(destination: Destination,
                                into transport: Transport,
                                via receivingIface: ModeInterface) throws {
        let announce = try Announce.make(for: destination)
        receivingIface.inboundHandler?(announce, receivingIface)
    }

    // MARK: - shouldForwardAnnounce unit tests

    // --- AP outbound: always blocked ---
    func testAPOutboundFromFullBlocked() {
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .accessPoint, nextHopMode: .full),
                       "AP outbound must always be blocked")
    }
    func testAPOutboundFromRoamingBlocked() {
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .accessPoint, nextHopMode: .roaming))
    }
    func testAPOutboundFromAPBlocked() {
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .accessPoint, nextHopMode: .accessPoint))
    }
    func testAPOutboundFromBoundaryBlocked() {
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .accessPoint, nextHopMode: .boundary))
    }

    // --- FULL / GATEWAY / P2P outbound: always forwarded ---
    func testFullOutboundFromAnyForwards() {
        for nhm: InterfaceMode in [.full, .gateway, .roaming, .accessPoint, .boundary, .pointToPoint] {
            XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .full, nextHopMode: nhm),
                          "FULL outbound must always forward (nextHopMode=\(nhm))")
        }
    }
    func testGatewayOutboundFromAnyForwards() {
        for nhm: InterfaceMode in [.full, .gateway, .roaming, .accessPoint, .boundary, .pointToPoint] {
            XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .gateway, nextHopMode: nhm),
                          "GATEWAY outbound must always forward (nextHopMode=\(nhm))")
        }
    }
    func testP2POutboundFromAnyForwards() {
        for nhm: InterfaceMode in [.full, .gateway, .roaming, .accessPoint, .boundary, .pointToPoint] {
            XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .pointToPoint, nextHopMode: nhm),
                          "P2P outbound must always forward")
        }
    }

    // --- ROAMING outbound: block if next-hop is ROAMING or BOUNDARY ---
    func testRoamingOutboundFromFullForwards() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .roaming, nextHopMode: .full))
    }
    func testRoamingOutboundFromGatewayForwards() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .roaming, nextHopMode: .gateway))
    }
    func testRoamingOutboundFromAPForwards() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .roaming, nextHopMode: .accessPoint),
                      "ROAMING outbound must forward when next-hop is AP (not ROAMING/BOUNDARY)")
    }
    func testRoamingOutboundFromRoamingBlocked() {
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .roaming, nextHopMode: .roaming),
                       "ROAMING outbound must block when next-hop is also ROAMING")
    }
    func testRoamingOutboundFromBoundaryBlocked() {
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .roaming, nextHopMode: .boundary),
                       "ROAMING outbound must block when next-hop is BOUNDARY")
    }

    // --- BOUNDARY outbound: block only if next-hop is ROAMING ---
    func testBoundaryOutboundFromFullForwards() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .boundary, nextHopMode: .full))
    }
    func testBoundaryOutboundFromGatewayForwards() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .boundary, nextHopMode: .gateway))
    }
    func testBoundaryOutboundFromAPForwards() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .boundary, nextHopMode: .accessPoint),
                      "BOUNDARY outbound must forward when next-hop is AP")
    }
    func testBoundaryOutboundFromBoundaryForwards() {
        XCTAssertTrue(Transport.shouldForwardAnnounce(outboundMode: .boundary, nextHopMode: .boundary),
                      "BOUNDARY outbound must forward when next-hop is BOUNDARY")
    }
    func testBoundaryOutboundFromRoamingBlocked() {
        XCTAssertFalse(Transport.shouldForwardAnnounce(outboundMode: .boundary, nextHopMode: .roaming),
                       "BOUNDARY outbound must block when next-hop is ROAMING")
    }

    // MARK: - Integration tests

    /// Announce received on a FULL interface must reach GATEWAY and ROAMING
    /// outbound, but NOT reach AP outbound (AP is always blocked).
    func testFullReceivingDoesNotForwardToAP() throws {
        let transport = Transport()
        transport.transportEnabled = true

        let fullReceive  = ModeInterface(name: "full-rx",  mode: .full)
        let gatewayOut   = ModeInterface(name: "gw",       mode: .gateway)
        let roamingOut   = ModeInterface(name: "roaming",  mode: .roaming)
        let apOut        = ModeInterface(name: "ap",       mode: .accessPoint)

        transport.register(interface: fullReceive)
        transport.register(interface: gatewayOut)
        transport.register(interface: roamingOut)
        transport.register(interface: apOut)

        let id   = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["full-rx"])
        try injectAnnounce(destination: dest, into: transport, via: fullReceive)

        XCTAssertEqual(gatewayOut.sent.filter { $0.packetType == .announce }.count, 1,
                       "FULL receive must forward to GATEWAY outbound")
        XCTAssertEqual(roamingOut.sent.filter { $0.packetType == .announce }.count, 1,
                       "FULL receive must forward to ROAMING outbound (next-hop is FULL, not ROAMING/BOUNDARY)")
        XCTAssertEqual(apOut.sent.filter { $0.packetType == .announce }.count, 0,
                       "FULL receive must NOT forward to AP outbound (AP is always blocked)")
    }

    /// Announce received on a ROAMING interface must NOT reach ROAMING or
    /// BOUNDARY outbound, but must reach FULL/GATEWAY outbound.
    func testRoamingReceivingBlocksRoamingAndBoundaryOutbound() throws {
        let transport = Transport()
        transport.transportEnabled = true

        let roamRx      = ModeInterface(name: "roam-rx",   mode: .roaming)
        let fullOut     = ModeInterface(name: "full-out",  mode: .full)
        let roamOut     = ModeInterface(name: "roam-out",  mode: .roaming)
        let boundaryOut = ModeInterface(name: "bound-out", mode: .boundary)

        transport.register(interface: roamRx)
        transport.register(interface: fullOut)
        transport.register(interface: roamOut)
        transport.register(interface: boundaryOut)

        let id   = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["roam-rx"])
        try injectAnnounce(destination: dest, into: transport, via: roamRx)

        XCTAssertEqual(fullOut.sent.filter { $0.packetType == .announce }.count, 1,
                       "ROAMING receive must forward to FULL outbound")
        XCTAssertEqual(roamOut.sent.filter { $0.packetType == .announce }.count, 0,
                       "ROAMING receive must NOT forward to another ROAMING outbound")
        XCTAssertEqual(boundaryOut.sent.filter { $0.packetType == .announce }.count, 0,
                       "ROAMING receive must NOT forward to BOUNDARY outbound")
    }

    /// Announce received on a BOUNDARY interface must NOT reach ROAMING outbound
    /// (next-hop is BOUNDARY, which blocks ROAMING outbound), but must reach
    /// FULL outbound.
    func testBoundaryReceivingBlocksRoamingOutbound() throws {
        let transport = Transport()
        transport.transportEnabled = true

        let boundRx   = ModeInterface(name: "bound-rx",  mode: .boundary)
        let fullOut   = ModeInterface(name: "full-out",  mode: .full)
        let roamOut   = ModeInterface(name: "roam-out",  mode: .roaming)

        transport.register(interface: boundRx)
        transport.register(interface: fullOut)
        transport.register(interface: roamOut)

        let id   = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single,
                                   appName: "test", aspects: ["bound-rx"])
        try injectAnnounce(destination: dest, into: transport, via: boundRx)

        XCTAssertEqual(fullOut.sent.filter { $0.packetType == .announce }.count, 1,
                       "BOUNDARY receive must forward to FULL outbound")
        XCTAssertEqual(roamOut.sent.filter { $0.packetType == .announce }.count, 0,
                       "BOUNDARY receive must NOT forward to ROAMING outbound (next-hop is BOUNDARY)")
    }
}
