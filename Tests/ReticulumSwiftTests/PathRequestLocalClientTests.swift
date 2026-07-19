import XCTest
@testable import ReticulumSwift

/// Cluster A2/A4 + C1/C3: path-request handling for shared-instance (local
/// client) topologies and the black-hole gate. Mirrors Python
/// `Transport.path_request` (RNS/Transport.py:2936-3077).
final class PathRequestLocalClientTests: XCTestCase {

    /// A recording mesh interface (routing endpoint, default mode .full).
    final class MeshIface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var mode: InterfaceMode = .full
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    /// A shared-instance server interface fronting connected local clients.
    final class ServingIface: Interface, LocalClientServingInterface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        var clientCount: Int = 1
        var isRoutingEndpoint: Bool { false }
        var inboundHandler: ((Packet, any Interface) -> Void)?
        var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}; func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    private func pathRequestPacket(target: Data, tag: Data) -> Packet {
        Packet(destinationType: .plain, packetType: .data,
               destinationHash: Transport.pathRequestDestinationHash,
               data: target + tag)
    }

    // MARK: - A2: local client's path request must reach the mesh

    func testLocalClientPathRequestForwardedToMeshWhenTransportDisabled() throws {
        let t = Transport()
        t.transportEnabled = false

        let serving = ServingIface(name: "Shared Instance[37428]")
        let mesh = MeshIface(name: "mesh")
        t.register(interface: serving)
        t.register(interface: mesh)

        let target = Data(repeating: 0xAB, count: 16)
        let tag = Data(repeating: 0x01, count: 16)

        // Request arrives from the local client on the serving interface.
        serving.inboundHandler?(pathRequestPacket(target: target, tag: tag), serving)

        let forwarded = mesh.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        XCTAssertGreaterThan(forwarded.count, 0,
            "a local client's path request must be forwarded to the mesh even with transport disabled")
    }

    // MARK: - A4: mesh path request must be offered to local clients

    func testMeshPathRequestForwardedToLocalClientsWhenNotTransport() throws {
        let t = Transport()
        t.transportEnabled = false

        let serving = ServingIface(name: "Shared Instance[37428]")
        let mesh = MeshIface(name: "mesh")
        t.register(interface: serving)
        t.register(interface: mesh)

        let target = Data(repeating: 0xCD, count: 16)
        let tag = Data(repeating: 0x02, count: 16)

        // Request arrives from a mesh peer for an unknown destination.
        mesh.inboundHandler?(pathRequestPacket(target: target, tag: tag), mesh)

        let offered = serving.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        XCTAssertGreaterThan(offered.count, 0,
            "a mesh path request must be forwarded down to connected local clients so they can answer")
    }

    // MARK: - C1: a non-transport node must not answer as a fake relay

    func testNonTransportNodeDoesNotAnswerPathRequestAsFakeRelay() throws {
        let t = Transport()
        t.transportEnabled = false   // plain endpoint, no local clients

        let mesh = MeshIface(name: "mesh")
        t.register(interface: mesh)

        // Overhear an announce for some destination D so it lands in the path
        // table + announce cache (as a real client would).
        let id = Identity()
        let dest = try Destination(identity: id, direction: .in, kind: .single, appName: "svc")
        mesh.inboundHandler?(try Announce.make(for: dest), mesh)
        XCTAssertNotNil(t.cachedAnnounces[dest.hash])
        mesh.sent.removeAll()

        // A mesh peer now path-requests D. We know a path, but we are NOT a
        // transport node → we must stay silent (Python falls through to `else`).
        let requestorTID = Data(repeating: 0x09, count: 16)
        let body = dest.hash + requestorTID + Data(repeating: 0x03, count: 16)
        let req = Packet(destinationType: .plain, packetType: .data,
                         destinationHash: Transport.pathRequestDestinationHash, data: body)
        mesh.inboundHandler?(req, mesh)

        let responses = mesh.sent.filter {
            $0.packetType == .announce && $0.destinationHash == dest.hash
        }
        XCTAssertEqual(responses.count, 0,
            "a non-transport node must not answer path requests naming itself as the relay")
    }

    // MARK: - C3: recursive discovery reuses the incoming tag

    func testRecursiveDiscoveryReusesIncomingTag() throws {
        let t = Transport()
        t.transportEnabled = true

        let source = MeshIface(name: "in"); source.mode = .gateway  // DISCOVER_PATHS_FOR
        let other = MeshIface(name: "out")
        t.register(interface: source)
        t.register(interface: other)

        let target = Data(repeating: 0xEE, count: 16)
        let incomingTag = Data(repeating: 0x7A, count: 16)
        let body = target + t.transportInstanceID + incomingTag
        let req = Packet(destinationType: .plain, packetType: .data,
                         destinationHash: Transport.pathRequestDestinationHash, data: body)
        source.inboundHandler?(req, source)

        let forwarded = other.sent.filter { $0.destinationHash == Transport.pathRequestDestinationHash }
        XCTAssertGreaterThan(forwarded.count, 0, "unknown request should be propagated for discovery")
        // Body shape (transport enabled): target(16) + transportID(16) + tag(16).
        let outTag = forwarded.first!.data.suffix(16)
        XCTAssertEqual(Data(outTag), incomingTag,
            "recursive discovery must reuse the incoming tag, not mint a fresh one")
    }
}
