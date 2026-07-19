import XCTest
@testable import ReticulumSwift

/// Regression coverage for the shared-instance "forward every announce to
/// connected local clients immediately, regardless of transportEnabled" path.
///
/// Bug: rnsd-swift only relayed announces to other interfaces from inside the
/// `transportEnabled` mesh-relay block. Most single-user rnsd instances run
/// with `enable_transport = No` (client-only), so apps sharing the daemon's
/// connection over the shared-instance socket (nomadnet, rnstatus, MeshChatX)
/// never received any announces the daemon overheard — even though the
/// daemon's own path table updated fine. Python avoids this because its
/// "if (len(Transport.local_client_interfaces)): ... send()" block is
/// unconditional, separate from the transport_enabled-gated retransmit block.
final class LocalClientAnnounceForwardingTests: XCTestCase {

    /// A loopback interface that records every outbound packet, paired with
    /// another instance to simulate real inbound delivery (see AnnounceForwardingTests).
    final class RecordingInterface: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        weak var paired: RecordingInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []

        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            sent.append(packet)
            let raw = try packet.pack()
            let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }

    /// Stands in for `PosixTCPServer`: a server-side interface fronting one
    /// or more locally-connected shared-instance clients.
    final class RecordingLocalClientInterface: Interface, LocalClientServingInterface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        var clientCount: Int = 1
        // Mirrors PosixTCPServer: not a mesh routing endpoint — its own
        // send() fans out to attached clients directly.
        var isRoutingEndpoint: Bool { false }
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []

        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    func testAnnounceForwardedToLocalClientEvenWhenTransportDisabled() throws {
        let transport = Transport()
        transport.transportEnabled = false

        let ifaceFromA = RecordingInterface(name: "fromA")
        let upstream = RecordingInterface(name: "upstream")
        ifaceFromA.paired = upstream; upstream.paired = ifaceFromA
        let localClient = RecordingLocalClientInterface(name: "Shared Instance[37428]")

        transport.register(interface: ifaceFromA)
        transport.register(interface: localClient)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let announce = try Announce.make(for: destination, appData: Data("hi".utf8))
        try upstream.send(announce)

        XCTAssertEqual(localClient.sent.count, 1, "announce must reach the local shared-instance client")
        XCTAssertEqual(localClient.sent.first?.packetType, .announce)
        XCTAssertEqual(localClient.sent.first?.hops, 0, "local-client forward passes hops through unchanged")
        XCTAssertEqual(localClient.sent.first?.headerType, .type2)
    }

    func testAnnounceNotEchoedBackToSourceLocalClient() throws {
        let transport = Transport()
        transport.transportEnabled = false

        let localClient = RecordingLocalClientInterface(name: "Shared Instance[37428]")
        transport.register(interface: localClient)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let announce = try Announce.make(for: destination)

        // Simulate the announce itself arriving FROM the local client
        // (e.g. a local app originating it) — it must not be echoed back.
        localClient.inboundHandler?(announce, localClient)

        XCTAssertEqual(localClient.sent.count, 0)
    }

    func testNoLocalClientsConnectedDoesNotCrashOrForward() throws {
        let transport = Transport()
        transport.transportEnabled = false

        let ifaceFromA = RecordingInterface(name: "fromA")
        let upstream = RecordingInterface(name: "upstream")
        ifaceFromA.paired = upstream; upstream.paired = ifaceFromA
        let localClient = RecordingLocalClientInterface(name: "Shared Instance[37428]")
        localClient.clientCount = 0  // server up, but nobody connected yet

        transport.register(interface: ifaceFromA)
        transport.register(interface: localClient)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        try upstream.send(try Announce.make(for: destination))

        XCTAssertEqual(localClient.sent.count, 0)
    }

    // MARK: - Cluster A1: local client's announce must reach the MESH

    /// A non-transport shared instance (enable_transport = No) must still
    /// propagate an announce originated by one of its connected clients out to
    /// the wider mesh — otherwise no peer ever learns the client's destination.
    /// Mirrors Python `if (transport_enabled or is_from_local_client) and
    /// context != PATH_RESPONSE:` (Transport.py:1935) with immediate retransmit
    /// for local-client announces (retries = PATHFINDER_R).
    func testLocalClientAnnounceForwardedToMeshWhenTransportDisabled() throws {
        let transport = Transport()
        transport.transportEnabled = false

        let mesh = RecordingInterface(name: "mesh")            // isRoutingEndpoint = true (default)
        let serving = RecordingLocalClientInterface(name: "Shared Instance[37428]")
        transport.register(interface: mesh)
        transport.register(interface: serving)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let announce = try Announce.make(for: destination, appData: Data("hi".utf8))

        // The announce arrives FROM the local client on the serving interface.
        serving.inboundHandler?(announce, serving)

        XCTAssertEqual(mesh.sent.count, 1,
                       "local client's announce must be propagated to the mesh even with transport disabled")
        XCTAssertEqual(mesh.sent.first?.packetType, .announce)
        XCTAssertEqual(mesh.sent.first?.hops, 1, "forwarded announce is hops+1")
        XCTAssertEqual(mesh.sent.first?.headerType, .type2)
        XCTAssertEqual(mesh.sent.first?.transportID, transport.transportInstanceID)
    }

    /// Guard: a plain MESH announce (not from a local client) must NOT be
    /// relayed by a non-transport node — only transport nodes relay mesh
    /// announces. This is the boundary the local-client OR-clause must not cross.
    func testMeshAnnounceNotForwardedByNonTransportNode() throws {
        let transport = Transport()
        transport.transportEnabled = false

        let meshA = RecordingInterface(name: "meshA")
        let meshB = RecordingInterface(name: "meshB")
        transport.register(interface: meshA)
        transport.register(interface: meshB)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        let announce = try Announce.make(for: destination)

        // Arrives on a mesh interface (not a local client).
        meshA.inboundHandler?(announce, meshA)

        XCTAssertEqual(meshB.sent.count, 0,
                       "a non-transport node must not relay mesh announces")
    }

    func testAnnounceStillForwardedToLocalClientWhenTransportEnabled() throws {
        // Regression guard: enabling transport must not disturb the
        // separate, unconditional local-client forward.
        let transport = Transport()
        transport.transportEnabled = true

        let ifaceFromA = RecordingInterface(name: "fromA")
        let upstream = RecordingInterface(name: "upstream")
        ifaceFromA.paired = upstream; upstream.paired = ifaceFromA
        let localClient = RecordingLocalClientInterface(name: "Shared Instance[37428]")

        transport.register(interface: ifaceFromA)
        transport.register(interface: localClient)

        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "x"
        )
        try upstream.send(try Announce.make(for: destination))

        XCTAssertEqual(localClient.sent.count, 1)
    }
}
