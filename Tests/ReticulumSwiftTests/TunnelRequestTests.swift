import XCTest
@testable import ReticulumSwift

/// Tunnel synthesis is what restores a client's paths across a reconnect: the client asks for
/// a tunnel on every successful connect (`wants_tunnel = True` at `TCPInterface.py:179` and
/// `BackboneInterface.py:653`), the transport emits the `rnstransport.tunnel.synthesize`
/// packet, and the remote side rebuilds the paths it held for that tunnel ID.
///
/// The port had the machinery and neither writer: `TCPClientInterface` and `BackboneInterface`
/// set `isOnline = true` on connect and nothing else, so a Swift client never requested a
/// tunnel and its paths died with each reconnect. Compounding it, the only synthesis trigger
/// was registration time — and `register` runs before `start()`, so a write in the async
/// connect callback would still have been missed.
final class TunnelRequestTests: XCTestCase {

    /// The one thing `synthesizeTunnel` puts on the wire, so a test can watch for it.
    private final class TunnelWatchingInterface: Interface {
        let interfaceState = InterfaceState()
        let name: String
        var bitrate: Int = 10_000_000
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var rawInboundHandler: ((Data, any Interface) -> Void)?
        var ifacIdentity: Identity?
        var ifacKey: Data?
        var ifacSize: Int = 0
        var gravity: Int = InterfaceMode.defaultGravity
        var announcesToInternal: Bool? = nil
        private(set) var synthesizeRequests = 0

        init(name: String, wantsTunnel: Bool) {
            self.name = name
            self.wantsTunnel = wantsTunnel
        }

        var wantsTunnel: Bool

        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws {
            if packet.destinationHash == Transport.tunnelSynthesizeHash {
                synthesizeRequests += 1
            }
        }
    }

    private func makeTransport() -> Transport {
        let transport = Transport()
        transport.ownerIdentity = Identity()
        return transport
    }

    // MARK: - The writers

    func testATCPClientAsksForATunnelOnConnect() {
        let iface = TCPClientInterface(name: "Uplink", host: "127.0.0.1", port: 4965)
        XCTAssertFalse(iface.wantsTunnel, "nothing to ask for before a connection exists")
        iface.noteConnected()
        XCTAssertTrue(iface.wantsTunnel,
                      """
                      a connected TCP client must request tunnel synthesis \
                      (TCPInterface.py:179) — without it the remote transport never rebuilds \
                      the paths it held for this client, so every reconnect silently loses \
                      them until each destination is re-announced
                      """)
    }

    func testABackboneClientAsksForATunnelOnConnect() {
        let iface = BackboneInterface(name: "Fat Pipe", host: "127.0.0.1", port: 4966)
        XCTAssertFalse(iface.wantsTunnel)
        iface.noteConnected()
        XCTAssertTrue(iface.wantsTunnel, "BackboneInterface.py:653 — same request, same reason")
    }

    // MARK: - The trigger

    /// Python re-synthesizes on every reconnect (`TCPInterface.py:298` calls
    /// `Transport.synthesize_tunnel` directly after the redial succeeds). The port's connect
    /// happens asynchronously *after* `register`, so a registration-time check alone cannot
    /// see it: the transport sweeps its interfaces instead.
    func testTheTransportSynthesizesForAnInterfaceThatAsksAfterRegistration() {
        let transport = makeTransport()
        let iface = TunnelWatchingInterface(name: "Late", wantsTunnel: false)
        transport.register(interface: iface)
        XCTAssertEqual(iface.synthesizeRequests, 0)

        iface.wantsTunnel = true           // as a connect callback would
        transport.synthesizePendingTunnels()

        XCTAssertEqual(iface.synthesizeRequests, 1,
                       """
                       an interface that asked for a tunnel after registration never got one — \
                       register() runs before start(), so the registration-time check is blind \
                       to every connection this stack actually makes
                       """)
        XCTAssertFalse(iface.wantsTunnel,
                       "the request is consumed, as Transport.py:2385 clears it")
    }

    func testASecondSweepDoesNotResynthesize() {
        let transport = makeTransport()
        let iface = TunnelWatchingInterface(name: "Once", wantsTunnel: true)
        transport.register(interface: iface)
        transport.synthesizePendingTunnels()
        transport.synthesizePendingTunnels()
        XCTAssertEqual(iface.synthesizeRequests, 1,
                       "one request per connect — the sweep must not re-emit for an interface "
                       + "whose request was already served")
    }

    func testAReconnectAsksAgain() {
        let transport = makeTransport()
        let iface = TunnelWatchingInterface(name: "Flappy", wantsTunnel: true)
        transport.register(interface: iface)
        transport.synthesizePendingTunnels()

        iface.wantsTunnel = true           // the redial succeeded
        transport.synthesizePendingTunnels()

        XCTAssertEqual(iface.synthesizeRequests, 2,
                       "each reconnect is a fresh request — Python calls synthesize_tunnel "
                       + "directly after every successful redial (TCPInterface.py:298)")
    }
}
